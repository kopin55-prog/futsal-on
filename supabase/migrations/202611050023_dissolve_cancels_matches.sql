-- 팀 해체 때 다가오는 일정 취소 (스프린트 02 1-7 / data-model.md 3-8)
--
-- dissolve_team 이 같은 처리 안에서 시작 전 일정(예정 상태)을 모두 취소한다. 취소한 사람 = 해체한 팀장.
-- 이미 시작한 경기·끝난 경기는 그대로 (경기 종료 처리·지난 경기 상세 삭제는 스프린트 03, Q-061 4번).
-- 해체된 팀은 자동 생성 대상에서 빠진다 (202611050021). 나머지는 202611050016 과 같다.

create or replace function public.dissolve_team(p_team_id uuid, p_confirm_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_name text;
begin
  perform private.lock_team_as_owner(p_team_id);
  select t.name into v_name from public.teams t where t.id = p_team_id;
  if not private.dissolve_confirmation_matches(v_name, p_confirm_name) then
    raise exception 'dissolve_confirmation_mismatch' using errcode = 'P0001';
  end if;

  update public.teams set dissolved_at = now(), logo_image_path = null where id = p_team_id;

  update public.team_members
     set status = 'dissolved', ended_at = now()
   where team_id = p_team_id and status = 'active';

  -- 실력 등급·그룹·라이벌은 팀 전체 삭제 (Q-015)
  delete from public.skill_ratings where team_id = p_team_id;
  delete from public.pairing_rules where team_id = p_team_id;

  -- 대기 신청 자동 거절 (Q-067 8번). 처리한 관리자는 없음.
  update public.join_requests
     set status = 'rejected', decided_at = now(), decided_by = null
   where team_id = p_team_id and status = 'pending';

  -- 초대 코드 무효화
  update public.team_invites set revoked_at = now()
   where team_id = p_team_id and revoked_at is null;

  -- 다가오는 일정 취소 (3-8). 해체 때는 일정 취소 알림을 따로 보내지 않는다 (Q-071 7번).
  update public.matches
     set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid
   where team_id = p_team_id and status = 'scheduled' and starts_at > now();

  -- TODO(알림 단계): 팀원 전원 team_dissolved 알림(해체한 팀장 제외, Q-071 7번),
  --   대기 신청자 "팀이 해체되었어요" 알림 (Q-067 8번)
  -- TODO(스프린트 03): 남은 최근 10경기 상세 삭제 (Q-061 4번)
end;
$$;

revoke execute on function public.dissolve_team(uuid, text) from public, anon;
grant execute on function public.dissolve_team(uuid, text) to authenticated;
