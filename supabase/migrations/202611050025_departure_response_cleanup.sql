-- 떠나는 사람의 참석 응답 정리 (스프린트 02 2-2 / data-model.md 2-5 절차 3, 3-8 / Q-038, Q-071 5번)
--
-- 팀 탈퇴·내보내기·회원 탈퇴 때 경기 시작 전 일정(취소된 일정 포함)의 그 사람 응답을 지운다.
-- 지운 응답이 "참석"이었으면 마감 뒤라도 경기 시작 전이면 대기 1번부터 자동 참석 (Q-071 5번).
-- 이미 시작한 경기의 응답은 그대로 둔다 (참여율 처리가 시작 시각 기준으로 센다, 7-7).
-- 스프린트 01 TODO 3곳(202611050006·202611050007·202611050012) 해소.
--
-- 잠금 순서: (팀 탈퇴·내보내기는 이미 팀 줄 배타 잠금) → 일정 줄을 id 순서로 배타 잠금 → 응답 삭제 → 자동 참석.

-- ---------------------------------------------------------------------------
-- 한 사람의 시작 전 응답 정리. p_team_id 가 null 이면 모든 팀 (회원 탈퇴).
-- ---------------------------------------------------------------------------
create function private.remove_upcoming_responses(p_user_id uuid, p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match_id uuid;
  v_state public.attendance_state;
begin
  for v_match_id in
    select m.id
      from public.matches m
      join public.attendance_responses r on r.match_id = m.id and r.user_id = p_user_id
     where (p_team_id is null or m.team_id = p_team_id)
       and m.starts_at > now()
     order by m.id
     for update of m
  loop
    delete from public.attendance_responses r
     where r.match_id = v_match_id and r.user_id = p_user_id
    returning r.state into v_state;
    if v_state = 'attending' then
      perform private.promote_waitlisted(v_match_id);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 탈퇴·내보내기 공통 정리 (202611050012 + 참석 응답)
-- ---------------------------------------------------------------------------
create or replace function private.cleanup_departed_member(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.skill_ratings s
   where s.team_id = p_team_id and s.user_id = p_user_id;

  delete from public.pairing_rule_members m
   using public.pairing_rules r
   where r.id = m.rule_id and r.team_id = p_team_id and m.user_id = p_user_id;

  -- 시작 전 일정 응답 삭제, 참석이었으면 대기 1번 자동 참석 (3-8, Q-038, Q-071 5번)
  perform private.remove_upcoming_responses(p_user_id, p_team_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 회원 탈퇴 (202611050007 + 참석 응답). service_role 전용 그대로.
-- ---------------------------------------------------------------------------
create or replace function public.delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocker text;
begin
  -- 같은 사람의 동시 처리 방지
  perform 1 from auth.users u where u.id = p_user_id for update;
  if not found then
    raise exception 'account_not_found' using errcode = 'P0001';
  end if;

  v_blocker := public.account_deletion_blocker(p_user_id);
  if v_blocker is not null then
    raise exception '%', v_blocker using errcode = 'P0001';
  end if;

  -- 시작 전 일정의 응답을 먼저 지우고, 참석이었으면 대기 1번 자동 참석 (2-5 절차 3, Q-038).
  -- 나머지(시작한 경기 응답 등)는 계정 삭제 연쇄로 지워진다.
  perform private.remove_upcoming_responses(p_user_id, null);

  -- TODO(팀 나누기 단계): lineup_change_logs before/after 안의 이 사람 ID 정리 (2-5)
  -- TODO(로고 사진 단계): 본인 소유 저장소 파일 삭제 (1차는 개인 사진 없음)

  -- 계정을 지우면 붙은 로그인 방법(auth.identities)과 profiles 이하 모든 줄이 같이 지워진다.
  delete from auth.users u where u.id = p_user_id;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.remove_upcoming_responses(uuid, uuid),
  private.cleanup_departed_member(uuid, uuid)
from authenticated, service_role;
revoke execute on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;
