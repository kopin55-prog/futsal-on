-- 실력 등급 (data-model.md 3-4 skill_ratings)
--
-- 이번 단계는 팀원 등급만 만든다. 게스트 등급 칸(guest_id → match_guests)은 게스트 표(4-3)를 만드는
-- 일정 단계 마이그레이션에서 추가하고, 그때 "user_id·guest_id 중 정확히 하나" 검사로 바꾼다.
-- 그래서 user_id 는 문서대로 비울 수 있는 칸으로 만들되, 지금은 검사로 반드시 채우게 한다.
--
-- - 줄이 없으면 "미정". 미정으로 되돌리면 줄을 지운다.
-- - 읽기·쓰기: 그 팀 관리자만. 일반 팀원은 본인 것도 읽지 못한다 (Q-016). 쓰기는 서버 함수로만.
-- - 팀 탈퇴·내보내기 때 그 사람 줄 삭제 (Q-015) → 202611050012. 회원 탈퇴는 같이 삭제(외래 키).
-- - Realtime 에 등록하지 않는다 (11장 7번).

create type public.skill_level as enum ('beginner', 'amateur', 'semipro', 'pro', 'undecided');

create table public.skill_ratings (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  user_id uuid references public.profiles (user_id) on delete cascade,
  level public.skill_level not null,
  updated_by uuid references public.profiles (user_id) on delete set null,
  updated_at timestamptz not null default now(),
  -- 게스트 칸이 생기기 전까지는 팀원 등급만 (위 설명)
  constraint skill_ratings_subject_present check (user_id is not null)
);

create unique index skill_ratings_team_user_key on public.skill_ratings (team_id, user_id);

revoke all on table public.skill_ratings from anon, authenticated, public;
alter table public.skill_ratings enable row level security;
grant select on table public.skill_ratings to authenticated;

create policy skill_ratings_select_staff on public.skill_ratings
  for select to authenticated
  using (private.is_team_staff(team_id));

-- 등급 정하기: 관리자. 대상은 그 팀의 현재 팀원(관리자 본인 포함).
create function public.set_skill_level(p_team_id uuid, p_user_id uuid, p_level public.skill_level)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  if not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if p_level is null then
    raise exception 'invalid_skill_level' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.user_id = p_user_id and m.status = 'active'
  ) then
    raise exception 'target_not_member' using errcode = 'P0001';
  end if;

  if p_level = 'undecided' then
    delete from public.skill_ratings where team_id = p_team_id and user_id = p_user_id;
    return;
  end if;

  insert into public.skill_ratings (team_id, user_id, level, updated_by, updated_at)
  values (p_team_id, p_user_id, p_level, v_uid, now())
  on conflict (team_id, user_id) do update
    set level = excluded.level,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function public.set_skill_level(uuid, uuid, public.skill_level) from public, anon;
grant execute on function public.set_skill_level(uuid, uuid, public.skill_level) to authenticated;
