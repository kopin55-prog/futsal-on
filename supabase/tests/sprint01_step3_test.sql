-- 스프린트 01 3단계 마이그레이션(202611050015) 동작 확인 스크립트.
-- 글자 수 상한은 데이터베이스에서 코드 포인트 × 8 로만 본다 (data-model.md 11장 14번). 정확한 글자 수는 앱이 검사한다.
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
  ('00000000-0000-4000-8000-0000000000c1', 'authenticated', 'authenticated', 'c1@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000c2', 'authenticated', 'authenticated', 'c2@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000c3', 'authenticated', 'authenticated', 'c3@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000c4', 'authenticated', 'authenticated', 'c4@test.invalid', now(), now());

set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-0000000000c1');
select public.create_profile('일번', '안녕', array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000c2');
select public.create_profile('이번', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000c3');
select public.create_profile('삼번', null, array['winger']::public.play_position[], false, true, true, true, false);

-- 팀 만들기: c1 팀장, c2 운영진, c3 팀원
select pg_temp.login('00000000-0000-4000-8000-0000000000c1');
insert into t_vars select 'team', public.create_team('코코FC', 3::smallint, '20:00', '22:00', null)::text;
insert into t_vars select 'code', team_code from public.teams where id = (select v::uuid from t_vars where k = 'team');
select pg_temp.login('00000000-0000-4000-8000-0000000000c2');
insert into t_vars select 'r2', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000c3');
insert into t_vars select 'r3', public.request_join((select v from t_vars where k = 'code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000c1');
select public.decide_join_request((select v::uuid from t_vars where k = 'r2'), true);
select public.decide_join_request((select v::uuid from t_vars where k = 'r3'), true);
select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000c2');

-- ================================================================ 팀 정보 수정
-- 운영진: 이름·운동일·모집. 로고 글자는 이름 기본값 규칙으로 자동 갱신 (Q-047)
select pg_temp.login('00000000-0000-4000-8000-0000000000c2');
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '  번개   FC ', 5::smallint, '22:00', '00:30', false);
select pg_temp.check((select name = '번개 FC' and logo_text = '번개' and regular_weekday = 5
    and regular_start_time = '22:00' and regular_end_time = '00:30' and not is_recruiting
  from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'manager updates info, logo auto');
-- 운영진은 로고 글자를 못 바꾼다 (Q-014). 아무것도 저장되지 않는다.
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '천둥FC', 5::smallint, '22:00', '00:30', true, 'KK')$$, 'not_permitted');
select pg_temp.check((select name = '번개 FC' and not is_recruiting from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'rejected call saved nothing');
-- 팀원은 못 고친다
select pg_temp.login('00000000-0000-4000-8000-0000000000c3');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '천둥FC', null, null, null, true)$$, 'not_permitted');
-- 팀 밖 사람도 못 고친다 (프로필 없는 사람 포함)
select pg_temp.login('00000000-0000-4000-8000-0000000000c4');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '천둥FC', null, null, null, true)$$, 'profile_required');

-- 팀장: 이름과 로고 글자를 함께. 넣은 로고 글자가 남는다 (이름 변경 뒤에 저장)
select pg_temp.login('00000000-0000-4000-8000-0000000000c1');
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '천둥FC', 5::smallint, '22:00', '00:30', true, ' KK ');
select pg_temp.check((select name = '천둥FC' and logo_text = 'KK' and is_recruiting from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'owner sets logo with rename');
-- 직접 바꾼 로고는 이름을 바꿔도 그대로
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '폭풍FC', 5::smallint, '22:00', '00:30', true);
select pg_temp.check((select logo_text = 'KK' from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'custom logo kept on rename');
-- 지금 이름 기본값으로 되돌리면 다시 자동 갱신 대상 (Q-047)
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '폭풍FC', 5::smallint, '22:00', '00:30', true, '폭풍');
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '바람FC', 5::smallint, '22:00', '00:30', true);
select pg_temp.check((select logo_text = '바람' from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'reset logo follows rename again');
-- 같은 이름의 기본값과 같은 글자를 이름 변경과 함께 넣어도 넣은 값이 남는다
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', 5::smallint, '22:00', '00:30', true, '바람');
select pg_temp.check((select name = '구름FC' and logo_text = '바람' from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'explicit logo wins over auto');

-- 잘못된 값
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '', null, null, null, true)$$, 'invalid_team_name');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), repeat('가', 81), null, null, null, true)$$, 'invalid_team_name');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), E'코코\nFC', null, null, null, true)$$, 'invalid_team_name');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), null, null, null, null, true)$$, 'invalid_team_name');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', 1::smallint, '22:00', '22:00', true)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', null, '20:00', null, true)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', 8::smallint, null, null, true)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', null, null, null, null)$$, 'invalid_team_info');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', null, null, null, true, 'ABC')$$, 'invalid_logo_text');
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '팀', null, null, null, true, '  ')$$, 'invalid_logo_text');
select pg_temp.check((select name = '구름FC' from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'invalid calls saved nothing');
-- 운동일 지우기 가능
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', null, null, null, true);
select pg_temp.check((select regular_weekday is null and regular_start_time is null from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'schedule cleared');

-- ================================================================ 시작 시각 변경과 경기 설정 저장 규칙
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', 3::smallint, '20:00', '22:00', true);
-- 0일 전 09:00 자동 생성, 10시간 전 마감 → 20:00 경기면 10:00 마감이라 허용
select public.update_team_settings((select v::uuid from t_vars where k = 'team'), null, 10, 0, '09:00');
-- 시작을 18:00 으로 당기면 마감 08:00 < 생성 09:00 → 거절
select pg_temp.expect_error($$select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', 3::smallint, '18:00', '22:00', true)$$, 'deadline_before_auto_create');
-- 표 직접 수정 경로도 같은 규칙
select pg_temp.expect_error($$update public.teams set regular_start_time = '18:00' where id = (select v::uuid from t_vars where k = 'team')$$, 'deadline_before_auto_create');
select pg_temp.check((select regular_start_time = '20:00' from public.teams where id = (select v::uuid from t_vars where k = 'team')), 'start time unchanged');
-- 시작을 늦추는 것은 허용, 시작 시각을 지우는 것도 허용 (자동 생성 없음)
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', 3::smallint, '21:00', '23:00', true);
select public.update_team_info((select v::uuid from t_vars where k = 'team'), '구름FC', 3::smallint, null, null, true);

-- ================================================================ 프로필 한 번에 저장
select public.update_own_profile('  새  이름 ', '  반가워요 ', array['goalkeeper', 'forward']::public.play_position[], true);
select pg_temp.check((select display_name = '새 이름' and bio = '반가워요' from public.profiles where user_id = auth.uid()), 'profile saved');
select pg_temp.check((select positions = array['goalkeeper', 'forward']::public.play_position[] and is_dedicated_gk
  from public.profile_play_prefs where user_id = auth.uid()), 'prefs saved');
-- 빈 자기소개는 비움
select public.update_own_profile('새 이름', '   ', array['goalkeeper']::public.play_position[], false);
select pg_temp.check((select bio is null from public.profiles where user_id = auth.uid()), 'blank bio -> null');
-- 포지션이 잘못되면 이름도 저장되지 않는다 (원자적)
select pg_temp.expect_error($$select public.update_own_profile('다른이름', '소개', array['forward', 'midfielder', 'winger', 'defender']::public.play_position[], false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.update_own_profile('다른이름', '소개', array['forward']::public.play_position[], true)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.update_own_profile('다른이름', '소개', array[]::public.play_position[], false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.update_own_profile('다른이름', '소개', null, false)$$, 'invalid_positions');
select pg_temp.check((select display_name = '새 이름' and bio is null from public.profiles where user_id = auth.uid()), 'name not saved when positions invalid');
-- 이름이 잘못되면 포지션도 저장되지 않는다
select pg_temp.expect_error($$select public.update_own_profile(repeat('가', 65), null, array['forward']::public.play_position[], false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.update_own_profile('', null, array['forward']::public.play_position[], false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.update_own_profile('이름', E'한\n줄', array['forward']::public.play_position[], false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.update_own_profile('이름', repeat('가', 161), array['forward']::public.play_position[], false)$$, 'invalid_profile');
select pg_temp.check((select positions = array['goalkeeper']::public.play_position[] from public.profile_play_prefs where user_id = auth.uid()), 'prefs not saved when name invalid');
-- 다른 사람 것은 바뀌지 않는다 (본인만)
select pg_temp.check((select display_name = '이번' from public.profiles where user_id = '00000000-0000-4000-8000-0000000000c2'), 'others untouched');
-- 프로필 없는 사람은 거절
select pg_temp.login('00000000-0000-4000-8000-0000000000c4');
select pg_temp.expect_error($$select public.update_own_profile('사번', null, array['forward']::public.play_position[], false)$$, 'profile_required');

-- ================================================================ 실행 권한
reset role;
select pg_temp.check(not has_function_privilege('anon', 'public.update_team_info(uuid, text, smallint, time, time, boolean, text)', 'execute'), 'anon cannot update team');
select pg_temp.check(not has_function_privilege('anon', 'public.update_own_profile(text, text, public.play_position[], boolean)', 'execute'), 'anon cannot update profile');
select pg_temp.check(has_function_privilege('authenticated', 'public.update_own_profile(text, text, public.play_position[], boolean)', 'execute'), 'authenticated can update profile');

select 'ALL PASSED' as result;
