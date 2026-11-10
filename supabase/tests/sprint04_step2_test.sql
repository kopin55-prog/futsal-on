-- 스프린트 04 2단계 마이그레이션(202611050065) 동작 확인 스크립트.
--   claim_push_batch 가 injury_return_check 줄에 받는 사람의 진행 중 부상 여부·그 일정 참석 응답을 돌려준다
--   (조용한 시간으로 늦게 나갈 복귀 확인 푸시 건너뛰기 재료, lead 결정 2026-11-10).
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
  select ('00000000-0000-4000-8000-0000000043' || lpad(p_n::text, 2, '0'))::uuid
$$;

create function pg_temp.kday(p_days int)
returns date
language sql
as $$
  select (now() at time zone 'Asia/Seoul')::date + p_days
$$;

-- ---------------------------------------------------------------------------
-- 준비: 팀 P (u1 팀장, u2·u3·u4·u5 팀원). 부상 동의: u2·u3·u4. u5 는 부상 없음
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'i43' || n || '@test.invalid', now(), now()
  from generate_series(1, 5) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, true);
select pg_temp.login(pg_temp.u(5));
select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);

select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('복귀푸시FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(2)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(3)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(4)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(5)); select public.request_join(pg_temp.v('codeP'), 'code');
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(r.id, true) from public.join_requests r where r.team_id = pg_temp.vid('P');
reset role;

-- u2·u3·u4: 진행 중 부상, 예상 복귀일 지남 (서버 권한으로 과거 날짜 준비)
insert into public.injuries (user_id, started_on, expected_return_on)
select pg_temp.u(n), pg_temp.kday(-14), pg_temp.kday(-1) from generate_series(2, 4) n;

-- 3일 뒤 경기 → 복귀 확인 알림 u2·u3·u4
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, capacity)
  values (pg_temp.vid('P'), 'auto', now() + interval '3 days', now() + interval '3 days 2 hours',
          now() + interval '2 days', 12)
  returning id)
insert into t_vars select 'm1', id::text from x;
select pg_temp.check((select count(*) = 3 from public.notifications
                       where kind = 'injury_return_check' and ref_id = pg_temp.vid('m1')), 'return checks created');

-- 알림이 생긴 뒤(푸시 전): u3 은 회복, u4 는 불참 응답(부상 유지), u2 는 그대로. u5 는 참석 응답(복귀 확인 대상 아님)
set local role authenticated;
select pg_temp.login(pg_temp.u(3)); select public.recover_injury();
select pg_temp.login(pg_temp.u(4)); select public.respond_attendance(pg_temp.vid('m1'), false);
select pg_temp.login(pg_temp.u(5)); select public.respond_attendance(pg_temp.vid('m1'), true);
reset role;

-- 조용한 시간이면 13:00 로 미뤄지므로 지금 보내게 당긴다
update public.notification_outbox o set send_at = now()
  from public.notifications n
 where n.id = o.notification_id and n.ref_id = pg_temp.vid('m1');

-- ---------------------------------------------------------------------------
-- 1. claim_push_batch 가 받는 사람의 부상·응답 상태를 돌려준다 (injury_return_check 만)
-- ---------------------------------------------------------------------------
create temp table t_claimed as
select c.*, n.user_id as recipient
  from public.claim_push_batch(500) c
  join public.notifications n on n.id = c.notification_id;

select pg_temp.check((select recipient_injury_active is true and recipient_rsvp_state is null from t_claimed
                       where kind = 'injury_return_check' and recipient = pg_temp.u(2)), 'still injured, no response');
select pg_temp.check((select recipient_injury_active is false and recipient_rsvp_state is null from t_claimed
                       where kind = 'injury_return_check' and recipient = pg_temp.u(3)), 'recovered before push');
select pg_temp.check((select recipient_injury_active is true and recipient_rsvp_state = 'declined' from t_claimed
                       where kind = 'injury_return_check' and recipient = pg_temp.u(4)), 'responded before push');
select pg_temp.check((select count(*) = 3 from t_claimed where kind = 'injury_return_check' and ref_id = pg_temp.vid('m1')),
                     'three return check rows');
-- 다른 종류(일정 생성 알림 등)는 null (u5 는 참석했지만 칸은 비어 있음)
select pg_temp.check((select count(*) > 0 and bool_and(recipient_injury_active is null and recipient_rsvp_state is null)
                        from t_claimed where kind <> 'injury_return_check' and ref_id = pg_temp.vid('m1')), 'other kinds null');
select pg_temp.check((select coalesce(bool_and(recipient_injury_active is null and recipient_rsvp_state is null), true)
                        from t_claimed where kind <> 'injury_return_check'), 'all non return-check rows null');
-- 기존 칸은 그대로
select pg_temp.check((select bool_and(match_status = 'scheduled' and recipient_active and lineup_status is null)
                        from t_claimed where ref_id = pg_temp.vid('m1')), 'existing columns kept');

-- ---------------------------------------------------------------------------
-- 2. 권한·설정 그대로
-- ---------------------------------------------------------------------------
select pg_temp.check(has_function_privilege('service_role', 'public.claim_push_batch(int)', 'execute')
                     and not has_function_privilege('authenticated', 'public.claim_push_batch(int)', 'execute')
                     and not has_function_privilege('anon', 'public.claim_push_batch(int)', 'execute'), 'claim grants');
select pg_temp.check((select p.prosecdef and p.proconfig @> array['search_path=""']
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname = 'claim_push_batch'), 'definer search_path fixed');

select 'ALL PASSED' as result;
