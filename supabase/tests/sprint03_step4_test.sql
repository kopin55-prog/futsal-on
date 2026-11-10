-- 스프린트 03 4단계 마이그레이션(202611050041~202611050051: 투표 설정, 기록 표, 투표 표, 알림 문구,
-- 경기 종료 처리, 투표 함수, 투표 마감, 배치 미확정 알림, notifier 재료, 해체 시 투표 폐기) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 지난 경기는 서버 권한(postgres)으로 표에 직접 넣어 준비하고, 예약 작업은 p_now 로 시각을 당겨 부른다.
-- 트랜잭션 안에서는 now() 가 고정이므로 소속 시작 시각(joined_at)을 과거로 당겨 둔다.

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
  select ('00000000-0000-4000-8000-0000000004a' || p_n::text)::uuid
$$;

create function pg_temp.su(p_squad int, p_n int)
returns jsonb
language sql
as $$
  select jsonb_build_object('squad_no', p_squad, 'user_id', pg_temp.u(p_n))
$$;

create function pg_temp.notif_total(p_kind text, p_match text)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
   where n.kind::text = p_kind and n.ref_id = pg_temp.vid(p_match)
$$;

create function pg_temp.notif_to(p_kind text, p_match text, p_n int)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
   where n.kind::text = p_kind and n.ref_id = pg_temp.vid(p_match) and n.user_id = pg_temp.u(p_n)
$$;

-- 투표 (로그인 바꿔서). 성공하면 'ok'
create function pg_temp.vote(p_n int, p_match text, p_cat text, p_cand int)
returns text
language plpgsql
as $$
begin
  perform pg_temp.login(pg_temp.u(p_n));
  perform public.cast_award_vote(pg_temp.vid(p_match), p_cat, pg_temp.u(p_cand));
  return 'ok';
end;
$$;
grant execute on function pg_temp.vote(int, text, text, int) to authenticated;

create function pg_temp.match_ids(p_n int[])
returns uuid[]
language sql
as $$
  select array_agg(pg_temp.u(x) order by pg_temp.u(x)) from unnest(p_n) x
$$;

-- ---------------------------------------------------------------------------
-- 0. 소급: 마이그레이션 시점에 끝나 있던 미처리 경기는 모두 처리 표시가 있다 (팀 월간 경기 수만)
-- ---------------------------------------------------------------------------
select pg_temp.check((select count(*) = 0 from public.matches
                       where status = 'scheduled' and ends_at <= now() and closed_out_at is null), 'backfill marks ended matches');
select pg_temp.check((select count(*) = 0 from public.attendance_records), 'backfill creates no attendance');
select pg_temp.check((select count(*) = 0 from public.award_polls), 'backfill opens no polls');
select pg_temp.check(
  (select coalesce(sum(match_count), 0) from public.team_monthly_matches)
  = (select count(*) from public.matches where status = 'scheduled' and ends_at <= now()), 'backfill month counts');
insert into t_vars select 'tmm_before', coalesce(sum(match_count), 0)::text from public.team_monthly_matches;

-- ---------------------------------------------------------------------------
-- 준비: e1~e9. 팀 P: e1 팀장, e2 운영진, e3~e7 팀원. 팀 Q: e8 팀장, e9 팀원
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'a4' || n || '@test.invalid', now(), now()
  from generate_series(1, 9) n;

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
select pg_temp.login(pg_temp.u(9));
select public.create_profile('구', null, array['forward']::public.play_position[], false, true, true, true, false);

select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('피FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(8));
insert into t_vars select 'Q', public.create_team('큐FC')::text;
insert into t_vars select 'codeQ', team_code from public.teams where id = pg_temp.vid('Q');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(3)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(4)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(5)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(6)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(7)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(9));
insert into t_vars select 'r9', public.request_join(pg_temp.v('codeQ'), 'code')::text;
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('P');
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
select pg_temp.login(pg_temp.u(8));
select public.decide_join_request(pg_temp.vid('r9'), true);
reset role;

update public.team_members set joined_at = timestamptz '2020-01-01 00:00+09'
 where team_id in (pg_temp.vid('P'), pg_temp.vid('Q'));

-- ---------------------------------------------------------------------------
-- 1. 투표 설정 (Q-076 1번)
-- ---------------------------------------------------------------------------
select pg_temp.check((select award_announce_time = time '15:00' from public.team_settings where team_id = pg_temp.vid('P')), 'default 15:00');
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error(format('select public.update_award_settings(%L, %L)', pg_temp.vid('P'), '09:30'), 'not_permitted');
select pg_temp.login(pg_temp.u(8));
select pg_temp.expect_error(format('select public.update_award_settings(%L, %L)', pg_temp.vid('P'), '09:30'), 'not_permitted');
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error(format('select public.update_award_settings(%L, null)', pg_temp.vid('P')), 'invalid_award_settings');
select pg_temp.check(public.update_award_settings(pg_temp.vid('P'), time '03:07:45') = time '03:07', 'manager sets dawn time, seconds dropped');
select pg_temp.check(public.update_award_settings(pg_temp.vid('P'), time '09:30') = time '09:30', 'manager sets 09:30');
select pg_temp.login(pg_temp.u(5));
select pg_temp.check((select award_announce_time = time '09:30' from public.team_settings where team_id = pg_temp.vid('P')), 'member reads setting');
reset role;
set local role anon;
select pg_temp.expect_error(format('select public.update_award_settings(%L, %L)', pg_temp.vid('P'), '10:00'), 'permission denied%');
reset role;

-- ---------------------------------------------------------------------------
-- 2. 일정 준비
--   mL: 확정 배치 (시작함·종료 전, 종료 = now+90분). 팀1 e1·e3, 팀2 e2·e4, 교체 e5 + 게스트
--   mR: 배치 미확정(초안에 e7만), 2025-12-31 22:00~2026-01-01 00:30. 참석 e3·e4, 대기 e6, 불참 e7, 게스트
--   mS: 배치 없음, 끝남, 참석 e3 혼자 → 출석만
--   mY: 배치 없음, 끝남, 참석 없음 → 경기 수만
--   mX: 취소, 끝남 → 아무것도 없음
--   mU: 시작함·종료 전, 배치 없음 → 배치 미확정 알림
-- ---------------------------------------------------------------------------
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '30 minutes', now() + interval '90 minutes', now() - interval '3 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mL', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', timestamptz '2025-12-31 22:00+09', timestamptz '2026-01-01 00:30+09',
          timestamptz '2025-12-31 20:00+09', pg_temp.u(1))
  returning id)
insert into t_vars select 'mR', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '5 hours', now() - interval '3 hours', now() - interval '7 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mS', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '6 hours', now() - interval '4 hours', now() - interval '8 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mY', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by, status, cancelled_at, cancelled_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '6 hours', now() - interval '4 hours', now() - interval '8 hours', pg_temp.u(1),
          'cancelled', now() - interval '9 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mX', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '1 minute', now() + interval '2 hours', now() - interval '2 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'mU', id::text from x;

insert into public.attendance_responses (match_id, user_id, state, waitlisted_at)
values (pg_temp.vid('mL'), pg_temp.u(6), 'attending', null),
       (pg_temp.vid('mR'), pg_temp.u(3), 'attending', null),
       (pg_temp.vid('mR'), pg_temp.u(4), 'attending', null),
       (pg_temp.vid('mR'), pg_temp.u(6), 'waitlisted', now() - interval '1 day'),
       (pg_temp.vid('mR'), pg_temp.u(7), 'declined', null),
       (pg_temp.vid('mS'), pg_temp.u(3), 'attending', null),
       (pg_temp.vid('mX'), pg_temp.u(3), 'attending', null),
       (pg_temp.vid('mX'), pg_temp.u(4), 'attending', null);

with x as (
  insert into public.match_guests (match_id, team_id, name, guest_no, added_by)
  values (pg_temp.vid('mL'), pg_temp.vid('P'), null, 1, pg_temp.u(1)) returning id)
insert into t_vars select 'gL', id::text from x;
insert into public.match_guests (match_id, team_id, name, guest_no, added_by)
values (pg_temp.vid('mR'), pg_temp.vid('P'), null, 1, pg_temp.u(1));

-- mR 초안 배치 (e7 만) → 무시되어야 함
with l as (
  insert into public.lineups (match_id, team_count, players_per_team) values (pg_temp.vid('mR'), 2, 1) returning id)
insert into public.lineup_slots (lineup_id, user_id) select l.id, pg_temp.u(7) from l;

-- mL 확정 배치
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.save_lineup(
  pg_temp.vid('mL'), null, 2, 2,
  '[{"squad_no":1,"bib_color":"red"},{"squad_no":2,"bib_color":"blue"}]'::jsonb,
  jsonb_build_array(pg_temp.su(1, 1), pg_temp.su(1, 3), pg_temp.su(2, 2), pg_temp.su(2, 4), pg_temp.su(null, 5),
                    jsonb_build_object('squad_no', null, 'guest_id', pg_temp.vid('gL'))),
  null, true);
-- e5 가 경기 시작 뒤 팀 탈퇴 → 배치에는 남지만 출석·투표 대상에서 빠짐 (Q-061 6번)
select pg_temp.login(pg_temp.u(5));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check((select count(*) = 1 from public.lineup_slots s join public.lineups l on l.id = s.lineup_id
                       where l.match_id = pg_temp.vid('mL') and s.user_id = pg_temp.u(5)), 'departed member stays in started lineup');

-- ---------------------------------------------------------------------------
-- 3. 배치 미확정 알림 (경기 시작 처리, Q-075 15번)
-- ---------------------------------------------------------------------------
select private.close_out_attendance_votes(now());
select pg_temp.check(pg_temp.notif_to('lineup_unconfirmed', 'mU', 1) = 1 and pg_temp.notif_to('lineup_unconfirmed', 'mU', 2) = 1
                     and pg_temp.notif_total('lineup_unconfirmed', 'mU') = 2, 'unconfirmed notice to owner and manager');
select pg_temp.check(pg_temp.notif_total('lineup_unconfirmed', 'mL') = 0, 'no notice for confirmed lineup');
select pg_temp.check(pg_temp.notif_total('lineup_unconfirmed', 'mS') = 0 and pg_temp.notif_total('lineup_unconfirmed', 'mR') = 0,
                     'no notice when processed after end');
select pg_temp.check(pg_temp.notif_total('lineup_unconfirmed', 'mX') = 0, 'no notice for cancelled');
select pg_temp.check((select body like '%팀 배치가 아직 확정 전이에요%' and title = '피FC' from public.notifications
                       where kind = 'lineup_unconfirmed' and user_id = pg_temp.u(1) and ref_id = pg_temp.vid('mU')), 'unconfirmed text');
select private.close_out_attendance_votes(now() + interval '1 minute');
select pg_temp.check(pg_temp.notif_total('lineup_unconfirmed', 'mU') = 2, 'unconfirmed notice once');

-- ---------------------------------------------------------------------------
-- 4. 경기 종료 처리
-- ---------------------------------------------------------------------------
-- 종료 전에는 처리 안 됨
select private.close_out_matches(now());
select pg_temp.check((select closed_out_at is null from public.matches where id = pg_temp.vid('mL')), 'not before end');
select pg_temp.check((select closed_out_at is not null from public.matches where id = pg_temp.vid('mR')), 'mR closed');
select pg_temp.check((select closed_out_at is null from public.matches where id = pg_temp.vid('mX')), 'cancelled skipped');

-- mR: 미확정 → 참석 응답자 e3·e4 (대기·불참·초안·게스트 제외), 시즌 2025, 월 2025-12
select pg_temp.check((select array_agg(user_id order by user_id) from public.attendance_records where match_id = pg_temp.vid('mR'))
                     = pg_temp.match_ids(array[3, 4]), 'mR attendance = attending members');
select pg_temp.check((select bool_and(season = 2025) from public.attendance_records where match_id = pg_temp.vid('mR')), 'season by start date');
select pg_temp.check((select attendance_count = 1 from public.monthly_attendance
                       where team_id = pg_temp.vid('P') and user_id = pg_temp.u(4) and month = date '2025-12-01'), 'month by start date');
select pg_temp.check((select match_count = 1 from public.team_monthly_matches
                       where team_id = pg_temp.vid('P') and month = date '2025-12-01'), 'team month count');
select pg_temp.check((select status = 'open' and opens_at = timestamptz '2026-01-01 00:30+09'
                             and closes_at = timestamptz '2026-01-02 09:30+09'
                        from public.award_polls where match_id = pg_temp.vid('mR')), 'mR poll: next day of end date at setting');
select pg_temp.check((select array_agg(user_id order by user_id) from public.award_participants where match_id = pg_temp.vid('mR'))
                     = pg_temp.match_ids(array[3, 4]), 'mR participants');
select pg_temp.check((select count(*) = 4 and sum(vote_count) = 0 from public.award_tallies where match_id = pg_temp.vid('mR')),
                     'zero tallies for each participant and category');
select pg_temp.check(pg_temp.notif_total('award_poll_opened', 'mR') = 2, 'poll opened notice to participants');

-- mS: 참석 1명 → 출석만, 투표 없음
select pg_temp.check((select count(*) = 1 from public.attendance_records where match_id = pg_temp.vid('mS')), 'mS attendance');
select pg_temp.check((select count(*) = 0 from public.award_polls where match_id = pg_temp.vid('mS')), 'mS no poll (<2)');
select pg_temp.check(pg_temp.notif_total('award_poll_opened', 'mS') = 0, 'mS no notice');
-- mY: 참석 없음 → 경기 수만
select pg_temp.check((select count(*) = 0 from public.attendance_records where match_id = pg_temp.vid('mY')), 'mY no attendance');
select pg_temp.check((select closed_out_at is not null from public.matches where id = pg_temp.vid('mY')), 'mY closed');
-- mX: 취소 → 아무것도 없음
select pg_temp.check((select count(*) = 0 from public.attendance_records where match_id = pg_temp.vid('mX')), 'mX nothing');

-- 이번 달 경기 수 = mS + mY (둘 다 이번 달 시작이라고 가정할 수 없으므로 두 경기 월 합으로 확인)
select pg_temp.check(
  (select coalesce(sum(match_count), 0) from public.team_monthly_matches where team_id = pg_temp.vid('P')) = 3, 'P month counts total 3');

-- mL 종료 처리 (종료 시각 + 1분)
insert into t_vars select 'endL', ends_at::text from public.matches where id = pg_temp.vid('mL');
select private.close_out_matches(pg_temp.v('endL')::timestamptz + interval '1 minute');
select pg_temp.check((select array_agg(user_id order by user_id) from public.attendance_records where match_id = pg_temp.vid('mL'))
                     = pg_temp.match_ids(array[1, 2, 3, 4]), 'mL attendance = lineup members at end (bench departed excluded, e6 attending not in lineup excluded)');
select pg_temp.check((select array_agg(user_id order by user_id) from public.award_participants where match_id = pg_temp.vid('mL'))
                     = pg_temp.match_ids(array[1, 2, 3, 4]), 'mL participants');
select pg_temp.check((select closes_at = private.award_closes_at(pg_temp.v('endL')::timestamptz, time '09:30')
                        from public.award_polls where match_id = pg_temp.vid('mL')), 'mL closes at setting');
select pg_temp.check((select attendance_count = 2 from public.member_season_stats
                       where user_id = pg_temp.u(3) and team_id = pg_temp.vid('P') and season = private.match_season(now())), 'e3 season count (mS + mL)');
select pg_temp.check(pg_temp.notif_total('award_poll_opened', 'mL') = 4, 'mL poll notice');
select pg_temp.check((select bool_and(o.send_at = n.created_at) from public.notifications n
                        join public.notification_outbox o on o.notification_id = n.id
                       where n.kind = 'award_poll_opened' and n.ref_id = pg_temp.vid('mL')), 'poll notice sent immediately');
select pg_temp.check((select body = '수고하셨어요! 오늘의 POM과 오늘의 골을 뽑아 주세요.' from public.notifications
                       where kind = 'award_poll_opened' and ref_id = pg_temp.vid('mL') and user_id = pg_temp.u(1)), 'poll opened text');

-- 두 번 돌려도 한 번만
insert into t_vars select 'stats_sum', sum(attendance_count)::text from public.member_season_stats where team_id = pg_temp.vid('P');
select private.close_out_matches(pg_temp.v('endL')::timestamptz + interval '2 minutes');
select pg_temp.check((select sum(attendance_count)::text from public.member_season_stats where team_id = pg_temp.vid('P')) = pg_temp.v('stats_sum'), 'idempotent stats');
select pg_temp.check((select count(*) = 8 from public.award_tallies where match_id = pg_temp.vid('mL')), 'idempotent tallies');
select pg_temp.check(pg_temp.notif_total('award_poll_opened', 'mL') = 4, 'idempotent notice');
select pg_temp.check((select coalesce(sum(match_count), 0) from public.team_monthly_matches where team_id = pg_temp.vid('P')) = 4, 'P month counts total 4');

-- ---------------------------------------------------------------------------
-- 5. 읽기 권한
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) = 3 and bool_and(user_id = pg_temp.u(3)) from public.attendance_records), 'own attendance only');
select pg_temp.check((select count(*) >= 1 and bool_and(user_id = pg_temp.u(3)) from public.member_season_stats), 'own season stats only');
select pg_temp.expect_error('select count(*) from public.monthly_attendance', 'permission denied%');
select pg_temp.expect_error('select count(*) from public.team_monthly_matches', 'permission denied%');
select pg_temp.expect_error('select count(*) from public.award_tallies', 'permission denied%');
select pg_temp.expect_error(format('insert into public.attendance_records (match_id, team_id, user_id, season) values (%L, %L, %L, 2026)',
                                   pg_temp.vid('mU'), pg_temp.vid('P'), pg_temp.u(3)), 'permission denied%');
select pg_temp.expect_error(format('update public.member_season_stats set pom_count = 9 where user_id = %L', pg_temp.u(3)), 'permission denied%');
select pg_temp.expect_error(format('insert into public.award_ballot_receipts values (%L, %L, %L)', pg_temp.vid('mL'), 'pom', pg_temp.u(3)), 'permission denied%');
select pg_temp.expect_error('select private.close_out_matches()', 'permission denied%');
select pg_temp.expect_error('select private.close_award_polls()', 'permission denied%');
select pg_temp.expect_error(format('select private.close_out_match(%L)', pg_temp.vid('mU')), 'permission denied%');
-- 팀원(대상자 아님 e6)은 회차·대상자를 봄
select pg_temp.login(pg_temp.u(6));
select pg_temp.check((select count(*) = 2 from public.award_polls where team_id = pg_temp.vid('P')), 'member sees polls');
select pg_temp.check((select count(*) = 4 from public.award_participants where match_id = pg_temp.vid('mL')), 'member sees participants');
-- 다른 팀·팀 없음
select pg_temp.login(pg_temp.u(8));
select pg_temp.check((select count(*) = 0 from public.award_polls where team_id = pg_temp.vid('P')), 'other team no polls');
select pg_temp.check((select count(*) = 0 from public.award_participants where match_id = pg_temp.vid('mL')), 'other team no participants');
select pg_temp.login(pg_temp.u(5));
select pg_temp.check((select count(*) = 0 from public.award_polls where team_id = pg_temp.vid('P')), 'departed no polls');
reset role;
set local role anon;
select pg_temp.expect_error('select count(*) from public.award_polls', 'permission denied%');
select pg_temp.expect_error('select count(*) from public.attendance_records', 'permission denied%');
reset role;

-- ---------------------------------------------------------------------------
-- 6. 투표 (mL: 대상자 e1~e4)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.expect_error($$select pg_temp.vote(6, 'mL', 'pom', 1)$$, 'award_not_participant');
select pg_temp.expect_error($$select pg_temp.vote(8, 'mL', 'pom', 1)$$, 'award_poll_not_found');
select pg_temp.expect_error($$select pg_temp.vote(5, 'mL', 'pom', 1)$$, 'award_poll_not_found');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mL', 'pom', 1)$$, 'award_self_vote');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mL', 'mvp', 3)$$, 'award_invalid_category');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mL', 'pom', 5)$$, 'award_invalid_candidate');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mL', 'pom', 6)$$, 'award_invalid_candidate');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mS', 'pom', 3)$$, 'award_poll_not_found');
select pg_temp.check(pg_temp.vote(1, 'mL', 'pom', 4) = 'ok', 'e1 pom e4');
select pg_temp.expect_error($$select pg_temp.vote(1, 'mL', 'pom', 3)$$, 'award_already_voted');
-- 같은 사람을 다른 항목에도
select pg_temp.check(pg_temp.vote(1, 'mL', 'goal_of_the_day', 4) = 'ok', 'e1 goal e4 (same person both)');
select pg_temp.check(pg_temp.vote(2, 'mL', 'pom', 4) = 'ok', 'e2 pom e4');
select pg_temp.check(pg_temp.vote(3, 'mL', 'pom', 1) = 'ok', 'e3 pom e1');
select pg_temp.check(pg_temp.vote(4, 'mL', 'pom', 1) = 'ok', 'e4 pom e1');
select pg_temp.check(pg_temp.vote(3, 'mL', 'goal_of_the_day', 2) = 'ok', 'e3 goal e2');
-- 참여 표시는 본인 것만 (관리자 포함)
select pg_temp.login(pg_temp.u(1));
select pg_temp.check((select count(*) = 2 and bool_and(voter_id = pg_temp.u(1)) from public.award_ballot_receipts), 'owner sees own receipts only');
select pg_temp.login(pg_temp.u(2));
select pg_temp.check((select count(*) = 1 and bool_and(voter_id = pg_temp.u(2)) from public.award_ballot_receipts), 'manager sees own receipts only');
select pg_temp.check((select count(*) = 0 from public.award_winners), 'no winners before close');
-- e4 가 마감 전 팀 탈퇴 → 투표 불가, 후보에서도 빠짐
select pg_temp.login(pg_temp.u(4));
select public.leave_team(pg_temp.vid('P'));
select pg_temp.expect_error($$select pg_temp.vote(4, 'mL', 'goal_of_the_day', 2)$$, 'award_poll_not_found');
select pg_temp.expect_error($$select pg_temp.vote(2, 'mL', 'goal_of_the_day', 4)$$, 'award_invalid_candidate');
select pg_temp.check(pg_temp.vote(2, 'mL', 'goal_of_the_day', 3) = 'ok', 'e2 goal e3');
reset role;
-- 집계: pom e4=2, e1=2 / goal e4=1, e2=1, e3=1
select pg_temp.check((select sum(vote_count) = 4 from public.award_tallies where match_id = pg_temp.vid('mL') and category = 'pom'), 'pom total 4');
select pg_temp.check((select sum(vote_count) = 3 from public.award_tallies where match_id = pg_temp.vid('mL') and category = 'goal_of_the_day'), 'goal total 3');
select pg_temp.check((select count(*) = 4 from public.award_ballot_receipts where match_id = pg_temp.vid('mL') and category = 'pom'), 'pom receipts 4');
-- 참여 표시에 후보·날짜 칸 없음, 득표 집계에 투표자·날짜 칸 없음 (6장)
select pg_temp.check((select array_agg(column_name::text order by column_name) from information_schema.columns
                       where table_schema = 'public' and table_name = 'award_ballot_receipts') = array['category', 'match_id', 'voter_id'], 'receipt columns');
select pg_temp.check((select array_agg(column_name::text order by column_name) from information_schema.columns
                       where table_schema = 'public' and table_name = 'award_tallies') = array['candidate_id', 'category', 'match_id', 'vote_count'], 'tally columns');
select pg_temp.check((select count(*) = 0 from pg_trigger where not tgisinternal
                       and tgrelid in ('public.award_tallies'::regclass, 'public.award_ballot_receipts'::regclass)), 'no triggers on tallies/receipts');
select pg_temp.check((select count(*) = 0 from pg_publication_tables
                       where tablename in ('award_tallies', 'award_ballot_receipts', 'award_participants', 'award_polls', 'award_winners')), 'not in realtime');
select pg_temp.check((select prorettype = 'void'::regtype from pg_proc where oid = 'public.cast_award_vote(uuid, text, uuid)'::regprocedure), 'vote returns nothing');

-- ---------------------------------------------------------------------------
-- 7. 투표 마감 (발표)
-- ---------------------------------------------------------------------------
insert into t_vars select 'closeL', closes_at::text from public.award_polls where match_id = pg_temp.vid('mL');
select private.close_award_polls(pg_temp.v('closeL')::timestamptz - interval '1 minute');
select pg_temp.check((select status = 'open' from public.award_polls where match_id = pg_temp.vid('mL')), 'not closed before closes_at');
select pg_temp.check((select status = 'closed' from public.award_polls where match_id = pg_temp.vid('mR')), 'past poll closed');
select pg_temp.check((select count(*) = 0 from public.award_winners where match_id = pg_temp.vid('mR')), 'no votes = no result');
select private.close_award_polls(pg_temp.v('closeL')::timestamptz);
select pg_temp.check((select array_agg(user_id order by user_id) from public.award_winners where match_id = pg_temp.vid('mL') and category = 'pom')
                     = pg_temp.match_ids(array[1, 4]), 'pom tie both win (departed included)');
select pg_temp.check((select array_agg(user_id order by user_id) from public.award_winners where match_id = pg_temp.vid('mL') and category = 'goal_of_the_day')
                     = pg_temp.match_ids(array[2, 3, 4]), 'goal three-way tie');
select pg_temp.check((select pom_count = 1 and goal_of_the_day_count = 1 from public.member_season_stats
                       where user_id = pg_temp.u(4) and team_id = pg_temp.vid('P') and season = private.match_season(now())), 'departed winner counted');
select pg_temp.check((select pom_count = 1 and goal_of_the_day_count = 0 from public.member_season_stats
                       where user_id = pg_temp.u(1) and team_id = pg_temp.vid('P') and season = private.match_season(now())), 'e1 pom count');
select pg_temp.check((select bool_and(season = private.match_season(now())) from public.award_winners where match_id = pg_temp.vid('mL')), 'winner season');
-- 결과 알림: 대상자 중 지금 팀원 (e1·e2·e3, 떠난 e4 제외). mR 은 e3 만
select pg_temp.check(pg_temp.notif_total('award_results_announced', 'mL') = 3 and pg_temp.notif_to('award_results_announced', 'mL', 4) = 0,
                     'results notice to current participants');
select pg_temp.check(pg_temp.notif_total('award_results_announced', 'mR') = 1 and pg_temp.notif_to('award_results_announced', 'mR', 3) = 1,
                     'mR results notice');
select pg_temp.check((select body = '오늘의 POM·오늘의 골 결과가 나왔어요!' from public.notifications
                       where kind = 'award_results_announced' and ref_id = pg_temp.vid('mL') and user_id = pg_temp.u(1)), 'results text');
-- 두 번 돌려도 한 번만
select private.close_award_polls(pg_temp.v('closeL')::timestamptz + interval '1 minute');
select pg_temp.check((select pom_count = 1 from public.member_season_stats
                       where user_id = pg_temp.u(1) and team_id = pg_temp.vid('P') and season = private.match_season(now())), 'close idempotent');
select pg_temp.check(pg_temp.notif_total('award_results_announced', 'mL') = 3, 'results notice once');
-- 마감 뒤 투표 불가, 팀원 전체가 1위를 봄 (경기에 없던 e6 포함), 득표수는 못 봄
set local role authenticated;
select pg_temp.expect_error($$select pg_temp.vote(3, 'mL', 'goal_of_the_day', 1)$$, 'award_poll_closed');
select pg_temp.login(pg_temp.u(6));
select pg_temp.check((select count(*) = 5 from public.award_winners where match_id = pg_temp.vid('mL')), 'member sees winners');
select pg_temp.login(pg_temp.u(8));
select pg_temp.check((select count(*) = 0 from public.award_winners where match_id = pg_temp.vid('mL')), 'other team no winners');
reset role;

-- 회원 탈퇴한 1위 → 그 사람 줄만 사라짐 (재계산 없음)
select public.delete_account(pg_temp.u(4));
select pg_temp.check((select array_agg(user_id order by user_id) from public.award_winners where match_id = pg_temp.vid('mL') and category = 'pom')
                     = pg_temp.match_ids(array[1]), 'deleted winner removed, no recalculation');
select pg_temp.check((select count(*) = 0 from public.attendance_records where user_id = pg_temp.u(4)), 'deleted account attendance gone');
select pg_temp.check((select count(*) = 0 from public.member_season_stats where user_id = pg_temp.u(4)), 'deleted account stats gone');
select pg_temp.check((select count(*) = 0 from public.monthly_attendance where user_id = pg_temp.u(4)), 'deleted account monthly gone');

-- ---------------------------------------------------------------------------
-- 8. notifier 재료: 투표 상태·마감 시각, 일정 종료 시각
-- ---------------------------------------------------------------------------
create temp table t_claimed as select * from public.claim_push_batch(500);
select pg_temp.check((select count(*) >= 1 and bool_and(award_poll_status = 'closed' and award_poll_closes_at is not null)
                        from t_claimed where kind = 'award_poll_opened' and ref_id = pg_temp.vid('mL')), 'claim returns poll status');
select pg_temp.check((select bool_and(match_ends_at is not null and award_poll_status is null)
                        from t_claimed where kind = 'lineup_unconfirmed' and ref_id = pg_temp.vid('mU')), 'claim returns match end');

-- ---------------------------------------------------------------------------
-- 9. 팀 해체: 진행 중 투표 폐기, 끝났지만 미처리 경기는 출석 먼저 (Q-076 5번)
--   qB: 처리됨·투표 진행 중 (e8 이 e9 에게 투표함) / qA: 끝났지만 미처리, 참석 e8·e9
-- ---------------------------------------------------------------------------
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('Q'), 'manual', now() - interval '5 hours', now() - interval '3 hours', now() - interval '7 hours', pg_temp.u(8))
  returning id)
insert into t_vars select 'qB', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('Q'), 'manual', now() - interval '2 hours', now() - interval '10 minutes', now() - interval '4 hours', pg_temp.u(8))
  returning id)
insert into t_vars select 'qA', id::text from x;
insert into public.attendance_responses (match_id, user_id, state)
values (pg_temp.vid('qB'), pg_temp.u(8), 'attending'), (pg_temp.vid('qB'), pg_temp.u(9), 'attending'),
       (pg_temp.vid('qA'), pg_temp.u(8), 'attending'), (pg_temp.vid('qA'), pg_temp.u(9), 'attending');
select private.close_out_match(pg_temp.vid('qB'));
select pg_temp.check((select status = 'open' from public.award_polls where match_id = pg_temp.vid('qB')), 'qB poll open');
set local role authenticated;
select pg_temp.check(pg_temp.vote(8, 'qB', 'pom', 9) = 'ok', 'e8 votes in Q');
select pg_temp.login(pg_temp.u(8));
select public.dissolve_team(pg_temp.vid('Q'), '큐FC');
reset role;
select pg_temp.check((select count(*) = 0 from public.award_polls where match_id = pg_temp.vid('qB')), 'open poll voided');
select pg_temp.check((select count(*) = 0 from public.award_tallies where match_id = pg_temp.vid('qB'))
                     and (select count(*) = 0 from public.award_ballot_receipts where match_id = pg_temp.vid('qB'))
                     and (select count(*) = 0 from public.award_participants where match_id = pg_temp.vid('qB')), 'poll rows voided');
select pg_temp.check((select count(*) = 0 from public.award_winners where team_id = pg_temp.vid('Q')), 'no award on dissolve');
select pg_temp.check((select coalesce(sum(pom_count), 0) = 0 from public.member_season_stats where team_id = pg_temp.vid('Q')), 'no award count on dissolve');
-- 7단계(202611050054)부터 해체 때 지난 경기는 출석 처리 뒤 삭제된다 (Q-061 4번). 카운트는 아래에서 확인
select pg_temp.check((select count(*) = 0 from public.matches where id = pg_temp.vid('qA')), 'unprocessed match closed out then deleted on dissolve');
select pg_temp.check((select count(*) = 0 from public.attendance_records where match_id = pg_temp.vid('qA')), 'attendance details deleted on dissolve');
select pg_temp.check((select count(*) = 0 from public.award_polls where match_id = pg_temp.vid('qA')), 'no poll opened on dissolve');
select pg_temp.check((select attendance_count = 2 from public.member_season_stats
                       where user_id = pg_temp.u(9) and team_id = pg_temp.vid('Q') and season = private.match_season(now())), 'season count kept');
select pg_temp.check(pg_temp.notif_total('award_results_announced', 'qB') = 0, 'no results notice on dissolve');

-- ---------------------------------------------------------------------------
-- 10. 예약 작업·함수 설정
-- ---------------------------------------------------------------------------
select pg_temp.check((select command from cron.job where jobname = 'close-out-matches') = 'select private.close_out_matches()', 'close-out cron');
select pg_temp.check((select command from cron.job where jobname = 'close-award-polls') = 'select private.close_award_polls()', 'close polls cron');
select pg_temp.check((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where (n.nspname = 'private' and p.proname in ('match_close_out_user_ids', 'close_out_match', 'close_out_matches',
                                                                      'close_award_poll', 'close_award_polls', 'is_award_poll_team_member',
                                                                      'close_out_attendance_vote'))
                          or (n.nspname = 'public' and p.proname in ('cast_award_vote', 'update_award_settings', 'claim_push_batch', 'dissolve_team'))),
                     'definer search_path fixed');
select pg_temp.check(not has_function_privilege('service_role', 'private.close_out_matches(timestamptz)', 'execute')
                     and not has_function_privilege('service_role', 'private.close_award_polls(timestamptz)', 'execute')
                     and not has_function_privilege('authenticated', 'private.close_out_match(uuid, boolean)', 'execute'), 'cron functions locked');
select pg_temp.check(has_function_privilege('authenticated', 'public.cast_award_vote(uuid, text, uuid)', 'execute')
                     and not has_function_privilege('anon', 'public.cast_award_vote(uuid, text, uuid)', 'execute'), 'vote grants');
select pg_temp.check((select bool_and(c.relrowsecurity) from pg_class c
                       where c.oid in ('public.attendance_records'::regclass, 'public.member_season_stats'::regclass,
                                       'public.monthly_attendance'::regclass, 'public.team_monthly_matches'::regclass,
                                       'public.award_polls'::regclass, 'public.award_participants'::regclass,
                                       'public.award_ballot_receipts'::regclass, 'public.award_tallies'::regclass,
                                       'public.award_winners'::regclass)), 'rls on');

-- 일정 삭제 → 출석 기록·투표 줄 같이 삭제, 카운트는 그대로 (7-2 일부)
insert into t_vars select 'e1_att', attendance_count::text from public.member_season_stats
 where user_id = pg_temp.u(1) and team_id = pg_temp.vid('P') and season = private.match_season(now());
delete from public.matches where id = pg_temp.vid('mL');
select pg_temp.check((select count(*) = 0 from public.attendance_records where match_id = pg_temp.vid('mL'))
                     and (select count(*) = 0 from public.award_polls where match_id = pg_temp.vid('mL'))
                     and (select count(*) = 0 from public.award_winners where match_id = pg_temp.vid('mL')), 'match delete cascades');
select pg_temp.check((select attendance_count::text from public.member_season_stats
                       where user_id = pg_temp.u(1) and team_id = pg_temp.vid('P') and season = private.match_season(now())) = pg_temp.v('e1_att'), 'counts survive delete');

select 'ALL PASSED' as result;
