-- 선호 포지션 선택지 변경: 골키퍼·수비·측면·공격·올라운더 ("중앙" 폐지) (스프린트 04 1-8 / data-model.md v4.6 2-3·4-3,
-- decisions 2026-11-10 kopn 지시·lead 정리)
--
-- - 올라운더는 단독 선택: 올라운더가 들어 있으면 그것 하나만. 그 밖의 규칙(1~3개, 중복 없음, 골키퍼도 개수에 포함)은 그대로.
-- - 전문 골키퍼는 positions 에 골키퍼가 필요(Q-019)하므로 올라운더와 함께일 수 없다(기존 검사 + 단독 검사로 자동으로 막힘).
-- - 게스트 포지션(선택, 최대 3개)도 같은 선택지·같은 단독 규칙.
-- - 기존 데이터(개발 DB): "중앙"(midfielder)을 빼고, 빼서 비면 올라운더로.
--   방법: 다른 포지션과 함께 있는 "중앙"은 먼저 지우고, "중앙" 하나만 남은 줄은 그대로 둔 채
--   enum 값 이름을 midfielder → allrounder 로 바꾼다. 그래서 "중앙"만 있던 줄은 올라운더가 되고,
--   enum 형을 다시 만들지 않으므로 이 형을 쓰는 서버 함수 인자·반환형은 바뀌지 않는다.
--   (enum 안 순서는 goalkeeper, defender, allrounder, winger, forward 가 된다. 순서로 정렬하는 곳은 없다.)
-- - add_match_guest 는 표 검사보다 먼저 invalid_positions 로 거절하도록 단독 검사를 더한다(202611050035 + 한 줄).
--   create_profile·update_own_profile 은 표 검사 위반을 이미 invalid_positions 로 바꾼다.

-- ---------------------------------------------------------------------------
-- 1) 기존 "중앙" 정리 (다른 포지션과 함께면 빼기)
-- ---------------------------------------------------------------------------
update public.profile_play_prefs
   set positions = array_remove(positions, 'midfielder'::public.play_position)
 where 'midfielder'::public.play_position = any (positions)
   and cardinality(positions) > 1;

update public.match_guests
   set positions = array_remove(positions, 'midfielder'::public.play_position)
 where 'midfielder'::public.play_position = any (positions)
   and cardinality(positions) > 1;

-- ---------------------------------------------------------------------------
-- 2) 값 이름 바꾸기: "중앙"만 남은 줄 → 올라운더
-- ---------------------------------------------------------------------------
alter type public.play_position rename value 'midfielder' to 'allrounder';

-- ---------------------------------------------------------------------------
-- 3) 올라운더 단독 검사
-- ---------------------------------------------------------------------------
create function private.positions_allrounder_alone(p_positions public.play_position[])
returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$
  select not ('allrounder'::public.play_position = any (p_positions)) or cardinality(p_positions) = 1
$$;

alter table public.profile_play_prefs
  add constraint profile_play_prefs_allrounder_alone check (private.positions_allrounder_alone(positions));

alter table public.match_guests
  add constraint match_guests_allrounder_alone
  check (positions is null or private.positions_allrounder_alone(positions));

-- ---------------------------------------------------------------------------
-- 4) 게스트 추가 (202611050035 + 올라운더 단독 검사)
-- ---------------------------------------------------------------------------
create or replace function public.add_match_guest(
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
  v_no int;
  v_positions public.play_position[];
  v_id uuid;
begin
  v_team_id := private.lock_match_for_guests(p_match_id);

  -- 비우면(공백·보이지 않는 문자만 포함) 이름 없음 → "게스트N"
  v_name := nullif(private.normalize_single_line_name(coalesce(p_name, '')), '');
  if v_name is not null
     and (private.grapheme_count(v_name) not between 1 and 8
          or not private.is_valid_single_line_name(v_name, 8)) then
    raise exception 'invalid_guest_name' using errcode = 'P0001';
  end if;

  -- "게스트+숫자" 모양은 이름 없는 게스트의 표시 이름과 겹치므로 쓸 수 없다 (Q-074 2번)
  if v_name is not null and private.is_reserved_guest_name(v_name) then
    raise exception 'reserved_guest_name' using errcode = 'P0001';
  end if;

  v_positions := case when coalesce(cardinality(p_positions), 0) = 0 then null else p_positions end;
  if v_positions is not null
     and (cardinality(v_positions) > 3
          or array_position(v_positions, null) is not null
          or not private.positions_are_distinct(v_positions)
          -- 올라운더는 단독 (v4.6)
          or not private.positions_allrounder_alone(v_positions)) then
    raise exception 'invalid_positions' using errcode = 'P0001';
  end if;

  if (select count(*) from public.match_guests g where g.match_id = p_match_id) >= 12 then
    raise exception 'guest_limit_reached' using errcode = 'P0001';
  end if;

  select coalesce(max(g.guest_no), 0) + 1 into v_no
    from public.match_guests g where g.match_id = p_match_id;

  if exists (
    select 1 from public.match_guests g
     where g.match_id = p_match_id
       and private.guest_display_name(g.name, g.guest_no) = private.guest_display_name(v_name, v_no)
  ) then
    raise exception 'duplicate_guest_name' using errcode = 'P0001';
  end if;

  begin
    insert into public.match_guests (match_id, team_id, guest_no, name, positions, added_by)
    values (p_match_id, v_team_id, v_no, v_name, v_positions, v_uid)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'duplicate_guest_name' using errcode = 'P0001';
  end;

  if p_skill_level is not null and p_skill_level <> 'undecided' then
    insert into public.skill_ratings (team_id, guest_id, level, updated_by, updated_at)
    values (v_team_id, v_id, p_skill_level, v_uid, now());
  end if;

  return v_id;
end;
$$;

revoke execute on all functions in schema private from public, anon;
-- 표 검사에 쓰므로 positions_are_distinct 와 같이 앱 사용자 실행 권한 (profile_play_prefs 는 본인이 칸 단위로 고칠 수 있음)
grant execute on function private.positions_allrounder_alone(public.play_position[]) to authenticated;
