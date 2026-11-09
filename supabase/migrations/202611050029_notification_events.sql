-- 알림 연결 (스프린트 02 3-2·3-5·3-6 / docs/notifications.md, data-model.md 9장)
--
-- 모든 알림은 private.notify(202611050028) 한 곳으로 만든다. 받는 사람:
--   match_created            일정 자동 생성·직접 추가 → 그 팀 현재 팀원 전체, 직접 추가한 운영진 본인 제외 (Q-071 7번)
--   match_cancelled          일정 취소 → 참석·대기·불참 응답자 전원, 취소한 본인 제외, 사유 포함 (Q-071 7번, Q-072 5번)
--                            팀 해체로 취소되면 보내지 않는다(해체 알림만, Q-071 7번)
--   waitlist_promoted        대기 → 참석 자동 전환 → 승격된 본인 (사건 값 = promoted_at, lead 정리 L-06)
--   manager_assigned/unassigned  운영진 지정·해제 → 본인 (Q-022)
--   ownership_received       팀장 위임 → 새 팀장만. 기존 팀장에게 운영진 지정 알림 없음 (Q-067 15번)
--   member_removed           내보내기 → 내보내진 본인만 (운영진이어도 이 알림 하나, Q-067 15번).
--                            다른 운영진에게 알릴지는 Q-073 5번 대기 → 지금은 본인만
--   member_left              팀 탈퇴 → 남은 팀장·운영진, 이름 포함 (Q-071 9번)
--   join_request_received    가입 신청 → 팀장·운영진, 신청자 이름 포함
--   join_request_decided     승인·거절 → 신청자
--   member_joined            승인으로 합류(초대 코드 신청도 승인으로 합류) → 새 팀원 본인 뺀 팀원 전체, 이름 포함,
--                            알림함에만 (Q-071 9번, Q-072 4번)
--   team_dissolved           해체 → 해체 순간 팀원 전원, 해체한 팀장 제외 (Q-071 7번)
--   join_request_auto_declined  해체로 자동 거절된 대기 신청자 "팀이 해체되었어요" (Q-067 8번). 일반 거절 알림은 따로 없음
--   member_account_deleted   회원 탈퇴 → 소속 팀(해체 안 된 팀)마다 팀장·운영진, 이름 포함.
--                            Q-044 예외로 actor_id 를 비워 이름이 남는다 (Q-072 3번). 30일 정리는 다른 알림과 같음
--
-- 일정 알림은 matches 표의 트리거로 연결한다 (자동 생성·직접 추가·취소 경로가 모두 같은 표를 지나므로 한 곳).
-- 나머지는 각 서버 함수 안에서 같은 처리로 부른다 (이전 마이그레이션의 함수 본문 + 알림 한 줄).

-- ---------------------------------------------------------------------------
-- 사건 값: 시각을 마이크로초 정수로 (같은 사건 재실행은 같은 값, 다른 처리는 다른 값)
-- ---------------------------------------------------------------------------
create function private.notification_event(p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select floor(extract(epoch from p_at) * 1000000)::bigint::text
$$;

-- ---------------------------------------------------------------------------
-- 일정 생성·취소 알림 (matches 트리거)
-- ---------------------------------------------------------------------------
create function private.matches_notify_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'scheduled' then
    perform private.notify(
      'match_created',
      array_remove(private.team_member_ids(new.team_id), new.created_by),
      new.team_id, 'match', new.id, '',
      null, jsonb_build_object('match_at', new.starts_at)
    );
  end if;
  return null;
end;
$$;

create trigger matches_notify_created
after insert on public.matches
for each row execute function private.matches_notify_created();

create function private.matches_notify_cancelled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipients uuid[];
begin
  -- 해체로 취소된 일정은 해체 알림만 (dissolve_team 이 팀 해체 표시를 먼저 남긴다)
  if exists (select 1 from public.teams t where t.id = new.team_id and t.dissolved_at is not null) then
    return null;
  end if;
  select coalesce(array_agg(r.user_id), '{}') into v_recipients
    from public.attendance_responses r
   where r.match_id = new.id;
  perform private.notify(
    'match_cancelled',
    array_remove(v_recipients, new.cancelled_by),
    new.team_id, 'match', new.id, '',
    null, jsonb_build_object('match_at', new.starts_at, 'reason', new.cancel_reason)
  );
  return null;
end;
$$;

create trigger matches_notify_cancelled
after update of status on public.matches
for each row
when (old.status = 'scheduled' and new.status = 'cancelled')
execute function private.matches_notify_cancelled();

-- ---------------------------------------------------------------------------
-- 대기 → 참석 (202611050024 + 승격 알림)
-- ---------------------------------------------------------------------------
create or replace function private.promote_waitlisted(p_match_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match public.matches;
  v_open int;
  v_count int := 0;
  v_row record;
  v_promoted_at timestamptz;
begin
  select m.* into v_match from public.matches m where m.id = p_match_id;
  if v_match.id is null or v_match.status <> 'scheduled' or v_match.starts_at <= now() then
    return 0;
  end if;

  if v_match.capacity is null then
    -- 정원 없음: 대기는 생기지 않지만, 혹시 남아 있으면 모두 참석
    v_open := null;
  else
    select v_match.capacity - count(*) into v_open
      from public.attendance_responses r
     where r.match_id = p_match_id and r.state = 'attending';
    if v_open <= 0 then
      return 0;
    end if;
  end if;

  for v_row in
    select r.id, r.user_id
      from public.attendance_responses r
     where r.match_id = p_match_id and r.state = 'waitlisted'
     order by r.waitlisted_at, r.id
     limit v_open
  loop
    v_promoted_at := clock_timestamp();
    update public.attendance_responses
       set state = 'attending',
           waitlisted_at = null,
           promoted_at = v_promoted_at,
           updated_at = v_promoted_at
     where id = v_row.id;
    v_count := v_count + 1;
    -- 승격된 본인 (사건 값 = promoted_at → 같은 일정에서 다시 승격되면 다시 알림, lead 정리 L-06)
    perform private.notify(
      'waitlist_promoted', array[v_row.user_id],
      v_match.team_id, 'match', v_match.id, private.notification_event(v_promoted_at),
      null, jsonb_build_object('match_at', v_match.starts_at)
    );
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 운영진 지정·해제, 팀장 위임 (202611050006 + 알림)
-- ---------------------------------------------------------------------------
create or replace function public.appoint_manager(p_team_id uuid, p_user_id uuid)
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
  v_role := private.active_role(p_team_id, p_user_id);
  if v_role is null then
    raise exception 'target_not_member' using errcode = 'P0001';
  elsif v_role <> 'member' then
    raise exception 'already_manager' using errcode = 'P0001';
  end if;
  if (select count(*) from public.team_members m
       where m.team_id = p_team_id and m.status = 'active' and m.role = 'manager') >= 2 then
    raise exception 'manager_limit_reached' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'manager'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  perform private.notify('manager_assigned', array[p_user_id], p_team_id, 'team', p_team_id,
                         private.notification_event(now()));
end;
$$;

create or replace function public.dismiss_manager(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  perform private.lock_team_as_owner(p_team_id);
  if private.active_role(p_team_id, p_user_id) is distinct from 'manager' then
    raise exception 'target_not_manager' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'member'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  perform private.notify('manager_unassigned', array[p_user_id], p_team_id, 'team', p_team_id,
                         private.notification_event(now()));
end;
$$;

create or replace function public.transfer_ownership(p_team_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  perform private.lock_team_as_owner(p_team_id);
  if private.active_role(p_team_id, p_user_id) is distinct from 'manager' then
    raise exception 'target_not_manager' using errcode = 'P0001';
  end if;
  update public.team_members set role = 'manager'
   where team_id = p_team_id and user_id = v_uid and status = 'active';
  update public.team_members set role = 'owner'
   where team_id = p_team_id and user_id = p_user_id and status = 'active';
  -- 새 팀장에게만. 운영진이 된 기존 팀장에게 운영진 지정 알림 없음 (Q-067 15번)
  perform private.notify('ownership_received', array[p_user_id], p_team_id, 'team', p_team_id,
                         private.notification_event(now()));
end;
$$;

-- ---------------------------------------------------------------------------
-- 내보내기·팀 탈퇴 (202611050012 + 알림)
-- ---------------------------------------------------------------------------
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
  -- 내보내진 본인에게만 (운영진이었어도 이 알림 하나). 다른 운영진 알림은 Q-073 5번 대기
  perform private.notify('member_removed', array[p_user_id], p_team_id, 'team', p_team_id,
                         private.notification_event(now()));
end;
$$;

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
  -- 남은 팀장·운영진에게, 떠난 사람 이름 (actor_id = 떠난 사람, Q-044)
  perform private.notify('member_left', private.team_staff_ids(p_team_id), p_team_id, 'team', p_team_id,
                         v_uid::text || ':' || private.notification_event(now()), v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- 가입 신청·승인·거절 (202611050014 + 알림)
-- ---------------------------------------------------------------------------
create or replace function private.insert_join_request(
  p_uid uuid,
  p_team_id uuid,
  p_via public.join_via,
  p_invite_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if exists (
    select 1 from public.team_members m
     where m.team_id = p_team_id and m.user_id = p_uid and m.status = 'active'
  ) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.join_requests r
     where r.team_id = p_team_id and r.user_id = p_uid and r.status = 'pending'
  ) then
    raise exception 'request_already_pending' using errcode = 'P0001';
  end if;
  perform private.check_join_limits(p_team_id, p_uid);
  begin
    insert into public.join_requests (team_id, user_id, via, invite_id)
    values (p_team_id, p_uid, p_via, p_invite_id)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'request_already_pending' using errcode = 'P0001';
  end;
  -- 팀장·운영진에게, 신청자 이름 (actor_id = 신청자, Q-044)
  perform private.notify('join_request_received', private.team_staff_ids(p_team_id), p_team_id,
                         'join_request', v_id, '', p_uid);
  return v_id;
end;
$$;

create or replace function public.decide_join_request(p_request_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_req public.join_requests;
  v_member_id uuid;
begin
  select r.* into v_req from public.join_requests r where r.id = p_request_id;
  if v_req.id is null or not private.is_team_staff(v_req.team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  -- 같은 팀의 승인·해체·역할 변경을 한 줄로 세운다 (인원 상한 검사가 엇갈리지 않게).
  perform 1 from public.teams t where t.id = v_req.team_id for update;
  select r.* into v_req from public.join_requests r where r.id = p_request_id for update;
  if v_req.status <> 'pending' then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;
  if p_approve is null then
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;

  if p_approve and not exists (
    select 1 from public.team_members m
     where m.team_id = v_req.team_id and m.user_id = v_req.user_id and m.status = 'active'
  ) then
    perform private.check_join_limits(v_req.team_id, v_req.user_id);
    insert into public.team_members (team_id, user_id, role, status)
    values (v_req.team_id, v_req.user_id, 'member', 'active')
    returning id into v_member_id;
  end if;

  update public.join_requests
     set status = case when p_approve then 'approved'::public.join_request_status
                       else 'rejected'::public.join_request_status end,
         decided_by = v_uid,
         decided_at = now()
   where id = v_req.id;

  -- 신청자에게 승인·거절 (사유 없음)
  perform private.notify('join_request_decided', array[v_req.user_id], v_req.team_id,
                         'join_request', v_req.id, '', null,
                         jsonb_build_object('approved', p_approve));
  -- 새로 합류했으면 본인 뺀 팀원 전체에게 합류 알림 (알림함에만, Q-071 9번, Q-072 4번)
  if v_member_id is not null then
    perform private.notify('member_joined', private.team_member_ids(v_req.team_id), v_req.team_id,
                           'team', v_req.team_id, v_member_id::text, v_req.user_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 해체 (202611050023 + 알림)
-- ---------------------------------------------------------------------------
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
  -- TODO(스프린트 03): 남은 최근 10경기 상세 삭제 (Q-061 4번)
end;
$$;

-- ---------------------------------------------------------------------------
-- 회원 탈퇴 (202611050025 + 팀 알림). service_role 전용 그대로.
-- ---------------------------------------------------------------------------
create or replace function public.delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocker text;
  v_name text;
  v_team_id uuid;
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

  -- 소속 팀(해체 안 된 팀)마다 팀장·운영진에게 이름이 든 탈퇴 알림 (Q-067 12번, Q-071 9번).
  -- Q-044 예외: actor_id 를 비워 탈퇴 뒤에도 이름이 남는다 (Q-072 3번). 30일 뒤 다른 알림과 같이 정리.
  select p.display_name into v_name from public.profiles p where p.user_id = p_user_id;
  if v_name is not null then
    for v_team_id in
      select m.team_id
        from public.team_members m
        join public.teams t on t.id = m.team_id
       where m.user_id = p_user_id and m.status = 'active' and t.dissolved_at is null
       order by m.team_id
    loop
      perform private.notify('member_account_deleted',
                             array_remove(private.team_staff_ids(v_team_id), p_user_id),
                             v_team_id, 'team', v_team_id, p_user_id::text,
                             null, jsonb_build_object('name', v_name));
    end loop;
  end if;

  -- 시작 전 일정의 응답을 먼저 지우고, 참석이었으면 대기 1번 자동 참석 + 알림 (2-5 절차 3, Q-038).
  -- 나머지(시작한 경기 응답 등)는 계정 삭제 연쇄로 지워진다.
  perform private.remove_upcoming_responses(p_user_id, null);

  -- TODO(팀 나누기 단계): lineup_change_logs before/after 안의 이 사람 ID 정리 (2-5)
  -- TODO(로고 사진 단계): 본인 소유 저장소 파일 삭제 (1차는 개인 사진 없음)

  -- 계정을 지우면 붙은 로그인 방법(auth.identities)과 profiles 이하 모든 줄이 같이 지워진다.
  -- 이 사람 이름이 든 다른 사람의 알림(actor_id = 이 사람)도 같이 지워진다 (Q-044).
  delete from auth.users u where u.id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.notification_event(timestamptz),
  private.matches_notify_created(),
  private.matches_notify_cancelled(),
  private.promote_waitlisted(uuid),
  private.insert_join_request(uuid, uuid, public.join_via, uuid)
from public, anon, authenticated, service_role;

revoke execute on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;
