-- 투표 설정: POM·오늘의 골 발표 시각 (스프린트 03 4단계 / data-model.md v4.5 3-2 / Q-076 1번)
--
-- team_settings.award_announce_time  발표 시각 (한국 시간, 경기 종료일 다음날). 기본 15:00, 새벽 포함 자유 선택.
--   - 투표 마감 = 발표 시각. 투표가 열릴 때(경기 종료 처리) 그때 설정으로 정한다 (202611050046).
--   - 설정을 바꿔도 이미 열린 투표의 마감은 그대로 (일정마다 따로 고르지 않음).
--   - 화면은 경기 설정과 따로 "투표 설정". 바꾸기는 관리자(팀장·운영진)만, 서버 함수 update_award_settings 로.
--   - 읽기는 기존 team_settings 규칙 그대로 (그 팀 팀원).
--   - 분 단위로 저장한다 (초는 버림).

alter table public.team_settings
  add column award_announce_time time not null default '15:00';

-- ---------------------------------------------------------------------------
-- 투표 설정 바꾸기: 관리자. 바뀐 발표 시각을 돌려준다.
-- ---------------------------------------------------------------------------
create function public.update_award_settings(p_team_id uuid, p_award_announce_time time)
returns time
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_time time;
begin
  if p_award_announce_time is null then
    raise exception 'invalid_award_settings' using errcode = 'P0001';
  end if;
  perform private.lock_team_as_staff(p_team_id);
  v_time := date_trunc('minute', p_award_announce_time);

  insert into public.team_settings as s (team_id, award_announce_time, updated_by, updated_at)
  values (p_team_id, v_time, v_uid, now())
  on conflict (team_id) do update
    set award_announce_time = excluded.award_announce_time,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  return v_time;
end;
$$;

revoke execute on function public.update_award_settings(uuid, time) from public, anon;
grant execute on function public.update_award_settings(uuid, time) to authenticated;
