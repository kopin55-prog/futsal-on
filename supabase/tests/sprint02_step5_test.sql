-- 스프린트 02 5단계 마이그레이션(202611050036 푸시 발송: claim_push_batch, finish_push_batch, notifier 예약 작업) 동작 확인.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 개발 DB 에 원래 있던 pending 대기열 줄은 이 트랜잭션 안에서만 보낼 시각을 1년 뒤로 밀어 둔다 (롤백되므로 실제로는 그대로).
-- 한 트랜잭션 안에서는 now() 가 같으므로 "알림이 생긴 뒤 팀을 떠남"은 알림의 created_at 을 1시간 앞으로 옮겨 준비한다.

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
grant all on t_vars to authenticated, anon, service_role;

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
  select ('00000000-0000-4000-8000-0000000000e' || p_n::text)::uuid
$$;

-- 잡은 줄을 담아 두는 표
create temp table t_claim (
  outbox_id uuid, notification_id uuid, kind text, title text, body text, team_id uuid, ref_type text, ref_id uuid,
  notified_at timestamptz, read_at timestamptz, match_status text, match_starts_at timestamptz,
  match_ends_at timestamptz, award_poll_status text, award_poll_closes_at timestamptz,  -- 202611050050 에서 추가
  lineup_status text,  -- 202611050052 에서 추가
  recipient_active boolean, recipient_left_at timestamptz, tokens text[]
);
grant all on t_claim to service_role;

-- 이 테스트의 match_created 대기열 줄 (사람 n, 일정 키)
create function pg_temp.ob(p_n int, p_match text)
returns uuid
language sql
as $$
  select o.id from public.notification_outbox o join public.notifications n on n.id = o.notification_id
   where n.kind = 'match_created' and n.user_id = pg_temp.u(p_n) and n.ref_id = pg_temp.vid(p_match)
$$;

insert into t_vars values
  ('d3', ((now() + interval '3 days') at time zone 'Asia/Seoul')::date::text);

insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'e' || n || '@test.invalid', now(), now()
  from generate_series(1, 7) n;

-- ================================================================ 준비
-- 팀 P: e1 팀장, e2·e3·e5·e6 팀원. e4·e7 은 팀 밖.
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2)); select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3)); select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4)); select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5)); select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(6)); select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('푸시FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'r2', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'r3', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'r5', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'r6', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid('r2'), true);
select public.decide_join_request(pg_temp.vid('r3'), true);
select public.decide_join_request(pg_temp.vid('r5'), true);
select public.decide_join_request(pg_temp.vid('r6'), true);

-- 기기 주소: e2 두 대, e3·e5 한 대, e6 없음 (5-1, register_device_token)
select pg_temp.login(pg_temp.u(2)); select public.register_device_token('tok-e2-a', 'android'); select public.register_device_token('tok-e2-b', 'android');
select pg_temp.login(pg_temp.u(3)); select public.register_device_token('tok-e3', 'android');
select pg_temp.login(pg_temp.u(5)); select public.register_device_token('tok-e5', 'android');
-- 같은 토큰을 다른 사람이 등록하면 소유가 옮겨진다 (SE-06, S-08): e4 가 e3 의 기기에서 로그인 → 다시 e3
select pg_temp.login(pg_temp.u(4)); select public.register_device_token('tok-e3', 'android');
select pg_temp.check((select count(*) = 1 from public.device_tokens where token = 'tok-e3'), 'token moved, not duplicated');
select pg_temp.check((select count(*) = 1 from public.device_tokens), 'e4 sees only own token');
select pg_temp.login(pg_temp.u(3)); select public.register_device_token('tok-e3', 'android');
-- 로그아웃: 본인 기기 주소만 지울 수 있다 (2-4)
select pg_temp.login(pg_temp.u(4));
delete from public.device_tokens where token = 'tok-e5';
select pg_temp.login(pg_temp.u(2));
select pg_temp.check((select count(*) = 2 from public.device_tokens), 'e2 sees own 2 tokens');

-- 일정: m1(예정), m2(취소), m3(이미 시작) — 팀장 e1 이 만든다 → e2·e3·e5·e6 에게 생성 알림
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'm1', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '19:00', pg_temp.v('d3')::date, '21:00')::text;
insert into t_vars select 'm2', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '15:00', pg_temp.v('d3')::date, '17:00')::text;
reset role;
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at)
  values (pg_temp.vid('P'), 'auto', now() - interval '1 hour', now() + interval '1 hour', now() - interval '2 hours')
  returning id)
insert into t_vars select 'm3', id::text from x;
select pg_temp.check(exists (select 1 from public.device_tokens where token = 'tok-e5' and user_id = pg_temp.u(5)), 'other user cannot delete token');

-- 이 테스트 줄만 보낼 시각이 지나게: 원래 pending 은 1년 뒤로, 이 팀 알림은 1분 전으로
update public.notification_outbox set send_at = now() + interval '1 year' where status = 'pending';
update public.notification_outbox o set send_at = now() - interval '1 minute'
  from public.notifications n
 where n.id = o.notification_id and n.team_id = pg_temp.vid('P') and o.status = 'pending';
-- 생성 알림은 1시간 전에 생긴 것으로 (그 뒤에 팀을 떠난 경우를 만들기 위해)
alter table public.notifications disable trigger notifications_before_update;
update public.notifications set created_at = now() - interval '1 hour'
 where team_id = pg_temp.vid('P') and kind = 'match_created';
alter table public.notifications enable trigger notifications_before_update;
-- 아직 보낼 시각이 안 된 줄 하나 (e6 의 m2 알림)
update public.notification_outbox set send_at = now() + interval '1 hour' where id = pg_temp.ob(6, 'm2');

-- e2 가 m1 알림을 읽음, e3 가 팀을 떠남, m2 취소
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
update public.notifications set read_at = now()
 where kind = 'match_created' and ref_id = pg_temp.vid('m1');
select pg_temp.login(pg_temp.u(3)); select public.leave_team(pg_temp.vid('P'));
select pg_temp.login(pg_temp.u(1)); select public.cancel_match(pg_temp.vid('m2'));

-- ================================================================ 권한 (SE-18)
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select * from public.claim_push_batch(10)$$, 'permission denied%');
select pg_temp.expect_error($$select public.finish_push_batch('[]'::jsonb, '{}')$$, 'permission denied%');
reset role;
set local role anon;
select pg_temp.expect_error($$select * from public.claim_push_batch(10)$$, 'permission denied%');
select pg_temp.expect_error($$select public.finish_push_batch('[]'::jsonb, '{}')$$, 'permission denied%');
reset role;
select pg_temp.check(not has_function_privilege('authenticated', 'public.claim_push_batch(int)', 'execute'), 'app cannot claim');
select pg_temp.check(not has_function_privilege('anon', 'public.finish_push_batch(jsonb, text[])', 'execute'), 'anon cannot finish');
select pg_temp.check(has_function_privilege('service_role', 'public.claim_push_batch(int)', 'execute'), 'service_role can claim');
select pg_temp.check(not has_function_privilege('service_role', 'private.call_cron_function(text)', 'execute'), 'service_role cannot call cron');

-- ================================================================ 잡기 (상한, 잠금, 재료)
set local role service_role;
insert into t_claim select * from public.claim_push_batch(1);
reset role;
select pg_temp.check((select count(*) = 1 from t_claim), 'limit respected');
select pg_temp.check((select o.status = 'failed' and o.sent_at is not null from public.notification_outbox o
  where o.id = (select outbox_id from t_claim)), 'claimed row leaves pending');
set local role service_role;
insert into t_claim select * from public.claim_push_batch(100);
reset role;
-- 이 팀의 보낼 시각 지난 줄이 모두 한 번씩만 잡힌다
select pg_temp.check((select count(*) = count(distinct outbox_id) from t_claim), 'no row claimed twice');
select pg_temp.check((select count(*) from t_claim) = (select count(*) from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.team_id = pg_temp.vid('P') and o.status = 'failed'), 'all due rows of team claimed');
select pg_temp.check(not exists (select 1 from t_claim where outbox_id = pg_temp.ob(6, 'm2')), 'future row not claimed');
select pg_temp.check((select status = 'pending' from public.notification_outbox where id = pg_temp.ob(6, 'm2')), 'future row still pending');
select pg_temp.check(not exists (select 1 from t_claim c join public.notification_outbox o on o.id = c.outbox_id
  join public.notifications n on n.id = o.notification_id where n.team_id is distinct from pg_temp.vid('P')), 'other pending rows untouched');
-- 다시 잡으면 아무것도 없다
set local role service_role;
select pg_temp.check((select count(*) = 0 from public.claim_push_batch(100) c
  where c.team_id = pg_temp.vid('P')), 'second claim gets nothing');
reset role;

-- 재료: 문구는 알림함 줄과 같음 (I-06)
select pg_temp.check((select bool_and(c.title = n.title and c.body = n.body and c.kind = n.kind::text and c.ref_id is not distinct from n.ref_id
  and c.team_id = n.team_id and c.notified_at = n.created_at)
  from t_claim c join public.notifications n on n.id = c.notification_id), 'text and target same as inbox');
-- e2 m1: 읽음, 기기 2대
select pg_temp.check((select read_at is not null and cardinality(tokens) = 2 and recipient_active
  from t_claim where outbox_id = pg_temp.ob(2, 'm1')), 'e2: read, two tokens');
-- e3 m1: 알림 뒤에 팀을 떠남
select pg_temp.check((select not recipient_active and recipient_left_at > notified_at and tokens = array['tok-e3']
  from t_claim where outbox_id = pg_temp.ob(3, 'm1')), 'e3: left after notice');
-- e5 m1: 보낼 것
select pg_temp.check((select read_at is null and recipient_active and match_status = 'scheduled' and match_starts_at > now()
  and tokens = array['tok-e5'] from t_claim where outbox_id = pg_temp.ob(5, 'm1')), 'e5 m1: sendable');
-- e5 m2: 일정 취소
select pg_temp.check((select match_status = 'cancelled' from t_claim where outbox_id = pg_temp.ob(5, 'm2')), 'e5 m2: cancelled');
-- e5 m3: 이미 시작
select pg_temp.check((select match_starts_at <= now() from t_claim where outbox_id = pg_temp.ob(5, 'm3')), 'e5 m3: started');
-- e6: 기기 없음
select pg_temp.check((select cardinality(tokens) = 0 from t_claim where outbox_id = pg_temp.ob(6, 'm1')), 'e6: no device');
-- 가입 승인 알림(대상 = 가입 신청, 일정 아님): 일정 재료 없음, 그 팀 소속
select pg_temp.check((select bool_and(match_status is null and recipient_active) from t_claim c
  join public.notifications n on n.id = c.notification_id where n.kind = 'join_request_decided' and n.user_id <> pg_temp.u(3)), 'join decided: no match facts');

-- ================================================================ 결과 적기
insert into t_vars values ('before_n', (select count(*)::text from public.notifications where team_id = pg_temp.vid('P')));
set local role service_role;
select pg_temp.check(public.finish_push_batch(
  jsonb_build_array(
    jsonb_build_object('id', pg_temp.ob(5, 'm1'), 'status', 'sent'),
    jsonb_build_object('id', pg_temp.ob(2, 'm1'), 'status', 'skipped'),
    jsonb_build_object('id', pg_temp.ob(3, 'm1'), 'status', 'skipped'),
    jsonb_build_object('id', pg_temp.ob(6, 'm1'), 'status', 'skipped'),
    jsonb_build_object('id', pg_temp.ob(5, 'm2'), 'status', 'skipped'),
    jsonb_build_object('id', pg_temp.ob(5, 'm3'), 'status', 'skipped'),
    -- 아직 잡지 않은 줄, 잘못된 상태 값은 무시
    jsonb_build_object('id', pg_temp.ob(6, 'm2'), 'status', 'sent'),
    jsonb_build_object('id', pg_temp.ob(2, 'm2'), 'status', 'pending')
  ),
  array['tok-e2-a']) = 6, 'finish updates claimed rows only');
reset role;
select pg_temp.check((select status = 'sent' and sent_at is not null from public.notification_outbox where id = pg_temp.ob(5, 'm1')), 'sent');
select pg_temp.check((select bool_and(status = 'skipped' and sent_at is not null) from public.notification_outbox
  where id in (pg_temp.ob(2, 'm1'), pg_temp.ob(3, 'm1'), pg_temp.ob(6, 'm1'), pg_temp.ob(5, 'm2'), pg_temp.ob(5, 'm3'))), 'skipped with time');
select pg_temp.check((select status = 'pending' from public.notification_outbox where id = pg_temp.ob(6, 'm2')), 'unclaimed row untouched');
select pg_temp.check((select status = 'failed' from public.notification_outbox where id = pg_temp.ob(2, 'm2')), 'bad status ignored (stays failed)');
-- 등록 안 된 토큰만 지워지고 같은 사람의 다른 기기는 남음 (I-03, SE-07)
select pg_temp.check(not exists (select 1 from public.device_tokens where token = 'tok-e2-a'), 'dead token removed');
select pg_temp.check(exists (select 1 from public.device_tokens where token = 'tok-e2-b'), 'other device kept');
-- 알림함은 그대로 (실패·건너뜀이어도)
select pg_temp.check((select count(*)::text from public.notifications where team_id = pg_temp.vid('P')) = pg_temp.v('before_n'), 'inbox unchanged');
select pg_temp.check((select read_at is null from public.notifications where kind = 'match_created' and user_id = pg_temp.u(5) and ref_id = pg_temp.vid('m1')), 'push does not mark read');

-- 회원 탈퇴하면 기기 주소·대기열이 같이 지워진다 (SE-23, J-02)
delete from auth.users where id = pg_temp.u(6);
select pg_temp.check(not exists (select 1 from public.notification_outbox where user_id = pg_temp.u(6)), 'deleted user outbox gone');
delete from auth.users where id = pg_temp.u(5);
select pg_temp.check(not exists (select 1 from public.device_tokens where user_id = pg_temp.u(5)), 'deleted user tokens gone');

-- ================================================================ 예약 작업·구조
select pg_temp.check((select schedule = '* * * * *' and command like '%private.call_cron_function(''notifier'')%'
  and command like '%status = ''pending''%' from cron.job where jobname = 'notifier'), 'notifier cron every minute, only when due');
select pg_temp.expect_error($$select private.call_cron_function('bogus')$$, 'unknown_function');
-- notifier 는 허용 목록에 있다 (배포 전이어도 요청만 실패. 이 트랜잭션은 롤백되어 요청이 나가지 않는다)
select private.call_cron_function('notifier');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.device_tokens'::regclass), 'RLS on device_tokens');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.notification_outbox'::regclass), 'RLS on outbox');
select pg_temp.check(not has_table_privilege('authenticated', 'public.notification_outbox', 'select'), 'app cannot read outbox');
select pg_temp.check(not has_table_privilege('authenticated', 'public.device_tokens', 'insert'), 'app cannot insert token directly');
select pg_temp.check(not has_table_privilege('anon', 'public.device_tokens', 'select'), 'anon cannot read tokens');
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%' and prosecdef)
  from pg_proc where pronamespace in ('public'::regnamespace, 'private'::regnamespace)
   and proname in ('claim_push_batch', 'finish_push_batch', 'call_cron_function')), 'definer search_path fixed');
select pg_temp.check((select count(*) = 3 from pg_proc where pronamespace in ('public'::regnamespace, 'private'::regnamespace)
   and proname in ('claim_push_batch', 'finish_push_batch', 'call_cron_function')), 'functions present');

select 'ALL PASSED' as result;
