-- 배치 저장·확정·확정 후 수정 (스프린트 03 1-2·1-3·1-4 / data-model.md 5-1~5-4 / Q-075 1·2·7·9번, Q-046, Q-061 3번)
--
-- public.save_lineup 한 함수로 처리한다 (명단 자격·시점 검사를 한 곳에 두려고).
--   - 관리자(팀장·운영진)만. 해체된 팀은 공용 확인 함수가 거짓 → not_permitted.
--   - 시점 (Q-075 1번): 참석 마감 뒤부터 경기 종료 전까지. 마감 전 lineup_not_open, 종료 후 match_already_ended (Q-061 3번).
--     취소된 일정 match_cancelled.
--   - 내용은 한 번에 통째로 저장한다: 팀 수·팀당 인원·팀 블록(번호·조끼 색)·명단·경고 종류.
--     · 팀 블록은 1..팀 수 번호마다 하나, 조끼 색은 한 배치 안에서 중복 불가 (5-2). 자동 배정 순서는 앱(Q-075 8번).
--     · 명단에 넣을 수 있는 사람 (Q-075 2번): 그 팀 현재 팀원 누구나(참석·대기·불참·미투표 상관없음, 참석 응답은 바뀌지 않음)
--       + 그 일정의 게스트. 한 배치에 한 번만. squad_no 가 비면 교체 블록.
--     · 참석자를 모두 넣어야 하는 규칙은 없다 (못 온 사람은 배치에서 빼는 것으로 처리, Q-046).
--     · 팀당 인원보다 많이 넣어도 거절하지 않는다 (직접 옮기기 결과를 막지 않음, 경고는 앱이 셈).
--     · as_goalkeeper 는 항상 false (GK 표시 안 함, Q-075 6번 — 202611050037 주석).
--   - 동시 수정 (Q-075 7번 (5)): 호출자는 마지막으로 읽은 배치의 updated_at 을 넘긴다(처음 만들 때는 null).
--     다르면 lineup_conflict → 앱이 "다른 운영진이 먼저 바꿨어요" 후 새로 불러온다.
--     (배치 뒤 자동 인원 변화(202611050040)도 updated_at 을 바꾸므로 그 뒤의 오래된 저장도 같은 오류.)
--   - 작성 중(draft): 내용만 바꾼다. 알림 없음. p_confirm = true 면 확정 (confirmed_at/by, 확정 알림).
--   - 확정 후(confirmed): 내용이 바뀌었으면 version +1, 변경 이력 1줄(전·후 사람 ID 만),
--     경기 시작 전이면 변경 알림, 시작 후면 알림 없음 (Q-046). 확정 취소(초안으로 되돌리기)는 없다 (Q-075 1번).
--     [변경 저장] 한 번 = 이 함수 한 번 = 알림 한 번 (Q-075 7번 (6)).
--   - 알림 받는 사람 (Q-075 10번):
--       확정  lineup_confirmed  배치 명단(팀 블록 + 교체 블록)의 현재 팀원 전원, 확정한 운영진 본인 제외. 게스트 제외.
--       변경  lineup_changed    변경 전 또는 후 명단에 있던 현재 팀원 모두(빠진 사람도 받음), 수정한 운영진 본인 제외.
--     같은 버전 알림은 한 번 (사건 값 = version). 문구는 private.notification_body (202611050039).
--   - 돌려주는 값: lineup_id, status, version, updated_at (실력·점수 없음).

-- ---------------------------------------------------------------------------
-- 배치 대상 일정 확인·잠금: 관리자, 취소 안 됨, 참석 마감 뒤, 경기 종료 전. 일정 줄을 돌려준다.
-- 잠금 순서: 팀 줄(배타) → 일정 줄(배타) → 배치 줄. 게스트·참석 처리와 같은 순서.
-- ---------------------------------------------------------------------------
create function private.lock_match_for_lineup(p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_match public.matches;
  v_now timestamptz := clock_timestamp();
begin
  select m.team_id into v_team_id from public.matches m where m.id = p_match_id;
  -- 없는 일정·다른 팀 일정은 구분하지 않고 거절
  perform private.lock_team_as_staff(v_team_id);
  select m.* into v_match from public.matches m where m.id = p_match_id for update;
  if v_match.status = 'cancelled' then
    raise exception 'match_cancelled' using errcode = 'P0001';
  end if;
  if v_now >= v_match.ends_at then
    raise exception 'match_already_ended' using errcode = 'P0001';
  end if;
  if v_now < v_match.rsvp_deadline_at then
    raise exception 'lineup_not_open' using errcode = 'P0001';
  end if;
  return v_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- 배치 내용 요약 (변경 이력 before/after, 바뀌었는지 비교). 사람 ID 만, 이름·등급 없음.
-- {"team_count":2,"players_per_team":6,
--  "squads":[{"squad_no":1,"bib_color":"red","user_ids":[...],"guest_ids":[...]}, ...],
--  "bench":{"user_ids":[...],"guest_ids":[...]}}
-- ---------------------------------------------------------------------------
create function private.lineup_snapshot(p_lineup_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'team_count', l.team_count,
    'players_per_team', l.players_per_team,
    'squads', coalesce((
      select jsonb_agg(jsonb_build_object(
               'squad_no', q.squad_no,
               'bib_color', q.bib_color,
               'user_ids', coalesce((select jsonb_agg(s.user_id order by s.user_id) from public.lineup_slots s
                                      where s.squad_id = q.id and s.user_id is not null), '[]'::jsonb),
               'guest_ids', coalesce((select jsonb_agg(s.guest_id order by s.guest_id) from public.lineup_slots s
                                       where s.squad_id = q.id and s.guest_id is not null), '[]'::jsonb)
             ) order by q.squad_no)
        from public.lineup_squads q where q.lineup_id = l.id), '[]'::jsonb),
    'bench', jsonb_build_object(
      'user_ids', coalesce((select jsonb_agg(s.user_id order by s.user_id) from public.lineup_slots s
                             where s.lineup_id = l.id and s.squad_id is null and s.user_id is not null), '[]'::jsonb),
      'guest_ids', coalesce((select jsonb_agg(s.guest_id order by s.guest_id) from public.lineup_slots s
                              where s.lineup_id = l.id and s.squad_id is null and s.guest_id is not null), '[]'::jsonb)
    )
  )
  from public.lineups l
  where l.id = p_lineup_id
$$;

-- 배치 명단의 팀원 중 지금 그 팀 팀원인 사람 (알림 받는 사람 재료)
create function private.lineup_member_ids(p_lineup_id uuid, p_team_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(s.user_id), '{}')
    from public.lineup_slots s
    join public.team_members m on m.user_id = s.user_id and m.team_id = p_team_id and m.status = 'active'
   where s.lineup_id = p_lineup_id
$$;

-- ---------------------------------------------------------------------------
-- 저장 (작성 중 저장·확정·확정 후 수정)
--   p_squads  [{"squad_no":1,"bib_color":"red"}, ...]          (팀 수만큼)
--   p_slots   [{"squad_no":1|null,"user_id":"..."}, {"squad_no":null,"guest_id":"..."}, ...]
-- ---------------------------------------------------------------------------
create function public.save_lineup(
  p_match_id uuid,
  p_expected_updated_at timestamptz,
  p_team_count int,
  p_players_per_team int,
  p_squads jsonb,
  p_slots jsonb,
  p_warnings text[] default null,
  p_confirm boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_profile();
  v_match public.matches;
  v_lineup public.lineups;
  v_warnings text[];
  v_before jsonb;
  v_after jsonb;
  v_before_ids uuid[];
  v_now timestamptz;
  v_bad int;
begin
  v_match := private.lock_match_for_lineup(p_match_id);
  v_now := clock_timestamp();

  select l.* into v_lineup from public.lineups l where l.match_id = p_match_id for update;
  -- 동시 수정: 마지막으로 읽은 배치와 다르면 거절 (처음 만들 때는 null)
  if v_lineup.id is null then
    if p_expected_updated_at is not null then
      raise exception 'lineup_conflict' using errcode = 'P0001';
    end if;
  elsif p_expected_updated_at is null or p_expected_updated_at <> v_lineup.updated_at then
    raise exception 'lineup_conflict' using errcode = 'P0001';
  end if;

  -- 팀 수·팀당 인원
  if p_team_count is null or p_team_count not between 2 and 11
     or p_players_per_team is null or p_players_per_team not between 1 and 50 then
    raise exception 'invalid_lineup' using errcode = 'P0001';
  end if;

  -- 경고 종류 (빈 목록 = 없음)
  v_warnings := case when cardinality(p_warnings) > 0 then p_warnings end;
  if not private.lineup_warnings_valid(v_warnings) then
    raise exception 'invalid_lineup' using errcode = 'P0001';
  end if;

  -- 팀 블록·명단 형식. 형식이 틀린 값(숫자·색·ID 가 아님 등)은 모두 invalid_lineup.
  -- (임시 표를 쓰지 않는다: SECURITY DEFINER 함수가 호출자 세션의 임시 표를 쓰면 위험)
  if p_squads is null or jsonb_typeof(p_squads) <> 'array' or jsonb_array_length(p_squads) <> p_team_count
     or p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    raise exception 'invalid_lineup' using errcode = 'P0001';
  end if;
  begin
    -- 팀 블록: 1..팀 수 번호마다 하나, 조끼 색 중복 없음 (5-2)
    if (select count(*) filter (where x.squad_no between 1 and p_team_count and x.bib_color is not null)
                <> p_team_count
            or count(distinct x.squad_no) <> p_team_count
            or count(distinct x.bib_color) <> p_team_count
          from jsonb_to_recordset(p_squads) as x(squad_no int, bib_color public.bib_color)) then
      raise exception 'invalid_lineup' using errcode = 'P0001';
    end if;

    -- 명단: 사람 하나씩, 팀 블록 번호는 1..팀 수 또는 비움(교체 블록), 한 배치에 한 번만
    if (select coalesce(bool_or(num_nonnulls(x.user_id, x.guest_id) <> 1
                                or (x.squad_no is not null and x.squad_no not between 1 and p_team_count)), false)
               or count(x.user_id) <> count(distinct x.user_id)
               or count(x.guest_id) <> count(distinct x.guest_id)
          from jsonb_to_recordset(p_slots) as x(squad_no int, user_id uuid, guest_id uuid)) then
      raise exception 'invalid_lineup' using errcode = 'P0001';
    end if;
  exception
    when data_exception or invalid_parameter_value then
      raise exception 'invalid_lineup' using errcode = 'P0001';
  end;

  -- 명단 자격: 그 팀 현재 팀원, 그 일정의 게스트 (Q-075 2번)
  select count(*) into v_bad
    from jsonb_to_recordset(p_slots) as i(squad_no int, user_id uuid, guest_id uuid)
   where (i.user_id is not null and private.active_role(v_match.team_id, i.user_id) is null)
      or (i.guest_id is not null and not exists (
            select 1 from public.match_guests g where g.id = i.guest_id and g.match_id = p_match_id));
  if v_bad > 0 then
    raise exception 'invalid_lineup_slot' using errcode = 'P0001';
  end if;

  -- 저장
  if v_lineup.id is null then
    insert into public.lineups (match_id, team_count, players_per_team, status, warnings, updated_at)
    values (p_match_id, p_team_count, p_players_per_team, 'draft', v_warnings, v_now)
    returning * into v_lineup;
  else
    if v_lineup.status = 'confirmed' then
      v_before := private.lineup_snapshot(v_lineup.id);
      v_before_ids := private.lineup_member_ids(v_lineup.id, v_match.team_id);
    end if;
    delete from public.lineup_squads q where q.lineup_id = v_lineup.id;  -- 팀 블록의 명단 줄도 같이 지워짐
    delete from public.lineup_slots s where s.lineup_id = v_lineup.id;   -- 교체 블록 줄
    update public.lineups l
       set team_count = p_team_count,
           players_per_team = p_players_per_team,
           warnings = v_warnings
     where l.id = v_lineup.id;
  end if;

  insert into public.lineup_squads (lineup_id, squad_no, bib_color)
  select v_lineup.id, i.squad_no, i.bib_color
    from jsonb_to_recordset(p_squads) as i(squad_no int, bib_color public.bib_color);

  insert into public.lineup_slots (lineup_id, squad_id, user_id, guest_id, as_goalkeeper)
  select v_lineup.id, q.id, i.user_id, i.guest_id, false
    from jsonb_to_recordset(p_slots) as i(squad_no int, user_id uuid, guest_id uuid)
    left join public.lineup_squads q on q.lineup_id = v_lineup.id and q.squad_no = i.squad_no;

  if v_lineup.status = 'confirmed' then
    -- 확정 후 수정: 내용이 바뀌었을 때만 버전·이력·알림
    v_after := private.lineup_snapshot(v_lineup.id);
    if v_after is distinct from v_before then
      update public.lineups l
         set version = l.version + 1, updated_at = v_now
       where l.id = v_lineup.id
      returning * into v_lineup;
      insert into public.lineup_change_logs (lineup_id, version, changed_by, changed_at, before, after)
      values (v_lineup.id, v_lineup.version, v_uid, v_now, v_before, v_after);
      -- 경기 시작 전이면 변경 알림, 시작 후면 없음 (Q-046)
      if v_now < v_match.starts_at then
        perform private.notify(
          'lineup_changed',
          array_remove(v_before_ids || private.lineup_member_ids(v_lineup.id, v_match.team_id), v_uid),
          v_match.team_id, 'match', v_match.id, v_lineup.version::text,
          null, jsonb_build_object('match_at', v_match.starts_at)
        );
      end if;
    else
      -- 사람 배치는 같고 경고만 바뀐 경우 등: 버전·이력·알림 없음
      update public.lineups l set updated_at = v_now where l.id = v_lineup.id
      returning * into v_lineup;
    end if;
  elsif p_confirm then
    update public.lineups l
       set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_uid, updated_at = v_now
     where l.id = v_lineup.id
    returning * into v_lineup;
    perform private.notify(
      'lineup_confirmed',
      array_remove(private.lineup_member_ids(v_lineup.id, v_match.team_id), v_uid),
      v_match.team_id, 'match', v_match.id, v_lineup.version::text,
      null, jsonb_build_object('match_at', v_match.starts_at)
    );
  else
    update public.lineups l set updated_at = v_now where l.id = v_lineup.id
    returning * into v_lineup;
  end if;

  return jsonb_build_object(
    'lineup_id', v_lineup.id,
    'status', v_lineup.status,
    'version', v_lineup.version,
    'updated_at', v_lineup.updated_at
  );
end;
$$;

revoke execute on all functions in schema private from public, anon;
revoke execute on function
  private.lock_match_for_lineup(uuid),
  private.lineup_snapshot(uuid),
  private.lineup_member_ids(uuid, uuid)
from authenticated, service_role;
revoke execute on function public.save_lineup(uuid, timestamptz, int, int, jsonb, jsonb, text[], boolean) from public, anon;
grant execute on function public.save_lineup(uuid, timestamptz, int, int, jsonb, jsonb, text[], boolean) to authenticated;
