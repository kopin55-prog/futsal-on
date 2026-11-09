-- 경기 설정에 미투표 알림 시간 (data-model.md v4.3 3-2 rsvp_reminder_hours, Q-072 1번)
--
-- - 미투표 알림 = 참석 투표 마감 몇 시간 전. 1·2·3·6·12·24 중 하나, 비면 끄기, 기본 2.
-- - 자동 생성 일정은 이 값으로 rsvp_reminder_at 을 계산하고, 직접 추가 화면은 이 값을 기본으로 채운다.
-- - 설정을 바꿔도 이미 만든 일정은 그대로 (M-12).
-- - update_team_settings 에 인자를 하나 더 받는다 (앱은 항상 화면의 현재 값을 보낸다. null = 끄기).

alter table public.team_settings
  add column rsvp_reminder_hours int default 2
    constraint team_settings_rsvp_reminder_hours_valid check (rsvp_reminder_hours in (1, 2, 3, 6, 12, 24));

drop function public.update_team_settings(uuid, int, int, int, time);

create function public.update_team_settings(
  p_team_id uuid,
  p_capacity int,
  p_rsvp_deadline_hours int,
  p_auto_create_days_before int,
  p_auto_create_time time,
  p_rsvp_reminder_hours int
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
      team_id, capacity, rsvp_deadline_hours, auto_create_days_before, auto_create_time, rsvp_reminder_hours,
      updated_by, updated_at
    )
    values (p_team_id, p_capacity, p_rsvp_deadline_hours, p_auto_create_days_before, p_auto_create_time,
            p_rsvp_reminder_hours, v_uid, now())
    on conflict (team_id) do update
      set capacity = excluded.capacity,
          rsvp_deadline_hours = excluded.rsvp_deadline_hours,
          auto_create_days_before = excluded.auto_create_days_before,
          auto_create_time = excluded.auto_create_time,
          rsvp_reminder_hours = excluded.rsvp_reminder_hours,
          updated_by = excluded.updated_by,
          updated_at = excluded.updated_at;
  exception when check_violation then
    raise exception 'invalid_team_settings' using errcode = 'P0001';
  end;
end;
$$;

revoke execute on function public.update_team_settings(uuid, int, int, int, time, int) from public, anon;
grant execute on function public.update_team_settings(uuid, int, int, int, time, int) to authenticated;
