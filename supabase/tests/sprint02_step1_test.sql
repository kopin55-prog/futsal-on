-- 스프린트 02 1단계 마이그레이션(202611050019 일정·참석·게스트 표, 202611050021 자동 생성,
-- 202611050022 직접 추가·취소, 202611050023 해체 시 일정 취소) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 자동 생성 규칙은 private.generate_auto_matches_for_team(team, p_now) 에 시각을 넘겨 확인한다 (2027년 1월 경기).
-- 운동일 변경 즉시 생성(1-3)과 직접 추가는 실제 지금 시각 기준으로 확인한다.

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

-- 한국 시간 기준 날짜·시각 (실제 지금 기준 테스트용)
insert into t_vars values
  ('d3', ((now() + interval '3 days') at time zone 'Asia/Seoul')::date::text),
  ('wd3', extract(isodow from ((now() + interval '3 days') at time zone 'Asia/Seoul'))::text),
  ('soon_date', ((now() + interval '1 hour') at time zone 'Asia/Seoul')::date::text),
  ('soon_time', date_trunc('minute', ((now() + interval '1 hour') at time zone 'Asia/Seoul'))::time::text),
  ('soon_end', (date_trunc('minute', ((now() + interval '1 hour') at time zone 'Asia/Seoul'))::time + interval '90 minutes')::text),
  ('soon_end_date', ((date_trunc('minute', now() + interval '1 hour') + interval '90 minutes') at time zone 'Asia/Seoul')::date::text),
  ('now_date', (now() at time zone 'Asia/Seoul')::date::text),
  ('now_time', (now() at time zone 'Asia/Seoul')::time::text),
  ('soon_wd', extract(isodow from ((now() + interval '1 hour') at time zone 'Asia/Seoul'))::text),
  ('past_date', ((now() - interval '1 hour') at time zone 'Asia/Seoul')::date::text),
  ('past_time', ((now() - interval '1 hour') at time zone 'Asia/Seoul')::time::text);

insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-4000-8000-0000000000e1', 'authenticated', 'authenticated', 'e1@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000e2', 'authenticated', 'authenticated', 'e2@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000e3', 'authenticated', 'authenticated', 'e3@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000e4', 'authenticated', 'authenticated', 'e4@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000e5', 'authenticated', 'authenticated', 'e5@test.invalid', now(), now());

set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select public.create_profile('일번', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
select public.create_profile('이번', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select public.create_profile('삼번', null, array['winger']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select public.create_profile('사번', null, array['winger']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select public.create_profile('오번', null, array['winger']::public.play_position[], false, true, true, true, false);

-- 팀 A: e1 팀장, e2 운영진, e3 팀원 (정기 운동일 없음, 지정 풋살장 카카오)
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
insert into t_vars select 'A', public.create_team('에이FC', null, null, null, null,
  '{"name": "강남 풋살파크", "address": "서울 강남구 1", "provider": "kakao", "place_id": "12345", "lat": 37.5, "lng": 127.0}'::jsonb)::text;
insert into t_vars select 'codeA', team_code from public.teams where id = pg_temp.vid('A');
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
insert into t_vars select 'r2', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
insert into t_vars select 'r3', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select public.decide_join_request(pg_temp.vid('r2'), true);
select public.decide_join_request(pg_temp.vid('r3'), true);
select public.appoint_manager(pg_temp.vid('A'), '00000000-0000-4000-8000-0000000000e2');
select public.update_team_settings(pg_temp.vid('A'), 12, 2, 6, '09:00', 2);
-- 팀 B: e5 팀장 (다른 팀 관리자)
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
insert into t_vars select 'B', public.create_team('비FC')::text;

select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('A')), 'no schedule → no auto match');

-- ================================================================ 1-4·1-5 직접 추가
-- 팀원·팀 밖·다른 팀 관리자 거절
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')$$, 'not_permitted');
select pg_temp.expect_error($$select public.create_match(null, pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')$$, 'not_permitted');

-- 운영진: 장소 없이
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
insert into t_vars select 'm1', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;
select pg_temp.check((select source = 'manual' and status = 'scheduled'
    and starts_at = (pg_temp.v('d3')::date + time '19:00') at time zone 'Asia/Seoul'
    and ends_at = (pg_temp.v('d3')::date + time '21:00') at time zone 'Asia/Seoul'
    and rsvp_deadline_at = starts_at - interval '2 hours'
    and capacity = 12
    and rsvp_reminder_at = rsvp_deadline_at - interval '2 hours'
    and cancel_reason is null
    and created_by = '00000000-0000-4000-8000-0000000000e2'
    and venue_name is null and venue_map_provider is null
    and cancelled_at is null and closed_out_at is null and attendance_closed_out_at is null
  from public.matches where id = pg_temp.vid('m1')), 'manual match: times KST, settings copied, created_by');
-- 같은 시간대 겹치는 일정 허용
insert into t_vars select 'm1b', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;
select pg_temp.check((select count(*) = 2 from public.matches where team_id = pg_temp.vid('A')
  and starts_at = (pg_temp.v('d3')::date + time '19:00') at time zone 'Asia/Seoul'), 'overlap allowed');
-- 카카오맵 장소 / 직접 입력 장소
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
insert into t_vars select 'm2', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '07:00', pg_temp.v('d3')::date, '08:00',
  '{"name": " 동네 구장 ", "address": "서울 1", "provider": "kakao", "place_id": "777", "lat": 37.1, "lng": 127.1}'::jsonb)::text;
select pg_temp.check((select venue_name = '동네 구장' and venue_address = '서울 1' and venue_map_provider = 'kakao'
    and venue_map_place_id = '777' and venue_lat = 37.1 and venue_lng = 127.1
  from public.matches where id = pg_temp.vid('m2')), 'manual match kakao venue');
insert into t_vars select 'm3', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '08:00', pg_temp.v('d3')::date, '09:00',
  '{"name": "학교 운동장"}'::jsonb)::text;
select pg_temp.check((select venue_name = '학교 운동장' and venue_address is null and venue_map_provider is null and venue_lat is null
  from public.matches where id = pg_temp.vid('m3')), 'manual match manual venue');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', '{"name": ""}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', '{"name": "a", "provider": "kakao", "place_id": "1"}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', '{"name": "a", "provider": "kakao", "place_id": "1", "lat": 100, "lng": 1}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', jsonb_build_object('name', repeat('가', 201)))$$, 'invalid_venue');
-- 자정 넘김: 23:00~01:00 → 다음날 01:00 종료
insert into t_vars select 'm4', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '23:00', pg_temp.v('d3')::date + 1, '01:00')::text;
select pg_temp.check((select ends_at = (pg_temp.v('d3')::date + 1 + time '01:00') at time zone 'Asia/Seoul'
    and ends_at - starts_at = interval '2 hours'
  from public.matches where id = pg_temp.vid('m4')), 'manual match crosses midnight');
-- 시각 규칙
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '19:00')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '23:00', pg_temp.v('d3')::date, '01:00')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date - 1, '21:00')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date + 1, '19:01')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), null, '19:00', pg_temp.v('d3')::date, '21:00')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, null, pg_temp.v('d3')::date, '21:00')$$, 'invalid_match_time');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, null)$$, 'invalid_match_time');
-- 지난 시각 불가
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('past_date')::date, pg_temp.v('past_time')::time, pg_temp.v('now_date')::date, pg_temp.v('now_time')::time)$$, 'match_in_past');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), current_date - 30, '10:00', current_date - 30, '12:00')$$, 'match_in_past');
-- 마감이 이미 지난 시각(1시간 뒤 번개, 마감 2시간 전) → 마감 = 시작
insert into t_vars select 'm5', public.create_match(pg_temp.vid('A'), pg_temp.v('soon_date')::date, pg_temp.v('soon_time')::time, pg_temp.v('soon_end_date')::date, pg_temp.v('soon_end')::time)::text;
select pg_temp.check((select rsvp_deadline_at = starts_at and starts_at > now() and ends_at - starts_at = interval '90 minutes'
  from public.matches where id = pg_temp.vid('m5')), 'deadline passed → deadline = start');
-- 마감 = 시작(1시간 뒤)이고 미투표 알림 2시간 전 → 이미 지난 시각이라 비움 (Q-072 1번)
select pg_temp.check((select rsvp_reminder_at is null from public.matches where id = pg_temp.vid('m5')), 'reminder already passed → null');
-- 마감·미투표 알림은 일정마다 고름 (Q-072 1번): 마감 5시간 전, 알림 마감 24시간 전
insert into t_vars select 'm6', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', null, 5, 24)::text;
select pg_temp.check((select rsvp_deadline_at = starts_at - interval '5 hours'
    and rsvp_reminder_at = starts_at - interval '29 hours' and capacity = 12
  from public.matches where id = pg_temp.vid('m6')), 'per-match deadline and reminder, capacity from team');
-- 알림 끄기(0) / 마감 0시간(시작 때 마감)
insert into t_vars select 'm7', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '20:00', pg_temp.v('d3')::date, '21:00', null, 0, 0)::text;
select pg_temp.check((select rsvp_deadline_at = starts_at and rsvp_reminder_at is null
  from public.matches where id = pg_temp.vid('m7')), 'reminder off, deadline at start');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', null, 2, 5)$$, 'invalid_match_settings');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', null, 2, -1)$$, 'invalid_match_settings');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', null, 721, 2)$$, 'invalid_match_settings');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00', null, -1, 2)$$, 'invalid_match_settings');
-- 팀 설정 미투표 알림: 기본 2, 1·2·3·6·12·24 또는 끄기(null)
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select pg_temp.check((select rsvp_reminder_hours = 2 from public.team_settings where team_id = pg_temp.vid('B')), 'new team reminder default 2');
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_error($$select public.update_team_settings(pg_temp.vid('A'), 12, 2, 6, '09:00', 5)$$, 'invalid_team_settings');
select public.update_team_settings(pg_temp.vid('A'), 12, 2, 6, '09:00', null);
select pg_temp.check((select rsvp_reminder_hours is null from public.team_settings where team_id = pg_temp.vid('A')), 'team reminder off');
insert into t_vars select 'm8', public.create_match(pg_temp.vid('A'), pg_temp.v('d3')::date, '18:00', pg_temp.v('d3')::date, '19:00')::text;
select pg_temp.check((select rsvp_reminder_at is null from public.matches where id = pg_temp.vid('m8')), 'team reminder off → manual default none');
select public.update_team_settings(pg_temp.vid('A'), 12, 2, 6, '09:00', 6);
select pg_temp.check((select rsvp_reminder_at is null from public.matches where id = pg_temp.vid('m8')), 'settings change keeps existing match');
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.expect_error($$select public.update_team_settings(pg_temp.vid('A'), 12, 2, 6, '09:00', 2)$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');

-- ================================================================ 1-1 읽기·쓰기 권한
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.check((select count(*) = 9 from public.matches where team_id = pg_temp.vid('A')), 'member reads team matches');
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select pg_temp.check((select count(*) = 0 from public.matches), 'outsider reads no matches');
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('A')), 'other team staff reads no matches');
-- 앱에서 표 직접 쓰기 거절
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '25 hours', now())$$, 'permission denied%');
select pg_temp.expect_error($$update public.matches set status = 'cancelled' where id = pg_temp.vid('m1')$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.matches where id = pg_temp.vid('m1')$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('m1'), '00000000-0000-4000-8000-0000000000e1', 'attending')$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('m1'), pg_temp.vid('A'), '게스트')$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, user_id, level) values (pg_temp.vid('A'), '00000000-0000-4000-8000-0000000000e3', 'pro')$$, 'permission denied%');

-- 서버가 쓴 응답·게스트·게스트 실력 (2단계 서버 함수 대신 관리자 권한으로 넣는다)
reset role;
insert into public.attendance_responses (match_id, user_id, state)
values (pg_temp.vid('m1'), '00000000-0000-4000-8000-0000000000e3', 'attending');
with x as (
  insert into public.match_guests (match_id, team_id, name, positions, added_by)
  values (pg_temp.vid('m1'), pg_temp.vid('A'), '용병', array['goalkeeper']::public.play_position[], '00000000-0000-4000-8000-0000000000e1')
  returning id)
insert into t_vars select 'g1', id::text from x;
insert into public.skill_ratings (team_id, guest_id, level) values (pg_temp.vid('A'), pg_temp.vid('g1'), 'semipro');
-- 검사: 대기는 순번 필요, 게스트 이름 1~8자·포지션 최대 3개·중복 없음, 다른 팀 일정 불가, 실력 대상 정확히 하나
select pg_temp.expect_error($$insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('m1'), '00000000-0000-4000-8000-0000000000e2', 'waitlisted')$$, '%attendance_responses_waitlist_order%');
select pg_temp.expect_error($$insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('m1'), '00000000-0000-4000-8000-0000000000e3', 'declined')$$, '%attendance_responses_one_per_user%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('m1'), pg_temp.vid('A'), repeat('가', 65))$$, '%match_guests_name_valid%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('m1'), pg_temp.vid('A'), ' 앞공백')$$, '%match_guests_name_valid%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name, positions) values (pg_temp.vid('m1'), pg_temp.vid('A'), '넷', array['goalkeeper','defender','midfielder','forward']::public.play_position[])$$, '%match_guests_positions_valid%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name, positions) values (pg_temp.vid('m1'), pg_temp.vid('A'), '중복', array['forward','forward']::public.play_position[])$$, '%match_guests_positions_valid%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('m1'), pg_temp.vid('B'), '남의팀')$$, '%match_guests_match_fk%');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, level) values (pg_temp.vid('A'), 'pro')$$, '%skill_ratings_one_subject%');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, user_id, guest_id, level) values (pg_temp.vid('A'), '00000000-0000-4000-8000-0000000000e3', pg_temp.vid('g1'), 'pro')$$, '%skill_ratings_one_subject%');
with x as (insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('m1'), pg_temp.vid('A'), '둘째') returning id)
insert into t_vars select 'g2', id::text from x;
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, guest_id, level) values (pg_temp.vid('B'), pg_temp.vid('g2'), 'pro')$$, '%skill_ratings_guest_fk%');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, guest_id, level) values (pg_temp.vid('A'), gen_random_uuid(), 'pro')$$, '%skill_ratings_guest_fk%');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, guest_id, level) values (pg_temp.vid('A'), pg_temp.vid('g1'), 'pro')$$, '%skill_ratings_guest_key%');
-- 일정 표 검사
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by) values (pg_temp.vid('A'), 'auto', now() + interval '1 day', now() + interval '25 hours', now(), '00000000-0000-4000-8000-0000000000e1')$$, '%matches_auto_has_no_creator%');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '1 day', now())$$, '%matches_ends_after_start%');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '25 hours', now() + interval '2 days')$$, '%matches_deadline_before_start%');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, status) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '25 hours', now(), 'cancelled')$$, '%matches_cancelled_consistent%');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, cancel_reason) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '25 hours', now(), '사유')$$, '%matches_cancelled_consistent%');
select pg_temp.expect_error($$insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at) values (pg_temp.vid('A'), 'manual', now() + interval '1 day', now() + interval '25 hours', now(), now())$$, '%matches_reminder_before_deadline%');
set local role authenticated;

-- 팀원: 응답·게스트 이름 읽기 가능, 게스트 포지션·게스트 실력 불가
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.check((select count(*) = 1 from public.attendance_responses where match_id = pg_temp.vid('m1')), 'member reads responses');
select pg_temp.check((select name = '용병' from public.match_guests where id = pg_temp.vid('g1')), 'member reads guest name');
select pg_temp.expect_error($$select positions from public.match_guests$$, 'permission denied%');
select pg_temp.expect_error($$select * from public.match_guests$$, 'permission denied%');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where guest_id = pg_temp.vid('g1')), 'member cannot read guest level');
-- 관리자: 게스트 실력 읽기 가능, 포지션은 표로는 불가 (2단계 서버 함수로)
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
select pg_temp.check((select level = 'semipro' from public.skill_ratings where guest_id = pg_temp.vid('g1')), 'staff reads guest level');
select pg_temp.expect_error($$select positions from public.match_guests$$, 'permission denied%');
-- 팀 밖: 0건
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select pg_temp.check((select count(*) = 0 from public.attendance_responses), 'outsider reads no responses');
select pg_temp.check((select count(*) = 0 from public.match_guests), 'outsider reads no guests');
-- 비로그인: 표 자체 거절
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select pg_temp.expect_error($$select count(*) from public.matches$$, 'permission denied%');
select pg_temp.expect_error($$select count(*) from public.attendance_responses$$, 'permission denied%');
select pg_temp.expect_error($$select id from public.match_guests$$, 'permission denied%');
select pg_temp.expect_error($$select public.create_match(pg_temp.vid('A'), current_date + 3, '19:00', current_date + 3, '21:00')$$, 'permission denied%');
reset role;
set local role authenticated;

-- ================================================================ 1-6 취소
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.expect_error($$select public.cancel_match(pg_temp.vid('m1'))$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
select pg_temp.expect_error($$select public.cancel_match(pg_temp.vid('m1'))$$, 'not_permitted');
select pg_temp.expect_error($$select public.cancel_match(gen_random_uuid())$$, 'not_permitted');
select pg_temp.expect_error($$select public.cancel_match(null)$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
-- 취소 사유: 이름과 같은 글자 정리, 1~20자 (Q-072 5번)
select pg_temp.expect_error($$select public.cancel_match(pg_temp.vid('m1'), repeat('가', 21))$$, 'invalid_cancel_reason');
select public.cancel_match(pg_temp.vid('m1'), E'  비 와서​   취소  ');
select pg_temp.check((select status = 'cancelled' and cancelled_at = now()
    and cancelled_by = '00000000-0000-4000-8000-0000000000e2'
    and cancel_reason = '비 와서 취소'
  from public.matches where id = pg_temp.vid('m1')), 'manager cancels with normalized reason');
-- 20자는 가능, 비우면 사유 없음
select public.cancel_match(pg_temp.vid('m7'), repeat('가', 20));
select pg_temp.check((select cancel_reason = repeat('가', 20) from public.matches where id = pg_temp.vid('m7')), 'reason 20 chars');
select public.cancel_match(pg_temp.vid('m8'), '   ');
select pg_temp.check((select status = 'cancelled' and cancel_reason is null from public.matches where id = pg_temp.vid('m8')), 'blank reason → none');
-- 팀원도 사유를 읽는다
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.check((select cancel_reason = '비 와서 취소' from public.matches where id = pg_temp.vid('m1')), 'member reads cancel reason');
select pg_temp.login('00000000-0000-4000-8000-0000000000e2');
-- 되돌리기·다시 취소 없음
select pg_temp.expect_error($$select public.cancel_match(pg_temp.vid('m1'))$$, 'match_already_cancelled');
-- 응답은 남는다 (취소 알림 받는 사람, 3단계)
select pg_temp.check((select count(*) = 1 from public.attendance_responses where match_id = pg_temp.vid('m1')), 'responses kept on cancel');
-- 시작한 경기는 취소 불가
reset role;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('A'), 'manual', now() - interval '1 minute', now() + interval '2 hours', now() - interval '2 hours', '00000000-0000-4000-8000-0000000000e1')
  returning id)
insert into t_vars select 'started', id::text from x;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_error($$select public.cancel_match(pg_temp.vid('started'))$$, 'match_already_started');

-- ================================================================ 1-2 자동 생성 (시각 지정)
-- 팀 G: 수 10:00~12:00, 기본 설정(6일 전 09:00, 마감 2시간 전, 정원 없음), 지정 풋살장 직접 입력
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
insert into t_vars select 'G', public.create_team('지FC', 3::smallint, '10:00', '12:00', null, '{"name": "지구장", "address": "부산"}'::jsonb)::text;
-- 팀 H: 금 22:00~00:30 (자정 넘김), 정원 10
insert into t_vars select 'H', public.create_team('에이치FC', 5::smallint, '22:00', '00:30')::text;
select public.update_team_settings(pg_temp.vid('H'), 10, 2, 6, '09:00', 2);
-- 팀 N: 종료 시각 없음(Q-073 8번 이후 새로 정할 수 없어 이전 데이터로 흉내, 아래) / 팀 W: 요일만
insert into t_vars select 'N', public.create_team('엔FC', 3::smallint, null, null)::text;
insert into t_vars select 'W', public.create_team('더블유FC', 3::smallint, null, null)::text;
-- 팀 T: 수 10:00~12:00, 13일 전 생성 → 한 번에 두 주
insert into t_vars select 'T', public.create_team('티FC', 3::smallint, '10:00', '12:00')::text;
select public.update_team_settings(pg_temp.vid('T'), null, 2, 13, '09:00', 2);
reset role;
-- 팀 N: 종료 시각이 비어 있는 이전 데이터 (202611050034 전에 저장된 팀)
alter table public.teams disable trigger teams_regular_end_required;
update public.teams set regular_start_time = '10:00' where id = pg_temp.vid('N');
alter table public.teams enable trigger teams_regular_end_required;

-- 2027-01-06(수) 경기 → 생성 2026-12-31(목) 09:00, 마감 2027-01-06 08:00
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G'), '2026-12-31 08:59+09') = 0, 'G: before create time → none');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G'), '2026-12-31 09:00+09') = 1, 'G: at create time → 1');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G'), '2026-12-31 09:05+09') = 0, 'G: second run → none');
select pg_temp.check((select count(*) = 1 and bool_and(
      source = 'auto' and status = 'scheduled' and created_by is null
      and starts_at = '2027-01-06 10:00+09' and ends_at = '2027-01-06 12:00+09'
      and rsvp_deadline_at = '2027-01-06 08:00+09' and capacity is null
      and rsvp_reminder_at = '2027-01-06 06:00+09'
      and venue_name = '지구장' and venue_address = '부산' and venue_map_provider is null)
  from public.matches where team_id = pg_temp.vid('G') and starts_at >= '2026-12-01'), 'G: auto match values');
insert into t_vars select 'gm', id::text from public.matches where team_id = pg_temp.vid('G') and starts_at = '2027-01-06 10:00+09';
-- 설정·지정 풋살장을 바꿔도 이미 만든 일정은 그대로 (M-12)
update public.team_settings set capacity = 20, rsvp_deadline_hours = 3, rsvp_reminder_hours = 24 where team_id = pg_temp.vid('G');
update public.teams set venue_name = '새구장', venue_address = null where id = pg_temp.vid('G');
select pg_temp.check((select capacity is null and rsvp_deadline_at = '2027-01-06 08:00+09' and venue_name = '지구장'
  from public.matches where id = pg_temp.vid('gm')), 'G: existing match unchanged after settings change');
-- 다음 주는 새 설정 (정원 20, 마감 3시간 전, 새 구장)
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G'), '2027-01-07 09:00+09') = 1, 'G: next week');
select pg_temp.check((select capacity = 20 and rsvp_deadline_at = '2027-01-13 07:00+09' and venue_name = '새구장'
    and rsvp_reminder_at = '2027-01-12 07:00+09'
  from public.matches where team_id = pg_temp.vid('G') and starts_at = '2027-01-13 10:00+09'), 'G: next week uses current settings');
-- 취소된 자동 일정은 다시 생기지 않는다
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e4');
select public.cancel_match(pg_temp.vid('gm'));
reset role;
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G'), '2027-01-01 12:00+09') = 0, 'G: cancelled auto match not recreated');
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('G') and starts_at = '2027-01-06 10:00+09'), 'G: still one row');
-- 마감이 지난 뒤에는 만들지 않는다 (팀 G2: 같은 일정, 처음 돌리는 시각이 마감)
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
insert into t_vars select 'G2', public.create_team('지투FC', 3::smallint, '10:00', '12:00')::text;
reset role;
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G2'), '2027-01-06 08:00+09') = 0, 'G2: at deadline → none');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G2'), '2027-01-06 07:59+09') = 1, 'G2: just before deadline → 1');
-- 생성 때 미투표 알림 시각(06:00)이 이미 지났으면 비움
select pg_temp.check((select rsvp_reminder_at is null and rsvp_deadline_at = '2027-01-06 08:00+09'
  from public.matches where team_id = pg_temp.vid('G2') and starts_at = '2027-01-06 10:00+09'), 'G2: passed reminder → null');
-- 팀 설정이 끄기면 비움
update public.team_settings set rsvp_reminder_hours = null where team_id = pg_temp.vid('G2');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('G2'), '2027-01-07 09:00+09') = 1, 'G2: next week');
select pg_temp.check((select rsvp_reminder_at is null
  from public.matches where team_id = pg_temp.vid('G2') and starts_at = '2027-01-13 10:00+09'), 'G2: reminder off → null');

-- 자정 넘김: 2027-01-08(금) 22:00 → 종료 01-09 00:30, 정원 복사
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('H'), '2027-01-02 09:00+09') = 1, 'H: generated');
select pg_temp.check((select ends_at = '2027-01-09 00:30+09' and rsvp_deadline_at = '2027-01-08 20:00+09' and capacity = 10
  from public.matches where team_id = pg_temp.vid('H') and starts_at = '2027-01-08 22:00+09'), 'H: crosses midnight');
-- 종료 시각 없음·요일만 → 만들지 않음
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('N'), '2026-12-31 09:00+09') = 0, 'N: no end time → none');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('W'), '2026-12-31 09:00+09') = 0, 'W: weekday only → none');
-- 13일 전 생성: 2026-12-24 09:00 시점에 01-06 경기만 (12-30 경기는 생성 12-17, 01-13 경기는 생성 12-31)
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('T'), '2026-12-24 09:00+09') = 2, 'T: 12-30 and 01-06');
select pg_temp.check((select array_agg(starts_at order by starts_at) = array['2026-12-30 10:00+09', '2027-01-06 10:00+09']::timestamptz[]
  from public.matches where team_id = pg_temp.vid('T') and starts_at >= '2026-12-01'), 'T: two upcoming weeks');
-- 예약 작업 전체 함수도 같은 규칙 (G2·H 는 이미 있으므로 다른 날짜로 확인)
select pg_temp.check(private.generate_auto_matches('2027-01-14 09:00+09') >= 2, 'all-teams run creates for several teams');
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('G') and starts_at = '2027-01-20 10:00+09'), 'all-teams run: G 01-20');
select pg_temp.check((select count(*) = 0 from public.matches where team_id in (pg_temp.vid('N'), pg_temp.vid('W'))), 'all-teams run: N, W none');

-- ================================================================ 1-3 운동일을 새로 정하거나 바꾼 주 (실제 지금 기준)
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e5');
-- 팀 만들 때 정함: 3일 뒤 요일 10:00~12:00 → 생성 시각(6일 전) 지남, 마감 전 → 바로 생성
insert into t_vars select 'L', public.create_team('엘FC', pg_temp.v('wd3')::smallint, '10:00', '12:00')::text;
select pg_temp.check((select count(*) = 1 and bool_and(source = 'auto'
    and starts_at = (pg_temp.v('d3')::date + time '10:00') at time zone 'Asia/Seoul')
  from public.matches where team_id = pg_temp.vid('L')), 'create_team with schedule → this week now');
-- 팀 정보 수정으로 정함
insert into t_vars select 'K', public.create_team('케이FC')::text;
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('K')), 'K: none before schedule');
select public.update_team_info(pg_temp.vid('K'), '케이FC', pg_temp.v('wd3')::smallint, '18:00', '20:00', true, null);
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('K')
  and starts_at = (pg_temp.v('d3')::date + time '18:00') at time zone 'Asia/Seoul'), 'set schedule → this week now');
-- 같은 값으로 다시 저장해도 더 생기지 않음
select public.update_team_info(pg_temp.vid('K'), '케이FC', pg_temp.v('wd3')::smallint, '18:00', '20:00', true, null);
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('K')), 'same schedule → nothing new');
-- 이번 주 마감이 지난 시각으로 바꿈(1시간 뒤 시작, 마감 2시간 전) → 이번 주 생성 안 함, 기존 일정 그대로
select public.update_team_info(pg_temp.vid('K'), '케이FC', pg_temp.v('soon_wd')::smallint, pg_temp.v('soon_time')::time, pg_temp.v('soon_end')::time, true, null);
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('K')), 'deadline passed → from next week, old match kept');
select pg_temp.check((select status = 'scheduled' from public.matches where team_id = pg_temp.vid('K')), 'old match still scheduled');
-- 표 직접 수정(칸 단위 권한) 경로도 같은 규칙
update public.teams set regular_start_time = '19:00', regular_end_time = '21:00', regular_weekday = pg_temp.v('wd3')::smallint
 where id = pg_temp.vid('K');
select pg_temp.check((select count(*) = 2 from public.matches where team_id = pg_temp.vid('K')), 'direct table update → generated');

-- ================================================================ 1-7 해체 시 다가오는 일정 취소
reset role;
-- 팀 A: 앞으로 일정 m1b·m2·m3·m4·m5 (예정), m1 (이미 취소), started (진행 중)
insert into t_vars select 'm1_cancelled_at', cancelled_at::text from public.matches where id = pg_temp.vid('m1');
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select public.dissolve_team(pg_temp.vid('A'), '에이FC');
reset role;
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('A') and status = 'scheduled' and starts_at > now()),
  'dissolve: no upcoming scheduled match');
select pg_temp.check((select bool_and(status = 'cancelled' and cancelled_by = '00000000-0000-4000-8000-0000000000e1' and cancelled_at = now())
  from public.matches where id in (pg_temp.vid('m1b'), pg_temp.vid('m2'), pg_temp.vid('m3'), pg_temp.vid('m4'), pg_temp.vid('m5'))),
  'dissolve: upcoming cancelled by owner');
select pg_temp.check((select status = 'scheduled' from public.matches where id = pg_temp.vid('started')), 'dissolve: started match untouched');
select pg_temp.check((select cancelled_by = '00000000-0000-4000-8000-0000000000e2' and cancelled_at::text = pg_temp.v('m1_cancelled_at')
  from public.matches where id = pg_temp.vid('m1')), 'dissolve: already cancelled untouched');
-- 해체된 팀은 자동 생성 안 함
update public.teams set regular_weekday = 3, regular_start_time = '10:00', regular_end_time = '12:00' where id = pg_temp.vid('A');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('A'), '2026-12-31 09:00+09') = 0, 'dissolved team → none');
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('A') and source = 'auto'), 'dissolved team: no auto match');
-- 해체 뒤 옛 팀원은 못 읽는다
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e3');
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('A')), 'ex-member reads no matches');
select pg_temp.check((select count(*) = 0 from public.attendance_responses), 'ex-member reads no responses');
reset role;

-- ================================================================ 일정 삭제 시 딸린 줄 삭제
delete from public.matches where id = pg_temp.vid('m1');
select pg_temp.check((select count(*) = 0 from public.attendance_responses where match_id = pg_temp.vid('m1')), 'delete cascades responses');
select pg_temp.check((select count(*) = 0 from public.match_guests where id = pg_temp.vid('g1')), 'delete cascades guests');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where guest_id = pg_temp.vid('g1')), 'delete cascades guest level');

-- 회원 탈퇴: 일정의 사람 칸은 비우고 응답은 지운다 (탈퇴를 막지 않음)
insert into public.attendance_responses (match_id, user_id, state)
values (pg_temp.vid('gm'), '00000000-0000-4000-8000-0000000000e4', 'declined');
select pg_temp.check(public.account_deletion_blocker('00000000-0000-4000-8000-0000000000e2') is null, 'e2 can delete account');
select public.delete_account('00000000-0000-4000-8000-0000000000e2');
select pg_temp.check((select cancelled_by is null and status = 'cancelled' and cancel_reason = repeat('가', 20) from public.matches where id = pg_temp.vid('m7')), 'account deletion clears cancelled_by, keeps reason');
select pg_temp.check((select count(*) = 0 from public.matches where created_by = '00000000-0000-4000-8000-0000000000e2'), 'account deletion clears created_by');

-- ================================================================ 실행 권한·예약 작업
select pg_temp.check(not has_function_privilege('authenticated', 'private.generate_auto_matches(timestamptz)', 'execute'), 'authenticated cannot run generator');
select pg_temp.check(not has_function_privilege('anon', 'private.generate_auto_matches(timestamptz)', 'execute'), 'anon cannot run generator');
select pg_temp.check(not has_function_privilege('service_role', 'private.generate_auto_matches(timestamptz)', 'execute'), 'service_role cannot run generator');
select pg_temp.check(not has_function_privilege('authenticated', 'private.generate_auto_matches_for_team(uuid, timestamptz)', 'execute'), 'authenticated cannot run team generator');
select pg_temp.check(not has_function_privilege('service_role', 'private.generate_auto_matches_for_team(uuid, timestamptz)', 'execute'), 'service_role cannot run team generator');
select pg_temp.check(not has_function_privilege('authenticated', 'private.parse_venue(jsonb)', 'execute'), 'venue parser not callable');
select pg_temp.check(not has_function_privilege('anon', 'public.create_match(uuid, date, time, date, time, jsonb, int, int)', 'execute'), 'anon cannot create match');
select pg_temp.check(has_function_privilege('authenticated', 'public.create_match(uuid, date, time, date, time, jsonb, int, int)', 'execute'), 'authenticated can create match');
select pg_temp.check(not has_function_privilege('anon', 'public.cancel_match(uuid, text)', 'execute'), 'anon cannot cancel');
select pg_temp.check(has_function_privilege('authenticated', 'public.cancel_match(uuid, text)', 'execute'), 'authenticated can cancel');
select pg_temp.check(has_function_privilege('authenticated', 'private.is_match_team_member(uuid)', 'execute'), 'policy helper callable');
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_error($$select private.generate_auto_matches()$$, 'permission denied%');
reset role;
select pg_temp.check(
  (select command from cron.job where jobname = 'generate-auto-matches') = 'select private.generate_auto_matches()'
  and (select schedule from cron.job where jobname = 'generate-auto-matches') = '* * * * *',
  'cron job every minute');
-- RLS 켜짐
select pg_temp.check((select bool_and(relrowsecurity) from pg_class
  where oid in ('public.matches'::regclass, 'public.attendance_responses'::regclass, 'public.match_guests'::regclass)), 'RLS on');
-- SECURITY DEFINER 함수는 search_path 고정
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and proname in (
    'generate_auto_matches_for_team', 'generate_auto_matches', 'teams_regular_schedule_changed', 'team_settings_created',
    'create_match', 'cancel_match', 'dissolve_team', 'apply_team_venue', 'is_match_team_member')), 'definer search_path fixed');

select 'ALL PASSED' as result;
