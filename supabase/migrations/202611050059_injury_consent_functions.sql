-- 부상 동의 나중에·철회 서버 함수 (스프린트 04 1-2 / data-model.md v4.5 8-1·8-2, Q-049, Q-052, Q-053, S-07)
--
-- agree_injury_consent()
--   - 가입 때 하지 않았거나 철회한 사람이 다시 동의: 유효한 injury_info 가 없을 때만 새 줄(현재 문구 버전).
--   - 이미 유효한 동의가 있으면 거절(injury_consent_exists). 이전 철회 줄은 그대로 둔다.
-- withdraw_consent(p_consent_type)
--   - injury_info 만 철회 가능. 이용약관·개인정보 동의는 거절(consent_not_withdrawable) — 철회 대신 회원 탈퇴 (Q-052).
--   - 한 처리 안에서 (1) 유효한 injury_info 줄에 withdrawn_at (2) 그 사람의 부상 기록 전부(진행 중·지난 것) 삭제
--     → 이력은 외래 키(같이 삭제)로 함께 지워진다. 다시 동의해도 지운 기록은 돌아오지 않는다.
--   - 유효한 부상 동의가 없으면 거절(injury_consent_not_found).
-- 공통: 본인만(다른 사람 ID 를 받지 않음), 프로필 없는 호출자 거절(Q-010). 오류는 P0001 + 영문 코드.
--
-- 동시성: 철회는 동의 줄을 UPDATE 로 잠근다. 부상 등록 함수(1-3)는 등록 전에 같은 동의 줄을 잠가(FOR SHARE)
-- 철회와 겹쳐 철회 뒤에 기록이 남는 일이 없게 한다. 팀원 읽기 규칙의 동의 확인(S-07)이 이중 장치다.

create function public.agree_injury_consent()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  if private.has_valid_injury_consent(v_uid) then
    raise exception 'injury_consent_exists' using errcode = 'P0001';
  end if;
  begin
    insert into public.user_consents (user_id, consent_type, consent_version)
    values (v_uid, 'injury_info', private.current_consent_version('injury_info'));
  exception when unique_violation then
    -- 같은 순간 두 번 눌러 고유 조건(user_consents_one_active_injury)에 걸린 경우
    raise exception 'injury_consent_exists' using errcode = 'P0001';
  end;
end;
$$;

create function public.withdraw_consent(p_consent_type public.consent_type)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_consent_id uuid;
begin
  if p_consent_type is distinct from 'injury_info'::public.consent_type then
    raise exception 'consent_not_withdrawable' using errcode = 'P0001';
  end if;

  update public.user_consents c
     set withdrawn_at = now()
   where c.user_id = v_uid
     and c.consent_type = 'injury_info'
     and c.withdrawn_at is null
  returning c.id into v_consent_id;

  if v_consent_id is null then
    raise exception 'injury_consent_not_found' using errcode = 'P0001';
  end if;

  -- 부상 기록 전부 삭제 (이력은 injury_events.injury_id 같이 삭제)
  delete from public.injuries i where i.user_id = v_uid;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.agree_injury_consent(),
  public.withdraw_consent(public.consent_type)
from public, anon;
grant execute on function
  public.agree_injury_consent(),
  public.withdraw_consent(public.consent_type)
to authenticated;
