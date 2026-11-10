-- 스프린트 02 3단계 마이그레이션(202611050028 알림함·대기열·알림 만들기, 202611050029 알림 연결,
-- 202611050030 미투표 알림·정리 예약 작업) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 한 트랜잭션 안에서는 now() 가 같으므로, 시각이 다른 사건(알림 시각 뒤 가입, 30일 지난 알림)은
-- 서버 권한(postgres)으로 표 값을 직접 바꿔 준비한다. 조용한 시간 계산은 private.notification_send_at 에 시각을 넘겨 확인한다.

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

create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000000d' || p_n::text)::uuid
$$;

-- 사람 n 이 받은 kind 알림 수 (postgres 로 읽는다)
create function pg_temp.cnt(p_kind text, p_n int)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
   where n.user_id = pg_temp.u(p_n) and n.kind::text = p_kind
$$;

-- kind 알림을 받은 사람 번호 목록 (정렬), 팀 한정
create function pg_temp.who(p_kind text, p_team text)
returns text
language sql
as $$
  select coalesce(string_agg(right(n.user_id::text, 1), ',' order by n.user_id::text), '')
    from public.notifications n
   where n.kind::text = p_kind and n.team_id = pg_temp.vid(p_team)
$$;

-- 한국 시간 → timestamptz
create function pg_temp.kst(p text)
returns timestamptz
language sql
as $$
  select (p::timestamp) at time zone 'Asia/Seoul'
$$;

insert into t_vars values
  ('d3', ((now() + interval '3 days') at time zone 'Asia/Seoul')::date::text);

insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'd' || n || '@test.invalid', now(), now()
  from generate_series(1, 9) n;

-- ================================================================ 3-1 보낼 시각 (조용한 시간)
-- SC-10, SC-13, H-02: 23:59 바로 / 00:00·03:00·07:59 → 같은 날 13:00 / 08:00·10:00·12:59 바로
select pg_temp.check(private.notification_send_at('match_created', pg_temp.kst('2026-11-10 23:59')) = pg_temp.kst('2026-11-10 23:59'), '23:59 now');
select pg_temp.check(private.notification_send_at('match_created', pg_temp.kst('2026-11-11 00:00')) = pg_temp.kst('2026-11-11 13:00'), '00:00 -> 13:00');
select pg_temp.check(private.notification_send_at('team_dissolved', pg_temp.kst('2026-11-11 03:00')) = pg_temp.kst('2026-11-11 13:00'), '03:00 -> 13:00');
select pg_temp.check(private.notification_send_at('join_request_received', pg_temp.kst('2026-11-11 07:59:59')) = pg_temp.kst('2026-11-11 13:00'), '07:59:59 -> 13:00');
select pg_temp.check(private.notification_send_at('match_created', pg_temp.kst('2026-11-11 08:00')) = pg_temp.kst('2026-11-11 08:00'), '08:00 now');
select pg_temp.check(private.notification_send_at('match_created', pg_temp.kst('2026-11-11 10:00')) = pg_temp.kst('2026-11-11 10:00'), '10:00 now');
select pg_temp.check(private.notification_send_at('match_created', pg_temp.kst('2026-11-11 12:59')) = pg_temp.kst('2026-11-11 12:59'), '12:59 now');
-- 미투표 알림은 조용한 시간이어도 바로 (Q-072 1번, SC-32, H-03)
select pg_temp.check(private.notification_send_at('rsvp_deadline_soon', pg_temp.kst('2026-11-11 06:00')) = pg_temp.kst('2026-11-11 06:00'), 'reminder in quiet hours now');
-- 결과 발표 알림도 조용한 시간이어도 바로 (Q-077 1번): 경계 00:00·07:59:59, 한가운데 03:00, 08:00
select pg_temp.check(private.notification_send_at('award_results_announced', pg_temp.kst('2026-11-11 00:00')) = pg_temp.kst('2026-11-11 00:00'), 'results 00:00 now');
select pg_temp.check(private.notification_send_at('award_results_announced', pg_temp.kst('2026-11-11 03:00')) = pg_temp.kst('2026-11-11 03:00'), 'results 03:00 now');
select pg_temp.check(private.notification_send_at('award_results_announced', pg_temp.kst('2026-11-11 07:59:59')) = pg_temp.kst('2026-11-11 07:59:59'), 'results 07:59:59 now');
select pg_temp.check(private.notification_send_at('award_results_announced', pg_temp.kst('2026-11-11 08:00')) = pg_temp.kst('2026-11-11 08:00'), 'results 08:00 now');
select pg_temp.check(private.notification_send_at('award_results_announced', pg_temp.kst('2026-11-10 23:59')) = pg_temp.kst('2026-11-10 23:59'), 'results 23:59 now');
-- 일시 표시
select pg_temp.check(private.match_time_label(pg_temp.kst('2026-11-11 10:00')) = '11월 11일(수) 10:00', 'time label');

-- ================================================================ 준비
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2)); select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3)); select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4)); select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5)); select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(6)); select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(7)); select public.create_profile('칠', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(8)); select public.create_profile('팔', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(9)); select public.create_profile('구', null, array['forward']::public.play_position[], false, true, true, true, false);

-- 팀 P: d1 팀장. 팀 Q: d7 팀장
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('피FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(7));
insert into t_vars select 'Q', public.create_team('큐FC')::text;
insert into t_vars select 'codeQ', team_code from public.teams where id = pg_temp.vid('Q');

-- ================================================================ 3-5 가입 신청·승인·합류
-- d2 신청 → 팀장 d1 에게 신청 알림(이름, actor = d2) (SC-47)
select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'r2', public.request_join(pg_temp.v('codeP'), 'code')::text;
reset role;
select pg_temp.check(pg_temp.who('join_request_received', 'P') = '1', 'request -> owner only');
select pg_temp.check((select actor_id = pg_temp.u(2) and body like '이님%' and ref_type = 'join_request' and ref_id = pg_temp.vid('r2')
  and title = '피FC' from public.notifications where kind = 'join_request_received' and user_id = pg_temp.u(1)), 'request text, actor, ref');
select pg_temp.check((select count(*) = 1 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'join_request_received' and o.status = 'pending' and o.send_at = private.notification_send_at(n.kind, n.created_at)), 'request queued');
set local role authenticated;

-- 승인 → 신청자에게 승인 알림, 팀원(d1)에게 합류 알림(알림함만) (SC-48, SC-53)
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid('r2'), true);
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
reset role;
select pg_temp.check(pg_temp.cnt('join_request_decided', 2) = 1, 'approved notice');
select pg_temp.check((select body like '%승인됐어요%' from public.notifications where kind = 'join_request_decided' and user_id = pg_temp.u(2)), 'approved text');
select pg_temp.check(pg_temp.who('member_joined', 'P') = '1', 'joined -> existing members only');
select pg_temp.check((select actor_id = pg_temp.u(2) and body like '이님%' from public.notifications where kind = 'member_joined'), 'joined actor');
select pg_temp.check(not exists (select 1 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'member_joined'), 'joined has no push');
select pg_temp.check(pg_temp.cnt('manager_assigned', 2) = 1 and pg_temp.cnt('manager_assigned', 1) = 0, 'assigned -> self only (SC-40)');
set local role authenticated;

-- d3~d6 신청 → 팀장·운영진(d1·d2) 에게. 운영진 d2 가 승인 → 합류 알림은 승인한 d2 포함, 새 팀원 본인 제외
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'r3', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'r4', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'r5', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'r6', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'rq5', public.request_join(pg_temp.v('codeQ'), 'code')::text;
select pg_temp.login(pg_temp.u(2));
select public.decide_join_request(pg_temp.vid('r3'), true);
select public.decide_join_request(pg_temp.vid('r4'), true);
select public.decide_join_request(pg_temp.vid('r5'), true);
select pg_temp.expect_error($$select public.decide_join_request(pg_temp.vid('r5'), false)$$, 'request_not_pending');
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid('r6'), true);
select pg_temp.login(pg_temp.u(7));
select public.decide_join_request(pg_temp.vid('rq5'), true);
reset role;
select pg_temp.check(pg_temp.cnt('join_request_received', 1) = 5 and pg_temp.cnt('join_request_received', 2) = 4, 'requests -> staff');
select pg_temp.check(pg_temp.cnt('join_request_received', 3) = 0 and pg_temp.cnt('join_request_received', 4) = 0, 'members get no request notices');
select pg_temp.check(pg_temp.cnt('join_request_decided', 5) = 2, 'one decided notice per request (SC-49)');
-- d3 합류 알림: d1·d2 / d6 합류: d1~d5 (승인한 d1 포함)
select pg_temp.check((select count(*) = 2 from public.notifications where kind = 'member_joined' and actor_id = pg_temp.u(3)), 'd3 joined -> d1,d2');
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) = '1,2,3,4,5'
  from public.notifications where kind = 'member_joined' and actor_id = pg_temp.u(6)), 'd6 joined -> d1..d5');
select pg_temp.check(pg_temp.cnt('member_joined', 6) = 0, 'no joined notice for self');
-- 거절 알림
set local role authenticated;
select pg_temp.login(pg_temp.u(8)); insert into t_vars select 'r8', public.request_join(pg_temp.v('codeQ'), 'code')::text;
select pg_temp.login(pg_temp.u(7)); select public.decide_join_request(pg_temp.vid('r8'), false);
reset role;
select pg_temp.check((select count(*) = 1 and bool_and(body like '%승인되지 않았어요%') from public.notifications
  where kind = 'join_request_decided' and user_id = pg_temp.u(8)), 'rejected notice');
set local role authenticated;

-- 운영진 해제 → 재지정: 사건마다 알림 (lead 정리 L-06, SC-03)
select pg_temp.login(pg_temp.u(1));
select public.dismiss_manager(pg_temp.vid('P'), pg_temp.u(2));
reset role;
-- 같은 트랜잭션 안에서는 now() 가 같으므로 사건 값이 같아진다. 실제로는 처리마다 다르므로 앞 알림의 키를 옛 시각으로 바꿔 둔다
-- (칸 보호 트리거를 이 트랜잭션에서만 잠시 끈다).
alter table public.notifications disable trigger notifications_before_update;
update public.notifications set dedupe_key = 'manager_assigned:' || pg_temp.v('P') || ':1'
 where kind = 'manager_assigned' and user_id = pg_temp.u(2);
alter table public.notifications enable trigger notifications_before_update;
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
reset role;
select pg_temp.check(pg_temp.cnt('manager_assigned', 2) = 2 and pg_temp.cnt('manager_unassigned', 2) = 1, 'assign/unassign each time');
select pg_temp.check(pg_temp.who('manager_unassigned', 'P') = '2', 'unassigned -> self only');
-- 같은 사건을 다시 부르면 무시 (F-02)
select pg_temp.check(private.notify('manager_unassigned', array[pg_temp.u(2)], pg_temp.vid('P'), 'team', pg_temp.vid('P'),
  private.notification_event(now())) = 0, 'same event deduped');
set local role authenticated;

-- ================================================================ 3-2 일정 알림
-- 운영진 d2 가 직접 추가 → d1·d3·d4·d5·d6, 추가한 d2 없음, 팀 Q 없음 (SC-21, G-01)
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'm1', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;
insert into t_vars select 'm2', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '15:00', pg_temp.v('d3')::date, '17:00')::text;
reset role;
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) = '1,3,4,5,6'
  from public.notifications where kind = 'match_created' and ref_id = pg_temp.vid('m1')), 'created -> members except creator');
select pg_temp.check(pg_temp.cnt('match_created', 7) = 0, 'other team gets none');
select pg_temp.check((select bool_and(body = private.match_time_label(m.starts_at) || ' 경기가 열렸어요! 이번 주도 뛰어야죠, 참석 투표 부탁드려요.' and ref_type = 'match' and actor_id is null)
  from public.notifications n join public.matches m on m.id = n.ref_id where n.kind = 'match_created'), 'created text');
select pg_temp.check((select count(*) = 5 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.ref_id = pg_temp.vid('m1') and o.send_at = private.notification_send_at(n.kind, n.created_at) and o.user_id = n.user_id), 'created queued (SC-01)');
-- 자동 일정(만든 사람 없음) → 팀원 전체
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at)
  values (pg_temp.vid('P'), 'auto', now() + interval '5 hours', now() + interval '7 hours', now() + interval '3 hours', now())
  returning id)
insert into t_vars select 'm3', id::text from x;
select pg_temp.check((select count(*) = 6 from public.notifications where kind = 'match_created' and ref_id = pg_temp.vid('m3')), 'auto created -> all members (SC-20)');

-- 승격 알림: 정원 2, d3·d4 참석, d5 대기 → d4 불참 → d5 승격 (SC-23)
update public.matches set capacity = 2 where id = pg_temp.vid('m1');
set local role authenticated;
select pg_temp.login(pg_temp.u(3)); select public.respond_attendance(pg_temp.vid('m1'), true);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m1'), true);
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m1'), true);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m1'), false);
reset role;
select pg_temp.check(pg_temp.who('waitlist_promoted', 'P') = '5', 'promoted -> self only');
select pg_temp.check((select body like '자리가 났어요!%' and ref_id = pg_temp.vid('m1') from public.notifications where kind = 'waitlist_promoted'), 'promoted text');
set local role authenticated;
-- 같은 일정에서 다시 승격 → 다시 알림 (사건 값 = promoted_at, L-06)
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m1'), false);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m1'), true);
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m1'), true);
select pg_temp.login(pg_temp.u(3)); select public.respond_attendance(pg_temp.vid('m1'), false);
reset role;
select pg_temp.check(pg_temp.cnt('waitlist_promoted', 5) = 2 and pg_temp.cnt('waitlist_promoted', 4) = 0, 'second promotion notified');
set local role authenticated;

-- 취소 알림: 응답자(d3 불참·d4·d5 참석, d1 불참) 중 취소한 d1 제외, 사유 포함. 미투표 d2·d6 없음 (SC-25)
select pg_temp.login(pg_temp.u(1)); select public.respond_attendance(pg_temp.vid('m1'), false);
select public.cancel_match(pg_temp.vid('m1'), '우천');
reset role;
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) = '3,4,5'
  from public.notifications where kind = 'match_cancelled' and ref_id = pg_temp.vid('m1')), 'cancelled -> responders except canceller');
select pg_temp.check((select bool_and(body like '% 경기가 취소됐어요. 사유: 우천') from public.notifications
  where kind = 'match_cancelled' and ref_id = pg_temp.vid('m1')), 'cancel reason in text');
set local role authenticated;
-- 사유 없이 취소 → 사유 부분 없음
select pg_temp.login(pg_temp.u(1)); select public.respond_attendance(pg_temp.vid('m2'), true);
select pg_temp.login(pg_temp.u(2)); select public.cancel_match(pg_temp.vid('m2'));
reset role;
select pg_temp.check((select count(*) = 1 and bool_and(body not like '%사유%' and user_id = pg_temp.u(1)) from public.notifications
  where kind = 'match_cancelled' and ref_id = pg_temp.vid('m2')), 'cancel without reason');

-- ================================================================ 3-5 팀 탈퇴 → 팀장·운영진 (이름)
set local role authenticated;
select pg_temp.login(pg_temp.u(6)); select public.leave_team(pg_temp.vid('P'));
reset role;
select pg_temp.check(pg_temp.who('member_left', 'P') = '1,2', 'left -> owner, managers (SC-42)');
select pg_temp.check((select bool_and(actor_id = pg_temp.u(6) and body = '육님이 팀을 떠났어요.') from public.notifications where kind = 'member_left'), 'left text, actor');

-- ================================================================ 3-3 미투표 알림
-- m3: 알림 시각 = now(). d9 는 알림 시각 뒤 가입. d3 참석, d4 불참. d6 은 떠남.
set local role authenticated;
select pg_temp.login(pg_temp.u(9)); insert into t_vars select 'r9', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(1)); select public.decide_join_request(pg_temp.vid('r9'), true);
select pg_temp.login(pg_temp.u(3)); select public.respond_attendance(pg_temp.vid('m3'), true);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m3'), false);
reset role;
update public.team_members set joined_at = now() + interval '30 seconds'
 where team_id = pg_temp.vid('P') and user_id = pg_temp.u(9) and status = 'active';
-- 알림 끔(m4), 알림 시각 전(m5), 취소된 일정(m6), 마감 지난 일정(m7)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '6 hours', now() + interval '8 hours', now() + interval '4 hours', null, pg_temp.u(1))
  returning id)
insert into t_vars select 'm4', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '6 hours', now() + interval '8 hours', now() + interval '4 hours', now() + interval '2 hours', pg_temp.u(1))
  returning id)
insert into t_vars select 'm5', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at, created_by,
                              status, cancelled_at, cancelled_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '6 hours', now() + interval '8 hours', now() + interval '4 hours', now(), pg_temp.u(1),
          'cancelled', now(), pg_temp.u(1))
  returning id)
insert into t_vars select 'm6', id::text from x;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at, created_by)
  values (pg_temp.vid('P'), 'manual', now() + interval '1 hour', now() + interval '3 hours', now() + interval '30 seconds', now(), pg_temp.u(1))
  returning id)
insert into t_vars select 'm7', id::text from x;

-- 알림 시각 전에는 아무것도 없다
select pg_temp.check(private.send_rsvp_reminders(now() - interval '1 second') = 0, 'nothing before reminder time');
-- 1분 뒤 실행: 미투표 현재 팀원 d1·d2·d5 만 (d3 참석, d4 불참, d6 떠남, d9 알림 뒤 가입). m4~m7 없음 (SC-27, SC-30, SC-34)
select pg_temp.check(private.send_rsvp_reminders(now() + interval '1 minute') = 3, 'reminders sent to 3');
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) = '1,2,5'
  from public.notifications where kind = 'rsvp_deadline_soon'), 'reminder recipients');
select pg_temp.check((select bool_and(ref_id = pg_temp.vid('m3')) from public.notifications where kind = 'rsvp_deadline_soon'), 'reminder only for m3');
select pg_temp.check((select bool_and(o.send_at = n.created_at) from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'rsvp_deadline_soon'), 'reminder push immediately');
-- 재실행해도 한 번 (SC-31)
select pg_temp.check(private.send_rsvp_reminders(now() + interval '2 minutes') = 0, 'reminder once');

-- ================================================================ 3-1 알림함 권한 (SC-08, F-05)
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) > 0 and bool_and(user_id = pg_temp.u(3)) from public.notifications), 'reads own only');
select pg_temp.check((select count(*) = 0 from public.notifications where user_id = pg_temp.u(4)), 'cannot read others');
select pg_temp.expect_error($$update public.notifications set title = 'x' where user_id = pg_temp.u(3)$$, 'permission denied%');
select pg_temp.expect_error($$update public.notifications set user_id = pg_temp.u(4)$$, 'permission denied%');
select pg_temp.expect_error($$update public.notifications set kind = 'team_dissolved'$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.notifications (user_id, kind, title, body, dedupe_key) values (pg_temp.u(3), 'team_dissolved', 'x', 'y', 'z')$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.notifications where user_id = pg_temp.u(3)$$, 'permission denied%');
select pg_temp.expect_error($$select count(*) from public.notification_outbox$$, 'permission denied%');
select pg_temp.expect_error($$update public.notification_outbox set status = 'sent'$$, 'permission denied%');
select pg_temp.expect_error($$select private.notify('team_dissolved', array[pg_temp.u(3)], pg_temp.vid('P'), 'team', pg_temp.vid('P'), 'x')$$, 'permission denied%');
select pg_temp.expect_error($$select private.send_rsvp_reminders()$$, 'permission denied%');
select pg_temp.expect_error($$select private.cleanup_notifications()$$, 'permission denied%');
-- 남의 알림 read_at 은 0줄 (보이지 않음)
update public.notifications set read_at = now() where user_id = pg_temp.u(4);
-- 하나 읽음: 서버 시각으로 기록, 다시 다른 값을 넣어도 처음 시각 그대로, 비우기 거절 (L-11)
insert into t_vars select 'n3', id::text from public.notifications where user_id = pg_temp.u(3) order by created_at, id limit 1;
select pg_temp.check(public.count_unread_notifications() = (select count(*)::int from public.notifications), 'all unread at first');
update public.notifications set read_at = '2000-01-01' where id = pg_temp.vid('n3');
select pg_temp.check((select read_at = now() from public.notifications where id = pg_temp.vid('n3')), 'read_at = server time');
update public.notifications set read_at = '2001-01-01' where id = pg_temp.vid('n3');
select pg_temp.check((select read_at = now() from public.notifications where id = pg_temp.vid('n3')), 'read_at keeps first value');
select pg_temp.expect_error($$update public.notifications set read_at = null where id = pg_temp.vid('n3')$$, 'cannot_mark_unread');
-- 모두 읽음
select pg_temp.check(public.mark_all_notifications_read() = (select count(*)::int - 1 from public.notifications), 'mark all returns count');
select pg_temp.check(public.count_unread_notifications() = 0, 'no unread after mark all');
select pg_temp.check(public.mark_all_notifications_read() = 0, 'mark all again = 0');
reset role;
select pg_temp.check((select bool_and(read_at is null) from public.notifications where user_id = pg_temp.u(4)), 'others untouched');
select pg_temp.check(not has_function_privilege('anon', 'public.mark_all_notifications_read()', 'execute'), 'anon cannot mark all');
select pg_temp.check(not has_function_privilege('anon', 'public.count_unread_notifications()', 'execute'), 'anon cannot count');
select pg_temp.check(has_function_privilege('authenticated', 'public.mark_all_notifications_read()', 'execute'), 'authenticated can mark all');
select pg_temp.check(not has_function_privilege('authenticated', 'private.notify(public.notification_kind, uuid[], uuid, text, uuid, text, uuid, jsonb)', 'execute'), 'app cannot notify');
select pg_temp.check(not has_function_privilege('service_role', 'private.notify(public.notification_kind, uuid[], uuid, text, uuid, text, uuid, jsonb)', 'execute'), 'service_role cannot notify');
select pg_temp.check(not has_function_privilege('service_role', 'private.send_rsvp_reminders(timestamptz)', 'execute'), 'service_role cannot remind');
select pg_temp.check(not has_function_privilege('service_role', 'private.cleanup_notifications(timestamptz)', 'execute'), 'service_role cannot cleanup');

-- ================================================================ 3-5 위임·내보내기
-- d1 → d2 위임: d2 에게만 ownership_received, 운영진이 된 d1 에게 지정 알림 없음 (SC-41)
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.transfer_ownership(pg_temp.vid('P'), pg_temp.u(2));
reset role;
select pg_temp.check(pg_temp.who('ownership_received', 'P') = '2', 'ownership -> new owner only');
select pg_temp.check(pg_temp.cnt('manager_assigned', 1) = 0, 'old owner gets no assigned notice');
-- d2(팀장) 가 운영진 d1 을 내보냄: d1 에게 내보내기 알림 하나만 (SC-44)
set local role authenticated;
select pg_temp.login(pg_temp.u(2)); select public.remove_member(pg_temp.vid('P'), pg_temp.u(1));
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(3));
reset role;
select pg_temp.check(pg_temp.who('member_removed', 'P') = '1', 'removed -> self only');
select pg_temp.check(pg_temp.cnt('manager_unassigned', 1) = 0, 'removed manager gets no unassigned notice');
select pg_temp.check(pg_temp.cnt('member_left', 2) = 1, 'removal is not a left notice');

-- ================================================================ 3-6 회원 탈퇴
-- d5 (팀 P·Q 소속) 탈퇴. m8(정원 1) 에 d5 참석·d4 대기 → d4 승격 알림.
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'm8', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '09:00', pg_temp.v('d3')::date, '10:00')::text;
reset role;
update public.matches set capacity = 1 where id = pg_temp.vid('m8');
set local role authenticated;
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m8'), true);
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m8'), true);
reset role;
-- 이름이 든 알림 (d5 신청·합류)
select pg_temp.check((select count(*) > 0 from public.notifications where actor_id = pg_temp.u(5)), 'd5 named notices exist');
select public.delete_account(pg_temp.u(5));
-- Q-044: d5 이름이 든 다른 알림은 사라진다 (SC-04, SC-17)
select pg_temp.check(not exists (select 1 from public.notifications where actor_id = pg_temp.u(5)), 'named notices removed');
select pg_temp.check(not exists (select 1 from public.notifications where user_id = pg_temp.u(5)), 'own notices removed');
-- 회원 탈퇴 알림: 팀 P 팀장 d2·운영진 d3, 팀 Q 팀장 d7. 이름이 남는다 (SC-50, SC-51)
select pg_temp.check(pg_temp.who('member_account_deleted', 'P') = '2,3', 'account deleted -> P staff');
select pg_temp.check(pg_temp.who('member_account_deleted', 'Q') = '7', 'account deleted -> Q staff');
select pg_temp.check((select bool_and(actor_id is null and body = '오님이 회원 탈퇴로 팀을 떠났어요.') from public.notifications
  where kind = 'member_account_deleted'), 'account deleted keeps name, no actor');
select pg_temp.check((select count(*) = 3 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'member_account_deleted'), 'account deleted queued');
-- 대기 1번 자동 참석 + 알림 (Q-038)
select pg_temp.check((select count(*) = 1 from public.notifications where kind = 'waitlist_promoted' and user_id = pg_temp.u(4) and ref_id = pg_temp.vid('m8')), 'promotion on account deletion');
-- 팀만 떠난 d6 의 이름은 남는다 (SC-05)
select pg_temp.check((select count(*) = 2 from public.notifications where kind = 'member_left' and actor_id = pg_temp.u(6)), 'left name stays');

-- ================================================================ 3-5 해체
-- d8 의 대기 신청, 응답 있는 시작 전 일정 m3 → 해체: 일정 취소 알림 없음, 팀원 d3·d4·d9 해체 알림, 팀장 d2 없음, d8 자동 거절 알림
set local role authenticated;
select pg_temp.login(pg_temp.u(8)); insert into t_vars select 'r8p', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(2)); select public.dissolve_team(pg_temp.vid('P'), '피FC');
reset role;
select pg_temp.check((select status = 'cancelled' from public.matches where id = pg_temp.vid('m3')), 'm3 cancelled by dissolve');
select pg_temp.check(not exists (select 1 from public.notifications where kind = 'match_cancelled' and ref_id in (pg_temp.vid('m3'), pg_temp.vid('m8'))), 'no cancel notice on dissolve (SC-26)');
select pg_temp.check(pg_temp.who('team_dissolved', 'P') = '3,4,9', 'dissolved -> members except owner (SC-45)');
select pg_temp.check((select count(*) = 1 from public.notifications where kind = 'join_request_auto_declined' and user_id = pg_temp.u(8)
  and ref_id = pg_temp.vid('r8p') and body like '팀이 해체되었어요%'), 'auto declined notice (SC-46)');
select pg_temp.check(not exists (select 1 from public.notifications where kind = 'join_request_decided' and ref_id = pg_temp.vid('r8p')), 'no plain reject notice');

-- ================================================================ 문구 규칙 (SC-06, SC-07)
-- 초대 코드·팀 식별코드가 문구에 없다. 이름이 든 알림은 actor_id 가 있고, 그 밖에는 비어 있다(회원 탈퇴 알림 예외).
select pg_temp.check(not exists (select 1 from public.notifications n where n.body like '%' || pg_temp.v('codeP') || '%' or n.body like '%' || pg_temp.v('codeQ') || '%'), 'no codes in text');
select pg_temp.check(not exists (select 1 from public.notifications n
  where (n.kind in ('join_request_received', 'member_left', 'member_joined')) <> (n.actor_id is not null)), 'actor only on named kinds');
select pg_temp.check(not exists (select 1 from public.notifications n where n.body like '%null%' or n.body is null), 'no empty parts');

-- ================================================================ 3-7 정리 (SC-09, SC-55)
insert into t_vars select 'old', n.id::text from public.notifications n join public.notification_outbox o on o.notification_id = n.id
 where n.user_id = pg_temp.u(3) order by n.id limit 1;
insert into t_vars select 'mid', n.id::text from public.notifications n join public.notification_outbox o on o.notification_id = n.id
 where n.user_id = pg_temp.u(4) order by n.id limit 1;
select pg_temp.check(pg_temp.v('old') is not null and pg_temp.v('mid') is not null, 'cleanup fixtures');
alter table public.notifications disable trigger notifications_before_update;
update public.notifications set created_at = now() - interval '31 days' where id = pg_temp.vid('old');
update public.notifications set created_at = now() - interval '29 days' where id = pg_temp.vid('mid');
update public.notifications set created_at = now() - interval '31 days', read_at = now()
 where kind = 'member_account_deleted' and team_id = pg_temp.vid('Q');
alter table public.notifications enable trigger notifications_before_update;
-- 발송 후 31일 / 29일 된 대기열 줄 (알림함 줄은 남아 있음)
update public.notification_outbox set status = 'sent', sent_at = now() - interval '31 days'
 where notification_id = pg_temp.vid('mid');
insert into t_vars select 'q29', o.id::text from public.notification_outbox o
 where o.status = 'pending' and o.notification_id <> pg_temp.vid('old') order by o.id limit 1;
update public.notification_outbox set status = 'skipped', sent_at = now() - interval '29 days' where id = pg_temp.vid('q29');
select private.cleanup_notifications(now());
select pg_temp.check(not exists (select 1 from public.notifications where id = pg_temp.vid('old')), '31 days notice removed');
select pg_temp.check(not exists (select 1 from public.notification_outbox where notification_id = pg_temp.vid('old')), 'its outbox removed');
select pg_temp.check(exists (select 1 from public.notifications where id = pg_temp.vid('mid')), '29 days notice kept');
select pg_temp.check(not exists (select 1 from public.notification_outbox where notification_id = pg_temp.vid('mid')), 'outbox 31 days after send removed');
select pg_temp.check(exists (select 1 from public.notification_outbox where id = pg_temp.vid('q29')), 'outbox 29 days after skip kept');
select pg_temp.check(not exists (select 1 from public.notifications where kind = 'member_account_deleted' and team_id = pg_temp.vid('Q')), 'read 31 days account notice removed');
select pg_temp.check(exists (select 1 from public.notifications where kind = 'member_account_deleted' and team_id = pg_temp.vid('P')), 'recent account notice kept');

-- ================================================================ 구조
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'RLS on notifications');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.notification_outbox'::regclass), 'RLS on outbox');
select pg_temp.check(not has_table_privilege('anon', 'public.notifications', 'select'), 'anon cannot read notifications');
select pg_temp.check(not has_table_privilege('authenticated', 'public.notification_outbox', 'select'), 'app cannot read outbox');
select pg_temp.check(
  (select command from cron.job where jobname = 'send-rsvp-reminders') = 'select private.send_rsvp_reminders()'
  and (select schedule from cron.job where jobname = 'send-rsvp-reminders') = '* * * * *', 'reminder cron every minute');
select pg_temp.check(
  (select command from cron.job where jobname = 'cleanup-notifications') = 'select private.cleanup_notifications()'
  and (select schedule from cron.job where jobname = 'cleanup-notifications') = '13 19 * * *', 'cleanup cron daily');
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and pronamespace in ('public'::regnamespace, 'private'::regnamespace) and proname in (
    'notify', 'team_staff_ids', 'team_member_ids', 'matches_notify_created', 'matches_notify_cancelled',
    'promote_waitlisted', 'appoint_manager', 'dismiss_manager', 'transfer_ownership', 'remove_member', 'leave_team',
    'insert_join_request', 'decide_join_request', 'dissolve_team', 'delete_account',
    'send_rsvp_reminders', 'cleanup_notifications')), 'definer search_path fixed');
select pg_temp.check((select count(*) = 17 from pg_proc where prosecdef and pronamespace in ('public'::regnamespace, 'private'::regnamespace) and proname in (
    'notify', 'team_staff_ids', 'team_member_ids', 'matches_notify_created', 'matches_notify_cancelled',
    'promote_waitlisted', 'appoint_manager', 'dismiss_manager', 'transfer_ownership', 'remove_member', 'leave_team',
    'insert_join_request', 'decide_join_request', 'dissolve_team', 'delete_account',
    'send_rsvp_reminders', 'cleanup_notifications')), 'all definer functions present');

select 'ALL PASSED' as result;
