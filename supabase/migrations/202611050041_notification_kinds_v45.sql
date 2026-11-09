-- 알림 종류 2개 추가 (data-model.md v4.5 9장 / Q-076 2번, Q-075 15번)
--
--   award_results_announced  POM·오늘의 골 결과 발표 (발표 시각에 투표 대상자에게)
--   lineup_unconfirmed       경기 시작 때 배치 미확정 (팀장·운영진에게 1회)
--
-- 새 enum 값은 값을 추가한 트랜잭션 안에서 쓸 수 없으므로 이 파일은 값 추가만 한다.
-- 문구는 202611050045, 보내는 곳은 202611050046·202611050048·202611050049.

alter type public.notification_kind add value if not exists 'award_results_announced';
alter type public.notification_kind add value if not exists 'lineup_unconfirmed';
