-- 스프린트 03 7단계 마이그레이션(202611050053~202611050056: 최근 10경기 정리, 해체 시 지난 경기 상세 삭제,
-- 회원 탈퇴 시 배치 변경 이력 정리, 해체 팀 남은 일정 정리) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 지난 경기와 딸린 기록은 서버 권한(postgres)으로 표에 직접 넣어 준비하고, 예약 작업은 p_now 로 시각을 당겨 부른다.

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
  select ('00000000-0000-4000-8000-0000000007a' || p_n::text)::uuid
$$;

-- 일정 만들기 (서버 권한). p_closed: 경기 종료 처리 표시
create function pg_temp.mk(p_key text, p_team text, p_starts timestamptz, p_closed boolean, p_cancelled boolean default false)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, status, cancelled_at, closed_out_at)
  values (pg_temp.vid(p_team), 'auto', p_starts, p_starts + interval '2 hours', p_starts - interval '2 hours',
          case when p_cancelled then 'cancelled'::public.match_status else 'scheduled'::public.match_status end,
          case when p_cancelled then p_starts - interval '1 day' end,
          case when p_closed then p_starts + interval '2 hours 1 minute' end)
  returning id into v_id;
  insert into t_vars values (p_key, v_id::text);
  return v_id;
end;
$$;

create function pg_temp.exists_match(p_key text)
returns boolean
language sql
as $$
  select exists (select 1 from public.matches where id = pg_temp.vid(p_key))
$$;

-- 한 경기에 딸린 줄 수 (외래 키로 같이 지워지는지 확인용)
create function pg_temp.detail_rows(p_key text)
returns int
language sql
as $$
  select ((select count(*) from public.attendance_responses where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.match_guests where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.skill_ratings s join public.match_guests g on g.id = s.guest_id
            where g.match_id = pg_temp.vid(p_key))
        + (select count(*) from public.lineups where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.lineup_squads q join public.lineups l on l.id = q.lineup_id
            where l.match_id = pg_temp.vid(p_key))
        + (select count(*) from public.lineup_slots s join public.lineups l on l.id = s.lineup_id
            where l.match_id = pg_temp.vid(p_key))
        + (select count(*) from public.lineup_change_logs c join public.lineups l on l.id = c.lineup_id
            where l.match_id = pg_temp.vid(p_key))
        + (select count(*) from public.award_polls where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.award_participants where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.award_ballot_receipts where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.award_tallies where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.award_winners where match_id = pg_temp.vid(p_key))
        + (select count(*) from public.attendance_records where match_id = pg_temp.vid(p_key)))::int
$$;

-- 배치 + 팀 블록 1개. 배치 id 를 돌려준다
create function pg_temp.lineup(p_match text, p_squad_users int[], p_bench_users int[])
returns uuid
language plpgsql
as $$
declare
  v_lineup uuid;
  v_squad uuid;
  n int;
begin
  insert into public.lineups (match_id, team_count, players_per_team, status, confirmed_at, version)
  values (pg_temp.vid(p_match), 2, 5, 'confirmed', now() - interval '20 days', 2)
  returning id into v_lineup;
  insert into public.lineup_squads (lineup_id, squad_no, bib_color) values (v_lineup, 1, 'red') returning id into v_squad;
  insert into public.lineup_squads (lineup_id, squad_no, bib_color) values (v_lineup, 2, 'blue');
  foreach n in array p_squad_users loop
    insert into public.lineup_slots (lineup_id, squad_id, user_id) values (v_lineup, v_squad, pg_temp.u(n));
  end loop;
  foreach n in array p_bench_users loop
    insert into public.lineup_slots (lineup_id, squad_id, user_id) values (v_lineup, null, pg_temp.u(n));
  end loop;
  return v_lineup;
end;
$$;

create function pg_temp.poll(p_match text, p_team text, p_status text, p_closes timestamptz, p_participants int[])
returns void
language plpgsql
as $$
declare
  n int;
begin
  insert into public.award_polls (match_id, team_id, opens_at, closes_at, status)
  values (pg_temp.vid(p_match), pg_temp.vid(p_team), p_closes - interval '1 day', p_closes, p_status::public.award_poll_status);
  foreach n in array p_participants loop
    insert into public.award_participants (match_id, user_id) values (pg_temp.vid(p_match), pg_temp.u(n));
    insert into public.award_tallies (match_id, category, candidate_id, vote_count)
    values (pg_temp.vid(p_match), 'pom', pg_temp.u(n), 0), (pg_temp.vid(p_match), 'goal_of_the_day', pg_temp.u(n), 0);
  end loop;
end;
$$;

create function pg_temp.stat(p_n int, p_team text, p_col text)
returns int
language plpgsql
as $$
declare
  v int;
begin
  execute format('select coalesce(sum(%I), 0)::int from public.member_season_stats where user_id = $1 and team_id = $2', p_col)
    into v using pg_temp.u(p_n), pg_temp.vid(p_team);
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 준비: 팀 P(u1 팀장, u2 운영진, u3~u6 팀원), 팀 Q(u7 팀장, u8 팀원)
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'a7' || n || '@test.invalid', now(), now()
  from generate_series(1, 8) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5));
select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(6));
select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(7));
select public.create_profile('칠', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(8));
select public.create_profile('팔', null, array['forward']::public.play_position[], false, true, true, true, false);

select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('보관FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(7));
insert into t_vars select 'Q', public.create_team('해체FC')::text;
insert into t_vars select 'codeQ', team_code from public.teams where id = pg_temp.vid('Q');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(3)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(4)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(5)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(6)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(8)); select public.request_join(pg_temp.v('codeQ'), 'code');
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('P');
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
select pg_temp.login(pg_temp.u(7));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('Q');
reset role;

update public.team_members set joined_at = timestamptz '2020-01-01 00:00+09'
 where team_id in (pg_temp.vid('P'), pg_temp.vid('Q'));

-- ---------------------------------------------------------------------------
-- 1. 팀 P 일정 (p0 가장 오래됨 ~ p12 가장 최근, 하루 간격, 모두 끝남)
--   p0: 경기 종료 처리 전 (closed_out_at 없음)  → 11번째 이전이어도 안 지움
--   p1: 처리·투표 마감 완료, 딸린 기록 전부     → 지움
--   p2: 처리 완료, 투표 진행 중                   → 마감 전에는 안 지움, 마감 직후 지움
--   p3~p12: 남길 10경기 (p3 = 10번째). p5 에 u5 기록, p12 에 변경 이력
--   c1: 취소, p3 보다 이전(p1·p2 사이)            → 지움
--   c2: 취소, p3·p4 사이                          → 남김
--   cF: 취소, 다가오는 일정 / pF: 다가오는 일정 / pL: 진행 중 → 남김
-- ---------------------------------------------------------------------------
insert into t_vars values ('base', (date_trunc('hour', now()) - interval '14 days')::text);
select pg_temp.mk('p' || i, 'P', pg_temp.v('base')::timestamptz + make_interval(days => i), i <> 0)
  from generate_series(0, 12) i;
select pg_temp.mk('c1', 'P', pg_temp.v('base')::timestamptz + interval '1 day 12 hours', false, true);
select pg_temp.mk('c2', 'P', pg_temp.v('base')::timestamptz + interval '3 days 12 hours', false, true);
select pg_temp.mk('cF', 'P', now() + interval '2 days', false, true);
select pg_temp.mk('pF', 'P', now() + interval '3 days', false);
select pg_temp.mk('pL', 'P', now() - interval '30 minutes', false);

-- p1 에 딸린 줄 전부 (7-2)
insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('p1'), pg_temp.u(3), 'attending');
insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('c1'), pg_temp.u(3), 'declined');
with g as (insert into public.match_guests (match_id, team_id) values (pg_temp.vid('p1'), pg_temp.vid('P')) returning id)
insert into t_vars select 'g1', id::text from g;
insert into public.skill_ratings (team_id, guest_id, level) values (pg_temp.vid('P'), pg_temp.vid('g1'), 'pro');
insert into t_vars select 'l1', pg_temp.lineup('p1', array[3], array[4])::text;
insert into public.lineup_slots (lineup_id, squad_id, guest_id) values (pg_temp.vid('l1'), null, pg_temp.vid('g1'));
insert into public.lineup_change_logs (lineup_id, version, changed_by, before, after)
values (pg_temp.vid('l1'), 2, pg_temp.u(1), '{}'::jsonb, '{}'::jsonb);
select pg_temp.poll('p1', 'P', 'closed', pg_temp.v('base')::timestamptz + interval '2 days', array[3, 4]);
update public.award_tallies set vote_count = 1 where match_id = pg_temp.vid('p1') and candidate_id = pg_temp.u(3) and category = 'pom';
insert into public.award_ballot_receipts (match_id, category, voter_id) values (pg_temp.vid('p1'), 'pom', pg_temp.u(4));
insert into public.award_winners (match_id, team_id, category, user_id, season)
values (pg_temp.vid('p1'), pg_temp.vid('P'), 'pom', pg_temp.u(3), 2026);
insert into public.attendance_records (match_id, team_id, user_id, season)
values (pg_temp.vid('p1'), pg_temp.vid('P'), pg_temp.u(3), 2026), (pg_temp.vid('p1'), pg_temp.vid('P'), pg_temp.u(4), 2026);
select pg_temp.check(pg_temp.detail_rows('p1') = 21, 'p1 details prepared');

-- p2: 투표 진행 중 (u4 가 POM 1표)
select pg_temp.poll('p2', 'P', 'open', now() + interval '1 hour', array[3, 4]);
update public.award_tallies set vote_count = 1 where match_id = pg_temp.vid('p2') and candidate_id = pg_temp.u(4) and category = 'pom';

-- p5: u5 출석·배치·1위 (팀 탈퇴 뒤에도 남는지, 7-5)
select pg_temp.lineup('p5', array[5, 3], array[]::int[]);
select pg_temp.poll('p5', 'P', 'closed', pg_temp.v('base')::timestamptz + interval '6 days', array[3, 5]);
insert into public.award_winners (match_id, team_id, category, user_id, season)
values (pg_temp.vid('p5'), pg_temp.vid('P'), 'pom', pg_temp.u(5), 2026);
insert into public.attendance_records (match_id, team_id, user_id, season)
values (pg_temp.vid('p5'), pg_temp.vid('P'), pg_temp.u(5), 2026);

-- p12: 변경 이력에 u4 (7-4)
insert into t_vars select 'l12', pg_temp.lineup('p12', array[3, 6], array[]::int[])::text;
insert into public.lineup_change_logs (lineup_id, version, changed_by, before, after)
values (pg_temp.vid('l12'), 2, pg_temp.u(4),
        jsonb_build_object('team_count', 2, 'players_per_team', 5,
          'squads', jsonb_build_array(
            jsonb_build_object('squad_no', 1, 'bib_color', 'red', 'user_ids', jsonb_build_array(pg_temp.u(3), pg_temp.u(4)), 'guest_ids', '[]'::jsonb),
            jsonb_build_object('squad_no', 2, 'bib_color', 'blue', 'user_ids', jsonb_build_array(pg_temp.u(6)), 'guest_ids', '[]'::jsonb)),
          'bench', jsonb_build_object('user_ids', '[]'::jsonb, 'guest_ids', '[]'::jsonb)),
        jsonb_build_object('team_count', 2, 'players_per_team', 5,
          'squads', jsonb_build_array(
            jsonb_build_object('squad_no', 1, 'bib_color', 'red', 'user_ids', jsonb_build_array(pg_temp.u(3)), 'guest_ids', '[]'::jsonb),
            jsonb_build_object('squad_no', 2, 'bib_color', 'blue', 'user_ids', jsonb_build_array(pg_temp.u(6)), 'guest_ids', '[]'::jsonb)),
          'bench', jsonb_build_object('user_ids', jsonb_build_array(pg_temp.u(4), pg_temp.u(6)), 'guest_ids', '[]'::jsonb)));

-- 카운트·월간 숫자 (정리로 바뀌지 않아야 함)
insert into public.member_season_stats (user_id, team_id, season, attendance_count, pom_count)
values (pg_temp.u(3), pg_temp.vid('P'), 2026, 7, 1), (pg_temp.u(4), pg_temp.vid('P'), 2026, 6, 0),
       (pg_temp.u(5), pg_temp.vid('P'), 2026, 3, 1), (pg_temp.u(6), pg_temp.vid('P'), 2026, 2, 0);
insert into public.monthly_attendance (team_id, user_id, month, attendance_count)
values (pg_temp.vid('P'), pg_temp.u(3), date '2026-11-01', 7), (pg_temp.vid('P'), pg_temp.u(5), date '2026-11-01', 3);
insert into public.team_monthly_matches (team_id, month, match_count) values (pg_temp.vid('P'), date '2026-11-01', 12);
insert into public.monthly_vote_participation (team_id, user_id, month, attendance_vote_eligible, attendance_vote_responded)
values (pg_temp.vid('P'), pg_temp.u(3), date '2026-11-01', 12, 10);
insert into public.notifications (user_id, team_id, kind, title, body, ref_type, ref_id, dedupe_key)
values (pg_temp.u(3), pg_temp.vid('P'), 'award_results_announced', 't', 'b', 'match', pg_temp.vid('p1'), 'step7-test');

-- ---------------------------------------------------------------------------
-- 2. 팀 탈퇴 (7-5): 떠난 사람의 지난 경기 줄과 카운트는 남는다
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(5));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check((select count(*) = 1 from public.lineup_slots s join public.lineups l on l.id = s.lineup_id
                       where l.match_id = pg_temp.vid('p5') and s.user_id = pg_temp.u(5)), 'leave keeps past lineup slot');
select pg_temp.check((select count(*) = 1 from public.attendance_records where match_id = pg_temp.vid('p5') and user_id = pg_temp.u(5)), 'leave keeps attendance record');
select pg_temp.check((select count(*) = 1 from public.award_participants where match_id = pg_temp.vid('p5') and user_id = pg_temp.u(5)), 'leave keeps participant');
select pg_temp.check((select count(*) = 1 from public.award_winners where match_id = pg_temp.vid('p5') and user_id = pg_temp.u(5)), 'leave keeps winner');
select pg_temp.check(pg_temp.stat(5, 'P', 'attendance_count') = 3 and pg_temp.stat(5, 'P', 'pom_count') = 1, 'leave keeps season stats');
select pg_temp.check((select attendance_count = 3 from public.monthly_attendance where user_id = pg_temp.u(5)), 'leave keeps monthly attendance');

-- ---------------------------------------------------------------------------
-- 3. 하루 1회 정리 (7-1)
-- ---------------------------------------------------------------------------
-- 끝난 경기 10개 미만인 팀 Q (지난 경기 3개 + 그보다 이전 취소) → 아무것도 안 지움
select pg_temp.mk('q0', 'Q', now() - interval '10 days', false, true);
select pg_temp.mk('qA', 'Q', now() - interval '3 days', true);
select pg_temp.mk('qC', 'Q', now() - interval '2 days', true);
select pg_temp.mk('qB', 'Q', now() - interval '3 hours', false);
select pg_temp.mk('qX', 'Q', now() - interval '5 days', false, true);
select pg_temp.mk('qL', 'Q', now() - interval '30 minutes', false);
select pg_temp.mk('qF', 'Q', now() + interval '2 days', false);
select pg_temp.check(private.prune_team_matches(pg_temp.vid('Q')) = 0, 'team under 10 untouched');

select pg_temp.check(private.prune_old_matches(now()) >= 2, 'daily prune runs');
select pg_temp.check(not pg_temp.exists_match('p1') and not pg_temp.exists_match('c1'), 'p1, c1 deleted');
select pg_temp.check(pg_temp.detail_rows('p1') = 0, 'p1 details cascade-deleted');
select pg_temp.check((select count(*) = 0 from public.attendance_responses where match_id = pg_temp.vid('c1')), 'c1 responses deleted');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where guest_id = pg_temp.vid('g1')), 'guest rating deleted');
select pg_temp.check(pg_temp.exists_match('p0'), 'not closed out: kept');
select pg_temp.check(pg_temp.exists_match('p2'), 'open poll: kept');
select pg_temp.check((select bool_and(pg_temp.exists_match('p' || i)) from generate_series(3, 12) i), 'recent 10 kept');
select pg_temp.check(pg_temp.exists_match('c2') and pg_temp.exists_match('cF') and pg_temp.exists_match('pF')
                     and pg_temp.exists_match('pL'), 'cancelled in window, upcoming, in-progress kept');
select pg_temp.check(pg_temp.stat(3, 'P', 'attendance_count') = 7 and pg_temp.stat(3, 'P', 'pom_count') = 1
                     and pg_temp.stat(4, 'P', 'attendance_count') = 6, 'season stats unchanged');
select pg_temp.check((select attendance_count = 7 from public.monthly_attendance where user_id = pg_temp.u(3)), 'monthly attendance unchanged');
select pg_temp.check((select match_count = 12 from public.team_monthly_matches where team_id = pg_temp.vid('P')), 'team monthly matches unchanged');
select pg_temp.check((select attendance_vote_eligible = 12 and attendance_vote_responded = 10
                        from public.monthly_vote_participation where user_id = pg_temp.u(3)), 'vote participation unchanged');
select pg_temp.check((select count(*) = 1 from public.notifications where dedupe_key = 'step7-test' and ref_id = pg_temp.vid('p1')), 'notification kept');
select pg_temp.check(private.prune_team_matches(pg_temp.vid('P')) = 0, 'second run deletes nothing');

-- p0 이 나중에 처리되면 다음 실행 때 지워짐
update public.matches set closed_out_at = now() where id = pg_temp.vid('p0');
select pg_temp.check(private.prune_team_matches(pg_temp.vid('P')) = 1 and not pg_temp.exists_match('p0'), 'p0 deleted after close-out');

-- ---------------------------------------------------------------------------
-- 4. 투표 마감 직후 정리 (7-5 실행 시점): p2 는 마감 전 안 지워지고 마감 처리 직후 지워짐
-- ---------------------------------------------------------------------------
select pg_temp.check(private.close_award_polls(now()) = 0 and pg_temp.exists_match('p2'), 'before close: p2 kept');
select pg_temp.check(private.close_award_polls(now() + interval '1 hour') = 1, 'p2 poll closed');
select pg_temp.check(not pg_temp.exists_match('p2') and pg_temp.detail_rows('p2') = 0, 'p2 deleted right after close');
select pg_temp.check(pg_temp.stat(4, 'P', 'pom_count') = 1, 'p2 winner counted before deletion');
select pg_temp.check((select count(*) = 1 from public.notifications
                       where ref_id = pg_temp.vid('p2') and kind = 'award_results_announced' and user_id = pg_temp.u(4)), 'result notice kept');
select pg_temp.check((select count(*) = 10 from public.matches where team_id = pg_temp.vid('P') and status = 'scheduled' and ends_at <= now()), 'P has 10 ended');

-- ---------------------------------------------------------------------------
-- 5. 회원 탈퇴 (7-4): 배치 변경 이력 안의 사람 ID 정리
-- ---------------------------------------------------------------------------
select public.delete_account(pg_temp.u(4));
select pg_temp.check((select count(*) = 1 from public.lineup_change_logs where lineup_id = pg_temp.vid('l12')), 'log row kept');
select pg_temp.check((select not (before::text like '%' || pg_temp.u(4)::text || '%')
                         and not (after::text like '%' || pg_temp.u(4)::text || '%')
                        from public.lineup_change_logs where lineup_id = pg_temp.vid('l12')), 'u4 removed from log');
select pg_temp.check((select before -> 'squads' -> 0 -> 'user_ids' = jsonb_build_array(pg_temp.u(3))
                         and before -> 'squads' -> 1 -> 'user_ids' = jsonb_build_array(pg_temp.u(6))
                         and after -> 'bench' -> 'user_ids' = jsonb_build_array(pg_temp.u(6))
                         and after -> 'squads' -> 0 ->> 'bib_color' = 'red'
                         and after ->> 'team_count' = '2'
                         and changed_by is null
                        from public.lineup_change_logs where lineup_id = pg_temp.vid('l12')), 'others kept in log');
select pg_temp.check((select count(*) = 0 from public.member_season_stats where user_id = pg_temp.u(4)), 'u4 stats deleted');
select pg_temp.check(pg_temp.stat(3, 'P', 'attendance_count') = 7 and pg_temp.stat(6, 'P', 'attendance_count') = 2, 'others stats unchanged');
-- 빈 모양·다른 모양은 그대로
select pg_temp.check(private.strip_user_from_lineup_snapshot('{}'::jsonb, pg_temp.u(3)) = '{}'::jsonb, 'empty snapshot unchanged');

-- ---------------------------------------------------------------------------
-- 6. 해체 (7-3): 처리 안 된 경기 출석 먼저 → 진행 중 투표 무효 → 지난 경기 전부 삭제. 개인 카운트는 남음
--   qA: 처리·투표 마감 완료 (u8 1위, 출석) / qB: 끝났지만 처리 전 (u8 참석) / qC: 투표 진행 중
--   qX·q0: 지난 취소 일정 / qL: 진행 중 / qF: 다가오는 일정
-- ---------------------------------------------------------------------------
select pg_temp.poll('qA', 'Q', 'closed', now() - interval '2 days', array[7, 8]);
insert into public.award_winners (match_id, team_id, category, user_id, season)
values (pg_temp.vid('qA'), pg_temp.vid('Q'), 'pom', pg_temp.u(8), 2026);
insert into public.attendance_records (match_id, team_id, user_id, season)
values (pg_temp.vid('qA'), pg_temp.vid('Q'), pg_temp.u(8), 2026);
insert into public.member_season_stats (user_id, team_id, season, attendance_count, pom_count)
values (pg_temp.u(8), pg_temp.vid('Q'), private.match_season(now() - interval '3 hours'), 1, 1);
insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('qB'), pg_temp.u(8), 'attending');
select pg_temp.poll('qC', 'Q', 'open', now() + interval '1 day', array[7, 8]);
update public.award_tallies set vote_count = 1 where match_id = pg_temp.vid('qC') and candidate_id = pg_temp.u(8) and category = 'pom';
insert into t_vars select 'tmmQ', coalesce(sum(match_count), 0)::text from public.team_monthly_matches where team_id = pg_temp.vid('Q');

set local role authenticated;
select pg_temp.login(pg_temp.u(7));
select public.dissolve_team(pg_temp.vid('Q'), '해체FC');
reset role;

select pg_temp.check(not pg_temp.exists_match('qA') and not pg_temp.exists_match('qB') and not pg_temp.exists_match('qC')
                     and not pg_temp.exists_match('qX') and not pg_temp.exists_match('q0'), 'past matches deleted');
select pg_temp.check(pg_temp.detail_rows('qA') + pg_temp.detail_rows('qB') + pg_temp.detail_rows('qC') = 0, 'past details deleted');
select pg_temp.check(pg_temp.exists_match('qL'), 'in-progress kept');
select pg_temp.check((select status = 'cancelled' from public.matches where id = pg_temp.vid('qF')), 'upcoming cancelled');
select pg_temp.check(pg_temp.stat(8, 'Q', 'attendance_count') = 2, 'unprocessed match attendance counted before delete');
select pg_temp.check(pg_temp.stat(8, 'Q', 'pom_count') = 1, 'open poll voided: no award, past award kept');
select pg_temp.check((select coalesce(sum(match_count), 0) from public.team_monthly_matches where team_id = pg_temp.vid('Q'))
                     = pg_temp.v('tmmQ')::int + 1, 'team monthly matches +1 for unprocessed match');
select pg_temp.check((select count(*) = 0 from public.award_polls where team_id = pg_temp.vid('Q')), 'no polls left');
select pg_temp.check((select count(*) = 0 from public.attendance_records where team_id = pg_temp.vid('Q')), 'no attendance records left');
-- 다른 팀은 그대로
select pg_temp.check((select count(*) = 10 from public.matches where team_id = pg_temp.vid('P') and status = 'scheduled' and ends_at <= now()), 'P untouched by Q dissolve');

-- 해체 팀의 남은 일정 (202611050056): 취소된 일정은 매일 정리에서 바로, 진행 중이던 경기는 종료 처리 뒤에
select pg_temp.check(private.prune_dissolved_team_matches(pg_temp.vid('P')) = 0, 'not dissolved: untouched');
select pg_temp.check(private.prune_dissolved_team_matches(pg_temp.vid('Q')) = 1, 'dissolved: cancelled upcoming deleted');
select pg_temp.check(not pg_temp.exists_match('qF') and pg_temp.exists_match('qL'), 'in-progress kept until close-out');
insert into t_vars select 'tmmQ2', coalesce(sum(match_count), 0)::text from public.team_monthly_matches where team_id = pg_temp.vid('Q');
select private.close_out_matches(now() + interval '2 hours');
select pg_temp.check((select closed_out_at is not null from public.matches where id = pg_temp.vid('qL')), 'qL closed out');
select pg_temp.check((select count(*) = 0 from public.award_polls where match_id = pg_temp.vid('qL')), 'no poll for dissolved team');
select pg_temp.check(private.prune_old_matches(now() + interval '2 hours') >= 1 and not pg_temp.exists_match('qL'), 'daily prune deletes closed-out qL');
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('Q')), 'dissolved team has no matches');
select pg_temp.check((select coalesce(sum(match_count), 0) from public.team_monthly_matches where team_id = pg_temp.vid('Q'))
                     = pg_temp.v('tmmQ2')::int + 1, 'team monthly matches kept (+1 for qL)');
select pg_temp.check(pg_temp.stat(8, 'Q', 'attendance_count') = 2 and pg_temp.stat(8, 'Q', 'pom_count') = 1, 'dissolved team counts kept');
-- 2시간 뒤 기준으로는 pL 도 끝나 처리됐으므로 P 는 pL~p4 10경기를 남기고 p3 를 지운다
select pg_temp.check((select count(*) = 10 from public.matches where team_id = pg_temp.vid('P') and status = 'scheduled' and ends_at <= now() + interval '2 hours')
                     and pg_temp.exists_match('pL') and pg_temp.exists_match('p4') and not pg_temp.exists_match('p3'), 'P keeps recent 10');

-- ---------------------------------------------------------------------------
-- 7. 실행 권한·예약 작업·보안 설정
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error('select private.prune_old_matches()', 'permission denied%');
select pg_temp.expect_error(format('select private.prune_dissolved_team_matches(%L)', pg_temp.vid('Q')), 'permission denied%');
select pg_temp.expect_error(format('select private.prune_team_matches(%L)', pg_temp.vid('P')), 'permission denied%');
select pg_temp.expect_error(format('select private.remove_user_from_lineup_logs(%L)', pg_temp.u(3)), 'permission denied%');
reset role;
set local role anon;
select pg_temp.expect_error('select private.prune_old_matches()', 'permission denied%');
reset role;
select pg_temp.check(not has_function_privilege('service_role', 'private.prune_old_matches(timestamptz)', 'execute')
                     and not has_function_privilege('service_role', 'private.prune_team_matches(uuid, timestamptz)', 'execute')
                     and not has_function_privilege('service_role', 'private.prune_dissolved_team_matches(uuid)', 'execute')
                     and not has_function_privilege('service_role', 'private.close_award_polls(timestamptz)', 'execute')
                     and not has_function_privilege('service_role', 'private.remove_user_from_lineup_logs(uuid)', 'execute')
                     and has_function_privilege('service_role', 'public.delete_account(uuid)', 'execute')
                     and not has_function_privilege('authenticated', 'public.delete_account(uuid)', 'execute'), 'execute grants');
select pg_temp.check((select command from cron.job where jobname = 'prune-old-matches') = 'select private.prune_old_matches()', 'prune cron');
select pg_temp.check((select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where ((n.nspname = 'private' and p.proname in ('prune_team_matches', 'prune_old_matches', 'prune_dissolved_team_matches', 'close_award_polls',
                                                                       'remove_user_from_lineup_logs', 'strip_user_from_lineup_snapshot'))
                           or (n.nspname = 'public' and p.proname in ('dissolve_team', 'delete_account')))
                         and not coalesce(p.proconfig @> array['search_path=""'], false)), 'search_path empty');
select pg_temp.check((select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 'RLS on all public tables');

select 'ALL PASSED' as result;
