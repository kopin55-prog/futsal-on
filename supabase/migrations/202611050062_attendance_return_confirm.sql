-- 참석 투표 시 부상 복귀 (스프린트 04 1-5 / 기획서 12장, data-model.md v4.6 4-2·8-2·8-3, Q-078 S4-09·S4-11)
--
-- respond_attendance(p_match_id, p_attending, p_return_via)  — 202611050024 를 바꾼다(인자 하나 추가, 기본값 있음).
--   - 진행 중 부상이 있는 사람이 "참석"을 누르면 서버가 return_confirmation_required 로 거절한다(응답 안 바뀜).
--     이미 참석·대기로 응답해 둔 경우(참석 후 부상 등록, S4-08)도 같다.
--   - 앱이 "부상에서 복귀하셨나요?"(기획서 문구) 확인을 받아 p_return_via 를 주고 다시 부르면 한 처리 안에서
--     참석 응답(정원이 차면 대기) + 부상 회복(status=recovered, recovered_at) + 이력 recovered 를 남긴다.
--       return_vote  : 일정 상세·홈 카드의 [참석] 확인 창 (2-5)
--       return_check : 복귀 확인 알림을 눌러 연 창의 [참석할게요] (2-6, S4-11)
--     정원이 차서 대기가 돼도 부상은 해제한다(S4-09, 뛰겠다는 뜻).
--   - 불참은 확인 없이 그대로, 부상 유지. p_return_via 는 무시한다.
--   - 마감·취소·팀원 확인이 부상 확인보다 먼저다(마감 뒤에는 확인 창을 띄울 이유가 없음).
--   - 부상이 없는데 p_return_via 를 주면(예: 다른 기기에서 먼저 회복) 보통 참석으로 처리한다.
--   - p_return_via = self 는 받지 않는다(invalid_attendance).
-- 잠금 순서: 팀 줄(공유) → 일정 줄(배타) → 본인 부상 줄(배타). 동의 철회(부상 줄 삭제)와 겹치면 철회 뒤에는
-- 부상이 없으므로 보통 참석이 된다.
-- 나머지 규칙은 202611050024 그대로 (마감 정각부터 거절, 연타는 그대로, 참석→불참이면 대기 자동 참석).

drop function public.respond_attendance(uuid, boolean);

create function public.respond_attendance(
  p_match_id uuid,
  p_attending boolean,
  p_return_via public.injury_event_via default null
)
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
  v_injury_id uuid;
begin
  if p_attending is null then
    raise exception 'invalid_attendance' using errcode = 'P0001';
  end if;
  if p_return_via = 'self' then
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

  -- 부상 중 참석은 복귀 확인 필요 (기획서 12장)
  if p_attending then
    select i.id into v_injury_id
      from public.injuries i
     where i.user_id = v_uid and i.status = 'active'
       for update;
    if v_injury_id is not null and p_return_via is null then
      raise exception 'return_confirmation_required' using errcode = 'P0001';
    end if;
  end if;

  select r.* into v_current
    from public.attendance_responses r
   where r.match_id = p_match_id and r.user_id = v_uid;

  if p_attending then
    if v_current.state in ('attending', 'waitlisted') then
      -- 이미 참석·대기면 응답은 그대로 (연타)
      v_new := v_current.state;
    else
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
    end if;
  else
    v_new := 'declined';
  end if;

  if v_current.state is distinct from v_new then
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
  end if;

  -- 복귀 확인 후 참석(대기 포함): 같은 처리 안에서 부상 회복 + 이력
  if v_injury_id is not null then
    update public.injuries
       set status = 'recovered', recovered_at = now()
     where id = v_injury_id;
    insert into public.injury_events (injury_id, kind, via) values (v_injury_id, 'recovered', p_return_via);
  end if;

  return v_new;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function public.respond_attendance(uuid, boolean, public.injury_event_via) from public, anon;
grant execute on function public.respond_attendance(uuid, boolean, public.injury_event_via) to authenticated;
