-- 게스트 v4.4 (data-model.md 4-3, Q-073 2·3번, decisions.md 2026-11-09)
--
-- - name 선택: 비우면 화면에 "게스트{guest_no}". 적으면 팀에서 쓸 이름과 같은 규칙(정리 후 1~8자).
-- - guest_no: 그 일정 안 게스트 번호. 1부터 추가 순서, 붙은 뒤 바뀌지 않는다(다른 게스트를 지워도 그대로).
--   새 번호 = 그 일정의 지금 가장 큰 번호 + 1. (가장 큰 번호의 게스트를 지운 뒤 다시 추가하면 그 번호가 다시
--   쓰인다 — 지운 번호까지 기억하려면 승인되지 않은 칸이 필요해 lead 보고.)
-- - 한 일정 게스트 최대 12명 (guest_limit_reached).
-- - 같은 일정 안에서 표시 이름("게스트N" 포함) 중복 불가 (duplicate_guest_name). 서버 함수가 먼저 검사하고,
--   표에도 고유 색인을 둔다(동시 추가는 일정 줄 잠금으로 한 줄씩 처리).
-- - 기존 줄 이전: 일정마다 created_at 순으로 번호를 붙이고, 같은 일정에 같은 이름이 있으면 뒤의 것은 이름을 비운다
--   ("게스트N"으로 보임). 개발 DB 에는 기존 게스트가 없다(2026-11-09 확인).
-- - 팀원 읽기 칸에 guest_no 추가. 포지션은 계속 관리자 전용 함수로만 (Q-017).

-- ---------------------------------------------------------------------------
-- 칸·이전
-- ---------------------------------------------------------------------------
alter table public.match_guests add column guest_no int;

update public.match_guests g
   set guest_no = x.n
  from (select id, row_number() over (partition by match_id order by created_at, id) as n
          from public.match_guests) x
 where x.id = g.id;

alter table public.match_guests alter column name drop not null;

update public.match_guests g
   set name = null
  from (select id, row_number() over (partition by match_id, name order by guest_no) as rn
          from public.match_guests) x
 where x.id = g.id and x.rn > 1;

alter table public.match_guests
  alter column guest_no set not null,
  add constraint match_guests_guest_no_range check (guest_no between 1 and 10000),
  drop constraint match_guests_name_valid,
  add constraint match_guests_name_valid check (name is null or private.is_valid_single_line_name(name, 8));

create unique index match_guests_no_once on public.match_guests (match_id, guest_no);

-- 화면 표시 이름 (이름이 없으면 "게스트{번호}"). 색인·서버 함수·앱이 같은 규칙.
create function private.guest_display_name(p_name text, p_guest_no int)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(p_name, '게스트' || p_guest_no::text)
$$;

create unique index match_guests_display_name_once
  on public.match_guests (match_id, private.guest_display_name(name, guest_no));

-- 번호를 주지 않고 넣으면 그 일정의 다음 번호 (서버 함수·서버 권한 직접 넣기 공통)
create function private.match_guests_assign_no()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.guest_no is null then
    select coalesce(max(g.guest_no), 0) + 1 into new.guest_no
      from public.match_guests g where g.match_id = new.match_id;
  end if;
  return new;
end;
$$;

create trigger match_guests_assign_no
before insert on public.match_guests
for each row execute function private.match_guests_assign_no();

-- 번호는 바뀌지 않는다
create function private.match_guests_keep_no()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.guest_no := old.guest_no;
  return new;
end;
$$;

create trigger match_guests_keep_no
before update on public.match_guests
for each row execute function private.match_guests_keep_no();

grant select (guest_no) on table public.match_guests to authenticated;

-- ---------------------------------------------------------------------------
-- 게스트 추가 (202611050026 + 이름 선택·번호·12명·같은 이름 불가)
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

-- ---------------------------------------------------------------------------
-- 관리자용 게스트 정보: 번호 추가 (돌려주는 칸이 바뀌어 다시 만든다)
-- ---------------------------------------------------------------------------
drop function public.get_match_guest_details(uuid);

create function public.get_match_guest_details(p_match_id uuid)
returns table (
  id uuid,
  guest_no int,
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
    select g.id, g.guest_no, g.name, g.positions, coalesce(s.level, 'undecided'::public.skill_level), g.added_by, g.created_at
      from public.match_guests g
      left join public.skill_ratings s on s.guest_id = g.id
     where g.match_id = p_match_id
     order by g.guest_no;
end;
$$;

-- ---------------------------------------------------------------------------
-- 실행 권한
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.match_guests_assign_no(),
  private.match_guests_keep_no()
from public, anon, authenticated, service_role;
revoke execute on function private.guest_display_name(text, int) from authenticated, service_role;
revoke execute on function public.get_match_guest_details(uuid) from public, anon;
grant execute on function public.get_match_guest_details(uuid) to authenticated;
