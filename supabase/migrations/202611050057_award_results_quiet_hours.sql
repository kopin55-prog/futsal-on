-- 결과 발표 알림은 조용한 시간에도 바로 푸시 (Q-077 1번, 2026-11-10)
--
-- 팀이 정한 발표 시각이 새벽(00:00~08:00)이어도 award_results_announced 는 그 시각에 바로 보낸다.
-- 조용한 시간 예외: rsvp_deadline_soon, award_poll_opened, award_results_announced.
-- create or replace 이므로 기존 권한(실행 권한 회수)은 그대로 유지된다.

create or replace function private.notification_send_at(p_kind public.notification_kind, p_at timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select case
    when p_kind in ('rsvp_deadline_soon', 'award_poll_opened', 'award_results_announced') then p_at
    when (p_at at time zone 'Asia/Seoul')::time < time '08:00' then
      ((p_at at time zone 'Asia/Seoul')::date + time '13:00') at time zone 'Asia/Seoul'
    else p_at
  end
$$;
