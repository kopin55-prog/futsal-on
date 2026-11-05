-- 스프린트 01 2단계 마이그레이션(202611050009~0013) 동작 확인 스크립트.
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
grant all on t_vars to authenticated;

insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-4000-8000-0000000000b1', 'authenticated', 'authenticated', 'b1@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000b2', 'authenticated', 'authenticated', 'b2@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000b3', 'authenticated', 'authenticated', 'b3@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000b4', 'authenticated', 'authenticated', 'b4@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000b5', 'authenticated', 'authenticated', 'b5@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000b8', 'authenticated', 'authenticated', 'b8@test.invalid', now() - interval '2 days', now()),
  ('00000000-0000-4000-8000-0000000000b9', 'authenticated', 'authenticated', 'b9@test.invalid', now() - interval '1 hour', now());

set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select public.create_profile('일번', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select public.create_profile('이번', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000b3');
select public.create_profile('삼번', null, array['winger']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
select public.create_profile('사번', null, array['midfielder']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
select public.create_profile('오번', null, array['goalkeeper']::public.play_position[], false, true, true, true, false);

-- ================================================================ 팀 만들기 + 경기 설정 기본값
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
-- 이름만 (이전 호출 방식 그대로)
insert into t_vars select 'team0', public.create_team('이름만 팀')::text;
select pg_temp.check((select regular_weekday is null and logo_text = '이름' from public.teams where id = (select v::uuid from t_vars where k = 'team0')), 'name-only team');
-- 정기 운동일 + 로고 글자
insert into t_vars select 'team', public.create_team('코코 FC', 3::smallint, '20:00', '22:00', 'K')::text;
select pg_temp.check((select regular_weekday = 3 and regular_start_time = '20:00' and regular_end_time = '22:00' and logo_text = 'K'
  from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'team with schedule and logo');
select pg_temp.check((select rsvp_deadline_hours = 2 and auto_create_days_before = 6 and auto_create_time = '09:00' and capacity is null
  from public.team_settings where team_id = (select v::uuid from t_vars where k = 'team')), 'default settings (2h before, Q-066)');
select pg_temp.check((select count(*) = 2 from public.team_settings), 'owner sees settings of both teams');
-- 빈 로고 글자 = 기본값
insert into t_vars select 'team2', public.create_team('나나 FC', null, null, null, '  ')::text;
select pg_temp.check((select logo_text = '나나' from public.teams where id = (select v::uuid from t_vars where k = 'team2')), 'blank logo -> default');
select pg_temp.expect_error($$select public.create_team('팀', null, null, null, 'ABC')$$, 'invalid_logo_text');
select pg_temp.expect_error($$select public.create_team('팀', 1::smallint, '22:00', '22:00', null)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.create_team('팀', null, '20:00', null, null)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.create_team('', 1::smallint, null, null, null)$$, 'invalid_team_name');
-- 경기 설정 직접 쓰기 불가
select pg_temp.expect_error($$update public.team_settings set rsvp_deadline_hours = 5$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.team_settings (team_id) values (gen_random_uuid())$$, 'permission denied%');

-- 경기 설정 바꾸기
select public.update_team_settings((select v::uuid from t_vars where k = 'team'), 12, 24, 6, '09:00');
select pg_temp.check((select capacity = 12 and rsvp_deadline_hours = 24 and updated_by = auth.uid()
  from public.team_settings where team_id = (select v::uuid from t_vars where k = 'team')), 'settings updated');
-- 마감(경기 20:00 - 40h = 이틀 전 04:00)이 자동 생성(0일 전 09:00)보다 앞섬 → 거절
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 40, 0, '09:00')$$, 'deadline_before_auto_create');
-- 경계: 0일 전 09:00 생성, 20:00 경기, 11시간 전 마감 = 09:00 → 같으면 거절, 10시간이면 허용
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 11, 0, '09:00')$$, 'deadline_before_auto_create');
select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 10, 0, '09:00');
-- 정기 운동 시작 시각이 없는 팀은 자동 생성이 없으므로 검사 없음
select public.update_team_settings((select v::uuid from t_vars where k = 'team0'), null, 40, 0, '09:00');
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), 0, 2, 6, '09:00')$$, 'invalid_team_settings');
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, -1, 6, '09:00')$$, 'invalid_team_settings');
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, null, 6, '09:00')$$, 'invalid_team_settings');

-- ================================================================ 팀원 모으기: b2·b3·b4·b5 가입
insert into t_vars select 'code', team_code from public.teams where id = (select v::uuid from t_vars where k = 'team');
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
insert into t_vars select 'r2', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
-- 팀 밖에서는 경기 설정을 못 본다
select pg_temp.check((select count(*) = 0 from public.team_settings), 'outsider cannot read settings');
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 2, 6, '09:00')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000b3');
insert into t_vars select 'r3', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
insert into t_vars select 'r4', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
insert into t_vars select 'r5', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select public.decide_join_request((select v::uuid from t_vars where k = 'r2'), true);
select public.decide_join_request((select v::uuid from t_vars where k = 'r3'), true);
select public.decide_join_request((select v::uuid from t_vars where k = 'r4'), true);
select public.decide_join_request((select v::uuid from t_vars where k = 'r5'), true);
select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b2');

-- 팀원은 경기 설정을 읽지만 고치지 못한다
select pg_temp.login('00000000-0000-4000-8000-0000000000b3');
select pg_temp.check((select count(*) = 1 from public.team_settings), 'member reads settings');
select pg_temp.expect_error($$select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 2, 6, '09:00')$$, 'not_permitted');
-- 운영진은 고칠 수 있다
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 2, 6, '09:00');

-- ================================================================ 실력 등급 (3-4)
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b3', 'pro');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b4', 'beginner');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b4', 'semipro');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), auth.uid(), 'amateur');
select pg_temp.check((select count(*) = 3 from public.skill_ratings), 'owner sees 3 ratings incl. own (Q-016)');
select pg_temp.check((select level = 'semipro' from public.skill_ratings where user_id = '00000000-0000-4000-8000-0000000000b4'), 'rating upsert');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), auth.uid(), 'undecided');
select pg_temp.check((select count(*) = 2 from public.skill_ratings), 'undecided removes row');
select pg_temp.expect_error($$select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b9', 'pro')$$, 'target_not_member');
select pg_temp.expect_error($$select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b3', null)$$, 'invalid_skill_level');
select pg_temp.expect_error($$insert into public.skill_ratings (team_id, user_id, level) values ((select v::uuid from t_vars where k = 'team'), auth.uid(), 'pro')$$, 'permission denied%');
-- 운영진은 읽고 쓴다
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select pg_temp.check((select count(*) = 2 from public.skill_ratings), 'manager reads ratings');
select public.set_skill_level((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b5', 'amateur');
-- 팀원은 본인 것도 못 읽는다 (Q-016)
select pg_temp.login('00000000-0000-4000-8000-0000000000b3');
select pg_temp.check((select count(*) = 0 from public.skill_ratings), 'member cannot read ratings, even own');
select pg_temp.expect_error($$select public.set_skill_level((select v::uuid from t_vars where k = 'team'), auth.uid(), 'pro')$$, 'not_permitted');

-- ================================================================ 그룹·라이벌 (3-7)
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
-- 그룹 b3+b4
insert into t_vars select 'g1', public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b4']::uuid[], true)::text;
-- 그룹 b4+b5 (b3-b4-b5 이어짐)
insert into t_vars select 'g2', public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b4','00000000-0000-4000-8000-0000000000b5']::uuid[], true)::text;
-- 라이벌 b3+b5: 간접 모순 → 거절, 아무것도 저장되지 않음
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'rival',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b5']::uuid[], true)$$, 'pairing_rule_conflict');
select pg_temp.check((select count(*) = 2 from public.pairing_rules), 'conflicting rule not saved');
-- 꺼진 라이벌로는 저장 가능
insert into t_vars select 'rv', public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'rival',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b5']::uuid[], false)::text;
-- 켜면 모순 → 거절
select pg_temp.expect_error($$select public.set_pairing_rule_enabled((select v::uuid from t_vars where k = 'rv'), true)$$, 'pairing_rule_conflict');
select pg_temp.check((select not is_enabled from public.pairing_rules where id = (select v::uuid from t_vars where k = 'rv')), 'rival still off');
-- 연결 고리 그룹 g2 를 끄면 라이벌을 켤 수 있다
select public.set_pairing_rule_enabled((select v::uuid from t_vars where k = 'g2'), false);
select public.set_pairing_rule_enabled((select v::uuid from t_vars where k = 'rv'), true);
-- 그런데 g2 를 다시 켜면 모순 → 거절
select pg_temp.expect_error($$select public.set_pairing_rule_enabled((select v::uuid from t_vars where k = 'g2'), true)$$, 'pairing_rule_conflict');
-- 직접 모순: 같은 두 사람 그룹+라이벌
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b5']::uuid[], true)$$, 'pairing_rule_conflict');
-- 사람 검사
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b3']::uuid[], true)$$, 'invalid_pairing_members');
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b3']::uuid[], true)$$, 'invalid_pairing_members');
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), null, 'group',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b9']::uuid[], true)$$, 'invalid_pairing_members');
-- 종류는 바꿀 수 없음
select pg_temp.expect_error($$select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), (select v::uuid from t_vars where k = 'g1'), 'rival',
  array['00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b4']::uuid[], true)$$, 'invalid_pairing_rule');
-- 사람 바꾸기: g1 을 b2+b3+b4 로
select public.save_pairing_rule((select v::uuid from t_vars where k = 'team'), (select v::uuid from t_vars where k = 'g1'), 'group',
  array['00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-0000000000b3','00000000-0000-4000-8000-0000000000b4']::uuid[], true);
select pg_temp.check((select count(*) = 3 from public.pairing_rule_members where rule_id = (select v::uuid from t_vars where k = 'g1')), 'g1 has 3 members');
-- 직접 쓰기 불가
select pg_temp.expect_error($$insert into public.pairing_rules (team_id, kind, is_enabled) values ((select v::uuid from t_vars where k = 'team'), 'group', true)$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.pairing_rule_members$$, 'permission denied%');
-- 팀원은 읽지도 못한다 (Q-017)
select pg_temp.login('00000000-0000-4000-8000-0000000000b3');
select pg_temp.check((select count(*) = 0 from public.pairing_rules), 'member cannot read rules');
select pg_temp.check((select count(*) = 0 from public.pairing_rule_members), 'member cannot read rule members');
select pg_temp.expect_error($$select public.delete_pairing_rule((select v::uuid from t_vars where k = 'g1'))$$, 'not_permitted');
-- 운영진은 읽는다
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select pg_temp.check((select count(*) = 3 from public.pairing_rules), 'manager reads rules');

-- ================================================================ 팀 탈퇴·내보내기 정리 (3-8, Q-015)
-- b5 탈퇴: 등급 삭제, g2(b4+b5) 와 rv(b3+b5) 에서 빠져 1명 → 꺼짐
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
select public.leave_team((select v::uuid from t_vars where k = 'team'));
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where user_id = '00000000-0000-4000-8000-0000000000b5'), 'leaver rating deleted');
select pg_temp.check((select count(*) = 0 from public.pairing_rule_members where user_id = '00000000-0000-4000-8000-0000000000b5'), 'leaver removed from rules');
select pg_temp.check((select not is_enabled from public.pairing_rules where id = (select v::uuid from t_vars where k = 'rv')), 'rival with 1 left is disabled');
select pg_temp.expect_error($$select public.set_pairing_rule_enabled((select v::uuid from t_vars where k = 'rv'), true)$$, 'invalid_pairing_members');
-- b4 내보내기: 등급 삭제, g1 은 b2+b3 남아 켜진 채
select public.remove_member((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000b4');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where user_id = '00000000-0000-4000-8000-0000000000b4'), 'removed rating deleted');
select pg_temp.check((select is_enabled from public.pairing_rules where id = (select v::uuid from t_vars where k = 'g1')), 'g1 still on with 2');
select pg_temp.check((select count(*) = 2 from public.pairing_rule_members where rule_id = (select v::uuid from t_vars where k = 'g1')), 'g1 has 2 members');
-- 재가입하면 미정부터 (줄 없음)
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
insert into t_vars select 'r5b', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select public.decide_join_request((select v::uuid from t_vars where k = 'r5b'), true);
select pg_temp.check((select count(*) = 0 from public.skill_ratings where user_id = '00000000-0000-4000-8000-0000000000b5'), 'rejoin starts undecided');
-- 삭제
select public.delete_pairing_rule((select v::uuid from t_vars where k = 'g2'));
select pg_temp.check((select count(*) = 2 from public.pairing_rules), 'rule deleted');

-- ================================================================ Q-067 4번: 자정 넘김
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
insert into t_vars select 'night', public.create_team('야간팀', 5::smallint, '22:00', '00:30')::text;
select pg_temp.check((select regular_end_time = '00:30' from public.teams where id = (select v::uuid from t_vars where k = 'night')), 'midnight crossing allowed');
select pg_temp.expect_error($$select public.create_team('같은시각', 5::smallint, '22:00', '22:00')$$, 'invalid_regular_schedule');

-- ================================================================ Q-067 10번: 중복 신청·취소
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code'), 'code')$$, 'already_member');
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
insert into t_vars select 'r4b', public.request_join((select v from t_vars where k = 'code'), 'search')::text;
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code'), 'code')$$, 'request_already_pending');
select pg_temp.check((select count(*) = 1 from public.list_my_pending_join_requests() where team_code = (select v from t_vars where k = 'code') and team_name = '코코 FC'), 'my pending list');
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select pg_temp.expect_error($$select public.cancel_join_request((select v::uuid from t_vars where k = 'r4b'))$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
select public.cancel_join_request((select v::uuid from t_vars where k = 'r4b'));
select pg_temp.check((select status = 'cancelled' from public.join_requests where id = (select v::uuid from t_vars where k = 'r4b')), 'cancelled');
select pg_temp.check((select count(*) = 0 from public.list_my_pending_join_requests()), 'pending list empty');
select pg_temp.expect_error($$select public.cancel_join_request((select v::uuid from t_vars where k = 'r4b'))$$, 'request_not_pending');
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select pg_temp.expect_error($$select public.decide_join_request((select v::uuid from t_vars where k = 'r4b'), true)$$, 'request_not_pending');

-- ================================================================ Q-067 5번: 소속 최대 10팀
-- b1 은 지금 4팀(team0, team, team2, night). 6개 더 만들면 10개, 11번째는 거절.
select public.create_team('추가' || g) from generate_series(1, 6) g;
select pg_temp.expect_error($$select public.create_team('열한번째')$$, 'team_limit_reached');
-- 10팀 소속인 사람의 신청도 거절
reset role;
insert into t_vars select 'code0', team_code from public.teams where id = (select v::uuid from t_vars where k = 'team0');
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
insert into t_vars select 'r4c', public.request_join((select v from t_vars where k = 'code0'), 'code')::text;
-- b4 가 10팀에 소속되도록 서버 권한으로 채운다
reset role;
insert into public.teams (name, team_code, created_by)
select '채움' || g, upper(substr(translate(encode(extensions.gen_random_bytes(8), 'hex'), '01', '23'), 1, 6)), null from generate_series(1, 10) g;
insert into public.team_members (team_id, user_id, role, status)
select t.id, '00000000-0000-4000-8000-0000000000b4', 'owner', 'active' from public.teams t where t.name like '채움%' and t.created_by is null and t.created_at = now()
   and not exists (select 1 from public.team_members m where m.team_id = t.id);
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select pg_temp.expect_error($$select public.decide_join_request((select v::uuid from t_vars where k = 'r4c'), true)$$, 'team_limit_reached');
select pg_temp.check((select status = 'pending' from public.join_requests where id = (select v::uuid from t_vars where k = 'r4c')), 'request stays pending after limit');

-- ================================================================ Q-067 5번: 팀 최대 100명
reset role;
insert into auth.users (id, aud, role, email, created_at, updated_at)
select ('00000000-0000-4000-9000-' || lpad(g::text, 12, '0'))::uuid, 'authenticated', 'authenticated', 'f' || g || '@test.invalid', now(), now()
  from generate_series(1, 99) g;
insert into public.profiles (user_id, display_name, age_14_confirmed_at)
select ('00000000-0000-4000-9000-' || lpad(g::text, 12, '0'))::uuid, '채움' || g, now() from generate_series(1, 99) g;
insert into public.team_members (team_id, user_id, role, status)
select (select v::uuid from t_vars where k = 'team0'), ('00000000-0000-4000-9000-' || lpad(g::text, 12, '0'))::uuid, 'member', 'active'
  from generate_series(1, 99) g;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code0'), 'code')$$, 'team_full');

-- ================================================================ Q-067 7·8번: 팀 해체
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
insert into t_vars select 'code2', team_code from public.teams where id = (select v::uuid from t_vars where k = 'team2');
insert into t_vars select 'inv2', public.issue_team_invite((select v::uuid from t_vars where k = 'team2'));
-- team2 에 b2 를 팀원으로, b5 는 대기 신청
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
insert into t_vars select 'r2t2', public.request_join_by_invite((select v from t_vars where k = 'inv2'))::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select public.decide_join_request((select v::uuid from t_vars where k = 'r2t2'), true);
select public.set_skill_level((select v::uuid from t_vars where k = 'team2'), '00000000-0000-4000-8000-0000000000b2', 'pro');
select pg_temp.login('00000000-0000-4000-8000-0000000000b5');
insert into t_vars select 'r5t2', public.request_join((select v from t_vars where k = 'code2'), 'code')::text;
-- 팀원은 해체 불가
select pg_temp.login('00000000-0000-4000-8000-0000000000b2');
select pg_temp.expect_error($$select public.dissolve_team((select v::uuid from t_vars where k = 'team2'), '나나 FC')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000b1');
select pg_temp.expect_error($$select public.dissolve_team((select v::uuid from t_vars where k = 'team2'), '나나')$$, 'dissolve_confirmation_mismatch');
select pg_temp.expect_error($$select public.dissolve_team((select v::uuid from t_vars where k = 'team2'), null)$$, 'dissolve_confirmation_mismatch');
-- 앞뒤 공백·연속 공백·대소문자 무시
select public.dissolve_team((select v::uuid from t_vars where k = 'team2'), E'  나나   fc ');
select pg_temp.check((select count(*) = 0 from public.teams where id = (select v::uuid from t_vars where k = 'team2')), 'dissolved team hidden');
select pg_temp.check((select bool_and(status = 'dissolved') and count(*) = 1 from public.team_members where team_id = (select v::uuid from t_vars where k = 'team2')), 'owner sees own dissolved row only');
reset role;
select pg_temp.check((select count(*) = 2 and bool_and(status = 'dissolved') from public.team_members where team_id = (select v::uuid from t_vars where k = 'team2')), 'all members dissolved');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where team_id = (select v::uuid from t_vars where k = 'team2')), 'ratings deleted on dissolve');
select pg_temp.check((select status = 'rejected' and decided_by is null from public.join_requests where id = (select v::uuid from t_vars where k = 'r5t2')), 'pending auto-rejected');
select pg_temp.check((select count(*) = 0 from public.team_invites where team_id = (select v::uuid from t_vars where k = 'team2') and revoked_at is null), 'invites revoked');
-- 해체 되돌리기 불가
update public.teams set dissolved_at = null where id = (select v::uuid from t_vars where k = 'team2');
select pg_temp.check((select dissolved_at is not null from public.teams where id = (select v::uuid from t_vars where k = 'team2')), 'dissolve cannot be undone');
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-0000000000b4');
select pg_temp.expect_error($$select * from public.find_team_by_code((select v from t_vars where k = 'code2'))$$, 'team_dissolved');
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code2'), 'code')$$, 'team_dissolved');
select pg_temp.expect_error($$select * from public.get_invite_team((select v from t_vars where k = 'inv2'))$$, 'team_dissolved');
select pg_temp.expect_error($$select public.request_join_by_invite((select v from t_vars where k = 'inv2'))$$, 'team_dissolved');
select pg_temp.check((select count(*) = 0 from public.search_teams('나나')), 'dissolved not in search');
-- 해체한 팀은 탈퇴 차단 이유가 아니다 (b1 은 다른 팀 팀장이라 여전히 차단)

-- ================================================================ 서버 전용 함수는 앱이 못 부른다
select pg_temp.expect_error($$select * from public.list_profileless_accounts(10)$$, 'permission denied%');
select pg_temp.expect_error($$select public.delete_profileless_account(auth.uid())$$, 'permission denied%');

-- ================================================================ 회원 탈퇴: 그룹에서 빠지고 2명 미만이면 꺼짐 (2-5)
reset role;
set local role service_role;
select public.delete_account('00000000-0000-4000-8000-0000000000b3');
reset role;
select pg_temp.check((select not is_enabled from public.pairing_rules where id = (select v::uuid from t_vars where k = 'g1')), 'g1 disabled after account deletion');
select pg_temp.check((select count(*) = 0 from public.skill_ratings where user_id = '00000000-0000-4000-8000-0000000000b3'), 'deleted account rating gone');
select pg_temp.check((select count(*) = 1 from public.team_settings where team_id = (select v::uuid from t_vars where k = 'team') and updated_by = '00000000-0000-4000-8000-0000000000b2'), 'settings updated_by kept');

-- ================================================================ 프로필 없는 계정 정리 (서버 전용)
set local role service_role;
select pg_temp.check((select count(*) >= 1 from public.list_profileless_accounts(1000) where user_id = '00000000-0000-4000-8000-0000000000b8'), 'old profileless listed');
select pg_temp.check((select count(*) = 0 from public.list_profileless_accounts(1000) where user_id in ('00000000-0000-4000-8000-0000000000b9', '00000000-0000-4000-8000-0000000000b1')), 'recent / with-profile not listed');
select pg_temp.check(public.delete_profileless_account('00000000-0000-4000-8000-0000000000b9') = false, 'recent not deleted');
select pg_temp.check(public.delete_profileless_account('00000000-0000-4000-8000-0000000000b1') = false, 'with profile not deleted');
select pg_temp.check(public.delete_profileless_account('00000000-0000-4000-8000-0000000000b8') = true, 'old profileless deleted');
reset role;
select pg_temp.check((select count(*) = 0 from auth.users where id = '00000000-0000-4000-8000-0000000000b8'), 'b8 gone');
select pg_temp.check((select count(*) = 1 from auth.users where id = '00000000-0000-4000-8000-0000000000b1'), 'b1 kept');

select 'ALL PASSED' as result;
