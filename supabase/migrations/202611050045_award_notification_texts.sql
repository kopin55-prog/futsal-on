-- POM·오늘의 골·배치 미확정 알림 문구 (스프린트 03 4-6 / Q-075 14·15번, Q-076 2번)
--
--   award_poll_opened        "수고하셨어요! 오늘의 POM과 오늘의 골을 뽑아 주세요."  (S3-14 오픈 문구 초안)
--   award_results_announced  "오늘의 POM·오늘의 골 결과가 나왔어요!"              (Q-076 2번 추천 문구)
--   lineup_unconfirmed       "{일시} 경기가 시작됐는데 팀 배치가 아직 확정 전이에요. 확정 부탁드려요!" (builder 초안)
-- 문구에 사람 이름·득표수·실력 등급 없음. 누르면 일정 상세 (ref_type = 'match').
-- 조용한 시간: award_poll_opened 만 예외(바로, 202611050028). 나머지 둘은 일반 규칙(00:00~08:00 → 13:00).
-- award_deadline_soon 은 쓰지 않으므로 문구가 없다 (Q-075 14번).
-- 나머지 문구는 202611050039 그대로.

create or replace function private.notification_body(p_kind public.notification_kind, p_args jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_name text := p_args ->> 'name';
  v_when text := case when p_args ? 'match_at'
                      then private.match_time_label((p_args ->> 'match_at')::timestamptz) end;
  v_reason text := nullif(p_args ->> 'reason', '');
begin
  return case p_kind
    when 'match_created' then
      v_when || ' 경기가 열렸어요! 이번 주도 뛰어야죠, 참석 투표 부탁드려요.'
    when 'rsvp_deadline_soon' then
      v_when || ' 경기 참석 투표가 곧 마감돼요. 아직 투표 전이시네요, 참석하실 거죠?'
    when 'waitlist_promoted' then
      '자리가 났어요! ' || v_when || ' 경기 대기에서 참석으로 바뀌었어요.'
    when 'match_cancelled' then
      v_when || ' 경기가 취소됐어요.' || coalesce(' 사유: ' || v_reason, '')
    when 'join_request_received' then
      v_name || '님이 가입을 신청했어요. 확인 부탁드려요!'
    when 'join_request_decided' then
      case when (p_args ->> 'approved')::boolean
           then '가입이 승인됐어요! 이제 같이 뛰어요.'
           else '아쉽지만 이번 가입 신청은 승인되지 않았어요.' end
    when 'join_request_auto_declined' then
      '팀이 해체되었어요. 보내주신 가입 신청은 마무리됐어요.'
    when 'member_left' then
      v_name || '님이 팀을 떠났어요.'
    when 'member_account_deleted' then
      v_name || '님이 회원 탈퇴로 팀을 떠났어요.'
    when 'member_joined' then
      v_name || '님이 새로 합류했어요! 반갑게 맞아 주세요.'
    when 'team_dissolved' then
      '팀이 해체됐어요. 그동안 함께 뛰어 주셔서 고마워요.'
    when 'manager_assigned' then
      '운영진이 되셨어요! 팀 운영 잘 부탁드려요.'
    when 'manager_unassigned' then
      '운영진에서 팀원으로 바뀌었어요. 그동안 고생 많으셨어요.'
    when 'ownership_received' then
      '팀장을 넘겨받으셨어요! 이제 팀을 잘 이끌어 주세요.'
    when 'lineup_confirmed' then
      v_when || ' 경기 팀 배치가 나왔어요! 내 팀을 확인해 보세요.'
    when 'lineup_changed' then
      v_when || ' 경기 팀 배치가 바뀌었어요. 다시 확인해 주세요.'
    when 'lineup_unconfirmed' then
      v_when || ' 경기가 시작됐는데 팀 배치가 아직 확정 전이에요. 확정 부탁드려요!'
    when 'award_poll_opened' then
      '수고하셨어요! 오늘의 POM과 오늘의 골을 뽑아 주세요.'
    when 'award_results_announced' then
      '오늘의 POM·오늘의 골 결과가 나왔어요!'
    when 'member_removed' then
      case when v_name is not null
           -- 팀장·운영진용 (builder 초안, Q-073 11번 "같은 말투로 builder 초안")
           then v_name || '님이 팀에서 내보내졌어요.'
           else '팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요.' end
    else null
  end;
end;
$$;

revoke execute on function private.notification_body(public.notification_kind, jsonb)
from public, anon, authenticated, service_role;
