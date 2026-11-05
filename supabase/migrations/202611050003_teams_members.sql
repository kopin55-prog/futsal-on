-- 팀과 팀 소속 (data-model.md 3-1 teams, 3-3 team_members) + 공용 권한 확인 함수 (11장 2번·4번)
--
-- 이번 단계에서 만들지 않는 3장 표: team_settings(3-2, 마감 기본값 미정 → lead 보고),
-- skill_ratings(3-4, 게스트 표 4-3 참조), pairing_rules·pairing_rule_members(3-7). 팀 나누기·일정 단계에서 만든다.

create type public.team_role as enum ('owner', 'manager', 'member');
create type public.membership_status as enum ('active', 'left', 'removed', 'dissolved');
create type public.map_provider as enum ('kakao');

-- ---------------------------------------------------------------------------
-- 3-1. 팀
-- ---------------------------------------------------------------------------
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  -- 팀 이름: 1~10자, 중복 허용, 한 줄 (Q-011, Q-012, Q-034, Q-048)
  name text not null
    constraint teams_name_valid check (private.is_valid_single_line_name(name, 10)),
  -- 팀 식별코드: 6자리, 0·O·1·I 제외, 앱 전체 고유, 변경 불가 (Q-029, Q-051)
  team_code text not null
    constraint teams_team_code_format check (team_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  -- 기본 로고 글자 1~2자 (Q-013). 변경은 팀장만(set_team_logo_text)
  logo_text text not null
    constraint teams_logo_text_valid check (private.is_valid_single_line_name(logo_text, 2)),
  logo_image_path text
    constraint teams_logo_image_path_len check (char_length(logo_image_path) between 1 and 512),
  -- 정기 운동 요일: 1=월 ... 7=일 (ISO)
  regular_weekday smallint
    constraint teams_regular_weekday_range check (regular_weekday between 1 and 7),
  regular_start_time time,
  regular_end_time time,
  venue_name text
    constraint teams_venue_name_len check (char_length(venue_name) between 1 and 200),
  venue_address text
    constraint teams_venue_address_len check (char_length(venue_address) between 1 and 300),
  venue_lat double precision
    constraint teams_venue_lat_range check (venue_lat between -90 and 90),
  venue_lng double precision
    constraint teams_venue_lng_range check (venue_lng between -180 and 180),
  venue_map_provider public.map_provider,
  venue_map_place_id text
    constraint teams_venue_place_id_len check (char_length(venue_map_place_id) between 1 and 100),
  -- 항상 한국 시간 (Q-027 M-18)
  timezone text not null default 'Asia/Seoul'
    constraint teams_timezone_seoul check (timezone = 'Asia/Seoul'),
  -- 새 팀 기본값 모집 중 (Q-021)
  is_recruiting boolean not null default true,
  created_by uuid references public.profiles (user_id) on delete set null,
  created_at timestamptz not null default now(),
  dissolved_at timestamptz,
  -- 시작 시각은 요일과 함께, 종료 시각은 시작과 함께, 종료는 시작보다 늦게
  constraint teams_regular_start_needs_weekday check (regular_start_time is null or regular_weekday is not null),
  constraint teams_regular_end_needs_start check (regular_end_time is null or regular_start_time is not null),
  constraint teams_regular_end_after_start check (regular_end_time is null or regular_end_time > regular_start_time),
  -- 장소 번호는 지도 서비스와 짝으로만, 좌표는 둘 다 있거나 둘 다 없음
  constraint teams_place_id_needs_provider check (venue_map_place_id is null or venue_map_provider is not null),
  constraint teams_lat_lng_pair check ((venue_lat is null) = (venue_lng is null))
);

-- 해체된 팀의 코드도 다시 쓰지 않으므로 전체 고유
create unique index teams_team_code_key on public.teams (team_code);

-- ---------------------------------------------------------------------------
-- 3-3. 팀 소속
-- ---------------------------------------------------------------------------
create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  role public.team_role not null,
  status public.membership_status not null default 'active',
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_by uuid references public.profiles (user_id) on delete set null,
  constraint team_members_ended_at_matches_status check ((status = 'active') = (ended_at is null))
);

-- 한 사람은 한 팀에 "소속 중" 줄이 최대 1개
create unique index team_members_one_active
  on public.team_members (team_id, user_id) where status = 'active';
-- 팀당 현재 팀장 최대 1명 (최소 1명은 아래 지연 검사)
create unique index team_members_one_owner
  on public.team_members (team_id) where status = 'active' and role = 'owner';
create index team_members_user_idx on public.team_members (user_id);

-- 해체되지 않은 팀은 현재 팀장이 정확히 1명, 운영진은 최대 2명 (3-3).
-- 트랜잭션 끝에서 검사한다(위임처럼 두 줄을 차례로 바꾸는 처리를 허용).
create function private.team_members_check_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid := coalesce(new.team_id, old.team_id);
  v_owners int;
  v_managers int;
begin
  if exists (select 1 from public.teams t where t.id = v_team_id and t.dissolved_at is null) then
    select count(*) filter (where m.role = 'owner'),
           count(*) filter (where m.role = 'manager')
      into v_owners, v_managers
      from public.team_members m
     where m.team_id = v_team_id and m.status = 'active';
    if v_owners <> 1 then
      raise exception 'team_owner_required' using errcode = 'P0001';
    end if;
    if v_managers > 2 then
      raise exception 'manager_limit_reached' using errcode = 'P0001';
    end if;
  end if;
  return null;
end;
$$;

create constraint trigger team_members_check_roles
after insert or update or delete on public.team_members
deferrable initially deferred
for each row execute function private.team_members_check_roles();

-- ---------------------------------------------------------------------------
-- 공용 확인 함수 (11장 2번, 4번): team_id 만 받고 사람은 auth.uid() 로 판단.
-- 소속 상태 active + 팀 해체 안 됨을 함께 확인. 해체된 팀은 모두 거짓.
-- ---------------------------------------------------------------------------
create function private.is_team_member(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where m.team_id = p_team_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and t.dissolved_at is null
  )
$$;

create function private.is_team_staff(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where m.team_id = p_team_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.role in ('owner', 'manager')
       and t.dissolved_at is null
  )
$$;

create function private.is_team_owner(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members m
      join public.teams t on t.id = m.team_id
     where m.team_id = p_team_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.role = 'owner'
       and t.dissolved_at is null
  )
$$;

-- 권한 규칙 전용: 호출자와 p_user_id 가 해체 안 된 같은 팀에 지금 함께 소속돼 있는지 (2-2 읽기 규칙).
-- API에 노출되지 않는 private 스키마에만 둔다.
create function private.is_active_teammate(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members me
      join public.team_members them on them.team_id = me.team_id
      join public.teams t on t.id = me.team_id
     where me.user_id = (select auth.uid())
       and me.status = 'active'
       and them.user_id = p_user_id
       and them.status = 'active'
       and t.dissolved_at is null
  )
$$;

-- 권한 규칙 전용: 호출자가 관리자인 팀에 p_user_id 가 지금 소속돼 있는지 (2-3 선호 포지션 읽기).
create function private.is_staff_over_member(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.team_members me
      join public.team_members them on them.team_id = me.team_id
      join public.teams t on t.id = me.team_id
     where me.user_id = (select auth.uid())
       and me.status = 'active'
       and me.role in ('owner', 'manager')
       and them.user_id = p_user_id
       and them.status = 'active'
       and t.dissolved_at is null
  )
$$;

-- ---------------------------------------------------------------------------
-- 팀 이름 정리와 로고 글자 자동 갱신 (Q-036, Q-047)
-- ---------------------------------------------------------------------------
create function private.teams_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.name := private.normalize_single_line_name(new.name);
  if tg_op = 'INSERT' then
    new.created_at := now();
    if new.logo_text is null then
      new.logo_text := private.default_logo_text(new.name);
    end if;
  else
    -- 앱이 바꿀 수 없는 칸은 서버 함수가 아닌 경로에서는 그대로 둔다 (칸 단위 권한과 이중 장치).
    new.id := old.id;
    new.team_code := old.team_code;
    -- 회원 탈퇴의 "비움"(ON DELETE SET NULL)만 허용
    new.created_by := case when new.created_by is null then null else old.created_by end;
    new.created_at := old.created_at;
    new.timezone := old.timezone;
    -- 이름이 바뀌었고, 지금 로고 글자가 바꾸기 전 이름의 기본값과 같으면 새 이름의 기본값으로.
    if new.name is distinct from old.name
       and old.logo_text = private.default_logo_text(old.name)
       and new.logo_text is not distinct from old.logo_text then
      new.logo_text := private.default_logo_text(new.name);
    end if;
  end if;
  return new;
end;
$$;

create trigger teams_before_write
before insert or update on public.teams
for each row execute function private.teams_before_write();

-- ---------------------------------------------------------------------------
-- 권한
-- ---------------------------------------------------------------------------
revoke all on table public.teams, public.team_members from anon, authenticated, public;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;

-- teams: 읽기 = 그 팀 팀원. 팀원이 아닌 사람은 찾기·초대 확인 서버 함수로만.
-- 고치기 = 관리자, 아래 칸만 (logo_text·team_code·dissolved_at 등은 서버 함수만, S-03).
grant select on table public.teams to authenticated;
grant update (
  name, logo_image_path,
  regular_weekday, regular_start_time, regular_end_time,
  venue_name, venue_address, venue_lat, venue_lng, venue_map_provider, venue_map_place_id,
  is_recruiting
) on table public.teams to authenticated;

create policy teams_select_member on public.teams
  for select to authenticated
  using (private.is_team_member(id));

create policy teams_update_staff on public.teams
  for update to authenticated
  using (private.is_team_staff(id))
  with check (private.is_team_staff(id));

-- team_members: 읽기 = 그 팀 팀원(현재 소속 명단) + 본인 소속 이력 전체. 쓰기는 서버 함수만.
grant select on table public.team_members to authenticated;

create policy team_members_select on public.team_members
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (status = 'active' and private.is_team_member(team_id))
  );

-- 프로필: 같은 팀에 지금 함께 소속된 사람도 읽기 (2-2)
create policy profiles_select_teammate on public.profiles
  for select to authenticated
  using (private.is_active_teammate(user_id));

-- 선호 포지션: 내가 관리자인 팀의 현재 팀원 것도 읽기 (2-3, Q-017)
create policy profile_play_prefs_select_staff on public.profile_play_prefs
  for select to authenticated
  using (private.is_staff_over_member(user_id));

revoke execute on all functions in schema private from public, anon;
grant execute on function
  private.is_team_member(uuid),
  private.is_team_staff(uuid),
  private.is_team_owner(uuid),
  private.is_active_teammate(uuid),
  private.is_staff_over_member(uuid)
to authenticated;
