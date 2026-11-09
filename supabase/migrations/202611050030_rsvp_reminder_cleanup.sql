-- 미투표 알림·알림 정리 예약 작업 (스프린트 02 3-3·3-7 / Q-072 1번, Q-041, S-18)
--
-- send_rsvp_reminders(p_now) — 매분
--   일정의 rsvp_reminder_at 이 지났고 마감 전인, 취소 안 된 일정(해체 안 된 팀)마다
--   그 시각에 이미 팀원이었고 지금도 팀원이며 아직 응답이 없는 사람에게 rsvp_deadline_soon 1회.
--   - rsvp_reminder_at 이 비어 있으면(끄기, 생성 때 이미 지남) 보내지 않는다 (Q-072 1번).
--   - 조용한 시간이어도 바로 (대기열 send_at = 지금, 202611050028).
--   - 한 사람에게 한 번: dedupe_key 가 일정마다 하나. 재실행해도 같다. 미투표자가 없으면 아무것도 만들지 않는다.
--   - 알림 시각 뒤에 가입한 사람은 받지 않는다 (재실행 때 늦게 받는 일이 없게, 표 칸 추가 없이 1회를 지킴).
--   - 부상자 제외는 private.is_injured_at 한 곳 (부상 표는 스프린트 04, 지금은 항상 아니오).
--   - 마감이 지난 일정은 건너뛴다 (예약 작업이 멈췄다가 늦게 돌아도 마감 뒤에 보내지 않음).
--
-- cleanup_notifications(p_now) — 하루 1번
--   - 알림함 줄: 만든 지 30일 지나면 삭제 (읽음 여부 무관, Q-041). 딸린 대기열 줄도 같이 삭제.
--     회원 탈퇴 알림(이름 남김)도 같다 (Q-072 3번).
--   - 대기열: 발송·건너뜀·실패 처리(sent_at) 후 30일 지나면 삭제 (S-18).
--
-- 두 함수 모두 앱 사용자와 service_role 은 실행할 수 없다. 예약 작업(pg_cron)만 부른다.

create function private.send_rsvp_reminders(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match record;
  v_recipients uuid[];
  v_count int := 0;
begin
  for v_match in
    select m.id, m.team_id, m.starts_at, m.rsvp_reminder_at
      from public.matches m
      join public.teams t on t.id = m.team_id
     where m.status = 'scheduled'
       and m.rsvp_reminder_at is not null
       and m.rsvp_reminder_at <= p_now
       and m.rsvp_deadline_at > p_now
       and t.dissolved_at is null
     order by m.rsvp_reminder_at, m.id
  loop
    select coalesce(array_agg(tm.user_id), '{}') into v_recipients
      from public.team_members tm
     where tm.team_id = v_match.team_id
       and tm.status = 'active'
       and tm.joined_at <= v_match.rsvp_reminder_at
       and not exists (
         select 1 from public.attendance_responses r
          where r.match_id = v_match.id and r.user_id = tm.user_id
       )
       and not private.is_injured_at(tm.user_id, p_now);

    v_count := v_count + private.notify(
      'rsvp_deadline_soon', v_recipients,
      v_match.team_id, 'match', v_match.id, '',
      null, jsonb_build_object('match_at', v_match.starts_at)
    );
  end loop;
  return v_count;
end;
$$;

create index matches_rsvp_reminder_pending on public.matches (rsvp_reminder_at)
  where status = 'scheduled' and rsvp_reminder_at is not null;

create function private.cleanup_notifications(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_notifications int;
  v_outbox int;
begin
  delete from public.notifications n
   where n.created_at < p_now - interval '30 days';
  get diagnostics v_notifications = row_count;

  delete from public.notification_outbox o
   where o.status <> 'pending'
     and o.sent_at < p_now - interval '30 days';
  get diagnostics v_outbox = row_count;

  return v_notifications + v_outbox;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.send_rsvp_reminders(timestamptz),
  private.cleanup_notifications(timestamptz)
from public, anon, authenticated, service_role;

-- 미투표 알림: 매분 (알림 시각은 분 단위가 아니어도 1분 안에 나간다)
select cron.unschedule(jobid) from cron.job where jobname = 'send-rsvp-reminders';
select cron.schedule(
  'send-rsvp-reminders',
  '* * * * *',
  $$select private.send_rsvp_reminders()$$
);

-- 알림 정리: 하루 1번 (UTC 19:13 = 한국 04:13)
select cron.unschedule(jobid) from cron.job where jobname = 'cleanup-notifications';
select cron.schedule(
  'cleanup-notifications',
  '13 19 * * *',
  $$select private.cleanup_notifications()$$
);
