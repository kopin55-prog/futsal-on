-- 경기 설정 (data-model.md 3-2 team_settings) + 팀 만들기 때 함께 생성
--
-- - 참석 투표 마감 기본값: 경기 시작 2시간 전 (Q-066 1번). 팀장·운영진이 바꿀 수 있다.
-- - 자동 생성 기본값: 경기 6일 전 09:00 (한국 시간).
-- - 저장 규칙: 마감 시각이 자동 생성 시각보다 앞서면 저장 불가 (서버 검사).
-- - 설정을 바꿔도 이미 만든 일정은 그대로 (Q-027 M-12) → 일정 단계에서 일정마다 값을 복사한다.
-- - 쓰기는 서버 함수(update_team_settings)로만. 읽기는 그 팀 팀원.

create table public.team_settings (
  team_id uuid primary key references public.teams (id) on delete cascade,
  -- 정원. 비어 있으면 "정원 없음"
  -- 정원 상한은 팀 최대 인원 100명 (Q-067 5번)
  capacity int
    constraint team_settings_capacity_range check (capacity between 1 and 100),
  -- 참석 투표 마감 = 경기 시작 몇 시간 전 (기본 2, Q-066)
  rsvp_deadline_hours int not null default 2
    constraint team_settings_rsvp_deadline_range check (rsvp_deadline_hours between 0 and 720),
  -- 자동 생성 = 경기 며칠 전 (기본 6)
  auto_create_days_before int not null default 6
    constraint team_settings_auto_create_days_range check (auto_create_days_before between 0 and 30),
  -- 자동 생성 시각 (한국 시간, 기본 09:00)
  auto_create_time time not null default '09:00',
  updated_by uuid references public.profiles (user_id) on delete set null,
  updated_at timestamptz not null default now()
);

-- 마감 시각이 자동 생성 시각보다 뒤인지 (3-2 저장 규칙).
-- 자동 생성은 정기 운동 시작 시각이 있을 때만 일어나므로, 시작 시각이 없으면 검사할 것이 없다.
create function private.team_settings_deadline_ok(
  p_regular_start_time time,
  p_rsvp_deadline_hours int,
  p_auto_create_days_before int,
  p_auto_create_time time
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_regular_start_time is null
      or make_interval(days => p_auto_create_days_before) + (p_regular_start_time - p_auto_create_time)
         > make_interval(hours => p_rsvp_deadline_hours)
$$;

-- ---------------------------------------------------------------------------
-- 권한: 읽기 = 그 팀 팀원. 쓰기 = 서버 함수만.
-- ---------------------------------------------------------------------------
revoke all on table public.team_settings from anon, authenticated, public;
alter table public.team_settings enable row level security;
grant select on table public.team_settings to authenticated;

create policy team_settings_select_member on public.team_settings
  for select to authenticated
  using (private.is_team_member(team_id));

-- 이미 있는 팀(개발 DB)에 기본 설정을 채운다.
insert into public.team_settings (team_id)
select t.id from public.teams t
 where not exists (select 1 from public.team_settings s where s.team_id = t.id);

-- ---------------------------------------------------------------------------
-- 경기 설정 바꾸기: 관리자
-- ---------------------------------------------------------------------------
create function public.update_team_settings(
  p_team_id uuid,
  p_capacity int,
  p_rsvp_deadline_hours int,
  p_auto_create_days_before int,
  p_auto_create_time time
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_start time;
begin
  if not private.is_team_staff(p_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  if p_rsvp_deadline_hours is null or p_auto_create_days_before is null or p_auto_create_time is null then
    raise exception 'invalid_team_settings' using errcode = 'P0001';
  end if;
  select t.regular_start_time into v_start from public.teams t where t.id = p_team_id for update;
  if not private.team_settings_deadline_ok(v_start, p_rsvp_deadline_hours, p_auto_create_days_before, p_auto_create_time) then
    raise exception 'deadline_before_auto_create' using errcode = 'P0001';
  end if;
  begin
    insert into public.team_settings as s (
      team_id, capacity, rsvp_deadline_hours, auto_create_days_before, auto_create_time, updated_by, updated_at
    )
    values (p_team_id, p_capacity, p_rsvp_deadline_hours, p_auto_create_days_before, p_auto_create_time, v_uid, now())
    on conflict (team_id) do update
      set capacity = excluded.capacity,
          rsvp_deadline_hours = excluded.rsvp_deadline_hours,
          auto_create_days_before = excluded.auto_create_days_before,
          auto_create_time = excluded.auto_create_time,
          updated_by = excluded.updated_by,
          updated_at = excluded.updated_at;
  exception when check_violation then
    raise exception 'invalid_team_settings' using errcode = 'P0001';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 만들기 (3-1): 팀 이름 필수, 정기 운동일·로고 글자 선택. 만든 사람이 팀장, 경기 설정 기본값 생성.
-- 이전 create_team(text) 를 대체한다 (인자 기본값으로 이름만 넘겨도 동작).
-- 지정 풋살장(카카오맵)·로고 사진은 Q-067 답변 후 (팀 정보 수정으로 추가).
-- ---------------------------------------------------------------------------
drop function public.create_team(text);

create function public.create_team(
  p_name text,
  p_regular_weekday smallint default null,
  p_regular_start_time time default null,
  p_regular_end_time time default null,
  p_logo_text text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
  v_logo text;
begin
  -- 한 사람이 소속할 수 있는 팀은 만든 팀 포함 최대 10개 (Q-067 5번)
  if (select count(*) from public.team_members m
        join public.teams t on t.id = m.team_id
       where m.user_id = v_uid and m.status = 'active' and t.dissolved_at is null) >= 10 then
    raise exception 'team_limit_reached' using errcode = 'P0001';
  end if;

  -- 로고 글자: 비우면 기본값(팀 이름 앞 두 글자, Q-013). 만든 사람은 팀장이므로 직접 정할 수 있다 (Q-014).
  if p_logo_text is not null and btrim(p_logo_text) <> '' then
    v_logo := private.normalize_single_line_name(p_logo_text);
    if private.grapheme_count(v_logo) not between 1 and 2
       or not private.is_valid_single_line_name(v_logo, 2) then
      raise exception 'invalid_logo_text' using errcode = 'P0001';
    end if;
  end if;

  begin
    insert into public.teams (name, team_code, created_by, logo_text)
    values (p_name, private.new_team_code(), v_uid, v_logo)
    returning id into v_team_id;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_team_name' using errcode = 'P0001';
  end;

  -- 정기 운동일: 요일 → 시작 → 종료 순으로 짝이 맞아야 한다 (표 검사).
  -- 자정 넘김(예: 22:00~00:30)은 202611050014 에서 허용 (Q-067 4번).
  if p_regular_weekday is not null or p_regular_start_time is not null or p_regular_end_time is not null then
    begin
      update public.teams
         set regular_weekday = p_regular_weekday,
             regular_start_time = p_regular_start_time,
             regular_end_time = p_regular_end_time
       where id = v_team_id;
    exception when check_violation then
      raise exception 'invalid_regular_schedule' using errcode = 'P0001';
    end;
  end if;

  insert into public.team_members (team_id, user_id, role, status)
  values (v_team_id, v_uid, 'owner', 'active');

  insert into public.team_settings (team_id, updated_by) values (v_team_id, v_uid);

  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.update_team_settings(uuid, int, int, int, time),
  public.create_team(text, smallint, time, time, text)
from public, anon;
grant execute on function
  public.update_team_settings(uuid, int, int, int, time),
  public.create_team(text, smallint, time, time, text)
to authenticated;
