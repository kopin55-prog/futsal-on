-- POM·오늘의 골 투표 함수 (스프린트 03 4-4 / data-model.md 6장 / Q-027 M-08, Q-075 13번)
--
-- public.cast_award_vote(match_id, category, candidate_id)
--   - 본인만 (auth.uid()), 프로필 필요.
--   - 투표할 수 있는 사람: 그 회차 대상자이면서 지금 그 팀 팀원 (6-2, 해체된 팀은 공용 확인 함수가 거짓).
--   - 진행 중만: status = open 이고 서버 시각이 마감 전.
--   - 항목(pom / goal_of_the_day)마다 따로 한 표. 같은 사람을 두 항목에 찍을 수 있음 (Q-075 13번 (1)(2)).
--   - 후보: 그 회차 대상자 중 본인이 아니고 지금 그 팀 팀원인 사람 (떠난 사람 후보 제외, Q-075 13번 (3)).
--   - 한 처리 안에서 참여 표시 1줄 + 득표 +1. 바꾸기·취소 없음 (같은 항목 두 번째는 already_voted).
--   - 아무것도 돌려주지 않는다 (득표수·순위 없음, 6-4 security 반영). 후보 값을 로그에 남기지 않는다 (11장 12번).
--   - 마감 처리(202611050048)와 겹치지 않게 회차 줄을 공유 잠금으로 잡는다 (마감 처리는 배타 잠금).
-- 오류: award_poll_not_found(회차 없음·팀원 아님 구분 없음) / award_not_participant / award_poll_closed /
--       award_invalid_category / award_self_vote / award_invalid_candidate / award_already_voted

create function public.cast_award_vote(p_match_id uuid, p_category text, p_candidate_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_poll public.award_polls;
  v_category public.award_category;
begin
  select p.* into v_poll from public.award_polls p where p.match_id = p_match_id for share;
  if v_poll.match_id is null or not private.is_team_member(v_poll.team_id) then
    raise exception 'award_poll_not_found' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.award_participants a
                  where a.match_id = p_match_id and a.user_id = v_uid) then
    raise exception 'award_not_participant' using errcode = 'P0001';
  end if;
  if v_poll.status <> 'open' or clock_timestamp() >= v_poll.closes_at then
    raise exception 'award_poll_closed' using errcode = 'P0001';
  end if;
  if p_category is null or p_category not in ('pom', 'goal_of_the_day') then
    raise exception 'award_invalid_category' using errcode = 'P0001';
  end if;
  v_category := p_category::public.award_category;
  if p_candidate_id is null then
    raise exception 'award_invalid_candidate' using errcode = 'P0001';
  end if;
  if p_candidate_id = v_uid then
    raise exception 'award_self_vote' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.award_participants a
      join public.team_members tm
        on tm.team_id = v_poll.team_id and tm.user_id = a.user_id and tm.status = 'active'
     where a.match_id = p_match_id and a.user_id = p_candidate_id
  ) then
    raise exception 'award_invalid_candidate' using errcode = 'P0001';
  end if;

  begin
    insert into public.award_ballot_receipts (match_id, category, voter_id)
    values (p_match_id, v_category, v_uid);
  exception when unique_violation then
    raise exception 'award_already_voted' using errcode = 'P0001';
  end;

  update public.award_tallies t
     set vote_count = t.vote_count + 1
   where t.match_id = p_match_id and t.category = v_category and t.candidate_id = p_candidate_id;
  if not found then
    -- 열 때 대상자 전원 0표 줄을 만들므로 생기지 않는 경우 (생기면 참여 표시도 되돌린다)
    raise exception 'award_invalid_candidate' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on function public.cast_award_vote(uuid, text, uuid) from public, anon;
grant execute on function public.cast_award_vote(uuid, text, uuid) to authenticated;
