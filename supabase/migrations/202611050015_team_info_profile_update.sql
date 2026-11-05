-- 스프린트 01 3단계: 팀 정보 수정·프로필 수정을 서버 함수 하나로 (표·칸 추가 없음)
--
-- 1) update_team_info: 팀 이름·정기 운동일·인원 모집 + (팀장만) 로고 글자를 한 번에 저장.
--    - 관리자(팀장·운영진). 로고 글자는 팀장만 (Q-014). 값을 넘기지 않으면(null) 로고 글자는 그대로 두고
--      팀 이름 변경 자동 갱신 규칙(Q-036, Q-047, teams_before_write 트리거)을 따른다.
--    - 로고 글자를 넘기면 이름을 바꾼 뒤에 따로 저장한다 → 팀장이 넣은 값이 항상 남는다.
--    - 지정 풋살장(카카오맵)·로고 사진은 Q-068 답변 후.
-- 2) 정기 운동 시작 시각을 바꿔 경기 설정의 저장 규칙(마감이 자동 생성보다 앞서면 불가, 3-2)이 깨지면 거절.
--    표 직접 수정(칸 단위 권한) 경로도 같은 규칙을 받도록 트리거로 둔다.
-- 3) update_own_profile: 이름·자기소개(profiles)와 선호 포지션·전문 골키퍼(profile_play_prefs)를
--    한 트랜잭션으로 저장 (둘 중 하나만 저장되는 일 없음). 본인만 (Q-067 2번).

-- ---------------------------------------------------------------------------
-- 2) 정기 운동 시작 시각 변경 시 경기 설정 저장 규칙 확인
-- ---------------------------------------------------------------------------
create function private.teams_check_settings_deadline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s public.team_settings;
begin
  if new.regular_start_time is distinct from old.regular_start_time then
    select s.* into v_s from public.team_settings s where s.team_id = new.id;
    if v_s.team_id is not null
       and not private.team_settings_deadline_ok(
         new.regular_start_time, v_s.rsvp_deadline_hours, v_s.auto_create_days_before, v_s.auto_create_time
       ) then
      raise exception 'deadline_before_auto_create' using errcode = 'P0001';
    end if;
  end if;
  return null;
end;
$$;

create trigger teams_check_settings_deadline
after update of regular_start_time on public.teams
for each row execute function private.teams_check_settings_deadline();

-- ---------------------------------------------------------------------------
-- 1) 팀 정보 수정
-- ---------------------------------------------------------------------------
create function public.update_team_info(
  p_team_id uuid,
  p_name text,
  p_regular_weekday smallint,
  p_regular_start_time time,
  p_regular_end_time time,
  p_is_recruiting boolean,
  p_logo_text text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_logo text;
begin
  perform private.lock_team_as_staff(p_team_id);
  if p_is_recruiting is null then
    raise exception 'invalid_team_info' using errcode = 'P0001';
  end if;

  -- 로고 글자: 팀장만. 검사는 set_team_logo_text 와 같다.
  if p_logo_text is not null then
    if not private.is_team_owner(p_team_id) then
      raise exception 'not_permitted' using errcode = 'P0001';
    end if;
    v_logo := private.normalize_single_line_name(p_logo_text);
    if private.grapheme_count(v_logo) not between 1 and 2
       or not private.is_valid_single_line_name(v_logo, 2) then
      raise exception 'invalid_logo_text' using errcode = 'P0001';
    end if;
  end if;

  begin
    update public.teams set name = p_name where id = p_team_id;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_team_name' using errcode = 'P0001';
  end;

  begin
    update public.teams
       set regular_weekday = p_regular_weekday,
           regular_start_time = p_regular_start_time,
           regular_end_time = p_regular_end_time,
           is_recruiting = p_is_recruiting
     where id = p_team_id;
  exception when check_violation then
    raise exception 'invalid_regular_schedule' using errcode = 'P0001';
  end;

  if v_logo is not null then
    update public.teams set logo_text = v_logo where id = p_team_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) 프로필 수정 (본인)
-- ---------------------------------------------------------------------------
create function public.update_own_profile(
  p_display_name text,
  p_bio text,
  p_positions public.play_position[],
  p_is_dedicated_gk boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
begin
  begin
    update public.profiles
       set display_name = p_display_name,
           bio = p_bio
     where user_id = v_uid;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_profile' using errcode = 'P0001';
  end;

  begin
    update public.profile_play_prefs
       set positions = p_positions,
           is_dedicated_gk = coalesce(p_is_dedicated_gk, false)
     where user_id = v_uid;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_positions' using errcode = 'P0001';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.update_team_info(uuid, text, smallint, time, time, boolean, text),
  public.update_own_profile(text, text, public.play_position[], boolean)
from public, anon;
grant execute on function
  public.update_team_info(uuid, text, smallint, time, time, boolean, text),
  public.update_own_profile(text, text, public.play_position[], boolean)
to authenticated;
