-- 참석 투표 (스프린트 02 2-1 / data-model.md 4-2 / Q-038, Q-071 5번, lead 정리 qa L-14)
--
-- respond_attendance(match, attending)
--   - 본인만 (다른 사람 ID 를 받지 않는다). 대리 응답·"미투표"로 되돌리기 없음 (Q-071 5번):
--     앱에는 표 쓰기 권한이 없고, 이 함수는 참석/불참만 받는다.
--   - 그 팀 현재 팀원만. 해체된 팀은 팀원 확인에서 거짓 → not_permitted. 취소된 일정 거절.
--   - 마감 시각 정각부터 거절 (서버 시각, lead 정리 L-14).
--   - 참석: 정원이 비었고 대기가 없으면 참석, 아니면 대기 (waitlisted_at = 누른 시각, 순번 기준).
--   - 불참: 참석이었으면 대기 1번부터 빈자리만큼 자동 참석 (promoted_at). 대기였으면 뒤 순번이 하나씩 당겨진다
--     (순번은 waitlisted_at 순서로 계산하므로 따로 고칠 것이 없다).
--   - 같은 응답을 다시 누르면 아무것도 바뀌지 않는다 (줄·순번·시각 그대로).
--   - 동시에 눌러도 정원을 넘지 않도록 팀 줄(공유 잠금) → 일정 줄(배타 잠금) 순서로 잠근다.
--     팀 탈퇴·내보내기·해체·일정 취소는 팀 줄을 배타 잠금하므로, 떠나는 중인 사람의 응답이 새로 생기지 않는다.
--   - responded_at = 처음 응답, updated_at = 마지막으로 바뀐 시각 (자동 참석 포함). 둘 다 실제 시각(clock_timestamp)
--     이라 같은 트랜잭션 시작 시각끼리 순서가 뒤바뀌지 않는다.
-- 부상 중인 사람의 "복귀 확인 후 참석"은 부상 표가 생기는 스프린트 04 에서 붙인다.

-- ---------------------------------------------------------------------------
-- 빈자리만큼 대기 앞 순번부터 참석으로 (참석 투표·떠나는 사람 정리 공통)
-- 부르는 쪽이 일정 줄을 잠근 상태여야 한다. 취소된 일정·시작한 경기는 아무것도 하지 않는다.
-- 마감 뒤라도 시작 전이면 자동 참석 (Q-071 5번).
-- ---------------------------------------------------------------------------
create function private.promote_waitlisted(p_match_id uuid)
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
    select r.id
      from public.attendance_responses r
     where r.match_id = p_match_id and r.state = 'waitlisted'
     order by r.waitlisted_at, r.id
     limit v_open
  loop
    update public.attendance_responses
       set state = 'attending',
           waitlisted_at = null,
           promoted_at = clock_timestamp(),
           updated_at = clock_timestamp()
     where id = v_row.id;
    v_count := v_count + 1;
    -- TODO(알림 단계): waitlist_promoted (승격된 본인, dedupe 키에 promoted_at, lead 정리 L-06)
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 참석 투표 (본인). 저장된 결과 상태를 돌려준다 (참석 / 대기 / 불참).
-- ---------------------------------------------------------------------------
create function public.respond_attendance(p_match_id uuid, p_attending boolean)
returns public.attendance_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
  v_match public.matches;
  v_current public.attendance_responses;
  v_new public.attendance_state;
  v_attending int;
  v_has_waitlist boolean;
begin
  if p_attending is null then
    raise exception 'invalid_attendance' using errcode = 'P0001';
  end if;

  select m.team_id into v_team_id from public.matches m where m.id = p_match_id;
  -- 없는 일정·다른 팀 일정은 구분하지 않고 거절
  if v_team_id is null then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  perform 1 from public.teams t where t.id = v_team_id for share;
  if not private.is_team_member(v_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;

  select m.* into v_match from public.matches m where m.id = p_match_id for update;
  if v_match.status = 'cancelled' then
    raise exception 'match_cancelled' using errcode = 'P0001';
  end if;
  -- 마감 정각부터 거절 (서버 시각)
  if now() >= v_match.rsvp_deadline_at then
    raise exception 'rsvp_closed' using errcode = 'P0001';
  end if;

  select r.* into v_current
    from public.attendance_responses r
   where r.match_id = p_match_id and r.user_id = v_uid;

  if p_attending then
    -- 이미 참석·대기면 그대로 (연타)
    if v_current.state in ('attending', 'waitlisted') then
      return v_current.state;
    end if;
    select count(*) into v_attending
      from public.attendance_responses r
     where r.match_id = p_match_id and r.state = 'attending';
    select exists (
      select 1 from public.attendance_responses r
       where r.match_id = p_match_id and r.state = 'waitlisted'
    ) into v_has_waitlist;
    if v_match.capacity is null or (v_attending < v_match.capacity and not v_has_waitlist) then
      v_new := 'attending';
    else
      v_new := 'waitlisted';
    end if;
  else
    if v_current.state = 'declined' then
      return v_current.state;
    end if;
    v_new := 'declined';
  end if;

  if v_current.id is null then
    insert into public.attendance_responses (match_id, user_id, state, waitlisted_at, responded_at, updated_at)
    values (
      p_match_id, v_uid, v_new,
      case when v_new = 'waitlisted' then clock_timestamp() end,
      clock_timestamp(), clock_timestamp()
    );
  else
    update public.attendance_responses
       set state = v_new,
           waitlisted_at = case when v_new = 'waitlisted' then clock_timestamp() end,
           promoted_at = null,
           updated_at = clock_timestamp()
     where id = v_current.id;
  end if;

  -- 참석자가 불참으로 바꾸면 대기 1번부터 자동 참석 (Q-038)
  if v_current.state = 'attending' and v_new = 'declined' then
    perform private.promote_waitlisted(p_match_id);
  end if;

  return v_new;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.promote_waitlisted(uuid) from authenticated, service_role;
revoke execute on function public.respond_attendance(uuid, boolean) from public, anon;
grant execute on function public.respond_attendance(uuid, boolean) to authenticated;
