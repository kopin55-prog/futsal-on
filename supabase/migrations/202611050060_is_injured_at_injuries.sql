-- private.is_injured_at 을 부상 표로 교체 (스프린트 04 1-4 / data-model.md v4.5 8-2, Q-062 2번, Q-072 1번)
--
-- 202611050027 의 자리 함수(항상 아니오)만 바꾼다. 부르는 곳은 그대로:
--   - 미투표 알림 private.send_rsvp_reminders: 그 시각 부상자는 받지 않음 (202611050030)
--   - 참여율 처리 private.close_out_attendance_vote: 마감 시각 부상자는 응답 +1 (202611050049)
-- 판단: 그 시각에 등록돼 있었고(등록일 ≤ 그 시각의 한국 날짜) 아직 회복 전(active, 또는 회복 시각이 그 시각 뒤)인
-- 부상 줄이 있으면 예. 동의 철회·회원 탈퇴로 지워진 기록은 없으므로 아니오.
-- 실행 권한은 그대로(앱 사용자·service_role 불가, CREATE OR REPLACE 는 권한을 유지한다).

create or replace function private.is_injured_at(p_user_id uuid, p_at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.injuries i
     where i.user_id = p_user_id
       and i.started_on <= (p_at at time zone 'Asia/Seoul')::date
       and (i.status = 'active' or i.recovered_at > p_at)
  )
$$;

revoke execute on function private.is_injured_at(uuid, timestamptz)
from public, anon, authenticated, service_role;
