-- 일정 직접 추가·취소 (스프린트 02 1-4, 1-5, 1-6 / data-model.md 4-1 / Q-027 M-16·M-17, Q-071 2번·3번·4번)
--
-- 직접 추가 create_match (1-4, 1-5)
--   - 관리자(팀장·운영진)만. 날짜·시작·종료 필수, 장소 선택(직접 입력 또는 카카오맵 검색 결과, 지정 풋살장과 같은 jsonb).
--   - 정원은 팀 경기 설정에서 복사 (기획서 8장). 마감·미투표 알림 시간은 일정마다 고름, 안 주면 팀 설정 값 (Q-072 1번).
--     미투표 알림 시각 = 실제 마감 - N시간, 이미 지났으면 비움. source=manual, created_by 기록.
--   - 시작 날짜·시각, 종료 날짜·시각 (자정 넘김은 종료 날짜로 표현). 종료가 시작과 같거나 이르면 불가 (lead 정리 qa L-15·L-03).
--     종료는 시작 후 24시간 이내 (일정 표 검사와 같음).
--   - 시작 시각이 지났으면 불가. 마감이 이미 지난 시각이면 그 일정의 마감 = 경기 시작 시각.
--   - 같은 시간대에 겹치는 일정 허용 (자동 일정과 같은 시각도 허용).
-- 취소 cancel_match (1-6)
--   - 관리자만, 경기 시작 전까지, 되돌리기 없음, 자동·직접 같은 규칙. status=cancelled, 취소 시각·취소한 사람 기록.
--   - 취소된 자동 일정은 다시 생기지 않는다 (matches_auto_once 가 취소된 줄도 포함).
--   - 취소 사유(선택, 1~20자, 이름과 같은 글자 정리, 비우면 없음, Q-072 5번).
-- 일정 수정 기능은 1차에 없음 (Q-071 4번).

-- ---------------------------------------------------------------------------
-- 장소 값 검사 (지정 풋살장 202611050017 과 같은 규칙을 한 곳에서)
--   null → 장소 없음 / {"name","address"} → 직접 입력 / {"name","address","provider":"kakao","place_id","lat","lng"}
-- ---------------------------------------------------------------------------
create function private.parse_venue(
  p_venue jsonb,
  out venue_name text,
  out venue_address text,
  out venue_map_provider public.map_provider,
  out venue_map_place_id text,
  out venue_lat double precision,
  out venue_lng double precision
)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_provider text;
begin
  if p_venue is null or jsonb_typeof(p_venue) = 'null' then
    return;
  end if;

  begin
    if jsonb_typeof(p_venue) <> 'object' then
      raise exception 'bad';
    end if;
    venue_name := nullif(btrim(p_venue ->> 'name'), '');
    venue_address := nullif(btrim(p_venue ->> 'address'), '');
    v_provider := nullif(btrim(p_venue ->> 'provider'), '');
    venue_map_place_id := nullif(btrim(p_venue ->> 'place_id'), '');
    venue_lat := (p_venue ->> 'lat')::double precision;
    venue_lng := (p_venue ->> 'lng')::double precision;
  exception when others then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end;

  if venue_name is null
     or venue_name ~ '[\r\n]'
     or char_length(venue_name) > 200
     or (venue_address is not null and (venue_address ~ '[\r\n]' or char_length(venue_address) > 300)) then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end if;

  if v_provider is null then
    -- 직접 입력: 지도 정보 없음
    if venue_map_place_id is not null or venue_lat is not null or venue_lng is not null then
      raise exception 'invalid_venue' using errcode = 'P0001';
    end if;
  elsif v_provider = 'kakao' then
    if venue_map_place_id is null or venue_lat is null or venue_lng is null
       or char_length(venue_map_place_id) > 100
       or venue_lat not between -90 and 90
       or venue_lng not between -180 and 180 then
      raise exception 'invalid_venue' using errcode = 'P0001';
    end if;
    venue_map_provider := 'kakao';
  else
    raise exception 'invalid_venue' using errcode = 'P0001';
  end if;
end;
$$;

-- 지정 풋살장 저장도 같은 검사를 쓴다 (동작은 202611050017 과 같음)
create or replace function private.apply_team_venue(p_team_id uuid, p_venue jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
begin
  select * into v from private.parse_venue(p_venue);
  begin
    update public.teams
       set venue_name = v.venue_name,
           venue_address = v.venue_address,
           venue_lat = v.venue_lat,
           venue_lng = v.venue_lng,
           venue_map_provider = v.venue_map_provider,
           venue_map_place_id = v.venue_map_place_id
     where id = p_team_id;
  exception when check_violation or invalid_text_representation then
    raise exception 'invalid_venue' using errcode = 'P0001';
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 일정 직접 추가
--   p_rsvp_deadline_hours: 마감 = 시작 몇 시간 전 (팀 설정과 같은 범위 0~720). null 이면 팀 설정 값
--   p_rsvp_reminder_hours: 미투표 알림 = 마감 몇 시간 전 (1·2·3·6·12·24), 0 = 끄기, null 이면 팀 설정 값
-- ---------------------------------------------------------------------------
create function public.create_match(
  p_team_id uuid,
  p_start_date date,
  p_start_time time,
  p_end_date date,
  p_end_time time,
  p_venue jsonb default null,
  p_rsvp_deadline_hours int default null,
  p_rsvp_reminder_hours int default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_s public.team_settings;
  v_venue record;
  v_starts timestamptz;
  v_ends timestamptz;
  v_deadline_hours int;
  v_reminder_hours int;
  v_deadline timestamptz;
  v_id uuid;
begin
  perform private.lock_team_as_staff(p_team_id);

  if p_start_date is null or p_start_time is null or p_end_date is null or p_end_time is null then
    raise exception 'invalid_match_time' using errcode = 'P0001';
  end if;
  v_starts := (p_start_date + p_start_time) at time zone 'Asia/Seoul';
  v_ends := (p_end_date + p_end_time) at time zone 'Asia/Seoul';
  if v_ends <= v_starts or v_ends > v_starts + interval '24 hours' then
    raise exception 'invalid_match_time' using errcode = 'P0001';
  end if;
  if v_starts <= now() then
    raise exception 'match_in_past' using errcode = 'P0001';
  end if;

  select * into v_venue from private.parse_venue(p_venue);

  select s.* into v_s from public.team_settings s where s.team_id = p_team_id;
  if v_s.team_id is null then
    raise exception 'invalid_team_settings' using errcode = 'P0001';
  end if;

  -- 시간 설정은 일정마다 (Q-072 1번). 안 주면 팀 설정 값. 정원은 계속 팀 설정 복사.
  v_deadline_hours := coalesce(p_rsvp_deadline_hours, v_s.rsvp_deadline_hours);
  if v_deadline_hours not between 0 and 720 then
    raise exception 'invalid_match_settings' using errcode = 'P0001';
  end if;
  if p_rsvp_reminder_hours is null then
    v_reminder_hours := v_s.rsvp_reminder_hours;
  elsif p_rsvp_reminder_hours = 0 then
    v_reminder_hours := null;
  elsif p_rsvp_reminder_hours in (1, 2, 3, 6, 12, 24) then
    v_reminder_hours := p_rsvp_reminder_hours;
  else
    raise exception 'invalid_match_settings' using errcode = 'P0001';
  end if;

  v_deadline := v_starts - make_interval(hours => v_deadline_hours);
  if v_deadline <= now() then
    -- 마감이 이미 지난 일정 (예: 1시간 뒤 번개): 마감 = 경기 시작 (Q-071 2번)
    v_deadline := v_starts;
  end if;

  insert into public.matches (
    team_id, source, starts_at, ends_at,
    venue_name, venue_address, venue_lat, venue_lng, venue_map_provider, venue_map_place_id,
    capacity, rsvp_deadline_at, rsvp_reminder_at, created_by
  )
  values (
    p_team_id, 'manual', v_starts, v_ends,
    v_venue.venue_name, v_venue.venue_address, v_venue.venue_lat, v_venue.venue_lng,
    v_venue.venue_map_provider, v_venue.venue_map_place_id,
    -- 미투표 알림 = (실제) 마감 - N시간, 이미 지났으면 비움 (Q-072 1번)
    v_s.capacity, v_deadline, private.rsvp_reminder_at(v_deadline, v_reminder_hours, now()), v_uid
  )
  returning id into v_id;

  -- (알림은 202611050029 에서 연결) 새 일정 알림 (추가한 운영진 본인 제외, Q-071 7번)
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 일정 취소
--   p_reason: 취소 사유(선택). 이름과 같은 글자 정리 후 1~20자, 비우면 사유 없음 (Q-072 5번)
-- ---------------------------------------------------------------------------
create function public.cancel_match(p_match_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
  v_match public.matches;
  v_reason text;
begin
  select m.team_id into v_team_id from public.matches m where m.id = p_match_id;
  -- 없는 일정·다른 팀 일정은 구분하지 않고 거절
  perform private.lock_team_as_staff(v_team_id);
  select m.* into v_match from public.matches m where m.id = p_match_id for update;

  if v_match.status = 'cancelled' then
    raise exception 'match_already_cancelled' using errcode = 'P0001';
  end if;
  if v_match.starts_at <= now() then
    raise exception 'match_already_started' using errcode = 'P0001';
  end if;

  if p_reason is not null then
    v_reason := nullif(private.normalize_single_line_name(p_reason), '');
    if v_reason is not null
       and (private.grapheme_count(v_reason) not between 1 and 20
            or not private.is_valid_single_line_name(v_reason, 20)) then
      raise exception 'invalid_cancel_reason' using errcode = 'P0001';
    end if;
  end if;

  update public.matches
     set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid, cancel_reason = v_reason
   where id = v_match.id;

  -- (알림은 202611050029 에서 연결) 일정 취소 알림 — 참석·대기·불참 응답자 전원, 취소한 본인 제외, 사유 포함 (Q-071 7번, Q-072 5번).
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  public.create_match(uuid, date, time, date, time, jsonb, int, int),
  public.cancel_match(uuid, text)
from public, anon;
grant execute on function
  public.create_match(uuid, date, time, date, time, jsonb, int, int),
  public.cancel_match(uuid, text)
to authenticated;
