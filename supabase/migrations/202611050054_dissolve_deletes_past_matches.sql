-- 팀 해체 시 지난 경기 상세 삭제 (스프린트 03 7-3 / data-model.md v4.5 3-8·7-5 / Q-061 4번, Q-076 5번)
--
-- public.dissolve_team (202611050051) 의 TODO 해소. 해체 처리 안의 순서:
--   (1) 끝났지만 경기 종료 처리 전인 경기 → 출석 처리 먼저 (투표는 열지 않음, 202611050051)
--   (2) 진행 중 투표 회차 → 무효(삭제, 수상 반영 없음, 202611050051)
--   (3) 종료 시각이 지난 그 팀 일정 전부(취소된 일정 포함) 삭제 → 배치·투표·출석 기록 등 딸린 줄이 같이 지워짐
--   (4) 그 뒤 기존 처리 (해체 표시, 소속, 실력 등급·그룹, 가입 신청, 초대 코드, 다가오는 일정 취소, 알림)
-- 시즌 카운트·월간 출석 수·팀 월간 경기 수·참석 투표 참여율은 남는다.
-- 진행 중(시작했고 안 끝남) 일정과 다가오는 일정(해체로 취소됨)은 지난 경기가 아니라 이 처리에서 지우지 않는다.

create or replace function public.dissolve_team(p_team_id uuid, p_confirm_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_name text;
  v_members uuid[];
  v_applicants uuid[];
  v_requests uuid[];
  i int;
  v_match_id uuid;
begin
  perform private.lock_team_as_owner(p_team_id);
  select t.name into v_name from public.teams t where t.id = p_team_id;
  if not private.dissolve_confirmation_matches(v_name, p_confirm_name) then
    raise exception 'dissolve_confirmation_mismatch' using errcode = 'P0001';
  end if;

  -- 알림 받을 사람을 해체 전에 정해 둔다
  v_members := array_remove(private.team_member_ids(p_team_id), v_uid);
  select coalesce(array_agg(r.user_id order by r.id), '{}'), coalesce(array_agg(r.id order by r.id), '{}')
    into v_applicants, v_requests
    from public.join_requests r
   where r.team_id = p_team_id and r.status = 'pending';

  -- (1) 이미 끝났는데 아직 경기 종료 처리 전인 경기: 해체 전에 출석 처리 (투표는 열지 않음, Q-076 5번)
  for v_match_id in
    select m.id from public.matches m
     where m.team_id = p_team_id and m.status = 'scheduled'
       and m.ends_at <= now() and m.closed_out_at is null
     order by m.ends_at, m.id
     for update
  loop
    perform private.close_out_match(v_match_id, false);
  end loop;

  -- (2) 진행 중 POM·오늘의 골 투표는 전부 무효 (폐기, 수상 반영 없음, Q-076 5번).
  -- 회차를 지우면 대상자·참여 표시·득표가 같이 지워진다.
  delete from public.award_polls where team_id = p_team_id and status = 'open';

  -- (3) 지난 경기 상세 삭제 (Q-061 4번, 7-5). 위 두 처리 뒤라 끝난 경기는 모두 카운트 반영이 끝난 상태.
  -- 종료 시각이 지난 일정(취소된 일정 포함)을 지우면 딸린 줄이 외래 키로 같이 지워진다.
  -- 반영 전 경기가 남아 있으면(위 처리 뒤라 있을 수 없음) 지우지 않는다.
  delete from public.matches m
   where m.team_id = p_team_id
     and m.ends_at <= now()
     and (m.status = 'cancelled'
          or (m.closed_out_at is not null
              and not exists (select 1 from public.award_polls p
                               where p.match_id = m.id and p.status <> 'closed')));

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

  -- 다가오는 일정 취소 (3-8). 해체 때는 일정 취소 알림을 따로 보내지 않는다 (Q-071 7번, 트리거가 해체 팀을 건너뜀).
  update public.matches
     set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid
   where team_id = p_team_id and status = 'scheduled' and starts_at > now();

  -- 해체 순간의 팀원 전원(해체한 팀장 제외, Q-071 7번)
  perform private.notify('team_dissolved', v_members, p_team_id, 'team', p_team_id, '');
  -- 자동 거절된 대기 신청자 "팀이 해체되었어요" (Q-067 8번)
  for i in 1 .. coalesce(array_length(v_requests, 1), 0) loop
    perform private.notify('join_request_auto_declined', array[v_applicants[i]], p_team_id,
                           'join_request', v_requests[i], '');
  end loop;
end;
$$;
