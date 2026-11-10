-- 팀 활동 지역 (data-model.md v4.7 3-1 region_sido·region_sigungu, Q-079 4번, decisions.md 2026-11-10)
--
-- - teams.region_sido(시·도, 예: 서울), teams.region_sigungu(시·군·구, 예: 성동구). 둘 다 선택.
--   시·군·구는 시·도 없이 저장할 수 없다. 글자 검사는 한 줄 이름 정리 규칙과 같다(줄바꿈·제어 문자·보이지 않는
--   문자·앞뒤/연속 공백 불가). 값 목록(행정구역 17개 시·도와 시·군·구)은 앱의 정적 목록이 정하고 서버는 글자만 본다.
-- - 팀 만들기·팀 정보 수정 서버 함수에서 받는다(정리 후 빈 값은 없음). 칸 단위 직접 수정 권한은 주지 않는다
--   (data-model 의 "관리자가 직접 고칠 수 있는 칸" 목록에 없음 → 서버 함수로만).
-- - 팀 이름 검색(search_teams)에 지역 필터(시·도, 시·군·구, 둘 다 선택)를 더하고, 이름 검색·식별코드 찾기 결과에
--   region_sido·region_sigungu 만 더 돌려준다. 주소·좌표·장소 번호·만든 사람·내부 ID 는 계속 주지 않는다.
--   최소 2자·최대 20개·특수문자 이스케이프·해체 팀 제외는 그대로(S-14). 사람당 호출 제한은 지금까지도 없었다
--   (decisions.md 2026-11-05 장소 검색과 같이 출시 전 보안 점검 때 다시 봄) → 그대로 둔다.
-- - 기존 팀은 비어 있음으로 둔다(자동 채움 없음).

-- ---------------------------------------------------------------------------
-- 표 칸
-- ---------------------------------------------------------------------------
alter table public.teams
  add column region_sido text
    constraint teams_region_sido_valid
      check (region_sido is null or char_length(region_sido) <= 10 and private.is_valid_single_line_name(region_sido, 10)),
  add column region_sigungu text
    constraint teams_region_sigungu_valid
      check (region_sigungu is null or char_length(region_sigungu) <= 20 and private.is_valid_single_line_name(region_sigungu, 20)),
  add constraint teams_region_sigungu_needs_sido
    check (region_sigungu is null or region_sido is not null);

-- 지역 필터 검색용
create index teams_region_idx on public.teams (region_sido, region_sigungu) where dissolved_at is null;

-- ---------------------------------------------------------------------------
-- 지역 값 정리·검사 (팀 만들기·수정, 검색 필터가 같이 쓴다). 빈 값 → null.
-- ---------------------------------------------------------------------------
create function private.normalize_region(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(private.normalize_single_line_name(coalesce(p_text, '')), '')
$$;

create function private.apply_team_region(p_team_id uuid, p_sido text, p_sigungu text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sido text := private.normalize_region(p_sido);
  v_sigungu text := private.normalize_region(p_sigungu);
begin
  if v_sigungu is not null and v_sido is null then
    raise exception 'invalid_region' using errcode = 'P0001';
  end if;
  begin
    update public.teams
       set region_sido = v_sido,
           region_sigungu = v_sigungu
     where id = p_team_id;
  exception when check_violation then
    raise exception 'invalid_region' using errcode = 'P0001';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 만들기: 202611050017 + 활동 지역
-- ---------------------------------------------------------------------------
drop function public.create_team(text, smallint, time, time, text, jsonb);

create function public.create_team(
  p_name text,
  p_regular_weekday smallint default null,
  p_regular_start_time time default null,
  p_regular_end_time time default null,
  p_logo_text text default null,
  p_venue jsonb default null,
  p_region_sido text default null,
  p_region_sigungu text default null
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

  if p_region_sido is not null or p_region_sigungu is not null then
    perform private.apply_team_region(v_team_id, p_region_sido, p_region_sigungu);
  end if;

  insert into public.team_members (team_id, user_id, role, status)
  values (v_team_id, v_uid, 'owner', 'active');

  insert into public.team_settings (team_id, updated_by) values (v_team_id, v_uid);

  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 정보 수정: 202611050017 + 활동 지역 (앱은 항상 화면의 현재 값을 보낸다. null = 없음)
-- ---------------------------------------------------------------------------
drop function public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text);

create function public.update_team_info(
  p_team_id uuid,
  p_name text,
  p_regular_weekday smallint,
  p_regular_start_time time,
  p_regular_end_time time,
  p_is_recruiting boolean,
  p_venue jsonb,
  p_logo_text text default null,
  p_region_sido text default null,
  p_region_sigungu text default null
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
  perform private.apply_team_region(p_team_id, p_region_sido, p_region_sigungu);

  if v_logo is not null then
    update public.teams set logo_text = v_logo where id = p_team_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 팀 이름 검색: 202611050006 + 지역 필터, 결과에 시·도·시·군·구
-- ---------------------------------------------------------------------------
drop function public.search_teams(text);

create function public.search_teams(
  p_query text,
  p_region_sido text default null,
  p_region_sigungu text default null
)
returns table (
  team_code text,
  name text,
  logo_text text,
  logo_image_path text,
  regular_weekday smallint,
  regular_start_time time,
  regular_end_time time,
  venue_name text,
  member_count int,
  is_recruiting boolean,
  region_sido text,
  region_sigungu text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_query text := private.normalize_single_line_name(coalesce(p_query, ''));
  v_sido text := private.normalize_region(p_region_sido);
  v_sigungu text := private.normalize_region(p_region_sigungu);
  v_pattern text;
begin
  if char_length(v_query) < 2 or char_length(v_query) > 80 then
    raise exception 'invalid_search_query' using errcode = 'P0001';
  end if;
  if (v_sigungu is not null and v_sido is null)
     or char_length(v_sido) > 10 or char_length(v_sigungu) > 20 then
    raise exception 'invalid_region' using errcode = 'P0001';
  end if;
  v_pattern := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    select t.team_code, t.name, t.logo_text, t.logo_image_path,
           t.regular_weekday, t.regular_start_time, t.regular_end_time, t.venue_name,
           private.team_search_row_count(t.id), t.is_recruiting,
           t.region_sido, t.region_sigungu
      from public.teams t
     where t.dissolved_at is null
       and t.name ilike v_pattern escape '\'
       and (v_sido is null or t.region_sido = v_sido)
       and (v_sigungu is null or t.region_sigungu = v_sigungu)
     order by t.name, t.team_code
     limit 20;
end;
$$;

-- ---------------------------------------------------------------------------
-- 식별코드 찾기: 202611050014 + 결과에 시·도·시·군·구 (반환 모양이 바뀌어 다시 만든다)
-- ---------------------------------------------------------------------------
drop function public.find_team_by_code(text);

create function public.find_team_by_code(p_team_code text)
returns table (
  team_code text,
  name text,
  logo_text text,
  logo_image_path text,
  regular_weekday smallint,
  regular_start_time time,
  regular_end_time time,
  venue_name text,
  member_count int,
  is_recruiting boolean,
  region_sido text,
  region_sigungu text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_code text := upper(btrim(coalesce(p_team_code, '')));
begin
  if exists (select 1 from public.teams t where t.team_code = v_code and t.dissolved_at is not null) then
    raise exception 'team_dissolved' using errcode = 'P0001';
  end if;
  return query
    select t.team_code, t.name, t.logo_text, t.logo_image_path,
           t.regular_weekday, t.regular_start_time, t.regular_end_time, t.venue_name,
           private.team_search_row_count(t.id), t.is_recruiting,
           t.region_sido, t.region_sigungu
      from public.teams t
     where t.dissolved_at is null
       and t.team_code = v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.create_team(text, smallint, time, time, text, jsonb, text, text),
  public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text, text, text),
  public.search_teams(text, text, text),
  public.find_team_by_code(text)
from public, anon;
grant execute on function
  public.create_team(text, smallint, time, time, text, jsonb, text, text),
  public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text, text, text),
  public.search_teams(text, text, text),
  public.find_team_by_code(text)
to authenticated;
