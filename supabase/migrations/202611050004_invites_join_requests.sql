-- 초대 코드와 가입 신청 (data-model.md 3-5 team_invites, 3-6 join_requests)

create type public.join_via as enum ('invite', 'search', 'code');
create type public.join_request_status as enum ('pending', 'approved', 'rejected', 'cancelled');

-- ---------------------------------------------------------------------------
-- 3-5. 초대 코드
-- ---------------------------------------------------------------------------
create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  -- 코드 값의 SHA-256 지문(16진수). 원본은 저장하지 않음 (Q-020)
  token_hash text not null unique
    constraint team_invites_token_hash_format check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid references public.profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);

-- 팀당 무효화되지 않은 코드 1개 (Q-020)
create unique index team_invites_one_open_per_team
  on public.team_invites (team_id) where revoked_at is null;

-- 발급 시각·만료 시각은 서버 시계로만 정하고 고칠 수 없다 (S-13).
create function private.team_invites_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.expires_at := new.created_at + interval '24 hours';
  else
    new.id := old.id;
    new.team_id := old.team_id;
    new.token_hash := old.token_hash;
    -- 회원 탈퇴의 "비움"(ON DELETE SET NULL)만 허용
    new.created_by := case when new.created_by is null then null else old.created_by end;
    new.created_at := old.created_at;
    new.expires_at := old.expires_at;
    -- 무효화는 한 번만 (되돌리기 불가)
    if old.revoked_at is not null then
      new.revoked_at := old.revoked_at;
    end if;
  end if;
  return new;
end;
$$;

create trigger team_invites_before_write
before insert or update on public.team_invites
for each row execute function private.team_invites_before_write();

-- ---------------------------------------------------------------------------
-- 3-6. 가입 신청
-- ---------------------------------------------------------------------------
create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  via public.join_via not null,
  invite_id uuid references public.team_invites (id) on delete set null,
  status public.join_request_status not null default 'pending',
  -- 신청 시각 = 초대 코드 만료 판단 기준. 서버 시계로만
  created_at timestamptz not null default now(),
  decided_by uuid references public.profiles (user_id) on delete set null,
  decided_at timestamptz,
  constraint join_requests_invite_only_via_invite check (invite_id is null or via = 'invite'),
  constraint join_requests_decided_at_matches_status check ((status = 'pending') = (decided_at is null))
);

-- 한 사람이 한 팀에 "대기" 신청은 1개만
create unique index join_requests_one_pending
  on public.join_requests (team_id, user_id) where status = 'pending';
create index join_requests_user_idx on public.join_requests (user_id);

create function private.join_requests_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.id := old.id;
    new.team_id := old.team_id;
    new.user_id := old.user_id;
    new.via := old.via;
    new.invite_id := case when old.invite_id is null then null else new.invite_id end;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

create trigger join_requests_before_write
before insert or update on public.join_requests
for each row execute function private.join_requests_before_write();

-- 권한 규칙 전용: p_user_id 가 호출자가 관리자인 팀에 "대기 중" 신청을 냈는지 (2-2, 2-3, S-18).
create function private.has_pending_request_to_my_staff_team(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.join_requests r
      join public.team_members me on me.team_id = r.team_id
      join public.teams t on t.id = r.team_id
     where r.user_id = p_user_id
       and r.status = 'pending'
       and me.user_id = (select auth.uid())
       and me.status = 'active'
       and me.role in ('owner', 'manager')
       and t.dissolved_at is null
  )
$$;

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke all on table public.team_invites, public.join_requests from anon, authenticated, public;

alter table public.team_invites enable row level security;
alter table public.join_requests enable row level security;

-- team_invites: 읽기 = 그 팀 관리자(발급 이력), 지문 칸 제외. 쓰기는 서버 함수만.
grant select (id, team_id, created_by, created_at, expires_at, revoked_at)
  on table public.team_invites to authenticated;

create policy team_invites_select_staff on public.team_invites
  for select to authenticated
  using (private.is_team_staff(team_id));

-- join_requests: 읽기 = 신청자 본인 + 그 팀 관리자. 쓰기는 서버 함수만.
grant select on table public.join_requests to authenticated;

create policy join_requests_select on public.join_requests
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_team_staff(team_id));

-- 대기 중 신청자의 프로필·선호 포지션은 그 팀 관리자도 읽기 (2-2, 2-3)
create policy profiles_select_pending_applicant on public.profiles
  for select to authenticated
  using (private.has_pending_request_to_my_staff_team(user_id));

create policy profile_play_prefs_select_pending_applicant on public.profile_play_prefs
  for select to authenticated
  using (private.has_pending_request_to_my_staff_team(user_id));

revoke execute on all functions in schema private from public, anon;
grant execute on function private.has_pending_request_to_my_staff_team(uuid) to authenticated;
