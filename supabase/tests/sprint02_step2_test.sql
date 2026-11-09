-- 스프린트 02 2단계 마이그레이션(202611050024 참석 투표, 202611050025 떠나는 사람 응답 정리,
-- 202611050026 게스트, 202611050027 참여율) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 마감이 지난 일정·이미 시작한 경기·지난 달 경기는 서버 권한(postgres)으로 표에 직접 넣어 준비한다.
-- 참여율 처리는 private.close_out_attendance_votes(p_now) 에 시각을 넘겨 확인한다.
-- 동시 요청(두 연결)은 이 스크립트로 확인할 수 없다. 잠금 순서는 마이그레이션 주석 참고.

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
  select ('00000000-0000-4000-8000-0000000000f' || p_n::text)::uuid
$$;

-- 응답 상태 (없으면 'none'), 대기 순번 (대기 아니면 null). postgres 로 읽는다.
create function pg_temp.st(p_match text, p_n int)
returns text
language sql
as $$
  select coalesce((select r.state::text from public.attendance_responses r
                    where r.match_id = pg_temp.vid(p_match) and r.user_id = pg_temp.u(p_n)), 'none')
$$;

create function pg_temp.wpos(p_match text, p_n int)
returns int
language sql
as $$
  select pos::int from (
    select r.user_id, row_number() over (order by r.waitlisted_at, r.id) as pos
      from public.attendance_responses r
     where r.match_id = pg_temp.vid(p_match) and r.state = 'waitlisted'
  ) w where w.user_id = pg_temp.u(p_n)
$$;

create function pg_temp.attending(p_match text)
returns int
language sql
as $$
  select count(*)::int from public.attendance_responses r
   where r.match_id = pg_temp.vid(p_match) and r.state = 'attending'
$$;

-- 참여율 (대상, 응답) 문자열. 줄이 없으면 'none'
create function pg_temp.vp(p_team text, p_n int, p_month date)
returns text
language sql
as $$
  select coalesce((select p.attendance_vote_eligible || '/' || p.attendance_vote_responded
                     from public.monthly_vote_participation p
                    where p.team_id = pg_temp.vid(p_team) and p.user_id = pg_temp.u(p_n) and p.month = p_month), 'none')
$$;

insert into t_vars values
  ('d3', ((now() + interval '3 days') at time zone 'Asia/Seoul')::date::text),
  ('this_month', date_trunc('month', (now() - interval '2 hours') at time zone 'Asia/Seoul')::date::text);

insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'f' || n || '@test.invalid', now(), now()
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

-- 팀 P: f1 팀장, f2 운영진, f3·f4·f5·f6·f9 팀원. 정원 2
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('피FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
-- 팀 Q: f7 팀장, f3 팀원 (다른 팀 영향 확인)
select pg_temp.login(pg_temp.u(7));
insert into t_vars select 'Q', public.create_team('큐FC')::text;
insert into t_vars select 'codeQ', team_code from public.teams where id = pg_temp.vid('Q');

select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'rp2', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'rp3', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'rp4', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'rp5', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'rp6', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(9)); insert into t_vars select 'rp9', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'rq3', public.request_join(pg_temp.v('codeQ'), 'code')::text;
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid(k), true) from unnest(array['rp2', 'rp3', 'rp4', 'rp5', 'rp6', 'rp9']) k;
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
select public.update_team_settings(pg_temp.vid('P'), 2, 2, 6, '09:00', 2);
select pg_temp.login(pg_temp.u(7));
select public.decide_join_request(pg_temp.vid('rq3'), true);

-- 일정 m1 (팀 P, 3일 뒤 19:00, 정원 2), m2 (정원 없음으로 바꿈), m3 (취소), q1 (팀 Q)
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'm1', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;
insert into t_vars select 'm2', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '15:00', pg_temp.v('d3')::date, '17:00')::text;
insert into t_vars select 'm3', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '11:00', pg_temp.v('d3')::date, '13:00')::text;
select public.cancel_match(pg_temp.vid('m3'));
select pg_temp.login(pg_temp.u(7));
insert into t_vars select 'q1', public.create_match(pg_temp.vid('Q'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;

reset role;
update public.matches set capacity = null where id = pg_temp.vid('m2');
-- m4: 마감 지남·시작 전 (팀 P, 정원 1)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '1 hour', now() + interval '3 hours', 1, now() - interval '1 minute', pg_temp.u(1))
  returning id)
insert into t_vars select 'm4', id::text from x;
-- m5: 이미 시작 (팀 P, 정원 1)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, capacity, rsvp_deadline_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() - interval '10 minutes', now() + interval '2 hours', 1, now() - interval '2 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'm5', id::text from x;
-- m6: 마감 = 지금 + 1초 직후 정각 확인용은 아래에서 따로
set local role authenticated;

-- ================================================================ 2-1 참석 투표
-- 팀 밖·다른 팀 거절 (SB-24)
select pg_temp.login(pg_temp.u(8));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'not_permitted');
select pg_temp.login(pg_temp.u(7));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'not_permitted');
select pg_temp.expect_error($$select public.respond_attendance('00000000-0000-4000-8000-000000000000', true)$$, 'not_permitted');
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), null)$$, 'invalid_attendance');
-- 취소된 일정 (SB-25), 마감 지난 일정 (SB-16)
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m3'), true)$$, 'match_cancelled');
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m4'), true)$$, 'rsvp_closed');
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m5'), false)$$, 'rsvp_closed');

-- 정원 2: f3·f4 참석, f5·f6·f1 대기 1·2·3번 (SB-03)
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'attending', 'f3 attending');
insert into t_vars select 'f3_upd', updated_at::text from public.attendance_responses where match_id = pg_temp.vid('m1') and user_id = pg_temp.u(3);
-- 연타: 그대로 (SB-15)
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'attending', 'f3 attending again');
select pg_temp.check((select count(*) = 1 and max(updated_at)::text = pg_temp.v('f3_upd') from public.attendance_responses
  where match_id = pg_temp.vid('m1') and user_id = pg_temp.u(3)), 'repeat press changes nothing');
select pg_temp.login(pg_temp.u(4));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'attending', 'f4 attending');
select pg_temp.login(pg_temp.u(5));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f5 waitlisted');
select pg_temp.login(pg_temp.u(6));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f6 waitlisted');
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f6 waitlisted again');
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f1 waitlisted');
reset role;
select pg_temp.check(pg_temp.wpos('m1', 5) = 1 and pg_temp.wpos('m1', 6) = 2 and pg_temp.wpos('m1', 1) = 3, 'waitlist order 5,6,1');
select pg_temp.check(pg_temp.attending('m1') = 2, 'attending = capacity');
set local role authenticated;

-- 팀원 전체가 명단을 읽는다, 다른 팀은 0건 (SB-02)
select pg_temp.login(pg_temp.u(9));
select pg_temp.check((select count(*) = 5 from public.attendance_responses where match_id = pg_temp.vid('m1')), 'member reads all responses');
select pg_temp.login(pg_temp.u(7));
select pg_temp.check((select count(*) = 0 from public.attendance_responses where match_id = pg_temp.vid('m1')), 'other team reads none');

-- 다른 사람 응답 직접 쓰기·미투표로 되돌리기(삭제) 거절 (SB-12, SB-14)
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$update public.attendance_responses set state = 'declined' where match_id = pg_temp.vid('m1')$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.attendance_responses where user_id = pg_temp.u(3)$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.attendance_responses (match_id, user_id, state) values (pg_temp.vid('m2'), pg_temp.u(4), 'attending')$$, 'permission denied%');

-- 참석자 f3 불참 → 대기 1번 f5 자동 참석, f6 이 1번 (SB-04)
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), false) = 'declined', 'f3 declined');
reset role;
select pg_temp.check(pg_temp.st('m1', 5) = 'attending', 'f5 promoted');
select pg_temp.check((select promoted_at is not null and waitlisted_at is null from public.attendance_responses
  where match_id = pg_temp.vid('m1') and user_id = pg_temp.u(5)), 'promoted_at recorded');
select pg_temp.check(pg_temp.wpos('m1', 6) = 1 and pg_temp.wpos('m1', 1) = 2, 'f6 now first');
select pg_temp.check(pg_temp.attending('m1') = 2, 'still capacity');
-- 응답 줄에 처음 응답·마지막으로 바꾼 시각이 따로 남는다 (Q-073 6번 명단 순서 재료)
select pg_temp.check((select responded_at < updated_at from public.attendance_responses
  where match_id = pg_temp.vid('m1') and user_id = pg_temp.u(3)), 'updated_at = last change');
set local role authenticated;

-- 대기 f6 불참 → 뒤 순번 당김, 다시 참석하면 맨 뒤 (SB-05)
select pg_temp.login(pg_temp.u(6));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), false) = 'declined', 'f6 declined');
reset role;
select pg_temp.check(pg_temp.wpos('m1', 1) = 1 and pg_temp.attending('m1') = 2, 'f1 first, no promotion from waitlist decline');
set local role authenticated;
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f6 re-attend waitlisted');
select pg_temp.login(pg_temp.u(3));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'f3 re-attend waitlisted');
reset role;
select pg_temp.check(pg_temp.wpos('m1', 1) = 1 and pg_temp.wpos('m1', 6) = 2 and pg_temp.wpos('m1', 3) = 3, 'order 1,6,3');
select pg_temp.check((select promoted_at is null from public.attendance_responses
  where match_id = pg_temp.vid('m1') and user_id = pg_temp.u(3)), 'manual change clears promoted_at');
set local role authenticated;

-- 정원 없음: 모두 참석 (SB-06)
select pg_temp.login(pg_temp.u(3)); select public.respond_attendance(pg_temp.vid('m2'), true);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m2'), true);
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m2'), true);
reset role;
select pg_temp.check(pg_temp.attending('m2') = 3, 'no capacity: all attend');
set local role authenticated;

-- ================================================================ 2-3 게스트
-- 팀원·다른 팀 거절 (SB-45)
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '게스트')$$, 'not_permitted');
select pg_temp.expect_error($$select public.get_match_guest_details(pg_temp.vid('m1'))$$, 'not_permitted');
select pg_temp.login(pg_temp.u(7));
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '게스트')$$, 'not_permitted');
select pg_temp.expect_error($$select public.add_match_guest('00000000-0000-4000-8000-000000000000', '게스트')$$, 'not_permitted');

-- 운영진 f2: 이름만 / 이름+포지션 3개+실력 (SB-40)
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'g1', public.add_match_guest(pg_temp.vid('m1'), '  김  철수 ')::text;
insert into t_vars select 'g2', public.add_match_guest(pg_temp.vid('m1'), '박'||chr(8203)||'영희',
  array['goalkeeper', 'defender', 'winger']::public.play_position[], 'amateur')::text;
insert into t_vars select 'g3', public.add_match_guest(pg_temp.vid('m1'), '여덟글자이름이야', array[]::public.play_position[], 'undecided')::text;
insert into t_vars select 'g4', public.add_match_guest(pg_temp.vid('m1'), '👨‍👩‍👧가족')::text;
-- 이름 규칙 (SB-42)
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '아홉글자이름입니다')$$, 'invalid_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '   ')$$, 'invalid_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), chr(8203))$$, 'invalid_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), null)$$, 'invalid_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '줄'||chr(10)||'바꿈')$$, 'invalid_guest_name');
-- 포지션 4개·중복 (SB-41)
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '넷', array['goalkeeper', 'defender', 'winger', 'forward']::public.play_position[])$$, 'invalid_positions');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '중복', array['winger', 'winger']::public.play_position[])$$, 'invalid_positions');
-- 취소된 일정 거절, 시작한 경기 거절, 마감 지났어도 시작 전이면 가능 (SB-47~49)
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m3'), '게스트')$$, 'match_cancelled');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m5'), '게스트')$$, 'match_already_started');
insert into t_vars select 'g5', public.add_match_guest(pg_temp.vid('m4'), '마감후')::text;

-- 관리자용 정보: 포지션·실력 (미정 포함)
select pg_temp.check((select count(*) = 4 from public.get_match_guest_details(pg_temp.vid('m1'))), 'details 4 guests');
select pg_temp.check((select name = '김 철수' and positions is null and skill_level = 'undecided' and added_by = pg_temp.u(2)
  from public.get_match_guest_details(pg_temp.vid('m1')) where id = pg_temp.vid('g1')), 'g1 normalized name');
select pg_temp.check((select name = '박영희' and positions = array['goalkeeper', 'defender', 'winger']::public.play_position[]
  and skill_level = 'amateur' from public.get_match_guest_details(pg_temp.vid('m1')) where id = pg_temp.vid('g2')), 'g2 details');
select pg_temp.check((select positions is null and skill_level = 'undecided'
  from public.get_match_guest_details(pg_temp.vid('m1')) where id = pg_temp.vid('g3')), 'g3 empty positions → none, undecided → no row');
select pg_temp.check((select count(*) = 1 from public.skill_ratings where guest_id is not null and team_id = pg_temp.vid('P')), 'only g2 has skill row');

-- 팀원: 이름은 보이고 포지션·실력은 못 본다 (SB-44)
select pg_temp.login(pg_temp.u(6));
select pg_temp.check((select count(*) = 4 from public.match_guests where match_id = pg_temp.vid('m1')), 'member sees guest names');
select pg_temp.expect_error($$select positions from public.match_guests$$, 'permission denied%');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where guest_id is not null), 'member sees no guest skill');
select pg_temp.expect_error($$select public.remove_match_guest(pg_temp.vid('g1'))$$, 'not_permitted');
select pg_temp.expect_error($$delete from public.match_guests where id = pg_temp.vid('g1')$$, 'permission denied%');

-- 게스트는 정원에 안 들어간다: m1 참석 2명(정원) + 게스트 4명, f9 참석 → 대기 (SB-07)
select pg_temp.login(pg_temp.u(9));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'waitlisted', 'guests do not use capacity');

-- 게스트 삭제: 실력 줄도 같이 (SB-50)
select pg_temp.login(pg_temp.u(2));
select public.remove_match_guest(pg_temp.vid('g2'));
reset role;
select pg_temp.check((select count(*) = 0 from public.skill_ratings where guest_id = pg_temp.vid('g2')), 'guest skill deleted with guest');
select pg_temp.check((select count(*) = 3 from public.match_guests where match_id = pg_temp.vid('m1')), '3 guests left');
-- 시작한 경기·취소된 일정의 게스트 삭제 거절
insert into public.match_guests (match_id, team_id, name, added_by) values (pg_temp.vid('m5'), pg_temp.vid('P'), '지난', pg_temp.u(2));
insert into t_vars select 'g6', id::text from public.match_guests where match_id = pg_temp.vid('m5');
set local role authenticated;
select pg_temp.expect_error($$select public.remove_match_guest(pg_temp.vid('g6'))$$, 'match_already_started');

-- 운영진 해제되면 바로 못 읽음 (SB-52)
select pg_temp.login(pg_temp.u(1));
select public.dismiss_manager(pg_temp.vid('P'), pg_temp.u(2));
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select public.get_match_guest_details(pg_temp.vid('m1'))$$, 'not_permitted');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('m1'), '게스트')$$, 'not_permitted');
select pg_temp.login(pg_temp.u(1));
select pg_temp.check((select count(*) = 3 from public.get_match_guest_details(pg_temp.vid('m1'))), 'owner reads details');

-- ================================================================ 2-2 떠나는 사람의 응답 정리
-- 지금 m1: 참석 f4·f5, 대기 f1·f6·f3·f9 / m2: 참석 f3·f4·f5 / q1: f3 참석 예정
select pg_temp.login(pg_temp.u(3));
select public.respond_attendance(pg_temp.vid('q1'), true);
reset role;
-- m4 (마감 지남·시작 전, 정원 1): f4 참석, f6 대기, f9 불참
insert into public.attendance_responses (match_id, user_id, state, waitlisted_at, responded_at, updated_at) values
  (pg_temp.vid('m4'), pg_temp.u(4), 'attending', null, now() - interval '1 day', now() - interval '1 day'),
  (pg_temp.vid('m4'), pg_temp.u(6), 'waitlisted', now() - interval '20 hours', now() - interval '20 hours', now() - interval '20 hours'),
  (pg_temp.vid('m4'), pg_temp.u(9), 'declined', null, now() - interval '20 hours', now() - interval '20 hours');
-- m5 (이미 시작, 정원 1): f5 참석, f9 대기
insert into public.attendance_responses (match_id, user_id, state, waitlisted_at, responded_at, updated_at) values
  (pg_temp.vid('m5'), pg_temp.u(5), 'attending', null, now() - interval '1 day', now() - interval '1 day'),
  (pg_temp.vid('m5'), pg_temp.u(9), 'waitlisted', now() - interval '20 hours', now() - interval '20 hours', now() - interval '20 hours');
set local role authenticated;

-- (a) 대기 중인 f3 팀 P 탈퇴: m1·m2 응답 삭제. m1 은 대기라 승격 없음, m2 는 정원 없음. 팀 Q 응답은 그대로 (SB-20, SB-23)
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.st('m1', 3) = 'none' and pg_temp.st('m2', 3) = 'none', 'f3 P responses deleted');
select pg_temp.check(pg_temp.st('q1', 3) = 'attending', 'f3 Q response kept');
select pg_temp.check(pg_temp.attending('m1') = 2 and pg_temp.wpos('m1', 1) = 1 and pg_temp.wpos('m1', 9) = 3, 'm1 unchanged except f3');
set local role authenticated;

-- (b) 참석 중인 f4 내보내기: m1 대기 1번 f1 자동 참석, m4 는 마감 뒤·시작 전이라도 f6 자동 참석 (SB-17, SB-18)
select pg_temp.login(pg_temp.u(1));
select public.remove_member(pg_temp.vid('P'), pg_temp.u(4));
reset role;
select pg_temp.check(pg_temp.st('m1', 4) = 'none' and pg_temp.st('m4', 4) = 'none' and pg_temp.st('m2', 4) = 'none', 'f4 responses deleted');
select pg_temp.check(pg_temp.st('m1', 1) = 'attending' and pg_temp.attending('m1') = 2, 'm1 f1 promoted');
select pg_temp.check(pg_temp.wpos('m1', 6) = 1 and pg_temp.wpos('m1', 9) = 2, 'm1 waitlist moved up');
select pg_temp.check(pg_temp.st('m4', 6) = 'attending', 'm4 promoted after deadline before start');
select pg_temp.check(pg_temp.st('m4', 9) = 'declined', 'm4 declined untouched');

-- (c) 참석 중인 f5 회원 탈퇴: m1 대기 1번 f6 자동 참석. 이미 시작한 m5 는 승격 없음 (SB-17, SB-22)
select public.delete_account(pg_temp.u(5));
select pg_temp.check(pg_temp.st('m1', 6) = 'attending' and pg_temp.attending('m1') = 2 and pg_temp.wpos('m1', 9) = 1, 'm1 f6 promoted on account deletion');
select pg_temp.check(pg_temp.st('m5', 9) = 'waitlisted', 'started match: no promotion');
select pg_temp.check(pg_temp.st('m5', 5) = 'none', 'account deletion removes rest by cascade');
-- 대기 없을 때 참석자 탈퇴: 참석 인원만 줄어든다 (SB-19), 불참 탈퇴는 삭제만 (SB-21)
set local role authenticated;
select pg_temp.login(pg_temp.u(6));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.st('m4', 6) = 'none' and pg_temp.attending('m4') = 0, 'm4 attending minus one, no waitlist');
select pg_temp.check(pg_temp.st('m1', 9) = 'attending', 'm1 f9 promoted when f6 left');
-- 이미 시작한 경기의 응답은 떠나도 남는다 (SB-22)
update public.attendance_responses set state = 'attending', waitlisted_at = null where match_id = pg_temp.vid('m5') and user_id = pg_temp.u(9);
set local role authenticated;
select pg_temp.login(pg_temp.u(9));
select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.st('m5', 9) = 'attending', 'started match response kept on leave');
select pg_temp.check(pg_temp.st('m4', 9) = 'none', 'declined response deleted on leave');
select pg_temp.check(pg_temp.st('m1', 9) = 'none', 'f9 m1 response deleted');
set local role authenticated;
-- 떠난 사람은 응답 불가 (SB-24)
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'not_permitted');

-- 해체된 팀 거절 (SB-25): 팀 Q 해체 → q1 취소, 팀원 확인에서 거절
select pg_temp.login(pg_temp.u(7));
select public.dissolve_team(pg_temp.vid('Q'), '큐FC');
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('q1'), false)$$, 'not_permitted');

-- ================================================================ 2-4 참여율
-- 팀 S: f8 팀장, f2·f4·f6·f9 팀원 (가입 시각·탈퇴 이력은 아래에서 직접 맞춘다)
select pg_temp.login(pg_temp.u(8));
insert into t_vars select 'S', public.create_team('에스FC')::text;
insert into t_vars select 'codeS', team_code from public.teams where id = pg_temp.vid('S');
select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'rs2', public.request_join(pg_temp.v('codeS'), 'code')::text;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'rs4', public.request_join(pg_temp.v('codeS'), 'code')::text;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'rs6', public.request_join(pg_temp.v('codeS'), 'code')::text;
select pg_temp.login(pg_temp.u(9)); insert into t_vars select 'rs9', public.request_join(pg_temp.v('codeS'), 'code')::text;
select pg_temp.login(pg_temp.u(8));
select public.decide_join_request(pg_temp.vid(k), true) from unnest(array['rs2', 'rs4', 'rs6', 'rs9']) k;
select public.appoint_manager(pg_temp.vid('S'), pg_temp.u(2));

reset role;
-- s1: 2시간 전 시작, 마감 4시간 전
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('S'), 'manual', now() - interval '2 hours', now() - interval '10 minutes', now() - interval '4 hours', pg_temp.u(8))
  returning id)
insert into t_vars select 's1', id::text from x;
-- 가입 시각: f8·f2·f4·f6 은 올해 1월, f9 는 s1 마감 30분 뒤 (마감 뒤 가입 → 대상 아님)
update public.team_members set joined_at = '2026-01-01 00:00+09' where team_id = pg_temp.vid('S') and user_id <> pg_temp.u(9);
update public.team_members set joined_at = now() - interval '3 hours 30 minutes' where team_id = pg_temp.vid('S') and user_id = pg_temp.u(9);
-- f3: 마감 뒤·시작 전 탈퇴 (대상 아님) / f7: 시작 뒤 탈퇴 (대상, 응답 있음) /
-- f1: 마감 전 탈퇴 후 마감 전 재가입 (대상, 응답 없음)
insert into public.team_members (team_id, user_id, role, status, joined_at, ended_at) values
  (pg_temp.vid('S'), pg_temp.u(3), 'member', 'left', '2026-01-01 00:00+09', now() - interval '3 hours'),
  (pg_temp.vid('S'), pg_temp.u(7), 'member', 'left', '2026-01-01 00:00+09', now() - interval '1 hour'),
  (pg_temp.vid('S'), pg_temp.u(1), 'member', 'left', '2026-01-01 00:00+09', now() - interval '5 hours'),
  (pg_temp.vid('S'), pg_temp.u(1), 'member', 'active', now() - interval '4 hours 30 minutes', null);
-- 응답: f8 참석, f2 불참, f4 대기, f7 참석 (모두 마감 전), f6·f1 없음
insert into public.attendance_responses (match_id, user_id, state, waitlisted_at, responded_at, updated_at) values
  (pg_temp.vid('s1'), pg_temp.u(8), 'attending', null, now() - interval '1 day', now() - interval '1 day'),
  (pg_temp.vid('s1'), pg_temp.u(2), 'declined', null, now() - interval '1 day', now() - interval '1 day'),
  (pg_temp.vid('s1'), pg_temp.u(4), 'waitlisted', now() - interval '1 day', now() - interval '1 day', now() - interval '1 day'),
  (pg_temp.vid('s1'), pg_temp.u(7), 'attending', null, now() - interval '1 day', now() - interval '1 day');
-- s2: 3/31 23:00 시작 (3월), s3: 4/1 00:30 시작·마감 3/31 22:30 (4월) (SB-61)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('S'), 'manual', '2026-03-31 23:00+09', '2026-04-01 00:30+09', '2026-03-31 21:00+09', pg_temp.u(8))
  returning id)
insert into t_vars select 's2', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('S'), 'manual', '2026-04-01 00:30+09', '2026-04-01 02:00+09', '2026-03-31 22:30+09', pg_temp.u(8))
  returning id)
insert into t_vars select 's3', id::text from x;
insert into public.attendance_responses (match_id, user_id, state, responded_at, updated_at) values
  (pg_temp.vid('s3'), pg_temp.u(2), 'attending', '2026-03-31 22:00+09', '2026-03-31 22:00+09');
-- s4: 마감 뒤·시작 전에 취소된 지난 일정 (세지 않음, R-32)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, status, cancelled_at, cancelled_by, created_by)
  values (pg_temp.vid('S'), 'manual', now() - interval '1 hour', now(), now() - interval '3 hours', 'cancelled', now() - interval '2 hours', pg_temp.u(8), pg_temp.u(8))
  returning id)
insert into t_vars select 's4', id::text from x;
-- s5: 1시간 뒤 시작 (SB-63)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, created_by)
  values (pg_temp.vid('S'), 'manual', date_trunc('minute', now()) + interval '1 hour', date_trunc('minute', now()) + interval '2 hours', date_trunc('minute', now()) + interval '30 minutes', pg_temp.u(8))
  returning id)
insert into t_vars select 's5', id::text from x;

-- 처리 전에는 숫자가 없다 (SB-60)
select pg_temp.check((select count(*) = 0 from public.monthly_vote_participation where team_id = pg_temp.vid('S')), 'nothing before close-out');

select private.close_out_attendance_votes();
select pg_temp.check((select attendance_closed_out_at is not null from public.matches where id = pg_temp.vid('s1')), 's1 closed out');
select pg_temp.check((select attendance_closed_out_at is null from public.matches where id = pg_temp.vid('s4')), 'cancelled not closed out');
select pg_temp.check((select attendance_closed_out_at is null from public.matches where id = pg_temp.vid('s5')), 'future not closed out');
-- R-27·R-31·R-34·SB-62·SB-64·SB-65
select pg_temp.check(pg_temp.vp('S', 8, pg_temp.v('this_month')::date) = '1/1', 'owner attending 1/1');
select pg_temp.check(pg_temp.vp('S', 2, pg_temp.v('this_month')::date) = '1/1', 'manager declined 1/1');
select pg_temp.check(pg_temp.vp('S', 4, pg_temp.v('this_month')::date) = '1/1', 'waitlisted 1/1');
select pg_temp.check(pg_temp.vp('S', 6, pg_temp.v('this_month')::date) = '1/0', 'no response 1/0');
select pg_temp.check(pg_temp.vp('S', 9, pg_temp.v('this_month')::date) = 'none', 'joined after deadline: not eligible');
select pg_temp.check(pg_temp.vp('S', 3, pg_temp.v('this_month')::date) = 'none', 'left after deadline before start: not eligible');
select pg_temp.check(pg_temp.vp('S', 7, pg_temp.v('this_month')::date) = '1/1', 'left after start: eligible');
select pg_temp.check(pg_temp.vp('S', 1, pg_temp.v('this_month')::date) = '1/0', 'rejoined before deadline: eligible');
-- 월은 시작일 기준 (SB-61): s2 3월, s3 4월. 3월 경기 때 팀원 = 1월 가입자 + f3·f7·f1(첫 소속)
select pg_temp.check(pg_temp.vp('S', 8, '2026-03-01') = '1/0' and pg_temp.vp('S', 8, '2026-04-01') = '1/0', 'month by start date (f8)');
select pg_temp.check(pg_temp.vp('S', 2, '2026-03-01') = '1/0' and pg_temp.vp('S', 2, '2026-04-01') = '1/1', 'month by start date (f2)');
select pg_temp.check(pg_temp.vp('S', 3, '2026-03-01') = '1/0' and pg_temp.vp('S', 9, '2026-03-01') = 'none', 'march eligibility');
-- 다시 실행해도 그대로 (R-36)
select private.close_out_attendance_votes();
select private.close_out_attendance_votes(now() + interval '1 minute');
select pg_temp.check(pg_temp.vp('S', 8, pg_temp.v('this_month')::date) = '1/1' and pg_temp.vp('S', 8, '2026-03-01') = '1/0', 'no double count');
-- 시작 1분 전 기준이면 s5 를 세지 않고, 시작 시각 기준이면 센다 (SB-63)
select private.close_out_attendance_votes((select starts_at - interval '1 minute' from public.matches where id = pg_temp.vid('s5')));
select pg_temp.check((select attendance_closed_out_at is null from public.matches where id = pg_temp.vid('s5')), 's5 not before start');
select private.close_out_attendance_votes((select starts_at from public.matches where id = pg_temp.vid('s5')));
select pg_temp.check((select attendance_closed_out_at is not null from public.matches where id = pg_temp.vid('s5')), 's5 at start');
-- 응답 ≤ 대상, 퍼센트 칸 없음 (R-37)
select pg_temp.check((select bool_and(attendance_vote_responded <= attendance_vote_eligible) from public.monthly_vote_participation), 'responded <= eligible');
select pg_temp.check((select count(*) = 5 from information_schema.columns
  where table_schema = 'public' and table_name = 'monthly_vote_participation'), 'only 5 columns');
-- 팀을 떠나도 남는다 (R-38)
insert into t_vars select 'vp6', pg_temp.vp('S', 6, pg_temp.v('this_month')::date);
update public.team_members set status = 'left', ended_at = now() where team_id = pg_temp.vid('S') and user_id = pg_temp.u(6) and status = 'active';
select pg_temp.check(pg_temp.vp('S', 6, pg_temp.v('this_month')::date) = pg_temp.v('vp6') and pg_temp.v('vp6') <> 'none', 'kept after leaving');
-- 부상 판단은 한 곳, 지금은 항상 아니오
select pg_temp.check(private.is_injured_at(pg_temp.u(6), now()) = false, 'injury stub false');

-- 앱은 읽기·쓰기·처리 함수 실행 불가 (R-39, SB-68)
set local role authenticated;
select pg_temp.login(pg_temp.u(8));
select pg_temp.expect_error($$select count(*) from public.monthly_vote_participation$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.monthly_vote_participation (team_id, user_id, month) values (pg_temp.vid('S'), pg_temp.u(8), '2026-11-01')$$, 'permission denied%');
select pg_temp.expect_error($$update public.monthly_vote_participation set attendance_vote_responded = 0$$, 'permission denied%');
select pg_temp.expect_error($$select private.close_out_attendance_votes()$$, 'permission denied%');
select pg_temp.expect_error($$select private.promote_waitlisted(pg_temp.vid('m1'))$$, 'permission denied%');
select pg_temp.expect_error($$select private.remove_upcoming_responses(pg_temp.u(8), null)$$, 'permission denied%');
reset role;
set local role anon;
select pg_temp.expect_error($$select count(*) from public.monthly_vote_participation$$, 'permission denied%');
select pg_temp.expect_error($$select public.respond_attendance('00000000-0000-4000-8000-000000000000', true)$$, 'permission denied%');
select pg_temp.expect_error($$select public.add_match_guest('00000000-0000-4000-8000-000000000000', '게스트')$$, 'permission denied%');
select pg_temp.expect_error($$select public.get_match_guest_details('00000000-0000-4000-8000-000000000000')$$, 'permission denied%');
reset role;
set local role service_role;
select pg_temp.expect_error($$select private.close_out_attendance_votes()$$, 'permission denied%');
reset role;

-- ================================================================ 공통
select pg_temp.check(
  (select command from cron.job where jobname = 'close-out-attendance-votes') = 'select private.close_out_attendance_votes()'
  and (select schedule from cron.job where jobname = 'close-out-attendance-votes') = '* * * * *',
  'close-out cron every minute');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.monthly_vote_participation'::regclass), 'RLS on');
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and proname in (
    'promote_waitlisted', 'respond_attendance', 'remove_upcoming_responses', 'cleanup_departed_member', 'delete_account',
    'lock_match_for_guests', 'add_match_guest', 'remove_match_guest', 'get_match_guest_details',
    'is_injured_at', 'close_out_attendance_vote', 'close_out_attendance_votes')), 'definer search_path fixed');
select pg_temp.check((select count(*) = 12 from pg_proc where prosecdef and proname in (
    'promote_waitlisted', 'respond_attendance', 'remove_upcoming_responses', 'cleanup_departed_member', 'delete_account',
    'lock_match_for_guests', 'add_match_guest', 'remove_match_guest', 'get_match_guest_details',
    'is_injured_at', 'close_out_attendance_vote', 'close_out_attendance_votes')), 'all definer functions present');

select 'ALL PASSED' as result;
