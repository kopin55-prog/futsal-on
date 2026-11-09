-- 스프린트 02 4단계 서버 변경(Q-073 반영) 동작 확인 스크립트.
--   202611050031 자동 생성: 같은 시작 시각의 취소 안 된 일정이 있으면 안 만듦 (Q-073 1번)
--   202611050032 게스트 v4.4: 이름 선택·guest_no·12명·같은 표시 이름 불가 (Q-073 2·3번)
--   202611050033 내보내기 알림: 본인 + 팀장·운영진(내보낸 사람 제외) (Q-073 6번)
--   202611050034 정기 운동 종료 시각 필수 (Q-073 8번)
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

create function pg_temp.v(p_k text) returns text language sql as $$ select v from t_vars where k = p_k $$;
create function pg_temp.vid(p_k text) returns uuid language sql as $$ select v::uuid from t_vars where k = p_k $$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select ('00000000-0000-4000-8000-0000000000c' || p_n::text)::uuid
$$;

-- 게스트 "번호=이름" 목록 (번호 순, 이름 없으면 -)
create function pg_temp.guests(p_match text)
returns text
language sql
as $$
  select coalesce(string_agg(g.guest_no || '=' || coalesce(g.name, '-'), ',' order by g.guest_no), '')
    from public.match_guests g where g.match_id = pg_temp.vid(p_match)
$$;

insert into t_vars values
  ('d3', ((now() + interval '3 days') at time zone 'Asia/Seoul')::date::text),
  ('d4', ((now() + interval '4 days') at time zone 'Asia/Seoul')::date::text);

insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'c' || n || '@test.invalid', now(), now()
  from generate_series(1, 6) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2)); select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3)); select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4)); select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(5)); select public.create_profile('오', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(6)); select public.create_profile('육', null, array['forward']::public.play_position[], false, true, true, true, false);

-- 팀 P: c1 팀장, c2·c3 운영진, c4·c5 팀원. 정기 운동 없음
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'P', public.create_team('피FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(2)); insert into t_vars select 'r2', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(3)); insert into t_vars select 'r3', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(4)); insert into t_vars select 'r4', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(5)); insert into t_vars select 'r5', public.request_join(pg_temp.v('codeP'), 'code')::text;
select pg_temp.login(pg_temp.u(1));
select public.decide_join_request(pg_temp.vid(k), true) from unnest(array['r2', 'r3', 'r4', 'r5']) k;
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(2));
select public.appoint_manager(pg_temp.vid('P'), pg_temp.u(3));

-- ================================================================ A-1 자동 생성: 같은 시작 시각 (Q-073 1번)
-- 3일 뒤 10:00 일정을 먼저 직접 추가 → 그 요일 10:00~12:00 정기 운동을 정해도(생성 시각 지남·마감 전) 자동 일정 없음
insert into t_vars select 'm1', public.create_match(pg_temp.vid('P'), pg_temp.v('d3')::date, '10:00', pg_temp.v('d3')::date, '12:00')::text;
select public.update_team_info(pg_temp.vid('P'), '피FC', extract(isodow from pg_temp.v('d3')::date)::smallint, '10:00', '12:00', true, null);
reset role;
select pg_temp.check((select count(*) = 1 from public.matches
  where team_id = pg_temp.vid('P') and starts_at = (pg_temp.v('d3')::date + time '10:00') at time zone 'Asia/Seoul'), 'manual at same start blocks auto');
select pg_temp.check((select count(*) = 0 from public.matches where team_id = pg_temp.vid('P') and source = 'auto'), 'no auto match');
-- 예약 작업이 다시 돌아도 그대로
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('P')) = 0, 'cron run creates nothing');
-- 직접 추가 일정을 취소하면 (생성 시각 지남·마감 전이므로) 자동 일정이 생긴다
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.cancel_match(pg_temp.vid('m1'));
reset role;
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('P')) = 1, 'auto after manual cancelled');
select pg_temp.check((select count(*) = 1 from public.matches where team_id = pg_temp.vid('P') and source = 'auto' and status = 'scheduled'), 'one auto match');
select pg_temp.check(private.generate_auto_matches_for_team(pg_temp.vid('P')) = 0, 'no duplicate auto');

-- ================================================================ A-4 정기 운동 종료 시각 필수 (Q-073 8번)
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.update_team_info(pg_temp.vid('P'), '피FC', 3::smallint, '10:00', null, true, null)$$, 'invalid_regular_schedule');
select pg_temp.expect_error($$select public.create_team('끝없음FC', 3::smallint, '10:00', null)$$, 'invalid_regular_schedule');
-- 요일만 / 요일·시작·종료(자정 넘김) / 모두 비우기는 가능
select public.update_team_info(pg_temp.vid('P'), '피FC', 3::smallint, null, null, true, null);
select public.update_team_info(pg_temp.vid('P'), '피FC', 3::smallint, '22:00', '00:30', true, null);
select public.update_team_info(pg_temp.vid('P'), '피FC', null, null, null, true, null);
-- 운영진의 표 직접 수정도 같은 검사
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$update public.teams set regular_weekday = 3, regular_start_time = '10:00', regular_end_time = null where id = pg_temp.vid('P')$$, '%teams_regular_end_required%');
reset role;
-- 종료가 비어 있는 기존 팀(이전 데이터)은 정기 운동과 상관없는 수정은 그대로 된다
alter table public.teams disable trigger teams_regular_end_required;
update public.teams set regular_weekday = 3, regular_start_time = '10:00', regular_end_time = null where id = pg_temp.vid('P');
alter table public.teams enable trigger teams_regular_end_required;
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.update_team_info(pg_temp.vid('P'), '새이름FC', 3::smallint, '10:00', null, false, null);
reset role;
select pg_temp.check((select name = '새이름FC' and not is_recruiting and regular_end_time is null from public.teams where id = pg_temp.vid('P')), 'legacy team other edits ok');
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.update_team_info(pg_temp.vid('P'), '새이름FC', 4::smallint, '10:00', null, false, null)$$, 'invalid_regular_schedule');
select public.update_team_info(pg_temp.vid('P'), '피FC', null, null, null, true, null);

-- ================================================================ A-2 게스트 v4.4 (Q-073 2·3번)
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'g', public.create_match(pg_temp.vid('P'), pg_temp.v('d4')::date, '19:00', pg_temp.v('d4')::date, '21:00')::text;
-- 이름 비움 → 게스트1, 게스트2 … (null·공백만·보이지 않는 문자만 모두 "비움")
insert into t_vars select 'g1', public.add_match_guest(pg_temp.vid('g'), null)::text;
insert into t_vars select 'g2', public.add_match_guest(pg_temp.vid('g'), '   ')::text;
insert into t_vars select 'g3', public.add_match_guest(pg_temp.vid('g'), '  김  철수 ', array['forward']::public.play_position[], 'pro')::text;
insert into t_vars select 'g4', public.add_match_guest(pg_temp.vid('g'), chr(8203))::text;
reset role;
select pg_temp.check(pg_temp.guests('g') = '1=-,2=-,3=김 철수,4=-', 'numbers in order, empty names null');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
-- 9자·줄바꿈 거절
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '아홉글자이름입니다')$$, 'invalid_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '줄'||chr(10)||'바꿈')$$, 'invalid_guest_name');
-- 같은 표시 이름 불가: 적은 이름끼리, 적은 이름과 "게스트N"
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '김 철수')$$, 'duplicate_guest_name');
-- "게스트+숫자" 모양 이름 불가 (Q-074 2번): 정리 뒤 공백을 빼고 판단, 전각 숫자 포함. 지금 있든 없든 불가
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '게스트2')$$, 'reserved_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '게스트6')$$, 'reserved_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '  게스트 6 ')$$, 'reserved_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), chr(8203)||'게스트'||chr(8203)||'12')$$, 'reserved_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '게스트06')$$, 'reserved_guest_name');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '게스트６')$$, 'reserved_guest_name');
reset role;
select pg_temp.check(private.is_reserved_guest_name('게스트 6') and not private.is_reserved_guest_name('게스트')
  and not private.is_reserved_guest_name('게스트A') and not private.is_reserved_guest_name('게스트6번')
  and not private.is_reserved_guest_name('김게스트6'), 'reserved shape rule');
-- 서버 권한 직접 넣기도 표 검사로 거절
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name, added_by)
  values (pg_temp.vid('g'), pg_temp.vid('P'), '게스트9', pg_temp.u(2))$$, '%match_guests_name_not_reserved%');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
-- 비슷하지만 다른 모양은 가능
insert into t_vars select 'g5', public.add_match_guest(pg_temp.vid('g'), '게스트6번')::text;
-- 게스트1 을 지워도 나머지 번호는 그대로, 새 게스트는 다음 번호. 8자 이름 가능
select public.remove_match_guest(pg_temp.vid('g1'));
insert into t_vars select 'g6', public.add_match_guest(pg_temp.vid('g'), '여덟글자이름이야')::text;
reset role;
select pg_temp.check(pg_temp.guests('g') = '2=-,3=김 철수,4=-,5=게스트6번,6=여덟글자이름이야', 'numbers fixed after delete');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
insert into t_vars select 'g7', public.add_match_guest(pg_temp.vid('g'), '일곱째')::text;
-- 최대 12명 (지금 6명 → 6명 더, 13번째 거절)
select public.add_match_guest(pg_temp.vid('g'), '추가' || n) from generate_series(1, 6) n;
reset role;
select pg_temp.check((select count(*) = 12 from public.match_guests where match_id = pg_temp.vid('g')), '12 guests');
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), '열셋')$$, 'guest_limit_reached');
-- 하나 지우면 다시 추가 가능
select public.remove_match_guest(pg_temp.vid('g7'));
select public.add_match_guest(pg_temp.vid('g'), '열둘째');
-- 관리자용 정보에 번호 포함, 번호 순
select pg_temp.check((select string_agg(guest_no::text, ',') from public.get_match_guest_details(pg_temp.vid('g')))
  = '2,3,4,5,6,8,9,10,11,12,13,14', 'details ordered by guest_no');
select pg_temp.check((select skill_level = 'pro' and name = '김 철수' and positions = array['forward']::public.play_position[]
  from public.get_match_guest_details(pg_temp.vid('g')) where guest_no = 3), 'details content');
-- 팀원: 번호·이름은 읽고 포지션은 못 읽는다, 추가·수정 불가
select pg_temp.login(pg_temp.u(4));
select pg_temp.check((select count(*) = 12 from public.match_guests where match_id = pg_temp.vid('g')), 'member reads guests');
select pg_temp.check((select name is null from public.match_guests where id = pg_temp.vid('g2') and guest_no = 2), 'member reads guest_no');
select pg_temp.expect_error($$select positions from public.match_guests$$, 'permission denied%');
select pg_temp.expect_error($$select public.add_match_guest(pg_temp.vid('g'), null)$$, 'not_permitted');
select pg_temp.expect_error($$update public.match_guests set guest_no = 99$$, 'permission denied%');
select pg_temp.expect_error($$select public.get_match_guest_details(pg_temp.vid('g'))$$, 'not_permitted');
reset role;
-- 번호는 서버 권한으로 바꿔도 그대로. 표에도 같은 번호·같은 표시 이름 색인
update public.match_guests set guest_no = 99 where id = pg_temp.vid('g2');
select pg_temp.check((select guest_no = 2 from public.match_guests where id = pg_temp.vid('g2')), 'guest_no immutable');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('g'), pg_temp.vid('P'), '김 철수')$$, '%match_guests_display_name_once%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, guest_no) values (pg_temp.vid('g'), pg_temp.vid('P'), 3)$$, '%match_guests_no_once%');
select pg_temp.expect_error($$insert into public.match_guests (match_id, team_id, name) values (pg_temp.vid('g'), pg_temp.vid('P'), ' 앞공백')$$, '%match_guests_name_valid%');

-- ================================================================ A-3 내보내기 알림 (Q-073 6번)
-- 팀장 c1 이 팀원 c4 를 내보냄 → c4(본인 문구) + c2·c3(운영진, 이름 포함). c1(내보낸 사람)·c5(팀원) 없음
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.remove_member(pg_temp.vid('P'), pg_temp.u(4));
reset role;
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) from public.notifications
  where kind = 'member_removed' and team_id = pg_temp.vid('P')) = '2,3,4', 'removed -> self + staff except remover');
select pg_temp.check((select body = '팀에서 내보내졌어요. 그동안 함께 뛰어 주셔서 고마워요.' and actor_id is null
  from public.notifications where kind = 'member_removed' and user_id = pg_temp.u(4)), 'self text approved');
select pg_temp.check((select bool_and(body = '사님이 팀에서 내보내졌어요.' and actor_id = pg_temp.u(4) and title = '피FC')
  from public.notifications where kind = 'member_removed' and user_id in (pg_temp.u(2), pg_temp.u(3))), 'staff text with name, actor');
select pg_temp.check((select count(*) = 3 from public.notification_outbox o join public.notifications n on n.id = o.notification_id
  where n.kind = 'member_removed' and n.team_id = pg_temp.vid('P')), 'all queued for push');
-- 운영진 c3 을 내보냄 → c3 본인 + c2 (c1 제외). c3 은 본인 문구 하나만
set local role authenticated;
select pg_temp.login(pg_temp.u(1)); select public.remove_member(pg_temp.vid('P'), pg_temp.u(3));
reset role;
select pg_temp.check((select count(*) = 2 from public.notifications where kind = 'member_removed' and user_id = pg_temp.u(2)), 'other manager gets each removal');
select pg_temp.check((select count(*) = 1 from public.notifications where user_id = pg_temp.u(3)
  and kind = 'member_removed' and actor_id is null), 'removed manager: own text');
select pg_temp.check((select count(*) = 0 from public.notifications where user_id = pg_temp.u(3) and kind = 'manager_unassigned'), 'no unassigned notice');
select pg_temp.check((select count(*) = 0 from public.notifications where user_id = pg_temp.u(1) and kind = 'member_removed'), 'remover gets none');
select pg_temp.check((select count(*) = 0 from public.notifications where user_id = pg_temp.u(5) and kind = 'member_removed'), 'members get none');

-- ================================================================ 구조
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.match_guests'::regclass), 'RLS on guests');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.teams'::regclass), 'RLS on teams');
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and pronamespace in ('public'::regnamespace, 'private'::regnamespace) and proname in (
    'generate_auto_matches_for_team', 'add_match_guest', 'get_match_guest_details', 'match_guests_assign_no', 'remove_member')),
  'definer search_path fixed');
select pg_temp.check((select count(*) = 5 from pg_proc where prosecdef and pronamespace in ('public'::regnamespace, 'private'::regnamespace) and proname in (
    'generate_auto_matches_for_team', 'add_match_guest', 'get_match_guest_details', 'match_guests_assign_no', 'remove_member')),
  'definer functions present');
select pg_temp.check(not has_function_privilege('authenticated', 'private.generate_auto_matches_for_team(uuid, timestamptz)', 'execute'), 'app cannot generate');
select pg_temp.check(not has_function_privilege('authenticated', 'private.match_guests_assign_no()', 'execute'), 'app cannot run trigger fn');
select pg_temp.check(not has_function_privilege('authenticated', 'private.teams_regular_end_required()', 'execute'), 'app cannot run end check fn');
select pg_temp.check(not has_function_privilege('anon', 'public.add_match_guest(uuid, text, public.play_position[], public.skill_level)', 'execute'), 'anon cannot add guest');
select pg_temp.check(not has_function_privilege('anon', 'public.get_match_guest_details(uuid)', 'execute'), 'anon cannot read guest details');
select pg_temp.check(not has_column_privilege('anon', 'public.match_guests', 'guest_no', 'select'), 'anon cannot read guest_no');

select 'ALL PASSED' as result;
