-- 스프린트 04 3·4단계 동작 확인 스크립트.
--   3-1 내 기록 읽기 함수(202611050066 get_my_records): 본인 것만, 팀별·시즌별, 떠난 팀·해체된 팀 포함, 득표수 없음.
--   4-1 대시보드 읽기 범위 회귀: 팀원 계정으로 표를 직접 읽어도 초안 배치·실력 등급·다른 사람 포지션·득표수·
--       지난 부상·가입 신청이 안 나온다(대시보드는 새 서버 함수 없이 기존 권한 규칙으로 읽는다).
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.

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
grant all on t_vars to authenticated, anon;

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

create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000044' || lpad(p_n::text, 2, '0'))::uuid
$$;

create temp table t_rec as select * from public.get_my_records() where false;
grant all on t_rec to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 준비
--   팀 A: u1 팀장, u2·u3·u7 팀원.  팀 B: u4 팀장, u2 팀원(나중에 탈퇴).  팀 E: u4 팀장, u2 팀원(나중에 해체)
--   u5: 팀 A 에 가입 신청만(대기). u6: 프로필 없음. u7: 부상 동의 + 진행 중 부상
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'r44' || n || '@test.invalid', now(), now()
  from generate_series(1, 7) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['defender']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5));
select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(7));
select public.create_profile('칠', null, array['forward']::public.play_position[], false, true, true, true, true);

select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'A', public.create_team('기록A')::text;
select pg_temp.login(pg_temp.u(4));
insert into t_vars select 'B', public.create_team('기록B')::text;
insert into t_vars select 'E', public.create_team('기록E')::text;
reset role;
insert into t_vars select 'codeA', team_code from public.teams where id = pg_temp.vid('A');
insert into t_vars select 'codeB', team_code from public.teams where id = pg_temp.vid('B');
insert into t_vars select 'codeE', team_code from public.teams where id = pg_temp.vid('E');

set local role authenticated;
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeA'), 'code');
select pg_temp.login(pg_temp.u(3)); select public.request_join(pg_temp.v('codeA'), 'code');
select pg_temp.login(pg_temp.u(7)); select public.request_join(pg_temp.v('codeA'), 'code');
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('A');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeB'), 'code');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeE'), 'code');
select pg_temp.login(pg_temp.u(4));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id in (pg_temp.vid('B'), pg_temp.vid('E'));
-- u5 는 팀 A 에 신청만 (대기)
select pg_temp.login(pg_temp.u(5)); select public.request_join(pg_temp.v('codeA'), 'code');
reset role;

-- 기록 숫자 (서버만 쓰는 표 → 서버 권한으로 준비)
insert into public.member_season_stats (user_id, team_id, season, attendance_count, pom_count, goal_of_the_day_count) values
  (pg_temp.u(2), pg_temp.vid('A'), 2025, 3, 1, 0),
  (pg_temp.u(2), pg_temp.vid('A'), 2026, 5, 0, 2),
  (pg_temp.u(2), pg_temp.vid('B'), 2026, 1, 0, 0),
  (pg_temp.u(2), pg_temp.vid('E'), 2026, 2, 1, 1),
  (pg_temp.u(3), pg_temp.vid('A'), 2026, 9, 4, 4);
insert into public.monthly_vote_participation (team_id, user_id, month, attendance_vote_eligible, attendance_vote_responded) values
  (pg_temp.vid('A'), pg_temp.u(2), date '2026-01-01', 2, 2),
  (pg_temp.vid('A'), pg_temp.u(2), date '2026-03-01', 2, 1),
  (pg_temp.vid('A'), pg_temp.u(2), date '2025-12-01', 3, 2),
  -- 팀 B 2025: 투표 기록만 있고 출석·수상 줄은 없음 → 숫자 0 + 투표 횟수
  (pg_temp.vid('B'), pg_temp.u(2), date '2025-07-01', 1, 0),
  (pg_temp.vid('A'), pg_temp.u(3), date '2026-01-01', 5, 5);

-- ---------------------------------------------------------------------------
-- 1. 본인 것만, 팀별·시즌별, 투표는 월 → 연도 합산
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
insert into t_rec select * from public.get_my_records();
reset role;

select pg_temp.check((select count(*) = 5 from t_rec), 'u2 rows: A2025, A2026, B2025, B2026, E2026');
select pg_temp.check((select attendance_count = 5 and pom_count = 0 and goal_of_the_day_count = 2
                             and vote_eligible = 4 and vote_responded = 3
                        from t_rec where team_id = pg_temp.vid('A') and season = 2026), 'A 2026 counts + votes summed');
select pg_temp.check((select attendance_count = 3 and pom_count = 1 and vote_eligible = 3 and vote_responded = 2
                        from t_rec where team_id = pg_temp.vid('A') and season = 2025), 'A 2025');
select pg_temp.check((select attendance_count = 0 and pom_count = 0 and goal_of_the_day_count = 0
                             and vote_eligible = 1 and vote_responded = 0
                        from t_rec where team_id = pg_temp.vid('B') and season = 2025), 'B 2025 votes only');
select pg_temp.check((select attendance_count = 1 and vote_eligible = 0 and vote_responded = 0
                        from t_rec where team_id = pg_temp.vid('B') and season = 2026), 'B 2026 stats only');
select pg_temp.check((select bool_and(is_member and not is_dissolved) from t_rec), 'all current, none dissolved');
select pg_temp.check((select team_name = '기록A' and logo_text is not null from t_rec
                       where team_id = pg_temp.vid('A') and season = 2026), 'team name and logo text');
-- 다른 사람(u3) 숫자는 없음
select pg_temp.check((select count(*) = 0 from t_rec where attendance_count = 9 or vote_eligible = 5), 'no other user numbers');
-- 득표수 칸 없음
select pg_temp.check((select count(*) = 0 from information_schema.routines r
                        join information_schema.parameters p on p.specific_name = r.specific_name
                       where r.routine_schema = 'public' and r.routine_name = 'get_my_records'
                         and p.parameter_mode = 'IN'), 'no input arguments');
select pg_temp.check((select count(*) = 0 from information_schema.parameters p
                        join information_schema.routines r on p.specific_name = r.specific_name
                       where r.routine_schema = 'public' and r.routine_name = 'get_my_records'
                         and p.parameter_name ilike '%vote_count%'), 'no vote count column');

-- 기록이 없는 사람(u1)은 0건, 팀 C 처럼 관계없는 사람도 0건
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.check((select count(*) = 0 from public.get_my_records()), 'u1 no records');
select pg_temp.login(pg_temp.u(5));
select pg_temp.check((select count(*) = 0 from public.get_my_records()), 'u5 no records');
reset role;

-- ---------------------------------------------------------------------------
-- 2. 떠난 팀·해체된 팀도 계속 보임 (R-03)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(2)); select public.leave_team(pg_temp.vid('B'));
select pg_temp.login(pg_temp.u(4)); select public.dissolve_team(pg_temp.vid('E'), '기록E');
select pg_temp.login(pg_temp.u(2));
delete from t_rec;
insert into t_rec select * from public.get_my_records();
-- 떠난 팀은 표를 직접 읽으면 안 보인다(기존 규칙)
select pg_temp.check((select count(*) = 0 from public.teams where id = pg_temp.vid('B')), 'left team not readable directly');
reset role;

select pg_temp.check((select count(*) = 5 from t_rec), 'still five rows');
select pg_temp.check((select bool_and(not is_member and not is_dissolved and team_name = '기록B')
                        from t_rec where team_id = pg_temp.vid('B')), 'left team flagged');
select pg_temp.check((select bool_and(not is_member and is_dissolved and team_name = '기록E' and pom_count = 1)
                        from t_rec where team_id = pg_temp.vid('E')), 'dissolved team flagged and kept');
select pg_temp.check((select is_member from t_rec where team_id = pg_temp.vid('A') and season = 2026), 'A still member');

-- ---------------------------------------------------------------------------
-- 3. 권한: 비로그인 실행 불가, 프로필 없는 호출자 거절, SECURITY DEFINER + search_path 고정
-- ---------------------------------------------------------------------------
select pg_temp.check(not has_function_privilege('anon', 'public.get_my_records()', 'execute')
                     and has_function_privilege('authenticated', 'public.get_my_records()', 'execute'), 'grants');
select pg_temp.check((select p.prosecdef and p.proconfig @> array['search_path=""']
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname = 'get_my_records'), 'definer search_path fixed');
do $$
begin
  set local role authenticated;
  perform pg_temp.login(pg_temp.u(6));
  begin
    perform * from public.get_my_records();
    raise exception 'check failed: profileless caller accepted';
  exception when others then
    if sqlerrm like 'check failed%' then raise; end if;
  end;
  reset role;
end;
$$;
-- 기록 표 직접 읽기: 본인 줄만 (member_season_stats), 참여율 표는 아무도 못 읽음 (기존 규칙 그대로)
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select pg_temp.check((select count(*) = 4 and bool_and(user_id = pg_temp.u(2)) from public.member_season_stats), 'stats own rows only');
reset role;

-- ---------------------------------------------------------------------------
-- 4. 대시보드 읽기 범위 회귀 (팀원 u3 이 표를 직접 읽음)
-- ---------------------------------------------------------------------------
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, capacity)
  values (pg_temp.vid('A'), 'manual', now() + interval '2 hours', now() + interval '4 hours', now() - interval '1 hour', 12)
  returning id)
insert into t_vars select 'm1', id::text from x;
insert into public.lineups (match_id, team_count, players_per_team) values (pg_temp.vid('m1'), 2, 5);
insert into public.skill_ratings (team_id, user_id, level) values (pg_temp.vid('A'), pg_temp.u(3), 'pro');
-- u2: 회복한 지난 부상, u7: 진행 중 부상(동의함)
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at)
values (pg_temp.u(2), current_date - 20, current_date - 6, 'recovered', now() - interval '5 days');
insert into public.injuries (user_id, started_on, expected_return_on, memo)
values (pg_temp.u(7), current_date - 3, current_date + 10, '발목');

set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) = 0 from public.lineups where match_id = pg_temp.vid('m1')), 'member: draft lineup hidden');
select pg_temp.check((select count(*) = 0 from public.skill_ratings), 'member: no skill ratings (own included)');
select pg_temp.check((select count(*) = 0 from public.profile_play_prefs where user_id <> pg_temp.u(3)), 'member: no other positions');
select pg_temp.check(not has_table_privilege('authenticated', 'public.award_tallies', 'select'), 'member: no vote counts (no grant)');
select pg_temp.check((select count(*) = 0 from public.join_requests where team_id = pg_temp.vid('A') and user_id <> pg_temp.u(3)), 'member: no others join requests');
select pg_temp.check((select count(*) = 1 and bool_and(user_id = pg_temp.u(7) and status = 'active') from public.injuries),
                     'member: only active injury of teammate');
select pg_temp.check((select count(*) = 4 from public.team_members where team_id = pg_temp.vid('A') and status = 'active'),
                     'member: header member count');
-- 관리자 u1: 초안·가입 신청 보임 (처리할 일 재료)
select pg_temp.login(pg_temp.u(1));
select pg_temp.check((select count(*) = 1 from public.lineups where match_id = pg_temp.vid('m1')), 'staff: draft visible');
select pg_temp.check((select count(*) = 1 from public.join_requests where team_id = pg_temp.vid('A') and status = 'pending'),
                     'staff: one pending request');
reset role;

-- ---------------------------------------------------------------------------
-- 5. 회원 탈퇴(프로필 삭제) → 그 사람 기록 숫자 삭제, 다른 사람 숫자는 그대로 (R-06)
-- ---------------------------------------------------------------------------
delete from public.profiles where user_id = pg_temp.u(3);
select pg_temp.check((select count(*) = 0 from public.member_season_stats where user_id = pg_temp.u(3))
                     and (select count(*) = 0 from public.monthly_vote_participation where user_id = pg_temp.u(3)), 'deleted user rows gone');
select pg_temp.check((select count(*) = 4 from public.member_season_stats where user_id = pg_temp.u(2)), 'others kept');

select 'ALL PASSED' as result;
