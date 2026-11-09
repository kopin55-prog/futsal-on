-- 일정 자동 생성 (스프린트 02 1-2, 1-3 / data-model.md 3-2, 4-1 / Q-027 M-12, Q-071 1번)
--
-- 규칙 하나로 정리한다:
--   정기 운동일(요일·시작·종료)이 있는 해체 안 된 팀의 각 경기 날짜에 대해
--     생성 시각 = 경기 날짜 - auto_create_days_before 일, auto_create_time (한국 시간)
--     마감 시각 = 경기 시작 - rsvp_deadline_hours 시간 (생성 당시 설정)
--   "생성 시각 <= 지금 < 마감 시각" 이면 그 경기의 자동 일정을 만든다 (이미 있으면 그대로).
--
-- - 1-2: 예약 작업이 매분 위 규칙으로 돌린다. 기본 설정(6일 전 09:00, 마감 2시간 전)이면
--   수 10:00~12:00 경기는 전주 목 09:00 에 생기고 마감은 수 08:00. 22:00~00:30 이면 종료는 다음날 00:30.
-- - 1-3 (Q-071 1번): 운동일을 새로 정하거나 바꾸면 그 자리에서 같은 규칙을 그 팀에만 돌린다.
--   → 이번 주 경기의 생성 시각이 이미 지났고 마감 전이면 바로 생성, 마감이 지났으면 다음 주부터.
--   이미 있는 일정은 그대로 (바꾸기 전 요일·시각의 일정도 남는다. 필요하면 운영진이 취소).
-- - 같은 팀·같은 시작 시각 자동 일정은 한 번만 (matches_auto_once, 취소된 것 포함).
-- - 정원·장소는 생성 당시 팀 설정·지정 풋살장을 복사. 설정을 바꿔도 이미 만든 일정은 그대로 (M-12).
-- - 미투표 알림 시각 = 마감 - rsvp_reminder_hours (Q-072 1번). 설정이 끄기거나 생성 때 이미 지났으면 비움.
-- - 종료 시각이 없는 정기 운동일은 경기 종료 시각을 정할 수 없어 만들지 않는다 (lead 보고).
-- - 앱 사용자(anon·authenticated)와 service_role 은 생성 함수를 실행할 수 없다. 예약 작업(pg_cron)과
--   아래 트리거(postgres 소유 SECURITY DEFINER)만 부른다.

-- 미투표 알림 시각 (자동 생성·직접 추가 공통). 끄기(null)거나 이미 지났으면 null.
create function private.rsvp_reminder_at(p_deadline timestamptz, p_hours int, p_now timestamptz)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select case
    when p_hours is null then null
    when p_deadline - make_interval(hours => p_hours) <= p_now then null
    else p_deadline - make_interval(hours => p_hours)
  end
$$;

create function private.generate_auto_matches_for_team(p_team_id uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_s public.team_settings;
  v_today date;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_creates timestamptz;
  v_deadline timestamptz;
  v_reminder timestamptz;
  v_rows int;
  v_count int := 0;
begin
  select t.* into v_team from public.teams t where t.id = p_team_id;
  if v_team.id is null
     or v_team.dissolved_at is not null
     or v_team.regular_weekday is null
     or v_team.regular_start_time is null
     or v_team.regular_end_time is null then
    return 0;
  end if;
  select s.* into v_s from public.team_settings s where s.team_id = p_team_id;
  if v_s.team_id is null then
    return 0;
  end if;

  v_today := (p_now at time zone 'Asia/Seoul')::date;
  -- 오늘 이후 첫 정기 운동 날짜 (오늘 포함)
  v_day := v_today + ((v_team.regular_weekday - extract(isodow from v_today)::int + 7) % 7);

  -- 생성 시각이 지난 날짜들 (auto_create_days_before 최대 30일 → 최대 6주)
  for i in 0..6 loop
    v_creates := ((v_day - v_s.auto_create_days_before) + v_s.auto_create_time) at time zone 'Asia/Seoul';
    exit when v_creates > p_now;

    v_starts := (v_day + v_team.regular_start_time) at time zone 'Asia/Seoul';
    v_deadline := v_starts - make_interval(hours => v_s.rsvp_deadline_hours);
    if p_now < v_deadline then
      v_reminder := private.rsvp_reminder_at(v_deadline, v_s.rsvp_reminder_hours, p_now);
      -- 자정 넘김 (예: 22:00~00:30) 이면 종료는 다음날
      v_ends := (case when v_team.regular_end_time > v_team.regular_start_time then v_day else v_day + 1 end
                 + v_team.regular_end_time) at time zone 'Asia/Seoul';
      insert into public.matches (
        team_id, source, starts_at, ends_at,
        venue_name, venue_address, venue_lat, venue_lng, venue_map_provider, venue_map_place_id,
        capacity, rsvp_deadline_at, rsvp_reminder_at
      )
      values (
        p_team_id, 'auto', v_starts, v_ends,
        v_team.venue_name, v_team.venue_address, v_team.venue_lat, v_team.venue_lng,
        v_team.venue_map_provider, v_team.venue_map_place_id,
        v_s.capacity, v_deadline, v_reminder
      )
      on conflict (team_id, starts_at) where source = 'auto' do nothing;
      get diagnostics v_rows = row_count;
      v_count := v_count + v_rows;
      -- TODO(알림 단계): 새 일정 알림 (docs/notifications.md)
    end if;

    v_day := v_day + 7;
  end loop;

  return v_count;
end;
$$;

-- 예약 작업: 모든 팀. 만든 일정 수를 돌려준다.
create function private.generate_auto_matches(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_count int := 0;
begin
  for v_team_id in
    select t.id
      from public.teams t
      join public.team_settings s on s.team_id = t.id
     where t.dissolved_at is null
       and t.regular_weekday is not null
       and t.regular_start_time is not null
       and t.regular_end_time is not null
  loop
    v_count := v_count + private.generate_auto_matches_for_team(v_team_id, p_now);
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1-3: 운동일을 새로 정하거나 바꾸면 바로 (서버 함수·표 직접 수정 모두)
-- 팀 만들기는 teams 를 만든 뒤 경기 설정 줄을 넣으므로, 경기 설정 줄이 생길 때도 돌린다.
-- ---------------------------------------------------------------------------
create function private.teams_regular_schedule_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.generate_auto_matches_for_team(new.id);
  return null;
end;
$$;

create trigger teams_regular_schedule_changed
after update of regular_weekday, regular_start_time, regular_end_time on public.teams
for each row
when (
  old.regular_weekday is distinct from new.regular_weekday
  or old.regular_start_time is distinct from new.regular_start_time
  or old.regular_end_time is distinct from new.regular_end_time
)
execute function private.teams_regular_schedule_changed();

create function private.team_settings_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.generate_auto_matches_for_team(new.team_id);
  return null;
end;
$$;

create trigger team_settings_created
after insert on public.team_settings
for each row execute function private.team_settings_created();

-- ---------------------------------------------------------------------------
-- 실행 권한: 앱·service_role 실행 불가
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.generate_auto_matches_for_team(uuid, timestamptz),
  private.generate_auto_matches(timestamptz),
  private.teams_regular_schedule_changed(),
  private.team_settings_created()
from public, anon, authenticated, service_role;

-- 예약 작업: 매분 (자동 생성 시각은 분 단위로 정할 수 있다)
select cron.unschedule(jobid) from cron.job where jobname = 'generate-auto-matches';
select cron.schedule(
  'generate-auto-matches',
  '* * * * *',
  $$select private.generate_auto_matches()$$
);
