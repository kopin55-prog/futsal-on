-- 직접 적는 게스트 이름에 "게스트+숫자" 모양 불가 (Q-074 2번, decisions.md 2026-11-09)
--
-- - 이름 없이 추가한 게스트는 화면에 "게스트{번호}" 로 보이므로, 적는 이름이 그 모양이면 나중 번호와 겹친다.
-- - 판단: 보이지 않는 문자·앞뒤 공백 정리(normalize_single_line_name) 뒤 남은 공백을 모두 빼고
--   "게스트" + 숫자(0-9, 전각 ０-９) 1개 이상이면 불가. 그래서 "게스트6", " 게스트 6 ", "게스트 06", "게스트６" 모두 불가.
--   "게스트" 만, "게스트A", "게스트6번", "김게스트6" 은 가능.
-- - add_match_guest 가 먼저 reserved_guest_name 으로 거절. 서버 권한 직접 넣기·바꾸기도 막도록 표 검사도 둔다
--   (기존 줄은 검사하지 않음: not valid).
-- - 앱(guest_models.dart isReservedGuestName)도 같은 규칙.
-- - 실행 권한은 표 검사에 쓰는 다른 private 이름 함수(is_valid_single_line_name)와 같게 둔다(public·anon 만 회수).

create function private.is_reserved_guest_name(p_name text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select private.remove_whitespace(private.normalize_single_line_name(p_name)) ~ '^게스트[0-9０-９]+$'
$$;

alter table public.match_guests
  add constraint match_guests_name_not_reserved
  check (name is null or not private.is_reserved_guest_name(name)) not valid;

-- 게스트 추가 (202611050032 + 예약 모양 검사)
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
          or not private.positions_are_distinct(v_positions)) then
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
