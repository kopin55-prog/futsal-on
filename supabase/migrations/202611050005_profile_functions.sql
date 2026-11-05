-- 가입(프로필 만들기·동의)과 기기 알림 주소 등록 서버 함수 (data-model.md 2-2, 2-4, 8-1, 11장 3·4번)
--
-- 공통 규칙
-- - SECURITY DEFINER + search_path = '' + 이름은 스키마까지 적는다.
-- - 첫 줄에서 auth.uid() 확인. 프로필이 없는 호출자는 create_profile 외 모든 함수에서 거절 (Q-010).
-- - 실패는 errcode P0001 + 메시지에 오류 코드(영문 snake_case)만 담는다. 앱이 코드로 문구를 고른다.
-- - 실행 권한은 PUBLIC·anon 회수, authenticated 에만.

-- ---------------------------------------------------------------------------
-- 공통 도우미
-- ---------------------------------------------------------------------------

-- 로그인한 호출자 ID. 없으면 거절.
create function private.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- 프로필이 있는 호출자 ID. 없으면 거절 (Q-010).
create function private.require_profile()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not exists (select 1 from public.profiles p where p.user_id = v_uid) then
    raise exception 'profile_required' using errcode = 'P0001';
  end if;
  return v_uid;
end;
$$;

-- 지금 받는 동의 문구 버전 (docs/consent-texts.md). 문구가 바뀌면 이 값을 새로 정한다.
-- 앱이 버전을 지정하지 못하게 서버가 기록한다.
-- TODO(lead 확인): 이용약관·개인정보 처리방침 본문은 출시 전 작성 예정이라 버전 값은 임시.
create function private.current_consent_version(p_type public.consent_type)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_type
    when 'terms' then 'terms-2026-11-05'
    when 'privacy' then 'privacy-2026-11-05'
    when 'injury_info' then 'injury_info-2026-11-05'
  end
$$;

-- ---------------------------------------------------------------------------
-- 가입 단계: 프로필 + 선호 포지션 + 동의 기록을 한 번에 (2-2, 8-1)
-- ---------------------------------------------------------------------------
create function public.create_profile(
  p_display_name text,
  p_bio text,
  p_positions public.play_position[],
  p_is_dedicated_gk boolean,
  p_age_14_confirmed boolean,
  p_terms_agreed boolean,
  p_privacy_agreed boolean,
  p_injury_info_agreed boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if exists (select 1 from public.profiles p where p.user_id = v_uid) then
    raise exception 'profile_exists' using errcode = 'P0001';
  end if;
  -- 만 14세 확인·약관·개인정보는 필수 (Q-023, Q-053). 부상 정보는 선택 (Q-049).
  if coalesce(p_age_14_confirmed, false) is not true then
    raise exception 'age_14_required' using errcode = 'P0001';
  end if;
  if coalesce(p_terms_agreed, false) is not true or coalesce(p_privacy_agreed, false) is not true then
    raise exception 'required_consents_missing' using errcode = 'P0001';
  end if;

  -- 이름 정리·검사는 표의 트리거·검사 조건이 앱과 같은 규칙으로 한다.
  begin
    insert into public.profiles (user_id, display_name, bio, age_14_confirmed_at)
    values (v_uid, p_display_name, p_bio, now());
  exception when check_violation then
    raise exception 'invalid_profile' using errcode = 'P0001';
  end;

  begin
    insert into public.profile_play_prefs (user_id, positions, is_dedicated_gk)
    values (v_uid, p_positions, coalesce(p_is_dedicated_gk, false));
  exception when check_violation or not_null_violation then
    raise exception 'invalid_positions' using errcode = 'P0001';
  end;

  insert into public.user_consents (user_id, consent_type, consent_version)
  values
    (v_uid, 'terms', private.current_consent_version('terms')),
    (v_uid, 'privacy', private.current_consent_version('privacy'));

  if coalesce(p_injury_info_agreed, false) then
    insert into public.user_consents (user_id, consent_type, consent_version)
    values (v_uid, 'injury_info', private.current_consent_version('injury_info'));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 기기 알림 주소 등록 (2-4, S-08): 같은 토큰이 다른 사람 소유면 호출자에게 옮긴다.
-- ---------------------------------------------------------------------------
create function public.register_device_token(p_token text, p_platform public.device_platform)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  if p_token is null or char_length(p_token) not between 1 and 4096 or p_platform is null then
    raise exception 'invalid_device_token' using errcode = 'P0001';
  end if;
  insert into public.device_tokens (user_id, token, platform, updated_at)
  values (v_uid, p_token, p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.create_profile(text, text, public.play_position[], boolean, boolean, boolean, boolean, boolean),
  public.register_device_token(text, public.device_platform)
from public, anon;
grant execute on function
  public.create_profile(text, text, public.play_position[], boolean, boolean, boolean, boolean, boolean),
  public.register_device_token(text, public.device_platform)
to authenticated;
