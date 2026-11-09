-- 자동 생성: 같은 시작 시각의 일정이 이미 있으면 만들지 않음 (Q-073 1번, decisions.md 2026-11-09)
--
-- 예) 정기 운동이 매주 수 10:00 인 팀에서 운영진이 자동 일정이 생기기 전에 "수 10:00" 을 직접 추가하면
--     생성 시각이 되어도 자동 일정을 또 만들지 않는다.
-- - 기준: 같은 팀, 같은 시작 시각, 취소 안 된 일정(자동·직접 추가 모두).
--   취소된 직접 추가 일정은 막지 않는다 → 그 뒤 생성 시각·마감 규칙이 맞으면 자동 일정이 생긴다.
--   취소된 자동 일정은 지금처럼 matches_auto_once 로 다시 생기지 않는다.
-- - 나머지 규칙은 202611050021 과 같다 (본문 복사 + 확인 한 줄).

create or replace function private.generate_auto_matches_for_team(p_team_id uuid, p_now timestamptz default now())
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
  v_day := v_today + ((v_team.regular_weekday - extract(isodow from v_today)::int + 7) % 7);

  for i in 0..6 loop
    v_creates := ((v_day - v_s.auto_create_days_before) + v_s.auto_create_time) at time zone 'Asia/Seoul';
    exit when v_creates > p_now;

    v_starts := (v_day + v_team.regular_start_time) at time zone 'Asia/Seoul';
    v_deadline := v_starts - make_interval(hours => v_s.rsvp_deadline_hours);
    if p_now < v_deadline
       -- 같은 시작 시각의 취소 안 된 일정(직접 추가 포함)이 있으면 만들지 않음 (Q-073 1번)
       and not exists (
         select 1 from public.matches m
          where m.team_id = p_team_id and m.starts_at = v_starts and m.status = 'scheduled'
       ) then
      v_reminder := private.rsvp_reminder_at(v_deadline, v_s.rsvp_reminder_hours, p_now);
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
    end if;

    v_day := v_day + 7;
  end loop;

  return v_count;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.generate_auto_matches_for_team(uuid, timestamptz)
from public, anon, authenticated, service_role;
