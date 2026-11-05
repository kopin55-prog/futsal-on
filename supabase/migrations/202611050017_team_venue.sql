-- 스프린트 01 4단계: 지정 풋살장 저장 (data-model.md 3-1 venue_*, Q-032, Q-068 2번, 기획서 5장 "없으면 직접 입력")
--
-- 팀 만들기·팀 정보 수정 서버 함수가 지정 풋살장도 한 번에 저장하도록 바꾼다 (표·칸 추가 없음).
-- 장소 값은 jsonb 하나로 받는다:
--   null                         → 지정 풋살장 없음 (수정에서는 지움)
--   {"name", "address"}          → 직접 입력 (지도 서비스·장소 번호·좌표 없음)
--   {"name", "address", "provider": "kakao", "place_id", "lat", "lng"} → 카카오맵 검색 결과
-- 이름 1~200자, 주소 0~300자(비우면 없음). 카카오 결과는 장소 번호·좌표가 모두 있어야 한다.

create function private.apply_team_venue(p_team_id uuid, p_venue jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_address text;
  v_provider text;
  v_place_id text;
  v_lat double precision;
  v_lng double precision;
begin
  if p_venue is null or jsonb_typeof(p_venue) = 'null' then
    update public.teams
       set venue_name = null, venue_address = null, venue_lat = null, venue_lng = null,
           venue_map_provider = null, venue_map_place_id = null
     where id = p_team_id;
    return;
  end if;

  begin
    if jsonb_typeof(p_venue) <> 'object' then
      raise exception 'bad';
    end if;
    v_name := nullif(btrim(p_venue ->> 'name'), '');
    v_address := nullif(btrim(p_venue ->> 'address'), '');
    v_provider := nullif(btrim(p_venue ->> 'provider'), '');
    v_place_id := nullif(btrim(p_venue ->> 'place_id'), '');
    v_lat := (p_venue ->> 'lat')::double precision;
    v_lng := (p_venue ->> 'lng')::double precision;
  exception when others then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end;

  if v_name is null
     or v_name ~ '[\r\n]'
     or (v_address is not null and v_address ~ '[\r\n]') then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end if;

  if v_provider is null then
    -- 직접 입력: 지도 정보 없음
    if v_place_id is not null or v_lat is not null or v_lng is not null then
      raise exception 'invalid_venue' using errcode = 'P0001';
    end if;
  elsif v_provider = 'kakao' then
    if v_place_id is null or v_lat is null or v_lng is null then
      raise exception 'invalid_venue' using errcode = 'P0001';
    end if;
  else
    raise exception 'invalid_venue' using errcode = 'P0001';
  end if;

  begin
    update public.teams
       set venue_name = v_name,
           venue_address = v_address,
           venue_lat = v_lat,
           venue_lng = v_lng,
           venue_map_provider = v_provider::public.map_provider,
           venue_map_place_id = v_place_id
     where id = p_team_id;
  exception when check_violation or invalid_text_representation then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 만들기: 202611050009 + 지정 풋살장
-- ---------------------------------------------------------------------------
drop function public.create_team(text, smallint, time, time, text);

create function public.create_team(
  p_name text,
  p_regular_weekday smallint default null,
  p_regular_start_time time default null,
  p_regular_end_time time default null,
  p_logo_text text default null,
  p_venue jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
  v_logo text;
begin
  -- 한 사람이 소속할 수 있는 팀은 만든 팀 포함 최대 10개 (Q-067 5번)
  if (select count(*) from public.team_members m
        join public.teams t on t.id = m.team_id
       where m.user_id = v_uid and m.status = 'active' and t.dissolved_at is null) >= 10 then
    raise exception 'team_limit_reached' using errcode = 'P0001';
  end if;

  -- 로고 글자: 비우면 기본값(팀 이름 앞 두 글자, Q-013). 만든 사람은 팀장이므로 직접 정할 수 있다 (Q-014).
  if p_logo_text is not null and btrim(p_logo_text) <> '' then
    v_logo := private.normalize_single_line_name(p_logo_text);
    if private.grapheme_count(v_logo) not between 1 and 2
       or not private.is_valid_single_line_name(v_logo, 2) then
      raise exception 'invalid_logo_text' using errcode = 'P0001';
    end if;
  end if;

  begin
    insert into public.teams (name, team_code, created_by, logo_text)
    values (p_name, private.new_team_code(), v_uid, v_logo)
    returning id into v_team_id;
  exception when check_violation or not_null_violation then
    raise exception 'invalid_team_name' using errcode = 'P0001';
  end;

  if p_regular_weekday is not null or p_regular_start_time is not null or p_regular_end_time is not null then
    begin
      update public.teams
         set regular_weekday = p_regular_weekday,
             regular_start_time = p_regular_start_time,
             regular_end_time = p_regular_end_time
       where id = v_team_id;
    exception when check_violation then
      raise exception 'invalid_regular_schedule' using errcode = 'P0001';
    end;
  end if;

  if p_venue is not null then
    perform private.apply_team_venue(v_team_id, p_venue);
  end if;

  insert into public.team_members (team_id, user_id, role, status)
  values (v_team_id, v_uid, 'owner', 'active');

  insert into public.team_settings (team_id, updated_by) values (v_team_id, v_uid);

  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 정보 수정: 202611050015 + 지정 풋살장 (항상 화면의 현재 값을 보낸다. null = 없음)
-- ---------------------------------------------------------------------------
drop function public.update_team_info(uuid, text, smallint, time, time, boolean, text);

create function public.update_team_info(
  p_team_id uuid,
  p_name text,
  p_regular_weekday smallint,
  p_regular_start_time time,
  p_regular_end_time time,
  p_is_recruiting boolean,
  p_venue jsonb,
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

  perform private.apply_team_venue(p_team_id, p_venue);

  if v_logo is not null then
    update public.teams set logo_text = v_logo where id = p_team_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.create_team(text, smallint, time, time, text, jsonb),
  public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text)
from public, anon;
grant execute on function
  public.create_team(text, smallint, time, time, text, jsonb),
  public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text)
to authenticated;
