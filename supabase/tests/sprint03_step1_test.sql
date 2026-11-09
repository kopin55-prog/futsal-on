-- 스프린트 03 1단계 마이그레이션(202611050037 배치 표, 202611050038 배치 저장, 202611050039 배치 알림 문구,
-- 202611050040 배치 뒤 인원 변화) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 마감이 지난 일정·시작한 경기·끝난 경기는 서버 권한(postgres)으로 표에 직접 넣어 준비한다.

create function pg_temp.expect_error(p_sql text, p_msg text)
returns void
language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like p_msg then
      raise exception 'case [%] expected [%] got [%]', p_sql, p_msg, sqlerrm;
    end if;
    return;
  end;
  raise exception 'case [%] expected error [%] but succeeded', p_sql, p_msg;
end;
$$;

create function pg_temp.check(p_ok boolean, p_label text)
returns void
language plpgsql
as $$
begin
  if p_ok is not true then
    raise exception 'check failed: %', p_label;
  end if;
end;
$$;

create function pg_temp.login(p_uid uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

create temp table t_vars (k text primary key, v text);
grant all on t_vars to authenticated;

create function pg_temp.v(p_k text)
returns text
language sql
as $$
  select v from t_vars where k = p_k
$$;

create function pg_temp.vid(p_k text)
returns uuid
language sql
as $$
  select v::uuid from t_vars where k = p_k
$$;

-- 사람 번호 → ID
create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000000e' || p_n::text)::uuid
$$;

-- 명단 줄 JSON: 팀원 (squad null = 교체 블록), 게스트
create function pg_temp.su(p_squad int, p_n int)
returns jsonb
language sql
as $$
  select jsonb_build_object('squad_no', p_squad, 'user_id', pg_temp.u(p_n))
$$;

create function pg_temp.sg(p_squad int, p_guest text)
returns jsonb
language sql
as $$
  select jsonb_build_object('squad_no', p_squad, 'guest_id', pg_temp.vid(p_guest))
$$;

-- 기본 팀 블록 2개 (빨강·파랑)
create function pg_temp.sq2()
returns jsonb
language sql
as $$
  select '[{"squad_no":1,"bib_color":"red"},{"squad_no":2,"bib_color":"blue"}]'::jsonb
$$;

-- 그 일정 배치의 updated_at (postgres 로 읽음, security definer 아님 → 호출 전 reset role 필요 없게 t_vars 에 저장)
create function pg_temp.remember_lineup(p_match text)
returns void
language sql
as $$
  insert into t_vars select 'upd_' || p_match, l.updated_at::text from public.lineups l where l.match_id = pg_temp.vid(p_match)
  on conflict (k) do update set v = excluded.v;
$$;

create function pg_temp.upd(p_match text)
returns timestamptz
language sql
as $$
  select v::timestamptz from t_vars where k = 'upd_' || p_match
$$;

-- 그 일정 배치의 명단 (사람 번호 또는 게스트 키, squad 번호 / 'B' = 교체). postgres 로 읽는다.
create function pg_temp.slot_of(p_match text, p_n int)
returns text
language sql
as $$
  select coalesce((
    select coalesce(q.squad_no::text, 'B')
      from public.lineup_slots s
      join public.lineups l on l.id = s.lineup_id
      left join public.lineup_squads q on q.id = s.squad_id
     where l.match_id = pg_temp.vid(p_match) and s.user_id = pg_temp.u(p_n)), 'none')
$$;

create function pg_temp.guest_slot_of(p_match text, p_guest text)
returns text
language sql
as $$
  select coalesce((
    select coalesce(q.squad_no::text, 'B')
      from public.lineup_slots s
      join public.lineups l on l.id = s.lineup_id
      left join public.lineup_squads q on q.id = s.squad_id
     where l.match_id = pg_temp.vid(p_match) and s.guest_id = pg_temp.vid(p_guest)), 'none')
$$;

-- 배치 알림 받은 사람 수
create function pg_temp.notif_count(p_kind text, p_match text, p_n int)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
   where n.kind::text = p_kind and n.ref_id = pg_temp.vid(p_match) and n.user_id = pg_temp.u(p_n)
$$;

create function pg_temp.notif_total(p_kind text, p_match text)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
   where n.kind::text = p_kind and n.ref_id = pg_temp.vid(p_match)
$$;

insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'e' || n || '@test.invalid', now(), now()
  from generate_series(1, 9) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['goalkeeper']::public.play_position[], true, true, true, true, false);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5));
select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(6));
select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(7));
select public.create_profile('칠', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(8));
select public.create_profile('팔', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(9));
select public.create_profile('구', null, array['forward']::public.play_position[], false, true, true, true, false);

-- 팀 P: e1 팀장, e2 운영진, e3~e7 팀원. 팀 Q: e8 팀장. e9 는 팀 없음
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('피FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(8));
insert into t_vars select 'Q', public.create_team('큐FC')::text;
select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'r2', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'r3', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'r4', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'r5', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'r6', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(7)); insert into t_vars select 'r7', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid(k), true) from unnest(array['r2', 'r3', 'r4', 'r5', 'r6', 'r7']) k;
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));

reset role;
-- mA: 마감 지남·2시간 뒤 시작 (정원 3) / mB: 마감 전 / mC: 시작함·종료 전 / mD: 끝남 / mE: 취소 / qA: 팀 Q
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '2 hours', now() + interval '4 hours', 3, now() - interval '1 minute', pg_temp.u(1))
  returning id)
insert into t_vars select 'mA', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '3 days', now() + interval '3 days 2 hours', null, now() + interval '2 days', pg_temp.u(1))
  returning id)
insert into t_vars select 'mB', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '30 minutes', now() + interval '90 minutes', null, now() - interval '3 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mC', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '3 hours', now() - interval '1 minute', null, now() - interval '5 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mD', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by, status, cancelled_at, cancelled_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '2 hours', now() + interval '4 hours', null, now() - interval '1 minute', pg_temp.u(1),
          'cancelled', now(), pg_temp.u(1))
  returning id)
insert into t_vars select 'mE', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('Q'), 'manual', now() + interval '2 hours', now() + interval '4 hours', null, now() - interval '1 minute', pg_temp.u(8))
  returning id)
insert into t_vars select 'qA', id::text from x;

-- mA 참석: e3·e4·e5 참석, e6 대기 1번 (정원 3)
insert into public.attendance_responses (match_id, user_id, state, waitlisted_at)
values (pg_temp.vid('mA'), pg_temp.u(3), 'attending', null),
       (pg_temp.vid('mA'), pg_temp.u(4), 'attending', null),
       (pg_temp.vid('mA'), pg_temp.u(5), 'attending', null),
       (pg_temp.vid('mA'), pg_temp.u(6), 'waitlisted', now());
set local role authenticated;

-- 게스트 g1 (mA, 배치 전), gq (팀 Q 일정)
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'g1', public.add_match_guest(pg_temp.vid('mA'), null, array['forward']::public.play_position[], 'pro')::text;
select pg_temp.login(pg_temp.u(8));
insert into t_vars select 'gq', public.add_match_guest(pg_temp.vid('qA'), null)::text;

-- ================================================================ 1-1 표·권한
-- 실력 등급·점수 칸 없음 (3-4, Q-075 5번)
reset role;
select pg_temp.check((select count(*) = 0 from information_schema.columns
  where table_schema = 'public'
    and table_name in ('lineups', 'lineup_squads', 'lineup_slots', 'lineup_change_logs')
    and (column_name like '%level%' or column_name like '%score%' or column_name like '%skill%')), 'no skill columns');
-- 모든 표 RLS 켜짐
select pg_temp.check((select count(*) = 4 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('lineups', 'lineup_squads', 'lineup_slots', 'lineup_change_logs')
    and c.relrowsecurity), 'rls enabled');
-- 새 SECURITY DEFINER 함수는 search_path 고정
select pg_temp.check((select bool_and(p.proconfig @> array['search_path=""'])
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and p.proname in ('save_lineup', 'lock_match_for_lineup', 'lineup_snapshot', 'lineup_member_ids',
    'is_match_team_staff', 'can_read_lineup', 'is_lineup_staff', 'add_to_lineup_bench',
    'attendance_promoted_to_lineup', 'guest_added_to_lineup', 'cleanup_departed_member')), 'definer search_path fixed');
-- 앱 사용자는 save_lineup 만 실행 (private 도우미 실행 불가)
select pg_temp.check(not has_function_privilege('authenticated', 'private.lineup_snapshot(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.add_to_lineup_bench(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.save_lineup(uuid, timestamptz, int, int, jsonb, jsonb, text[], boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.save_lineup(uuid, timestamptz, int, int, jsonb, jsonb, text[], boolean)', 'execute'),
  'function privileges');
set local role authenticated;

-- 앱 직접 쓰기 거절 (관리자도)
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$insert into public.lineups (match_id, team_count, players_per_team) values (pg_temp.vid('mA'), 2, 6)$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.lineup_slots$$, 'permission denied%');
select pg_temp.expect_error($$update public.lineup_squads set bib_color = 'red'$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.lineup_change_logs (lineup_id, version, before, after) values (gen_random_uuid(), 2, '{}', '{}')$$, 'permission denied%');

-- ================================================================ 1-2 저장 권한·시점
-- 팀원·다른 팀·팀 없음 거절 (L-01)
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'not_permitted');
select pg_temp.login(pg_temp.u(8));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'not_permitted');
select pg_temp.login(pg_temp.u(9));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'not_permitted');
select pg_temp.expect_error($$select public.save_lineup('00000000-0000-4000-8000-000000000000', null, 2, 6, pg_temp.sq2(), '[]')$$, 'not_permitted');

-- 시점: 참석 마감 전 / 경기 종료 후 / 취소 (Q-075 1번, Q-061 3번)
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mB'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'lineup_not_open');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mD'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'match_already_ended');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mE'), null, 2, 6, pg_temp.sq2(), '[]')$$, 'match_cancelled');

-- 형식 검사
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 1, 6, '[{"squad_no":1,"bib_color":"red"}]', '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 12, 6, pg_temp.sq2(), '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 0, pg_temp.sq2(), '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 3, 6, pg_temp.sq2(), '[]')$$, 'invalid_lineup');
-- 같은 배치 안 조끼 색 중복 (5-2)
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6,
  '[{"squad_no":1,"bib_color":"red"},{"squad_no":2,"bib_color":"red"}]', '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6,
  '[{"squad_no":1,"bib_color":"red"},{"squad_no":1,"bib_color":"blue"}]', '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6,
  '[{"squad_no":1,"bib_color":"red"},{"squad_no":2,"bib_color":"gold"}]', '[]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '{"a":1}')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[1]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[{"squad_no":1,"user_id":"x"}]')$$, 'invalid_lineup');
-- 사람 없음·둘 다·같은 사람 두 번·없는 팀 블록 번호
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[{"squad_no":1}]')$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 3) || jsonb_build_object('guest_id', pg_temp.vid('g1'))))$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(2, 3)))$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(3, 3)))$$, 'invalid_lineup');
-- 경고 종류는 정해진 3가지만
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[]', array['프로 2명'])$$, 'invalid_lineup');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(), '[]', array['group_split', 'group_split'])$$, 'invalid_lineup');
-- 명단 자격: 다른 팀 사람, 팀 없는 사람, 다른 일정 게스트 (Q-075 2번)
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 8)))$$, 'invalid_lineup_slot');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(null, 9)))$$, 'invalid_lineup_slot');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 6, pg_temp.sq2(),
  jsonb_build_array(pg_temp.sg(1, 'gq')))$$, 'invalid_lineup_slot');

-- ================================================================ 1-2 초안 저장
-- e3·e4 빨강, e5·e2 파랑, g1 파랑, e7(미투표) 교체 블록 (Q-075 2번: 미투표자도 교체 블록에)
insert into t_vars select 'resA1', public.save_lineup(pg_temp.vid('mA'), null, 2, 3, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(1, 4), pg_temp.su(2, 5), pg_temp.su(2, 2), pg_temp.sg(2, 'g1'), pg_temp.su(null, 7)),
  array['group_split'])::text;
select pg_temp.check((pg_temp.v('resA1')::jsonb ->> 'status') = 'draft' and (pg_temp.v('resA1')::jsonb ->> 'version') = '1', 'draft saved');
select pg_temp.check(not (pg_temp.v('resA1')::jsonb ? 'level') and not (pg_temp.v('resA1')::jsonb ? 'score'), 'result has no skill');
reset role;
select pg_temp.check(pg_temp.slot_of('mA', 3) = '1' and pg_temp.slot_of('mA', 4) = '1' and pg_temp.slot_of('mA', 5) = '2'
  and pg_temp.slot_of('mA', 2) = '2' and pg_temp.slot_of('mA', 7) = 'B' and pg_temp.guest_slot_of('mA', 'g1') = '2'
  and pg_temp.slot_of('mA', 6) = 'none', 'draft slots');
select pg_temp.check((select bool_and(not s.as_goalkeeper) from public.lineup_slots s
  join public.lineups l on l.id = s.lineup_id where l.match_id = pg_temp.vid('mA')), 'as_goalkeeper always false');
select pg_temp.check((select warnings = array['group_split'] and confirmed_at is null from public.lineups
  where match_id = pg_temp.vid('mA')), 'warnings stored');
-- 초안 저장은 알림 없음
select pg_temp.check(pg_temp.notif_total('lineup_confirmed', 'mA') = 0 and pg_temp.notif_total('lineup_changed', 'mA') = 0, 'no notification for draft');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- 초안은 팀원에게 0건 (배치·팀 블록·명단 모두, L-02). 관리자는 읽음.
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) = 0 from public.lineups where match_id = pg_temp.vid('mA')), 'member cannot read draft');
select pg_temp.check((select count(*) = 0 from public.lineup_squads), 'member cannot read draft squads');
select pg_temp.check((select count(*) = 0 from public.lineup_slots), 'member cannot read draft slots');
select pg_temp.login(pg_temp.u(2));
select pg_temp.check((select count(*) = 1 from public.lineups where match_id = pg_temp.vid('mA')), 'manager reads draft');
select pg_temp.check((select count(*) = 6 from public.lineup_slots), 'manager reads draft slots');
select pg_temp.login(pg_temp.u(8));
select pg_temp.check((select count(*) = 0 from public.lineups) and (select count(*) = 0 from public.lineup_slots), 'other team reads none');

-- 동시 수정 (Q-075 7번 (5)): 이미 있는데 null, 오래된 시각 → lineup_conflict
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), null, 2, 3, pg_temp.sq2(), '[]')$$, 'lineup_conflict');
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA') - interval '1 second', 2, 3, pg_temp.sq2(), '[]')$$, 'lineup_conflict');

-- 초안 다시 저장 (조끼 색 변경: 빨강 → 노조끼) → 내용 바뀜, 버전 1 그대로, 알림 없음
insert into t_vars select 'resA2', public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3,
  '[{"squad_no":1,"bib_color":"no_bib"},{"squad_no":2,"bib_color":"blue"}]',
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(1, 4), pg_temp.su(2, 5), pg_temp.su(2, 2), pg_temp.sg(2, 'g1'), pg_temp.su(null, 7)))::text;
select pg_temp.check((pg_temp.v('resA2')::jsonb ->> 'version') = '1' and (pg_temp.v('resA2')::jsonb ->> 'status') = 'draft', 'draft resaved');
reset role;
select pg_temp.check((select warnings is null from public.lineups where match_id = pg_temp.vid('mA')), 'empty warnings = null');
select pg_temp.check((select array_agg(q.bib_color::text order by q.squad_no) = array['no_bib', 'blue'] from public.lineup_squads q
  join public.lineups l on l.id = q.lineup_id where l.match_id = pg_temp.vid('mA')), 'bib colors replaced');
select pg_temp.check((select count(*) = 0 from public.lineup_change_logs), 'no change log for draft');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- ================================================================ 1-3 확정 + 1-5 확정 알림
-- 운영진 e2 가 확정 → 명단 팀원(e3·e4·e5·e7) 이 받음, 확정한 e2 본인·명단에 없는 e1·e6·게스트 제외 (Q-075 10번)
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'resA3', public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3,
  '[{"squad_no":1,"bib_color":"no_bib"},{"squad_no":2,"bib_color":"blue"}]',
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(1, 4), pg_temp.su(2, 5), pg_temp.su(2, 2), pg_temp.sg(2, 'g1'), pg_temp.su(null, 7)),
  null, true)::text;
select pg_temp.check((pg_temp.v('resA3')::jsonb ->> 'status') = 'confirmed' and (pg_temp.v('resA3')::jsonb ->> 'version') = '1', 'confirmed');
reset role;
select pg_temp.check((select confirmed_by = pg_temp.u(2) and confirmed_at is not null from public.lineups
  where match_id = pg_temp.vid('mA')), 'confirmed_by recorded');
select pg_temp.check(pg_temp.notif_count('lineup_confirmed', 'mA', 3) = 1 and pg_temp.notif_count('lineup_confirmed', 'mA', 4) = 1
  and pg_temp.notif_count('lineup_confirmed', 'mA', 5) = 1 and pg_temp.notif_count('lineup_confirmed', 'mA', 7) = 1, 'confirm recipients');
select pg_temp.check(pg_temp.notif_count('lineup_confirmed', 'mA', 2) = 0 and pg_temp.notif_count('lineup_confirmed', 'mA', 1) = 0
  and pg_temp.notif_count('lineup_confirmed', 'mA', 6) = 0 and pg_temp.notif_total('lineup_confirmed', 'mA') = 4, 'confirm non-recipients');
select pg_temp.check((select bool_and(n.body = private.match_time_label(m.starts_at) || ' 경기 팀 배치가 나왔어요! 내 팀을 확인해 보세요.'
    and n.title = '피FC' and n.ref_type = 'match' and n.actor_id is null)
  from public.notifications n join public.matches m on m.id = n.ref_id
  where n.kind = 'lineup_confirmed' and n.ref_id = pg_temp.vid('mA')), 'confirm text');
select pg_temp.check((select count(*) = 4 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'lineup_confirmed' and n.ref_id = pg_temp.vid('mA')), 'confirm queued for push');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- 확정 뒤 팀원 전체가 읽음 (명단에 없는 e6 포함), 다른 팀 0건, 변경 이력은 관리자만 (L-02, L-08)
select pg_temp.login(pg_temp.u(6));
select pg_temp.check((select count(*) = 1 from public.lineups where match_id = pg_temp.vid('mA')), 'member reads confirmed');
select pg_temp.check((select count(*) = 2 from public.lineup_squads), 'member reads confirmed squads');
select pg_temp.check((select count(*) = 6 from public.lineup_slots), 'member reads confirmed slots');
select pg_temp.login(pg_temp.u(8));
select pg_temp.check((select count(*) = 0 from public.lineups) and (select count(*) = 0 from public.lineup_squads), 'other team still none');
reset role;
set local role anon;
select pg_temp.expect_error($$select count(*) from public.lineups$$, 'permission denied%');
reset role;
set local role authenticated;

-- 확정 상태에서 p_confirm = false 로 저장해도 초안으로 돌아가지 않음 (확정 취소 없음, Q-075 1번).
-- 내용이 같으면 버전·이력·알림 없음
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'resA4', public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3,
  '[{"squad_no":1,"bib_color":"no_bib"},{"squad_no":2,"bib_color":"blue"}]',
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(1, 4), pg_temp.su(2, 5), pg_temp.su(2, 2), pg_temp.sg(2, 'g1'), pg_temp.su(null, 7)),
  array['rival_same_team'], false)::text;
select pg_temp.check((pg_temp.v('resA4')::jsonb ->> 'status') = 'confirmed' and (pg_temp.v('resA4')::jsonb ->> 'version') = '1', 'no revert, same version');
reset role;
select pg_temp.check((select count(*) = 0 from public.lineup_change_logs), 'no log when people unchanged');
select pg_temp.check(pg_temp.notif_total('lineup_changed', 'mA') = 0, 'no change notification when unchanged');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- ================================================================ 1-4 확정 후 수정 (시작 전) + 1-5 변경 알림
-- e2 가 e4 를 파랑으로, e7 을 뺌 → version 2, 이력 1줄, 변경 전·후 명단 팀원(e3·e4·e5·e7) 이 받음, e2 본인 제외
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'resA5', public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3,
  '[{"squad_no":1,"bib_color":"no_bib"},{"squad_no":2,"bib_color":"blue"}]',
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(2, 4), pg_temp.su(2, 5), pg_temp.su(2, 2), pg_temp.sg(1, 'g1')))::text;
select pg_temp.check((pg_temp.v('resA5')::jsonb ->> 'version') = '2', 'version 2');
-- 같은 화면(오래된 updated_at)으로 다시 저장 → lineup_conflict
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3, pg_temp.sq2(), '[]')$$, 'lineup_conflict');
reset role;
select pg_temp.check((select count(*) = 1 and min(c.version) = 2 and min(changed_by::text) = pg_temp.u(2)::text from public.lineup_change_logs c
  join public.lineups l on l.id = c.lineup_id where l.match_id = pg_temp.vid('mA')), 'one change log');
select pg_temp.check((select (c.before -> 'bench' -> 'user_ids') @> to_jsonb(array[pg_temp.u(7)])
    and not ((c.after -> 'bench' -> 'user_ids') @> to_jsonb(array[pg_temp.u(7)]))
    and (c.after -> 'squads' -> 1 -> 'user_ids') @> to_jsonb(array[pg_temp.u(4)])
    and (c.after -> 'squads' -> 0 -> 'guest_ids') @> to_jsonb(array[pg_temp.vid('g1')])
  from public.lineup_change_logs c), 'change log before/after');
-- 이력에는 사람 ID 만 (이름·등급 없음)
select pg_temp.check((select c.before::text not like '%삼%' and c.after::text not like '%level%'
    and c.after::text not like '%pro%' and c.after::text not like '%amateur%' from public.lineup_change_logs c), 'log has ids only');
select pg_temp.check(pg_temp.notif_count('lineup_changed', 'mA', 3) = 1 and pg_temp.notif_count('lineup_changed', 'mA', 4) = 1
  and pg_temp.notif_count('lineup_changed', 'mA', 5) = 1 and pg_temp.notif_count('lineup_changed', 'mA', 7) = 1, 'change recipients incl. removed');
select pg_temp.check(pg_temp.notif_count('lineup_changed', 'mA', 2) = 0 and pg_temp.notif_count('lineup_changed', 'mA', 1) = 0
  and pg_temp.notif_total('lineup_changed', 'mA') = 4, 'change non-recipients');
select pg_temp.check((select bool_and(n.body = private.match_time_label(m.starts_at) || ' 경기 팀 배치가 바뀌었어요. 다시 확인해 주세요.'
    and n.dedupe_key like 'lineup_changed:%:2')
  from public.notifications n join public.matches m on m.id = n.ref_id
  where n.kind = 'lineup_changed' and n.ref_id = pg_temp.vid('mA')), 'change text and dedupe by version');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- 변경 이력: 관리자는 읽고 팀원은 0건 (L-08)
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) = 0 from public.lineup_change_logs), 'member cannot read change logs');
select pg_temp.login(pg_temp.u(1));
select pg_temp.check((select count(*) = 1 from public.lineup_change_logs), 'owner reads change logs');

-- 두 번째 수정 → version 3, 알림은 저장 한 번에 한 번 (Q-075 7번 (6))
insert into t_vars select 'resA6', public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3,
  '[{"squad_no":1,"bib_color":"no_bib"},{"squad_no":2,"bib_color":"blue"}]',
  jsonb_build_array(pg_temp.su(1, 3), pg_temp.su(2, 4), pg_temp.su(1, 5), pg_temp.su(2, 2), pg_temp.sg(1, 'g1')))::text;
select pg_temp.check((pg_temp.v('resA6')::jsonb ->> 'version') = '3', 'version 3');
reset role;
-- e1 이 수정 → e2 도 받음 (명단에 있음), e1 제외
select pg_temp.check(pg_temp.notif_count('lineup_changed', 'mA', 2) = 1 and pg_temp.notif_count('lineup_changed', 'mA', 3) = 2
  and pg_temp.notif_count('lineup_changed', 'mA', 7) = 1 and pg_temp.notif_count('lineup_changed', 'mA', 1) = 0, 'second change notified once');
select pg_temp.remember_lineup('mA');
set local role authenticated;

-- ================================================================ 시작한 경기 (mC): 확정·수정 가능, 수정 알림 없음 (Q-046)
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'resC1', public.save_lineup(pg_temp.vid('mC'), null, 2, 2, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 5), pg_temp.su(2, 4)), null, true)::text;
select pg_temp.check((pg_temp.v('resC1')::jsonb ->> 'status') = 'confirmed', 'confirm after start allowed');
reset role;
select pg_temp.check(pg_temp.notif_total('lineup_confirmed', 'mC') = 2, 'confirm after start still notifies roster');
select pg_temp.remember_lineup('mC');
set local role authenticated;
insert into t_vars select 'resC2', public.save_lineup(pg_temp.vid('mC'), pg_temp.upd('mC'), 2, 2, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 5), pg_temp.su(1, 4)))::text;
select pg_temp.check((pg_temp.v('resC2')::jsonb ->> 'version') = '2', 'edit after start bumps version');
reset role;
select pg_temp.check((select count(*) = 1 from public.lineup_change_logs c join public.lineups l on l.id = c.lineup_id
  where l.match_id = pg_temp.vid('mC')), 'edit after start logged');
select pg_temp.check(pg_temp.notif_total('lineup_changed', 'mC') = 0, 'no change notification after start');
-- 확정된 배치도 경기 종료 후에는 수정 거절 (Q-061 3번): mC 종료 시각을 지난 것으로 바꿔 확인
select pg_temp.remember_lineup('mC');
update public.matches set ends_at = now() - interval '1 second' where id = pg_temp.vid('mC');
set local role authenticated;
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mC'), pg_temp.upd('mC'), 2, 2, pg_temp.sq2(), '[]')$$, 'match_already_ended');
reset role;
update public.matches set ends_at = now() + interval '90 minutes' where id = pg_temp.vid('mC');
set local role authenticated;

-- ================================================================ 강등된 운영진은 바로 거절 (3-5)
select pg_temp.login(pg_temp.u(1));
select public.dismiss_manager(pg_temp.vid('P'), pg_temp.u(2));
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3, pg_temp.sq2(), '[]')$$, 'not_permitted');
select pg_temp.check((select count(*) = 0 from public.lineup_change_logs), 'demoted cannot read change logs');
select pg_temp.check((select count(*) = 1 from public.lineups where match_id = pg_temp.vid('mA')), 'demoted still reads confirmed as member');

-- ================================================================ 1-6 배치 뒤 인원 변화 (Q-075 3번)
-- (1)+(2) 참석자 e3 팀 탈퇴 → 시작 전 배치(mA)에서 빠짐, 대기 1번 e6 자동 참석 → 교체 블록. 알림·버전 없음
reset role;
insert into t_vars select 'chg_before', (select count(*) from public.notifications where kind in ('lineup_changed', 'lineup_confirmed'))::text;
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.slot_of('mA', 3) = 'none', 'departed member removed from upcoming lineup');
select pg_temp.check((select state = 'attending' from public.attendance_responses
  where match_id = pg_temp.vid('mA') and user_id = pg_temp.u(6)), 'e6 promoted');
select pg_temp.check(pg_temp.slot_of('mA', 6) = 'B', 'promoted member added to bench');
select pg_temp.check((select version = 3 and updated_at > pg_temp.upd('mA') from public.lineups where match_id = pg_temp.vid('mA')),
  'auto change: no version bump, updated_at changed');
select pg_temp.check((select count(*) = 1 from public.lineup_change_logs c join public.lineups l on l.id = c.lineup_id
  where l.match_id = pg_temp.vid('mA') and c.version = 3) and (select count(*) = 2 from public.lineup_change_logs c
  join public.lineups l on l.id = c.lineup_id where l.match_id = pg_temp.vid('mA')), 'auto change: no change log');
set local role authenticated;
-- 자동 변화 전에 불러온 화면으로 저장 → lineup_conflict (다시 불러오기)
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3, pg_temp.sq2(), '[]')$$, 'lineup_conflict');
-- 떠난 사람은 명단에 다시 넣을 수 없음
reset role;
select pg_temp.remember_lineup('mA');
set local role authenticated;
select pg_temp.expect_error($$select public.save_lineup(pg_temp.vid('mA'), pg_temp.upd('mA'), 2, 3, pg_temp.sq2(),
  jsonb_build_array(pg_temp.su(1, 3)))$$, 'invalid_lineup_slot');

-- (3) 게스트 추가 → 교체 블록, (4) 게스트 삭제 → 명단에서 빠짐
insert into t_vars select 'g2', public.add_match_guest(pg_temp.vid('mA'), '둘째')::text;
select public.remove_match_guest(pg_temp.vid('g1'));
reset role;
select pg_temp.check(pg_temp.guest_slot_of('mA', 'g2') = 'B', 'new guest added to bench');
select pg_temp.check((select count(*) = 0 from public.lineup_slots where guest_id = pg_temp.vid('g1')), 'removed guest gone from lineup');
set local role authenticated;
-- 배치가 없는 일정에 게스트 추가 → 아무 배치도 생기지 않음
insert into t_vars select 'gB', public.add_match_guest(pg_temp.vid('mB'), null)::text;
reset role;
select pg_temp.check((select count(*) = 0 from public.lineups where match_id = pg_temp.vid('mB')), 'no lineup created by guest add');

-- 시작한 경기의 배치에는 남음: e5 팀 탈퇴 → mA 에서 빠지고 mC 에는 남음 (Q-075 3번)
set local role authenticated;
select pg_temp.login(pg_temp.u(5));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.slot_of('mA', 5) = 'none' and pg_temp.slot_of('mC', 5) = '1', 'started lineup keeps departed member');
select pg_temp.check((select count(*) from public.notifications where kind in ('lineup_changed', 'lineup_confirmed'))::text
  = pg_temp.v('chg_before'), 'auto changes send no lineup notification');

-- 회원 탈퇴 → 명단 줄이 같이 지워짐 (5-3)
select public.delete_account(pg_temp.u(4));
select pg_temp.check(pg_temp.slot_of('mA', 4) = 'none' and pg_temp.slot_of('mC', 4) = 'none', 'deleted account slots cascade');

-- 일정 삭제 → 배치·팀 블록·명단·이력이 같이 지워짐 (7-2 일부)
delete from public.matches where id = pg_temp.vid('mC');
select pg_temp.check((select count(*) = 0 from public.lineups where match_id = pg_temp.vid('mC')), 'lineup deleted with match');
select pg_temp.check((select count(*) = 1 from public.lineups), 'only mA lineup left');
select pg_temp.check((select count(*) = 2 from public.lineup_change_logs), 'only mA logs left');

select 'ALL PASSED' as result;
