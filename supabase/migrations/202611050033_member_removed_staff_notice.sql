-- 내보내기 알림: 내보내진 본인 + 팀장·운영진 모두, 내보낸 사람 제외 (Q-073 6번, decisions.md 2026-11-09)
--
-- - 종류는 같은 member_removed 를 쓴다 (data-model 9장 종류 목록을 늘리지 않음). 문구만 받는 사람에 따라 다르다.
--     본인:          "팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요." (Q-073 11번 승인 임시 문구)
--     팀장·운영진:   "{이름}님이 팀에서 내보내졌어요."  (builder 초안, 같은 말투 — kopn 확인 대기)
-- - 팀장·운영진용은 이름이 들어가므로 actor_id = 내보내진 사람 (Q-044: 그 사람이 회원 탈퇴하면 같이 지워짐).
-- - 받는 사람: 내보낸 뒤의 현재 팀장·운영진에서 내보낸 사람을 뺀다. 내보내진 사람은 이미 팀원이 아니라 빠진다.
-- - 사건 값에 내보내진 사람 ID 를 넣어 같은 때 여러 명을 내보내도 각각 알림 (lead 정리 L-06).

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
    when 'member_removed' then
      case when v_name is not null
           -- 팀장·운영진용 (builder 초안, Q-073 11번 "같은 말투로 builder 초안")
           then v_name || '님이 팀에서 내보내졌어요.'
           else '팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요.' end
    else null
  end;
end;
$$;

create or replace function public.remove_member(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_role public.team_role;
  v_event text;
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
  v_event := private.notification_event(now());
  -- 내보내진 본인 (운영진이었어도 이 알림 하나, Q-067 15번)
  perform private.notify('member_removed', array[p_user_id], p_team_id, 'team', p_team_id, v_event);
  -- 팀장·운영진 모두, 내보낸 사람 제외, 이름 포함 (Q-073 6번)
  perform private.notify('member_removed', array_remove(private.team_staff_ids(p_team_id), v_uid),
                         p_team_id, 'team', p_team_id, p_user_id::text || ':' || v_event, p_user_id);
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.notification_body(public.notification_kind, jsonb)
from public, anon, authenticated, service_role;
revoke execute on function public.remove_member(uuid, uuid) from public, anon;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
