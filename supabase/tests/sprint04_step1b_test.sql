-- 스프린트 04 1단계 나머지 마이그레이션(202611050061~202611050064) 동작 확인 스크립트.
--   1-3 부상 등록·연장·회복·메모 수정, 1-5 참석 투표 시 복귀, 1-6 복귀 확인 알림, 1-8 선호 포지션 선택지(올라운더).
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.

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
  select ('00000000-0000-4000-8000-0000000042' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- 오늘(한국 날짜) + p_days
create function pg_temp.kday(p_days int)
returns date
language sql
as $$
  select (now() at time zone 'Asia/Seoul')::date + p_days
$$;

-- 한국 날짜 + 시각 → timestamptz
create function pg_temp.kat(p_days int, p_time time)
returns timestamptz
language sql
as $$
  select (pg_temp.kday(p_days) + p_time) at time zone 'Asia/Seoul'
$$;

-- 서버 권한으로 본 p_n 의 진행 중 부상 (없으면 null 줄)
create function pg_temp.active(p_n int)
returns public.injuries
language sql
as $$
  select i.* from public.injuries i where i.user_id = pg_temp.u(p_n) and i.status = 'active'
$$;

create function pg_temp.events(p_n int, p_kind text, p_via text)
returns int
language sql
as $$
  select count(*)::int from public.injury_events e join public.injuries i on i.id = e.injury_id
   where i.user_id = pg_temp.u(p_n) and e.kind::text = p_kind and e.via::text = p_via
$$;

-- 부상 줄 직접 만들기 (서버 권한, 과거 날짜 준비용)
create function pg_temp.injury(p_n int, p_started date, p_return date)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into public.injuries (user_id, started_on, expected_return_on)
  values (pg_temp.u(p_n), p_started, p_return)
  returning id into v_id;
  insert into public.injury_events (injury_id, kind, via) values (v_id, 'reported', 'self');
  return v_id;
end;
$$;

-- 일정 직접 넣기 (서버 권한 = 자동 생성과 같은 표 경로). 시작은 p_days 일 뒤 p_time(한국 시간)
create function pg_temp.match(p_key text, p_team text, p_days int, p_time time, p_capacity int default null,
                              p_deadline timestamptz default null)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
  v_starts timestamptz := pg_temp.kat(p_days, p_time);
begin
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, capacity)
  values (pg_temp.vid(p_team), 'auto', v_starts, v_starts + interval '2 hours',
          coalesce(p_deadline, v_starts - interval '1 hour'), p_capacity)
  returning id into v_id;
  insert into t_vars values (p_key, v_id::text);
  return v_id;
end;
$$;

create function pg_temp.state(p_match text, p_n int)
returns text
language sql
as $$
  select state::text from public.attendance_responses where match_id = pg_temp.vid(p_match) and user_id = pg_temp.u(p_n)
$$;

create function pg_temp.return_checks(p_n int, p_match text)
returns int
language sql
as $$
  select count(*)::int from public.notifications
   where user_id = pg_temp.u(p_n) and kind = 'injury_return_check' and ref_id = pg_temp.vid(p_match)
$$;

-- ---------------------------------------------------------------------------
-- 준비
--   팀 P: u1 팀장, u2·u3·u5·u6 팀원
--   팀 Q: u4 팀장, u2·u7 팀원  (u2 는 두 팀 소속)
--   u8: 팀 없음, u9: 로그인 계정만 있고 프로필 없음
--   부상 동의(가입 때): u2·u5·u6·u7. 동의 안 함: u1·u3·u4·u8
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'i42' || n || '@test.invalid', now(), now()
  from generate_series(1, 9) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5));
select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(6));
select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(7));
select public.create_profile('칠', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(8));
select public.create_profile('팔', null, array['forward']::public.play_position[], false, true, true, true, false);

select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('복귀FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(4));
insert into t_vars select 'Q', public.create_team('재활FC')::text;
insert into t_vars select 'codeQ', team_code from public.teams where id = pg_temp.vid('Q');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(3)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(5)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(6)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeQ'), 'code');
select pg_temp.login(pg_temp.u(7)); select public.request_join(pg_temp.v('codeQ'), 'code');
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(4));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('Q');
reset role;

-- ================================================================ 1-3 부상 등록
set local role authenticated;
-- 동의 없음 → 거절, 프로필 없음 → 거절
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.report_injury(2, null)$$, 'injury_consent_required');
select pg_temp.login(pg_temp.u(9));
select pg_temp.expect_error($$select public.report_injury(2, null)$$, 'profile_required');
-- 기간 1~12주만
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select public.report_injury(0, null)$$, 'injury_invalid_weeks');
select pg_temp.expect_error($$select public.report_injury(13, null)$$, 'injury_invalid_weeks');
select pg_temp.expect_error($$select public.report_injury(null, null)$$, 'injury_invalid_weeks');
-- 메모 규칙: 줄바꿈·제어 문자·160 코드 포인트 초과 거절
select pg_temp.expect_error($$select public.report_injury(2, E'발목\n인대')$$, 'invalid_injury_memo');
select pg_temp.expect_error($$select public.report_injury(2, repeat('가', 161))$$, 'invalid_injury_memo');
-- 정상 등록: 예상 복귀일 = 오늘 + 주 × 7, 메모 앞뒤 공백 정리, 이력 reported/self
insert into t_vars select 'i2', public.report_injury(4, '  발목  ')::text;
reset role;
select pg_temp.check((select started_on = pg_temp.kday(0) and expected_return_on = pg_temp.kday(28) and memo = '발목'
                        and status = 'active' and recovered_at is null
                        from public.injuries where id = pg_temp.vid('i2')), 'report: dates, memo');
select pg_temp.check(pg_temp.events(2, 'reported', 'self') = 1, 'report: event reported/self');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
-- 진행 중 부상이 있으면 거절
select pg_temp.expect_error($$select public.report_injury(1, null)$$, 'injury_already_active');
-- 12주 경계, 빈 메모는 없음
select pg_temp.login(pg_temp.u(5));
insert into t_vars select 'i5', public.report_injury(12, '   ')::text;
reset role;
select pg_temp.check((select expected_return_on = pg_temp.kday(84) and memo is null from public.injuries where id = pg_temp.vid('i5')),
  'report: 12 weeks, blank memo is null');

-- ================================================================ 1-3 메모 수정 (이력 없음)
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select public.update_injury_memo('발목 인대');
select pg_temp.expect_error($$select public.update_injury_memo(E'a\tb')$$, 'invalid_injury_memo');
select public.update_injury_memo('  ');
reset role;
select pg_temp.check((select memo is null from public.injuries where id = pg_temp.vid('i2')), 'memo cleared');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select public.update_injury_memo('발목 인대');
reset role;
select pg_temp.check((select memo = '발목 인대' from public.injuries where id = pg_temp.vid('i2')), 'memo updated');
select pg_temp.check((select count(*) = 1 from public.injury_events where injury_id = pg_temp.vid('i2')), 'memo edit leaves no event');
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.update_injury_memo('손목')$$, 'injury_not_active');

-- ================================================================ 1-3 연장 (S4-07 늦은 쪽 + 주 수)
-- 예상 복귀일 전: 예상 복귀일부터
select pg_temp.login(pg_temp.u(2));
select pg_temp.check(public.extend_injury(1) = pg_temp.kday(35), 'extend before expected: from expected');
select pg_temp.expect_error($$select public.extend_injury(3)$$, 'injury_invalid_weeks');
select pg_temp.expect_error($$select public.extend_injury(0)$$, 'injury_invalid_weeks');
select pg_temp.expect_error($$select public.extend_injury(1, 'return_vote')$$, 'injury_invalid_via');
reset role;
select pg_temp.check((select expected_return_on = pg_temp.kday(35) from public.injuries where id = pg_temp.vid('i2')), 'extend saved');
select pg_temp.check((select count(*) = 1 from public.injury_events
                        where injury_id = pg_temp.vid('i2') and kind = 'extended' and weeks_added = 1 and via = 'self'),
  'extend event weeks 1 self');
-- 예상 복귀일이 지남: 오늘부터. 복귀 확인 알림에서 연장하면 via return_check
insert into t_vars select 'i6', pg_temp.injury(6, pg_temp.kday(-20), pg_temp.kday(-3))::text;
set local role authenticated;
select pg_temp.login(pg_temp.u(6));
select pg_temp.check(public.extend_injury(2) = pg_temp.kday(14), 'extend after expected: from today');
select pg_temp.check(public.extend_injury(1, 'return_check') = pg_temp.kday(21), 'extend from return check');
reset role;
select pg_temp.check((select count(*) = 1 from public.injury_events
                        where injury_id = pg_temp.vid('i6') and kind = 'extended' and weeks_added = 2 and via = 'self'),
  'extend event weeks 2 self');
select pg_temp.check((select count(*) = 1 from public.injury_events
                        where injury_id = pg_temp.vid('i6') and kind = 'extended' and weeks_added = 1 and via = 'return_check'),
  'extend event via return_check');
-- 예상 복귀일 당일: 오늘부터 (= 예상일부터)
insert into t_vars select 'i7', pg_temp.injury(7, pg_temp.kday(-7), pg_temp.kday(0))::text;
set local role authenticated;
select pg_temp.login(pg_temp.u(7));
select pg_temp.check(public.extend_injury(1) = pg_temp.kday(7), 'extend on expected day');
-- 진행 중 부상 없으면 거절
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.extend_injury(1)$$, 'injury_not_active');

-- ================================================================ 1-3 회복
select pg_temp.login(pg_temp.u(7));
select public.recover_injury();
select pg_temp.expect_error($$select public.recover_injury()$$, 'injury_not_active');
select pg_temp.expect_error($$select public.extend_injury(1)$$, 'injury_not_active');
select pg_temp.expect_error($$select public.update_injury_memo('x')$$, 'injury_not_active');
reset role;
select pg_temp.check((select status = 'recovered' and recovered_at is not null from public.injuries where id = pg_temp.vid('i7')),
  'recover: status, recovered_at');
select pg_temp.check(pg_temp.events(7, 'recovered', 'self') = 1, 'recover: event recovered/self');
-- 회복 뒤 다시 등록 가능 (지난 기록은 남음)
set local role authenticated;
select pg_temp.login(pg_temp.u(7));
select public.report_injury(1, null);
reset role;
select pg_temp.check((select count(*) = 2 from public.injuries where user_id = pg_temp.u(7)), 'report again after recovery');
-- 동의 철회 뒤 등록 거절
set local role authenticated;
select pg_temp.login(pg_temp.u(7));
select public.withdraw_consent('injury_info');
select pg_temp.expect_error($$select public.report_injury(1, null)$$, 'injury_consent_required');
select public.agree_injury_consent();
reset role;
-- 등록 함수는 동의 줄을 FOR SHARE 로 잠근다 (철회와 동시 처리 방지)
select pg_temp.check((select pg_get_functiondef('public.report_injury(int, text)'::regprocedure) ilike '%for share%'),
  'report locks consent row for share');

-- ================================================================ 1-5 참석 투표 시 복귀
-- m1: 팀 P, 3일 뒤, 정원 3
select pg_temp.match('m1', 'P', 3, '10:00', 3);
set local role authenticated;
-- u5(부상 중) 참석 → 복귀 확인 필요, 응답 안 생김
select pg_temp.login(pg_temp.u(5));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'return_confirmation_required');
select pg_temp.check(pg_temp.state('m1', 5) is null, 'no response after confirmation required');
-- via self 는 받지 않음
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true, 'self')$$, 'invalid_attendance');
-- 불참: 확인 없이, 부상 유지 (via 를 줘도 무시)
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), false, 'return_vote') = 'declined', 'injured decline');
reset role;
select pg_temp.check((pg_temp.active(5)).id = pg_temp.vid('i5'), 'decline keeps injury');
select pg_temp.check(pg_temp.events(5, 'recovered', 'return_vote') = 0, 'decline: no recovery event');
set local role authenticated;
select pg_temp.login(pg_temp.u(5));
-- 다시 참석(확인 없이) → 거절, 불참 그대로
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'return_confirmation_required');
select pg_temp.check(pg_temp.state('m1', 5) = 'declined', 'still declined');
-- 확인 후 참석 → 참석 + 부상 회복(이력 return_vote) 한 처리
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true, 'return_vote') = 'attending', 'confirmed attend');
reset role;
select pg_temp.check((select status = 'recovered' and recovered_at is not null from public.injuries where id = pg_temp.vid('i5')),
  'confirmed attend recovers');
select pg_temp.check(pg_temp.events(5, 'recovered', 'return_vote') = 1, 'recovery event return_vote');
-- 부상 없는 사람은 그대로 참석 (via 를 줘도 보통 참석)
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true) = 'attending', 'healthy attend');
select pg_temp.login(pg_temp.u(3));
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true, 'return_vote') = 'attending', 'healthy attend with via');
-- 정원이 찼을 때 부상자 확인 참석 → 대기 + 부상 해제 (S4-09), 알림 창 경로 via return_check
select pg_temp.login(pg_temp.u(6));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'return_confirmation_required');
select pg_temp.check(public.respond_attendance(pg_temp.vid('m1'), true, 'return_check') = 'waitlisted', 'full: waitlisted');
reset role;
select pg_temp.check((select status = 'recovered' from public.injuries where id = pg_temp.vid('i6')), 'waitlisted still recovers');
select pg_temp.check(pg_temp.events(6, 'recovered', 'return_check') = 1, 'recovery event return_check');

-- 이미 참석으로 응답해 둔 뒤 부상 등록(S4-08): 응답은 자동으로 안 바뀜.
-- 다시 참석을 누르면 확인 필요, 확인하면 응답 그대로 + 부상 해제. 불참으로 바꾸기는 확인 없이 가능
select pg_temp.match('m2', 'P', 4, '10:00');
set local role authenticated;
select pg_temp.login(pg_temp.u(6));
select public.respond_attendance(pg_temp.vid('m2'), true);
select public.report_injury(2, null);
select pg_temp.check(pg_temp.state('m2', 6) = 'attending', 'report keeps existing attending');
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m2'), true)$$, 'return_confirmation_required');
select pg_temp.check(pg_temp.state('m2', 6) = 'attending', 'still attending after refusal');
select pg_temp.check(public.respond_attendance(pg_temp.vid('m2'), true, 'return_vote') = 'attending', 'confirm keeps attending');
reset role;
select pg_temp.check((pg_temp.active(6)).id is null, 'confirm on attending recovers');
set local role authenticated;
select pg_temp.login(pg_temp.u(6));
select public.report_injury(2, null);
select pg_temp.check(public.respond_attendance(pg_temp.vid('m2'), false) = 'declined', 'injured can switch to decline');
reset role;
select pg_temp.check((pg_temp.active(6)).id is not null, 'decline keeps new injury');

-- 마감 뒤에는 복귀 확인보다 마감 거절이 먼저, 팀원 아님은 not_permitted
select pg_temp.match('m3', 'P', 2, '10:00', null, now() - interval '1 minute');
set local role authenticated;
select pg_temp.login(pg_temp.u(6));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m3'), true)$$, 'rsvp_closed');
select pg_temp.login(pg_temp.u(8));
select pg_temp.expect_error($$select public.respond_attendance(pg_temp.vid('m1'), true)$$, 'not_permitted');
-- 기존 인자 두 개 호출도 그대로 동작 (앱 이전 버전 호환)
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(public.respond_attendance(p_match_id => pg_temp.vid('m2'), p_attending => true) = 'attending', 'two-arg call');
reset role;

-- ================================================================ 1-6 복귀 확인 알림
-- 준비: 부상 정리 후 다시 만든다 (서버 권한)
delete from public.injuries;
-- u2: 진행 중, 예상 복귀 7일 뒤 (팀 P·Q)
insert into t_vars select 'r2', pg_temp.injury(2, pg_temp.kday(-7), pg_temp.kday(7))::text;
-- u5: 진행 중, 예상 복귀 30일 뒤
insert into t_vars select 'r5', pg_temp.injury(5, pg_temp.kday(-1), pg_temp.kday(30))::text;
-- u6: 회복함 (예상 복귀일 지남)
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at)
values (pg_temp.u(6), pg_temp.kday(-30), pg_temp.kday(-10), 'recovered', now() - interval '1 day');
-- u3: 동의가 없는데 줄이 남은 순간 (S-07 이중 장치 대비) — 받지 않음
insert into t_vars select 'r3', pg_temp.injury(3, pg_temp.kday(-30), pg_temp.kday(-10))::text;

-- 경기 날짜 < 예상 복귀일 → 안 감 (S4-10)
select pg_temp.match('n6', 'P', 6, '10:00');
select pg_temp.check(pg_temp.return_checks(2, 'n6') = 0, 'before expected date: none');
select pg_temp.check((select return_check_sent_for is null from public.injuries where id = pg_temp.vid('r2')), 'sent_for empty');
-- 경기 날짜 = 예상 복귀일 → 감 (새벽에 열려도 경기 날짜 기준)
select pg_temp.match('n7', 'P', 7, '00:30');
select pg_temp.check(pg_temp.return_checks(2, 'n7') = 1, 'on expected date: sent');
select pg_temp.check(pg_temp.return_checks(5, 'n7') = 0, 'u5 before expected: none');
select pg_temp.check(pg_temp.return_checks(6, 'n7') = 0, 'recovered: none');
select pg_temp.check(pg_temp.return_checks(3, 'n7') = 0, 'no consent: none');
select pg_temp.check((select count(*) = 1 from public.notifications where kind = 'injury_return_check' and ref_id = pg_temp.vid('n7')),
  'only one recipient');
select pg_temp.check((select title = '복귀FC'
                         and body = '부상은 회복되셨나요? 경기가 열렸습니다. 참석하시겠습니까?'
                         and ref_type = 'match' and team_id = pg_temp.vid('P') and actor_id is null
                         and dedupe_key = 'injury_return_check:' || pg_temp.v('n7') || ':'
                         from public.notifications
                        where user_id = pg_temp.u(2) and kind = 'injury_return_check' and ref_id = pg_temp.vid('n7')),
  'return check notification fields');
select pg_temp.check((select count(*) = 1 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
                        where n.user_id = pg_temp.u(2) and n.kind = 'injury_return_check' and n.ref_id = pg_temp.vid('n7')
                          and o.status = 'pending'),
  'return check queued for push');
select pg_temp.check((select return_check_sent_for = pg_temp.vid('n7') from public.injuries where id = pg_temp.vid('r2')),
  'sent_for = match');
-- 일반 일정 생성 알림도 함께 감 (복귀 확인 알림은 별도)
select pg_temp.check((select count(*) = 1 from public.notifications
                        where user_id = pg_temp.u(2) and kind = 'match_created' and ref_id = pg_temp.vid('n7')), 'match_created too');
-- 같은 일정에는 한 번: 일정이 지워졌다 같은 ID 로 다시 들어와도 중복 방지 키로 안 감
delete from public.matches where id = pg_temp.vid('n7');
select pg_temp.check((select return_check_sent_for is null from public.injuries where id = pg_temp.vid('r2')), 'match delete clears sent_for');
insert into public.matches (id, team_id, source, starts_at, ends_at, rsvp_deadline_at)
values (pg_temp.vid('n7'), pg_temp.vid('P'), 'auto', pg_temp.kat(7, '00:30'), pg_temp.kat(7, '02:30'), pg_temp.kat(6, '23:30'));
select pg_temp.check(pg_temp.return_checks(2, 'n7') = 1, 'same match: once');
-- 다음 일정이 열리면 다시 감 (회복하지 않았으므로)
select pg_temp.match('n8', 'P', 8, '10:00');
select pg_temp.check(pg_temp.return_checks(2, 'n8') = 1, 'next match: sent again');
-- 다른 팀(Q) 일정이 열리면 그 팀 이름으로 따로 감 (S4-10)
select pg_temp.match('q8', 'Q', 8, '19:00');
select pg_temp.check(pg_temp.return_checks(2, 'q8') = 1, 'team Q: sent separately');
select pg_temp.check((select title = '재활FC' from public.notifications
                        where user_id = pg_temp.u(2) and kind = 'injury_return_check' and ref_id = pg_temp.vid('q8')), 'team Q title');
select pg_temp.check(pg_temp.return_checks(7, 'q8') = 0, 'healthy Q member: none');
-- 직접 추가(create_match) 경로도 같음. 직접 추가한 사람이 아닌 부상자에게 감
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'c9', public.create_match(pg_temp.vid('P'), pg_temp.kday(9), '19:00', pg_temp.kday(9), '21:00')::text;
reset role;
select pg_temp.check(pg_temp.return_checks(2, 'c9') = 1, 'create_match path: sent');
-- 경기 날짜가 예상 복귀일 이후인 u5 도 먼 일정에는 받음
select pg_temp.match('n31', 'P', 31, '10:00');
select pg_temp.check(pg_temp.return_checks(5, 'n31') = 1 and pg_temp.return_checks(2, 'n31') = 1, 'far match: both injured');
-- 회복하면 더는 안 감
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select public.recover_injury();
reset role;
select pg_temp.match('n32', 'P', 32, '10:00');
select pg_temp.check(pg_temp.return_checks(2, 'n32') = 0 and pg_temp.return_checks(5, 'n32') = 1, 'recovered: stops');
-- 조용한 시간 규칙은 일반 알림과 같음 (03:00 → 13:00, 10:00 → 바로)
select pg_temp.check(private.notification_send_at('injury_return_check', pg_temp.kat(0, '03:00')) = pg_temp.kat(0, '13:00'),
  'quiet hours: 13:00');
select pg_temp.check(private.notification_send_at('injury_return_check', pg_temp.kat(0, '10:00')) = pg_temp.kat(0, '10:00'),
  'daytime: immediate');
-- 앱 사용자는 복귀 확인 알림을 만들 수 없음
select pg_temp.check(not has_function_privilege('authenticated', 'private.matches_notify_return_check()', 'execute')
  and not has_function_privilege('anon', 'private.matches_notify_return_check()', 'execute'), 'trigger fn not executable');

-- ================================================================ 1-8 선호 포지션 (올라운더)
select pg_temp.check((select enum_range(null::public.play_position)::text = '{goalkeeper,defender,allrounder,winger,forward}'),
  'enum values (no midfielder)');
set local role authenticated;
-- 올라운더 단독은 가능, 다른 포지션과 함께는 불가
select pg_temp.login(pg_temp.u(8));
select public.update_own_profile('팔', null, array['allrounder']::public.play_position[], false);
select pg_temp.expect_error($$select public.update_own_profile('팔', null, array['allrounder','forward']::public.play_position[], false)$$,
  'invalid_positions');
-- 올라운더 + 전문 골키퍼 불가 (골키퍼가 필요하고, 골키퍼를 넣으면 단독이 깨짐)
select pg_temp.expect_error($$select public.update_own_profile('팔', null, array['allrounder']::public.play_position[], true)$$,
  'invalid_positions');
select pg_temp.expect_error($$select public.update_own_profile('팔', null, array['allrounder','goalkeeper']::public.play_position[], true)$$,
  'invalid_positions');
-- 표 직접 수정(칸 단위 권한)도 막힘
select pg_temp.expect_error($$update public.profile_play_prefs set positions = array['allrounder','defender']::public.play_position[] where user_id = pg_temp.u(8)$$,
  '%profile_play_prefs_allrounder_alone%');
select pg_temp.check((select positions = array['allrounder']::public.play_position[] from public.profile_play_prefs where user_id = pg_temp.u(8)),
  'allrounder saved');
-- 나머지 규칙 그대로: 1~3개, 골키퍼 포함, 전문 골키퍼면 골키퍼
select public.update_own_profile('팔', null, array['goalkeeper','defender','winger']::public.play_position[], true);
select pg_temp.expect_error($$select public.update_own_profile('팔', null, array['defender','winger','forward']::public.play_position[], true)$$,
  'invalid_positions');
-- 가입도 같은 규칙
select pg_temp.login(pg_temp.u(9));
select pg_temp.expect_error($$select public.create_profile('구', null, array['allrounder','winger']::public.play_position[], false, true, true, true, false)$$,
  'invalid_positions');
select public.create_profile('구', null, array['allrounder']::public.play_position[], false, true, true, true, false);
-- 게스트 포지션도 같은 선택지
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('n8'), null, array['allrounder','forward']::public.play_position[])$$,
  'invalid_positions');
insert into t_vars select 'g1', public.add_match_guest(pg_temp.vid('n8'), null, array['allrounder']::public.play_position[])::text;
insert into t_vars select 'g2', public.add_match_guest(pg_temp.vid('n8'), null, array['goalkeeper','defender','forward']::public.play_position[])::text;
reset role;
select pg_temp.check((select positions = array['allrounder']::public.play_position[] from public.match_guests where id = pg_temp.vid('g1')),
  'guest allrounder saved');
select pg_temp.expect_error($$update public.match_guests set positions = array['allrounder','winger']::public.play_position[] where id = pg_temp.vid('g2')$$,
  '%match_guests_allrounder_alone%');

-- ================================================================ 함수 속성
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and proname in (
    'report_injury', 'extend_injury', 'recover_injury', 'update_injury_memo', 'respond_attendance',
    'matches_notify_return_check', 'add_match_guest')), 'definer search_path fixed');
select pg_temp.check((select count(*) = 7 from pg_proc where prosecdef and proname in (
    'report_injury', 'extend_injury', 'recover_injury', 'update_injury_memo', 'respond_attendance',
    'matches_notify_return_check', 'add_match_guest')), 'definer functions present (one respond_attendance)');
select pg_temp.check(has_function_privilege('authenticated', 'public.report_injury(int, text)', 'execute')
  and has_function_privilege('authenticated', 'public.extend_injury(int, public.injury_event_via)', 'execute')
  and has_function_privilege('authenticated', 'public.recover_injury()', 'execute')
  and has_function_privilege('authenticated', 'public.update_injury_memo(text)', 'execute')
  and has_function_privilege('authenticated', 'public.respond_attendance(uuid, boolean, public.injury_event_via)', 'execute')
  and not has_function_privilege('anon', 'public.report_injury(int, text)', 'execute')
  and not has_function_privilege('anon', 'public.extend_injury(int, public.injury_event_via)', 'execute')
  and not has_function_privilege('anon', 'public.recover_injury()', 'execute')
  and not has_function_privilege('anon', 'public.update_injury_memo(text)', 'execute')
  and not has_function_privilege('anon', 'public.respond_attendance(uuid, boolean, public.injury_event_via)', 'execute'),
  'function privileges');

select 'ALL PASSED' as result;
