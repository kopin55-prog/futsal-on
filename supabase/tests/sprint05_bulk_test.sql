-- 큰 팀 관리 서버 함수(202611050068, Q-079 3번 b·c) 동작 확인 스크립트.
--   - decide_join_requests: 팀장·운영진만, 신청 순서대로 승인, 정원 100명·사람당 팀 10개에 걸린 신청은 대기로 남김,
--     이미 처리된 신청·다른 팀 신청은 건너뜀, 거절, 사람마다 알림 (단건과 같음)
--   - set_skill_levels: 팀장·운영진만, 현재 팀원만(하나라도 아니면 아무것도 안 씀), 미정이면 지움
--   - 단건 decide_join_request 는 그대로
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

create function pg_temp.login(p_uid uuid)
returns void
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

create temp table t_vars (k text primary key, v text);
grant all on t_vars to authenticated, anon;

create function pg_temp.vid(p_k text)
returns uuid
language sql
as $$
  select v::uuid from t_vars where k = p_k
$$;

create function pg_temp.v(p_k text)
returns text
language sql
as $$
  select v from t_vars where k = p_k
$$;

create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000068' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- 신청 결과를 "번호:결과" 로 (정렬)
create temp table t_res (request_id uuid, result text);
grant all on t_res to authenticated;

create function pg_temp.res()
returns text
language sql
as $$
  select string_agg(coalesce(k.k, '?') || ':' || r.result, ',' order by coalesce(k.k, '?'))
    from t_res r left join t_vars k on k.v = r.request_id::text
$$;

create function pg_temp.cnt(p_kind text, p_n int)
returns int
language sql
security definer
as $$
  select count(*)::int from public.notifications n
   where n.user_id = pg_temp.u(p_n) and n.kind::text = p_kind
$$;

create function pg_temp.status(p_k text)
returns text
language sql
security definer
as $$
  select status::text from public.join_requests where id = (select v::uuid from t_vars where k = p_k)
$$;

-- ---------------------------------------------------------------------------
-- 함수 모양
-- ---------------------------------------------------------------------------
select pg_temp.check((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where (n.nspname, p.proname) in (('public', 'decide_join_requests'), ('public', 'set_skill_levels'),
                                                        ('public', 'decide_join_request'), ('private', 'apply_join_decision'))),
                     'security definer with empty search_path');
select pg_temp.check((select count(*) = 4
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where (n.nspname, p.proname) in (('public', 'decide_join_requests'), ('public', 'set_skill_levels'),
                                                        ('public', 'decide_join_request'), ('private', 'apply_join_decision'))),
                     'four functions');
select pg_temp.check(not has_function_privilege('anon', 'public.decide_join_requests(uuid, uuid[], boolean)', 'execute'), 'anon cannot bulk decide');
select pg_temp.check(not has_function_privilege('anon', 'public.set_skill_levels(uuid, uuid[], public.skill_level)', 'execute'), 'anon cannot bulk skill');
select pg_temp.check(has_function_privilege('authenticated', 'public.decide_join_requests(uuid, uuid[], boolean)', 'execute'), 'authenticated bulk decide');
select pg_temp.check(not has_function_privilege('authenticated', 'private.apply_join_decision(public.join_requests, boolean, uuid)', 'execute'), 'private helper not callable');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.join_requests'::regclass)
                     and (select relrowsecurity from pg_class where oid = 'public.skill_ratings'::regclass), 'RLS on');

-- ---------------------------------------------------------------------------
-- 준비: u1 팀장, u2 운영진, u3 팀원, u4~u10 신청자, u12 다른 팀 팀장
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'b68' || n || '@test.invalid', now(), now()
  from generate_series(1, 12) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(n)), public.create_profile('사람' || n, null, array['forward']::public.play_position[], false, true, true, true, false)
  from generate_series(1, 12) n;
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'A', public.create_team('일괄테스트A')::text;
select pg_temp.login(pg_temp.u(12));
insert into t_vars select 'B', public.create_team('일괄테스트B')::text;
reset role;
insert into t_vars select 'codeA', team_code from public.teams where id = pg_temp.vid('A');
insert into t_vars select 'codeB', team_code from public.teams where id = pg_temp.vid('B');
insert into public.team_members (team_id, user_id, role, status) values
  (pg_temp.vid('A'), pg_temp.u(2), 'manager', 'active'),
  (pg_temp.vid('A'), pg_temp.u(3), 'member', 'active');

-- ---------------------------------------------------------------------------
-- 1. 신청 순서대로 승인, 사람당 팀 10개에 걸린 신청은 대기로
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'r4', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login(pg_temp.u(9)); insert into t_vars select 'r9', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'r5', public.request_join(pg_temp.v('codeA'), 'code')::text;
-- u4 는 팀 B 에도 신청 (다른 팀 신청은 A 처리에서 건너뜀)
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'r4b', public.request_join(pg_temp.v('codeB'), 'code')::text;
reset role;
-- 신청 시각은 트리거가 고정한다(한 트랜잭션 안에서는 모두 같은 now()). 신청 순서를 만들기 위해 테스트에서만 잠시 끈다.
alter table public.join_requests disable trigger join_requests_before_write;
update public.join_requests set created_at = now() - interval '3 hours' where id = pg_temp.vid('r4');
update public.join_requests set created_at = now() - interval '2 hours' where id = pg_temp.vid('r9');
update public.join_requests set created_at = now() - interval '1 hours' where id = pg_temp.vid('r5');
alter table public.join_requests enable trigger join_requests_before_write;
select pg_temp.check((select created_at < now() - interval '2 hours' from public.join_requests where id = pg_temp.vid('r4')), 'created_at set for ordering');
-- u9 는 신청 뒤 다른 팀 10개에 들어감 (u12 가 팀 9개를 더 만든다)
set local role authenticated;
select pg_temp.login(pg_temp.u(12));
select public.create_team('채움팀' || g) from generate_series(1, 9) g;
reset role;
insert into public.team_members (team_id, user_id, role, status)
select t.id, pg_temp.u(9), 'member', 'active' from public.teams t
 where t.id in (select team_id from public.team_members where user_id = pg_temp.u(12) and status = 'active');
select pg_temp.check((select count(*) = 10 from public.team_members where user_id = pg_temp.u(9) and status = 'active'), 'u9 in 10 teams');

-- 팀원은 못 함
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select * from public.decide_join_requests(pg_temp.vid('A'), array[pg_temp.vid('r4')], true)$$, 'not_permitted');
-- 다른 팀 팀장도 A 는 못 함
select pg_temp.login(pg_temp.u(12));
select pg_temp.expect_error($$select * from public.decide_join_requests(pg_temp.vid('A'), array[pg_temp.vid('r4')], true)$$, 'not_permitted');
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select * from public.decide_join_requests(pg_temp.vid('A'), array[pg_temp.vid('r4')], null)$$, 'invalid_decision');
-- 빈 목록은 아무 일 없음
select pg_temp.check((select count(*) = 0 from public.decide_join_requests(pg_temp.vid('A'), '{}', true)), 'empty list');
select pg_temp.check((select count(*) = 0 from public.decide_join_requests(pg_temp.vid('A'), null, true)), 'null list');

-- 운영진이 순서를 섞어 보내도 신청 순서대로
insert into t_res select * from public.decide_join_requests(pg_temp.vid('A'),
  array[pg_temp.vid('r5'), pg_temp.vid('r9'), pg_temp.vid('r4'), pg_temp.vid('r4b'), pg_temp.vid('r4')], true);
select pg_temp.check(pg_temp.res() = 'r4:approved,r4b:already_decided,r5:approved,r9:team_limit_reached', 'limit skip: ' || pg_temp.res());
reset role;
select pg_temp.check(pg_temp.status('r4') = 'approved' and pg_temp.status('r5') = 'approved', 'approved');
select pg_temp.check(pg_temp.status('r9') = 'pending', 'limit request stays pending');
select pg_temp.check(pg_temp.status('r4b') = 'pending', 'other team request untouched');
select pg_temp.check((select decided_by = pg_temp.u(2) from public.join_requests where id = pg_temp.vid('r4')), 'decided_by');
select pg_temp.check((select count(*) = 1 from public.team_members where team_id = pg_temp.vid('A') and user_id = pg_temp.u(4) and status = 'active'), 'u4 member');
select pg_temp.check(not exists (select 1 from public.team_members where team_id = pg_temp.vid('A') and user_id = pg_temp.u(9)), 'u9 not member');
-- 알림: 신청자마다 1번, 합류 알림은 팀원에게 사람마다
select pg_temp.check(pg_temp.cnt('join_request_decided', 4) = 1 and pg_temp.cnt('join_request_decided', 5) = 1, 'decided notice each');
select pg_temp.check(pg_temp.cnt('join_request_decided', 9) = 0, 'no notice for skipped');
select pg_temp.check(pg_temp.cnt('member_joined', 3) = 2, 'member_joined per person to member');
select pg_temp.check(pg_temp.cnt('member_joined', 4) = 1, 'u4 told about u5 only');
select pg_temp.check((select bool_and(n.body like '%승인됐어요%') from public.notifications n
                       where n.kind = 'join_request_decided' and n.user_id in (pg_temp.u(4), pg_temp.u(5))), 'approved text');

-- ---------------------------------------------------------------------------
-- 2. 정원 100명: 들어갈 수 있는 만큼 신청 순서대로, 나머지는 대기로
-- ---------------------------------------------------------------------------
-- 지금 5명(u1~u5) → 채움 93명 = 98명
insert into auth.users (id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-9068-' || lpad(g::text, 12, '0'))::uuid, 'authenticated', 'authenticated', 'f68' || g || '@test.invalid', now(), now()
  from generate_series(1, 93) g;
insert into public.profiles (user_id, display_name, age_14_confirmed_at)
select ('00000000-0000-4000-9068-' || lpad(g::text, 12, '0'))::uuid, '채움' || g, now() from generate_series(1, 93) g;
insert into public.team_members (team_id, user_id, role, status)
select pg_temp.vid('A'), ('00000000-0000-4000-9068-' || lpad(g::text, 12, '0'))::uuid, 'member', 'active'
  from generate_series(1, 93) g;
select pg_temp.check((select count(*) = 98 from public.team_members where team_id = pg_temp.vid('A') and status = 'active'), '98 members');

set local role authenticated;
select pg_temp.login(pg_temp.u(6)); insert into t_vars select 'r6', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login(pg_temp.u(7)); insert into t_vars select 'r7', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login(pg_temp.u(8)); insert into t_vars select 'r8', public.request_join(pg_temp.v('codeA'), 'code')::text;
select pg_temp.login(pg_temp.u(10)); insert into t_vars select 'r10', public.request_join(pg_temp.v('codeA'), 'code')::text;
reset role;
alter table public.join_requests disable trigger join_requests_before_write;
update public.join_requests set created_at = now() - interval '40 minutes' where id = pg_temp.vid('r6');
update public.join_requests set created_at = now() - interval '30 minutes' where id = pg_temp.vid('r7');
update public.join_requests set created_at = now() - interval '20 minutes' where id = pg_temp.vid('r8');
update public.join_requests set created_at = now() - interval '10 minutes' where id = pg_temp.vid('r10');
alter table public.join_requests enable trigger join_requests_before_write;

truncate t_res;
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
insert into t_res select * from public.decide_join_requests(pg_temp.vid('A'),
  array[pg_temp.vid('r10'), pg_temp.vid('r8'), pg_temp.vid('r7'), pg_temp.vid('r6')], true);
select pg_temp.check(pg_temp.res() = 'r10:team_full,r6:approved,r7:approved,r8:team_full', 'capacity: ' || pg_temp.res());
reset role;
select pg_temp.check((select count(*) = 100 from public.team_members where team_id = pg_temp.vid('A') and status = 'active'), '100 members');
select pg_temp.check(pg_temp.status('r8') = 'pending' and pg_temp.status('r10') = 'pending', 'full requests stay pending');
select pg_temp.check(pg_temp.cnt('join_request_decided', 8) = 0 and pg_temp.cnt('join_request_decided', 10) = 0, 'no notice for full');
select pg_temp.check(pg_temp.cnt('join_request_decided', 6) = 1 and pg_temp.cnt('join_request_decided', 7) = 1, 'notice for approved');
-- 단건도 정원 그대로
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.decide_join_request(pg_temp.vid('r8'), true)$$, 'team_full');

-- ---------------------------------------------------------------------------
-- 3. 여러 명 거절 (정원과 무관), 이미 처리된 것·없는 것은 건너뜀
-- ---------------------------------------------------------------------------
truncate t_res;
insert into t_res select * from public.decide_join_requests(pg_temp.vid('A'),
  array[pg_temp.vid('r8'), pg_temp.vid('r10'), pg_temp.vid('r6'), pg_temp.vid('r9'), gen_random_uuid()], false);
select pg_temp.check(pg_temp.res() = '?:already_decided,r10:rejected,r6:already_decided,r8:rejected,r9:rejected', 'reject: ' || pg_temp.res());
reset role;
select pg_temp.check(pg_temp.status('r8') = 'rejected' and pg_temp.status('r10') = 'rejected' and pg_temp.status('r9') = 'rejected', 'rejected');
select pg_temp.check(pg_temp.status('r6') = 'approved', 'approved stays approved');
select pg_temp.check((select count(*) = 100 from public.team_members where team_id = pg_temp.vid('A') and status = 'active'), 'still 100');
select pg_temp.check(pg_temp.cnt('join_request_decided', 8) = 1 and pg_temp.cnt('join_request_decided', 9) = 1, 'reject notice each');
select pg_temp.check((select count(*) = 3 and bool_and(n.body like '%승인되지 않았어요%') from public.notifications n
                       where n.kind = 'join_request_decided' and n.user_id in (pg_temp.u(8), pg_temp.u(9), pg_temp.u(10))), 'rejected text');
select pg_temp.check(pg_temp.cnt('member_joined', 3) = 4, 'no member_joined for rejects');

-- ---------------------------------------------------------------------------
-- 4. 실력 등급 여러 명 한 번에
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(3), pg_temp.u(4), pg_temp.u(5), pg_temp.u(4), pg_temp.u(2)], 'pro');
reset role;
select pg_temp.check((select count(*) = 4 from public.skill_ratings where team_id = pg_temp.vid('A') and level = 'pro'
                       and updated_by = pg_temp.u(2)), 'four set (dedup, own included)');

set local role authenticated;
-- 팀원·다른 팀 팀장은 못 함
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(4)], 'beginner')$$, 'not_permitted');
select pg_temp.login(pg_temp.u(12));
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(4)], 'beginner')$$, 'not_permitted');
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(4)], null)$$, 'invalid_skill_level');
-- 현재 팀원이 아닌 사람(거절된 u8, 다른 팀 u12, null)이 하나라도 있으면 아무것도 안 씀
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(3), pg_temp.u(8)], 'beginner')$$, 'target_not_member');
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(3), pg_temp.u(12)], 'beginner')$$, 'target_not_member');
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(3), null], 'beginner')$$, 'target_not_member');
reset role;
select pg_temp.check((select level = 'pro' from public.skill_ratings where team_id = pg_temp.vid('A') and user_id = pg_temp.u(3)), 'nothing written on failure');

-- 떠난 팀원도 대상이 아니다
update public.team_members set status = 'left', ended_at = now() where team_id = pg_temp.vid('A') and user_id = pg_temp.u(7);
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(7)], 'beginner')$$, 'target_not_member');
-- 빈 목록은 아무 일 없음
select public.set_skill_levels(pg_temp.vid('A'), '{}', 'beginner');
select public.set_skill_levels(pg_temp.vid('A'), null, 'beginner');
-- 바꾸기, 미정은 지움
select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(3), pg_temp.u(6)], 'beginner');
select public.set_skill_levels(pg_temp.vid('A'), array[pg_temp.u(4), pg_temp.u(5)], 'undecided');
reset role;
select pg_temp.check((select level = 'beginner' and updated_by = pg_temp.u(1) from public.skill_ratings where team_id = pg_temp.vid('A') and user_id = pg_temp.u(3)), 'changed');
select pg_temp.check((select level = 'beginner' from public.skill_ratings where team_id = pg_temp.vid('A') and user_id = pg_temp.u(6)), 'new row');
select pg_temp.check(not exists (select 1 from public.skill_ratings where team_id = pg_temp.vid('A') and user_id in (pg_temp.u(4), pg_temp.u(5))), 'undecided deletes');
select pg_temp.check((select level = 'pro' from public.skill_ratings where team_id = pg_temp.vid('A') and user_id = pg_temp.u(2)), 'others untouched');
-- 팀원은 등급을 읽을 수 없다 (기존 권한 그대로)
set local role authenticated;
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select count(*) = 0 from public.skill_ratings), 'member cannot read ratings');
reset role;

select 'ALL PASSED' as result;
