-- 정기 운동 종료 시각 필수 (Q-073 8번, data-model.md 3-1 regular_end_time, decisions.md 2026-11-09)
--
-- - 시작 시각을 정하면 종료 시각도 있어야 한다. 팀 만들기·팀 정보 수정·관리자의 표 직접 수정 모두 같은 검사.
-- - 표 검사(check)로 넣으면 종료가 비어 있는 기존 팀은 정기 운동과 상관없는 수정(이름·모집 등)까지 막히므로,
--   정기 운동 칸을 새로 넣거나 바꿀 때만 검사하는 트리거로 둔다. 오류는 check_violation 으로 내서
--   create_team·update_team_info 가 지금처럼 invalid_regular_schedule 로 바꿔 돌려준다.
-- - 종료가 비어 있는 기존 팀은 그대로 둔다(자동 일정이 생기지 않는 상태 유지, 202611050021). 처리 방안은 lead 보고.
--   개발 DB 에는 해당 팀이 없다(2026-11-09 확인).
-- - 화면은 시작을 고르면 종료를 시작 2시간 뒤로 기본 채운다(앱). 일정 최대 24시간은 matches 표·create_match 에 이미 있음.

create function private.teams_regular_end_required()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.regular_start_time is not null and new.regular_end_time is null
     and (tg_op = 'INSERT'
          or old.regular_weekday is distinct from new.regular_weekday
          or old.regular_start_time is distinct from new.regular_start_time
          or old.regular_end_time is distinct from new.regular_end_time) then
    raise exception 'teams_regular_end_required' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger teams_regular_end_required
before insert or update of regular_weekday, regular_start_time, regular_end_time on public.teams
for each row execute function private.teams_regular_end_required();

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.teams_regular_end_required()
from public, anon, authenticated, service_role;
