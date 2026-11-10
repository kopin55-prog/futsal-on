-- 부상 복귀 확인 알림 (스프린트 04 1-6 / docs/notifications.md, data-model.md v4.6 8-2·9장, Q-078 S4-10·S4-11)
--
-- injury_return_check
--   - 일정이 생길 때(자동 생성·직접 추가 모두 matches 표를 지나므로 matches 트리거 한 곳) 그 팀 현재 팀원 중
--     진행 중 부상이 있고, 경기 날짜(시작 시각의 한국 날짜) ≥ 예상 복귀일인 사람에게 보낸다(S4-10 "경기 날짜 기준").
--     주인의 부상 동의가 유효할 때만(S-07, 철회 중인 순간 대비).
--   - 같은 일정에는 한 번: injuries.return_check_sent_for(마지막으로 보낸 일정) + dedupe_key(종류:일정 ID).
--     두 팀에 소속이면 팀마다 그 팀 일정이 열릴 때 각각 받는다(S4-10).
--   - 일정을 직접 추가한 운영진 본인이 부상자여도 받는다(일정 생성 알림과 달리 본인의 부상 확인이므로).
--   - 받는 사람은 본인 1명이고 문구에 다른 사람 이름·부상 메모가 없다(actor 없음, 9장·S-07).
--   - 제목은 팀 이름(private.notify, decisions 2026-11-09). 누르면 그 일정(ref_type = 'match') → 앱의 확인 창(S4-11).
--   - 조용한 시간 규칙은 일반 알림과 같다(00:00~08:00 → 13:00, private.notification_send_at 그대로).
--     푸시 전에 경기가 시작했으면 notifier 가 건너뛴다(기존 규칙).
--   - 문구: notifications.md 확정 문구 "부상은 회복되셨나요? 경기가 열렸습니다. 참석하시겠습니까?" 그대로.
-- 해체된 팀은 private.team_member_ids 가 빈 목록이라 보내지 않는다. 취소 상태로 들어온 줄은 대상이 아니다.

-- ---------------------------------------------------------------------------
-- 문구 (202611050045 + injury_return_check)
-- ---------------------------------------------------------------------------
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
    when 'lineup_confirmed' then
      v_when || ' 경기 팀 배치가 나왔어요! 내 팀을 확인해 보세요.'
    when 'lineup_changed' then
      v_when || ' 경기 팀 배치가 바뀌었어요. 다시 확인해 주세요.'
    when 'lineup_unconfirmed' then
      v_when || ' 경기가 시작됐는데 팀 배치가 아직 확정 전이에요. 확정 부탁드려요!'
    when 'award_poll_opened' then
      '수고하셨어요! 오늘의 POM과 오늘의 골을 뽑아 주세요.'
    when 'award_results_announced' then
      '오늘의 POM·오늘의 골 결과가 나왔어요!'
    when 'injury_return_check' then
      -- notifications.md 확정 문구 (부상 메모 없음)
      '부상은 회복되셨나요? 경기가 열렸습니다. 참석하시겠습니까?'
    when 'member_removed' then
      case when v_name is not null
           -- 팀장·운영진용 (builder 초안, Q-073 11번 "같은 말투로 builder 초안")
           then v_name || '님이 팀에서 내보내졌어요.'
           else '팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요.' end
    else null
  end;
end;
$$;

revoke execute on function private.notification_body(public.notification_kind, jsonb)
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 일정 생성 → 복귀 확인 알림 (matches 트리거)
-- ---------------------------------------------------------------------------
create function private.matches_notify_return_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_users uuid[];
begin
  if new.status <> 'scheduled' then
    return null;
  end if;

  with targets as (
    select i.id, i.user_id
      from public.injuries i
     where i.status = 'active'
       and i.user_id = any (private.team_member_ids(new.team_id))
       -- 경기 날짜 기준 (S4-10)
       and i.expected_return_on <= (new.starts_at at time zone 'Asia/Seoul')::date
       and i.return_check_sent_for is distinct from new.id
       and private.has_valid_injury_consent(i.user_id)
       for update of i
  )
  select coalesce(array_agg(t.id), '{}'), coalesce(array_agg(t.user_id), '{}')
    into v_ids, v_users
    from targets t;

  if cardinality(v_ids) = 0 then
    return null;
  end if;

  perform private.notify(
    'injury_return_check', v_users,
    new.team_id, 'match', new.id, '',
    null, jsonb_build_object('match_at', new.starts_at)
  );
  update public.injuries set return_check_sent_for = new.id where id = any (v_ids);
  return null;
end;
$$;

create trigger matches_notify_return_check
after insert on public.matches
for each row execute function private.matches_notify_return_check();

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.matches_notify_return_check() from authenticated, service_role;
