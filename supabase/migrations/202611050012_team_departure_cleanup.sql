-- 팀 탈퇴·내보내기 때 실력 등급·그룹 소속 삭제 (data-model.md 3-8, Q-015)
--
-- 외래 키 연쇄가 아니라 상태 변경이므로 팀 탈퇴·내보내기 서버 함수가 같은 처리 안에서 지운다.
-- 그룹·라이벌에서 빠져 2명 미만이 된 설정은 pairing_rule_members 트리거가 끈다.
-- 다가오는 일정 참석 응답 정리(대기 1번 자동 전환)는 일정 단계에서 이 도우미에 추가한다.

create function private.cleanup_departed_member(p_team_id uuid, p_user_id uuid)
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

  -- TODO(일정 단계): 다가오는 일정 참석 응답 삭제, 참석이었으면 대기 1번 자동 전환 + 알림 (3-8, Q-038)
end;
$$;

-- 내보내기: 팀장만, 운영진도 바로 (Q-018)
create or replace function public.remove_member(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
begin
  perform private.lock_team_as_owner(p_team_id);
  if p_user_id = v_uid then
    raise exception 'cannot_target_self' using errcode = 'P0001';
  end if;
  v_role := private.active_role(p_team_id, p_user_id);
  if v_role is null then
    raise exception 'target_not_member' using errcode = 'P0001';
  end if;
  update public.team_members
     set status = 'removed', ended_at = now(), ended_by = v_uid
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  perform private.cleanup_departed_member(p_team_id, p_user_id);
  -- TODO(알림 단계): member_removed (Q-022)
end;
$$;

-- 팀 탈퇴: 본인. 팀장은 위임 또는 해체 전에는 불가 (Q-037)
create or replace function public.leave_team(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
begin
  perform 1 from public.teams t where t.id = p_team_id for update;
  v_role := private.active_role(p_team_id, v_uid);
  if v_role is null or not private.is_team_member(p_team_id) then
    raise exception 'not_member' using errcode = 'P0001';
  end if;
  if v_role = 'owner' then
    raise exception 'owner_must_transfer_or_dissolve' using errcode = 'P0001';
  end if;
  update public.team_members
     set status = 'left', ended_at = now()
   where team_id = p_team_id and user_id = v_uid and status = 'active';
  perform private.cleanup_departed_member(p_team_id, v_uid);
  -- TODO(알림 단계): member_left
end;
$$;

revoke execute on all functions in schema private from public, anon;
