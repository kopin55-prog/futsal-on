-- 부상 등록·연장·회복·메모 수정 서버 함수 (스프린트 04 1-3 / data-model.md v4.6 8-2·8-3, Q-078 S4-06·S4-07·S4-08)
--
-- 모두 본인만(다른 사람 ID 를 받지 않음), 프로필 없는 호출자 거절(Q-010). 오류는 P0001 + 영문 코드.
--
-- report_injury(p_weeks, p_memo)
--   - 유효한 부상 동의가 없으면 거절(injury_consent_required). 동의 줄을 FOR SHARE 로 잠가 철회(withdraw_consent,
--     같은 줄 UPDATE)와 겹쳐 철회 뒤에 기록이 남는 일을 막는다(202611050059 주석). 철회가 먼저 끝났으면 잠금 뒤
--     다시 읽은 줄이 조건(withdrawn_at is null)에 맞지 않아 거절된다.
--   - 진행 중 부상이 있으면 거절(injury_already_active). 동시에 두 번 눌러도 부분 고유 조건이 막는다.
--   - 예상 회복 기간은 1~12주(S4-06 (1)). 예상 복귀일 = 등록일(한국 날짜) + 주 × 7. 이력 reported/self.
--   - 메모: 표의 규칙(11장 14번, 앞뒤 공백 정리 후 비면 없음). 어기면 invalid_injury_memo.
--   - 이미 "참석"으로 응답한 다가오는 경기는 자동으로 바꾸지 않는다(S4-08). 안내와 [불참으로 바꾸기]는 앱이
--     respond_attendance(불참)로 한다(부상 중이어도 불참은 확인 없이 가능, 1-5).
-- extend_injury(p_weeks, p_via)
--   - +1주·+2주만(injury_invalid_weeks). 기준 날짜는 늦은 쪽: 예상 복귀일이 지났으면 오늘, 아니면 예상 복귀일(S4-07).
--   - p_via: 직접(self, 기본) 또는 복귀 확인 알림에서 "아직 회복 중"(return_check, S4-11). 이력 extended + weeks_added.
-- recover_injury()
--   - status=recovered, recovered_at=지금, 이력 recovered/self. 참석 투표로 복귀하는 경로는 respond_attendance(1-5).
-- update_injury_memo(p_memo)
--   - 진행 중 부상의 메모만 고친다. 이력은 남기지 않는다(S4-06 (2)). 기간 줄이기는 없다(S4-06 (3)).
-- 진행 중 부상이 없으면 연장·회복·메모 수정은 injury_not_active.
-- 함수 안에서 메모 값을 로그로 남기지 않는다(13장 12번).

create function public.report_injury(p_weeks int, p_memo text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_id uuid;
begin
  if p_weeks is null or p_weeks not between 1 and 12 then
    raise exception 'injury_invalid_weeks' using errcode = 'P0001';
  end if;

  -- 유효한 부상 동의 확인 + 철회와 동시 처리 방지 (같은 줄 공유 잠금)
  perform 1
     from public.user_consents c
    where c.user_id = v_uid
      and c.consent_type = 'injury_info'
      and c.withdrawn_at is null
      for share;
  if not found then
    raise exception 'injury_consent_required' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.injuries i where i.user_id = v_uid and i.status = 'active') then
    raise exception 'injury_already_active' using errcode = 'P0001';
  end if;

  begin
    insert into public.injuries (user_id, started_on, expected_return_on, memo)
    values (v_uid, v_today, v_today + p_weeks * 7, p_memo)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'injury_already_active' using errcode = 'P0001';
    when check_violation then
      raise exception 'invalid_injury_memo' using errcode = 'P0001';
  end;

  insert into public.injury_events (injury_id, kind, via) values (v_id, 'reported', 'self');
  return v_id;
end;
$$;

create function public.extend_injury(p_weeks int, p_via public.injury_event_via default 'self')
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_injury public.injuries;
  v_new date;
begin
  if p_weeks is null or p_weeks not in (1, 2) then
    raise exception 'injury_invalid_weeks' using errcode = 'P0001';
  end if;
  if p_via is null or p_via not in ('self', 'return_check') then
    raise exception 'injury_invalid_via' using errcode = 'P0001';
  end if;

  select i.* into v_injury
    from public.injuries i
   where i.user_id = v_uid and i.status = 'active'
     for update;
  if v_injury.id is null then
    raise exception 'injury_not_active' using errcode = 'P0001';
  end if;

  -- 늦은 쪽 + 주 수 (S4-07)
  v_new := greatest(v_injury.expected_return_on, v_today) + p_weeks * 7;
  update public.injuries set expected_return_on = v_new where id = v_injury.id;
  insert into public.injury_events (injury_id, kind, weeks_added, via)
  values (v_injury.id, 'extended', p_weeks, p_via);
  return v_new;
end;
$$;

create function public.recover_injury()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_id uuid;
begin
  update public.injuries i
     set status = 'recovered', recovered_at = now()
   where i.user_id = v_uid and i.status = 'active'
  returning i.id into v_id;
  if v_id is null then
    raise exception 'injury_not_active' using errcode = 'P0001';
  end if;
  insert into public.injury_events (injury_id, kind, via) values (v_id, 'recovered', 'self');
end;
$$;

create function public.update_injury_memo(p_memo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_id uuid;
begin
  begin
    update public.injuries i
       set memo = p_memo
     where i.user_id = v_uid and i.status = 'active'
    returning i.id into v_id;
  exception when check_violation then
    raise exception 'invalid_injury_memo' using errcode = 'P0001';
  end;
  if v_id is null then
    raise exception 'injury_not_active' using errcode = 'P0001';
  end if;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.report_injury(int, text),
  public.extend_injury(int, public.injury_event_via),
  public.recover_injury(),
  public.update_injury_memo(text)
from public, anon;
grant execute on function
  public.report_injury(int, text),
  public.extend_injury(int, public.injury_event_via),
  public.recover_injury(),
  public.update_injury_memo(text)
to authenticated;
