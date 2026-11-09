-- 게스트 추가·삭제와 관리자용 게스트 정보 (스프린트 02 2-3 / data-model.md 3-4, 4-3 / Q-017, Q-027 M-19, Q-071 6번)
--
-- - 관리자(팀장·운영진)만. 경기 시작 전까지, 취소된 일정은 불가 (Q-071 6번). 마감과는 무관.
-- - 이름: 팀에서 쓸 이름과 같은 규칙 (보이지 않는 문자 삭제·연속 공백 하나로 정리 후 1~8자, Q-034, Q-048).
-- - 포지션: 선택, 최대 3개, 중복 없음 (빈 목록 = 없음).
-- - 대략 실력: 선택, 실력 등급 5단계 중 하나 (Q-071 6번). "미정"이거나 안 고르면 줄을 만들지 않는다(3-4 "줄이 없으면 미정").
--   실력 등급 표(skill_ratings)의 guest_id 줄로 저장 → 관리자만 읽음. 게스트를 지우면 같이 지워진다.
-- - 정원과 별도 (참석 투표의 정원 계산은 attendance_responses 만 센다).
-- - 매번 새로 입력, 목록 저장 없음 (M-19). 게스트 관련 알림 없음 (Q-071 6번).
-- - 포지션·실력은 관리자만 (Q-017): 팀원용 표 읽기 권한에는 positions 칸이 없다(202611050019).
--   관리자는 get_match_guest_details 로 읽는다. 운영진에서 해제되면 바로 못 읽는다.
-- - 미확정 (Q-073 7번 대기): 한 일정 안 같은 이름 게스트 금지, 한 일정 게스트 최대 20명은 넣지 않았다.
-- 게스트 정보 수정 함수는 만들지 않는다 (문서에 없음. 잘못 넣었으면 지우고 다시 추가).

-- 게스트 대상 일정 확인·잠금: 관리자, 예정 상태, 시작 전. 일정의 팀 ID 를 돌려준다.
create function private.lock_match_for_guests(p_match_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_match public.matches;
begin
  select m.team_id into v_team_id from public.matches m where m.id = p_match_id;
  -- 없는 일정·다른 팀 일정은 구분하지 않고 거절
  perform private.lock_team_as_staff(v_team_id);
  select m.* into v_match from public.matches m where m.id = p_match_id for update;
  if v_match.status = 'cancelled' then
    raise exception 'match_cancelled' using errcode = 'P0001';
  end if;
  if v_match.starts_at <= now() then
    raise exception 'match_already_started' using errcode = 'P0001';
  end if;
  return v_team_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 게스트 추가. 새 게스트 ID.
-- ---------------------------------------------------------------------------
create function public.add_match_guest(
  p_match_id uuid,
  p_name text,
  p_positions public.play_position[] default null,
  p_skill_level public.skill_level default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
  v_name text;
  v_positions public.play_position[];
  v_id uuid;
begin
  v_team_id := private.lock_match_for_guests(p_match_id);

  v_name := private.normalize_single_line_name(coalesce(p_name, ''));
  if v_name = ''
     or private.grapheme_count(v_name) not between 1 and 8
     or not private.is_valid_single_line_name(v_name, 8) then
    raise exception 'invalid_guest_name' using errcode = 'P0001';
  end if;

  v_positions := case when coalesce(cardinality(p_positions), 0) = 0 then null else p_positions end;
  if v_positions is not null
     and (cardinality(v_positions) > 3
          or array_position(v_positions, null) is not null
          or not private.positions_are_distinct(v_positions)) then
    raise exception 'invalid_positions' using errcode = 'P0001';
  end if;

  insert into public.match_guests (match_id, team_id, name, positions, added_by)
  values (p_match_id, v_team_id, v_name, v_positions, v_uid)
  returning id into v_id;

  if p_skill_level is not null and p_skill_level <> 'undecided' then
    insert into public.skill_ratings (team_id, guest_id, level, updated_by, updated_at)
    values (v_team_id, v_id, p_skill_level, v_uid, now());
  end if;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 게스트 삭제 (대략 실력 줄도 같이 삭제)
-- ---------------------------------------------------------------------------
create function public.remove_match_guest(p_guest_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_match_id uuid;
begin
  select g.match_id into v_match_id from public.match_guests g where g.id = p_guest_id;
  if v_match_id is null then
    -- 없는 게스트·다른 팀 게스트는 구분하지 않고 거절
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  perform private.lock_match_for_guests(v_match_id);
  delete from public.match_guests g where g.id = p_guest_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 관리자용 게스트 정보 (이름·포지션·대략 실력). 팀원·다른 팀은 거절.
-- 시작한 경기·취소된 일정도 읽을 수 있다 (팀 나누기·기록 확인용).
-- ---------------------------------------------------------------------------
create function public.get_match_guest_details(p_match_id uuid)
returns table (
  id uuid,
  name text,
  positions public.play_position[],
  skill_level public.skill_level,
  added_by uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_team_id uuid;
begin
  select m.team_id into v_team_id from public.matches m where m.id = p_match_id;
  if v_team_id is null or not private.is_team_staff(v_team_id) then
    raise exception 'not_permitted' using errcode = 'P0001';
  end if;
  return query
    select g.id, g.name, g.positions, coalesce(s.level, 'undecided'::public.skill_level), g.added_by, g.created_at
      from public.match_guests g
      left join public.skill_ratings s on s.guest_id = g.id
     where g.match_id = p_match_id
     order by g.created_at, g.id;
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function private.lock_match_for_guests(uuid) from authenticated, service_role;
revoke execute on function
  public.add_match_guest(uuid, text, public.play_position[], public.skill_level),
  public.remove_match_guest(uuid),
  public.get_match_guest_details(uuid)
from public, anon;
grant execute on function
  public.add_match_guest(uuid, text, public.play_position[], public.skill_level),
  public.remove_match_guest(uuid),
  public.get_match_guest_details(uuid)
to authenticated;
