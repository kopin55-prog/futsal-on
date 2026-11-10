-- 스프린트 01 마이그레이션 동작 확인 스크립트.
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
  ('00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated', 'a1@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated', 'a2@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000a3', 'authenticated', 'authenticated', 'a3@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000a4', 'authenticated', 'authenticated', 'a4@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000a5', 'authenticated', 'authenticated', 'a5@test.invalid', now() - interval '2 days', now()),
  ('00000000-0000-4000-8000-0000000000a6', 'authenticated', 'authenticated', 'a6@test.invalid', now() - interval '1 hour', now());

-- ---------------------------------------------------------------- a1: 가입 전
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
set local role authenticated;

select pg_temp.expect_error($$select public.create_team('코코 FC')$$, 'profile_required');
select pg_temp.expect_error($$insert into public.profiles (user_id, display_name, age_14_confirmed_at) values (auth.uid(), 'x', now())$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.user_consents (user_id, consent_type, consent_version) values (auth.uid(), 'terms', 'terms-x')$$, 'permission denied%');

-- 가입
select public.create_profile(E' 철수​  킴 ', '  안녕  ', array['forward','winger']::public.play_position[], false, true, true, true, false);
select pg_temp.check((select display_name = '철수 킴' and bio = '안녕' from public.profiles where user_id = auth.uid()), 'name normalized');
select pg_temp.check((select count(*) = 2 from public.user_consents), 'a1 has 2 consents');
select pg_temp.check((select bool_and(consent_version like consent_type::text || '-%') from public.user_consents), 'consent versions');
select pg_temp.expect_error($$select public.create_profile('x', null, array['forward']::public.play_position[], false, true, true, true, false)$$, 'profile_exists');

-- ---------------------------------------------------------------- a2: 가입 검사
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
select pg_temp.expect_error($$select public.create_profile('영희', null, array['forward']::public.play_position[], false, false, true, true, false)$$, 'age_14_required');
select pg_temp.expect_error($$select public.create_profile('영희', null, array['forward']::public.play_position[], false, true, false, true, false)$$, 'required_consents_missing');
select pg_temp.expect_error($$select public.create_profile('영희', null, array['forward','winger','defender','goalkeeper']::public.play_position[], false, true, true, true, false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.create_profile('영희', null, array['forward','forward']::public.play_position[], false, true, true, true, false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.create_profile('영희', null, array['forward']::public.play_position[], true, true, true, true, false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.create_profile('영희', null, array[]::public.play_position[], false, true, true, true, false)$$, 'invalid_positions');
select pg_temp.expect_error($$select public.create_profile(E'​ㅤ ', null, array['forward']::public.play_position[], false, true, true, true, false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.create_profile(repeat('가', 65), null, array['forward']::public.play_position[], false, true, true, true, false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.create_profile(E'영\n희', null, array['forward']::public.play_position[], false, true, true, true, false)$$, 'invalid_profile');
select pg_temp.expect_error($$select public.create_profile('영희', E'줄\n바꿈', array['forward']::public.play_position[], false, true, true, true, false)$$, 'invalid_profile');
select public.create_profile('영희', null, array['goalkeeper']::public.play_position[], true, true, true, true, true);
select pg_temp.check((select count(*) = 3 from public.user_consents), 'a2 has 3 consents (injury)');
select pg_temp.check((select count(*) = 1 from public.profiles), 'a2 sees only own profile');

-- ---------------------------------------------------------------- a3, a4 가입
select pg_temp.login('00000000-0000-4000-8000-0000000000a3');
select public.create_profile('민수', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000a4');
select public.create_profile('지훈', null, array['allrounder']::public.play_position[], false, true, true, true, false);

-- ---------------------------------------------------------------- a1: 팀 만들기
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
insert into t_vars select 'team', public.create_team(E'  코코   FC ')::text;
select pg_temp.check((select name = '코코 FC' and logo_text = '코코' and is_recruiting and team_code ~ '^[A-HJ-NP-Z2-9]{6}$' from public.teams), 'team created');
select pg_temp.check((select role = 'owner' from public.team_members where user_id = auth.uid()), 'a1 owner');
insert into t_vars select 'code', team_code from public.teams;
select pg_temp.expect_error($$select public.create_team('')$$, 'invalid_team_name');
select pg_temp.expect_error($$select public.create_team(repeat('가', 81))$$, 'invalid_team_name');

-- ---------------------------------------------------------------- a2: 팀 밖에서
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
select pg_temp.check((select count(*) = 0 from public.teams), 'outsider cannot read teams');
select pg_temp.check((select count(*) = 0 from public.team_members), 'outsider cannot read members');
select pg_temp.check((select count(*) = 1 from public.find_team_by_code(lower((select v from t_vars where k = 'code'))) where name = '코코 FC' and member_count = 1), 'find by lower code');
select pg_temp.check((select count(*) = 0 from public.find_team_by_code('OOOOOO')), 'no team with O');
select pg_temp.check((select count(*) = 1 from public.search_teams('코코')), 'search');
select pg_temp.check((select count(*) = 0 from public.search_teams('%%')), 'search escapes %');
select pg_temp.expect_error($$select * from public.search_teams('코')$$, 'invalid_search_query');
select pg_temp.expect_error($$select public.issue_team_invite((select v::uuid from t_vars where k = 'team'))$$, 'not_permitted');

-- ---------------------------------------------------------------- a1: 초대 코드
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
insert into t_vars select 'invite', public.issue_team_invite((select v::uuid from t_vars where k = 'team'));
select pg_temp.check((select char_length(v) = 43 from t_vars where k = 'invite'), 'invite length');
select pg_temp.check((select count(*) = 1 from public.team_invites where revoked_at is null and expires_at = created_at + interval '24 hours'), 'invite row');
select pg_temp.expect_error($$select token_hash from public.team_invites$$, 'permission denied%');

-- ---------------------------------------------------------------- a3: 초대로 신청
select pg_temp.login('00000000-0000-4000-8000-0000000000a3');
select pg_temp.check((select team_name = '코코 FC' from public.get_invite_team((select v from t_vars where k = 'invite'))), 'invite lookup');
select pg_temp.expect_error($$select * from public.get_invite_team('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$, 'invite_invalid');
insert into t_vars select 'req3', public.request_join_by_invite((select v from t_vars where k = 'invite'))::text;
select pg_temp.expect_error($$select public.request_join_by_invite((select v from t_vars where k = 'invite'))$$, 'request_already_pending');
select pg_temp.check((select count(*) = 1 from public.join_requests), 'applicant sees own request');

-- ---------------------------------------------------------------- 모집 끔 → 검색 경로 신청 불가
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
update public.teams set is_recruiting = false;
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code'), 'search')$$, 'team_not_recruiting');
select pg_temp.expect_error($$select public.request_join((select v from t_vars where k = 'code'), 'invite')$$, 'invalid_join_via');
select pg_temp.check((select count(*) = 1 from public.find_team_by_code((select v from t_vars where k = 'code')) where not is_recruiting), 'closed team still found');
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
update public.teams set is_recruiting = true;
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
insert into t_vars select 'req2', public.request_join(lower((select v from t_vars where k = 'code')), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000a4');
insert into t_vars select 'req4', public.request_join((select v from t_vars where k = 'code'), 'search')::text;

-- ---------------------------------------------------------------- a1: 신청자 프로필 보기, 승인
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select pg_temp.check((select count(*) = 4 from public.profiles), 'staff sees pending applicants profiles');
select pg_temp.check((select count(*) = 4 from public.profile_play_prefs), 'staff sees pending applicants prefs');
select pg_temp.check((select count(*) = 3 from public.join_requests where status = 'pending'), 'staff sees requests');
select public.decide_join_request((select v::uuid from t_vars where k = 'req2'), true);
select public.decide_join_request((select v::uuid from t_vars where k = 'req3'), true);
select pg_temp.expect_error($$select public.decide_join_request((select v::uuid from t_vars where k = 'req3'), true)$$, 'request_not_pending');

-- ---------------------------------------------------------------- a2: 팀원
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
select pg_temp.check((select count(*) = 1 from public.teams), 'member reads team');
select pg_temp.check((select count(*) = 3 from public.team_members), 'member reads roster');
select pg_temp.check((select count(*) = 3 from public.profiles), 'member reads teammates profiles (not pending a4)');
select pg_temp.check((select count(*) = 1 from public.profile_play_prefs), 'member reads only own prefs');
select pg_temp.check((select count(*) = 1 from public.join_requests), 'member sees only own request');
update public.teams set name = '해킹';
select pg_temp.check((select name = '코코 FC' from public.teams), 'member cannot rename');
select pg_temp.expect_error($$update public.teams set logo_text = 'XX'$$, 'permission denied%');
select pg_temp.expect_error($$update public.teams set dissolved_at = now()$$, 'permission denied%');
select pg_temp.expect_error($$update public.team_members set role = 'owner'$$, 'permission denied%');
select pg_temp.expect_error($$select public.decide_join_request((select v::uuid from t_vars where k = 'req4'), true)$$, 'not_permitted');
select pg_temp.expect_error($$select public.appoint_manager((select v::uuid from t_vars where k = 'team'), auth.uid())$$, 'not_permitted');
-- 본인 프로필·포지션 수정
update public.profiles set display_name = E'영희​  B';
select pg_temp.check((select display_name = '영희 B' from public.profiles where user_id = auth.uid()), 'self rename normalized');
select pg_temp.expect_error($$update public.profiles set age_14_confirmed_at = now()$$, 'permission denied%');
select pg_temp.expect_error($$update public.profile_play_prefs set is_dedicated_gk = true, positions = array['forward']::public.play_position[]$$, '%profile_play_prefs_dedicated_gk%');
update public.profile_play_prefs set positions = array['goalkeeper','forward']::public.play_position[];
select pg_temp.check((select cardinality(positions) = 2 from public.profile_play_prefs where user_id = auth.uid()), 'self prefs update');

-- ---------------------------------------------------------------- a1: 역할 관리
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a2');
select pg_temp.expect_error($$select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a2')$$, 'already_manager');
select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a3');
select public.decide_join_request((select v::uuid from t_vars where k = 'req4'), true);
select pg_temp.expect_error($$select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a4')$$, 'manager_limit_reached');
select pg_temp.expect_error($$select public.appoint_manager((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a5')$$, 'target_not_member');
select pg_temp.check((select count(*) = 4 from public.profile_play_prefs), 'owner reads members prefs');

-- ---------------------------------------------------------------- 로고 글자 (Q-013, Q-036, Q-047)
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
update public.teams set name = '새 이름';
select pg_temp.check((select logo_text = '새이' from public.teams), 'logo auto follows rename');
select pg_temp.expect_error($$select public.set_team_logo_text((select v::uuid from t_vars where k = 'team'), 'XY')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select pg_temp.expect_error($$select public.set_team_logo_text((select v::uuid from t_vars where k = 'team'), 'ABC')$$, 'invalid_logo_text');
select pg_temp.expect_error($$select public.set_team_logo_text((select v::uuid from t_vars where k = 'team'), E' ​ ')$$, 'invalid_logo_text');
select public.set_team_logo_text((select v::uuid from t_vars where k = 'team'), E'👨‍👩‍👧F');
select pg_temp.check((select logo_text = E'👨‍👩‍👧F' from public.teams), 'emoji logo');
update public.teams set name = '또 다른';
select pg_temp.check((select logo_text = E'👨‍👩‍👧F' from public.teams), 'custom logo kept on rename');
select public.set_team_logo_text((select v::uuid from t_vars where k = 'team'), '또다');
update public.teams set name = '세번째';
select pg_temp.check((select logo_text = '세번' from public.teams), 'logo reset to default resumes auto');

-- ---------------------------------------------------------------- 초대 재발급 → 이전 코드 무효
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
insert into t_vars select 'invite2', public.issue_team_invite((select v::uuid from t_vars where k = 'team'));
select pg_temp.check((select count(*) = 2 and count(*) filter (where revoked_at is null) = 1 from public.team_invites), 'manager sees invites, one open');
select pg_temp.login('00000000-0000-4000-8000-0000000000a6');
-- a6 는 프로필 없음
select pg_temp.expect_error($$select * from public.get_invite_team((select v from t_vars where k = 'invite2'))$$, 'profile_required');

-- ---------------------------------------------------------------- 위임·탈퇴·내보내기
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select pg_temp.expect_error($$select public.transfer_ownership((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a4')$$, 'target_not_manager');
select pg_temp.expect_error($$select public.leave_team((select v::uuid from t_vars where k = 'team'))$$, 'owner_must_transfer_or_dissolve');
select public.transfer_ownership((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a3');
select pg_temp.check((select role = 'manager' from public.team_members where user_id = auth.uid() and status = 'active'), 'old owner became manager');
select pg_temp.expect_error($$select public.remove_member((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a4')$$, 'not_permitted');
select pg_temp.login('00000000-0000-4000-8000-0000000000a3');
select pg_temp.check((select role = 'owner' from public.team_members where user_id = auth.uid() and status = 'active'), 'new owner');
select public.remove_member((select v::uuid from t_vars where k = 'team'), '00000000-0000-4000-8000-0000000000a2');
select pg_temp.expect_error($$select public.remove_member((select v::uuid from t_vars where k = 'team'), auth.uid())$$, 'cannot_target_self');
select pg_temp.login('00000000-0000-4000-8000-0000000000a2');
select pg_temp.check((select count(*) = 0 from public.teams), 'removed member loses team access');
select pg_temp.check((select count(*) = 1 and bool_and(status = 'removed') from public.team_members), 'removed member sees own history');
select pg_temp.check((select count(*) = 1 from public.profiles), 'removed member sees only self');
select pg_temp.login('00000000-0000-4000-8000-0000000000a4');
select public.leave_team((select v::uuid from t_vars where k = 'team'));
select pg_temp.expect_error($$select public.leave_team((select v::uuid from t_vars where k = 'team'))$$, 'not_member');

-- ---------------------------------------------------------------- 기기 알림 주소 소유 이전 (S-08)
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select public.register_device_token('tok-1', 'android');
select pg_temp.check((select count(*) = 1 from public.device_tokens), 'a1 token');
select pg_temp.login('00000000-0000-4000-8000-0000000000a4');
select public.register_device_token('tok-1', 'android');
select pg_temp.check((select count(*) = 1 from public.device_tokens), 'token moved to a4');
select pg_temp.login('00000000-0000-4000-8000-0000000000a1');
select pg_temp.check((select count(*) = 0 from public.device_tokens), 'a1 lost token');

-- ---------------------------------------------------------------- 앱은 탈퇴·정리 함수를 부를 수 없음
select pg_temp.expect_error($$select public.delete_account(auth.uid())$$, 'permission denied%');
select pg_temp.expect_error($$select public.account_deletion_blocker(auth.uid())$$, 'permission denied%');
select pg_temp.expect_error($$select private.cleanup_profileless_accounts()$$, 'permission denied%');

-- ---------------------------------------------------------------- 서버(service_role): 회원 탈퇴
reset role;
set local role service_role;
select pg_temp.check(public.account_deletion_blocker('00000000-0000-4000-8000-0000000000a3') = 'owner_must_transfer_or_dissolve', 'owner blocked');
select pg_temp.expect_error($$select public.delete_account('00000000-0000-4000-8000-0000000000a3')$$, 'owner_must_transfer_or_dissolve');
select pg_temp.check(public.account_deletion_blocker('00000000-0000-4000-8000-0000000000a2') is null, 'a2 deletable');
select public.delete_account('00000000-0000-4000-8000-0000000000a2');
reset role;
select pg_temp.check((select count(*) = 0 from auth.users where id = '00000000-0000-4000-8000-0000000000a2'), 'a2 auth user gone');
select pg_temp.check((select count(*) = 0 from public.profiles where user_id = '00000000-0000-4000-8000-0000000000a2'), 'a2 profile gone');
select pg_temp.check((select count(*) = 0 from public.user_consents where user_id = '00000000-0000-4000-8000-0000000000a2'), 'a2 consents gone');
select pg_temp.check((select count(*) = 0 from public.team_members where user_id = '00000000-0000-4000-8000-0000000000a2'), 'a2 memberships gone');
select pg_temp.check((select count(*) = 0 from public.join_requests where user_id = '00000000-0000-4000-8000-0000000000a2'), 'a2 requests gone');
select pg_temp.check((select count(*) = 1 from public.team_invites where created_by is null), 'invite issued by a2 kept with created_by null');

-- ---------------------------------------------------------------- 프로필 없는 계정 정리
select pg_temp.check(private.cleanup_profileless_accounts() = 1, 'cleanup removes one old profileless');
select pg_temp.check((select count(*) = 0 from auth.users where id = '00000000-0000-4000-8000-0000000000a5'), 'a5 removed');
select pg_temp.check((select count(*) = 1 from auth.users where id = '00000000-0000-4000-8000-0000000000a6'), 'a6 (recent) kept');

-- ---------------------------------------------------------------- 팀장 0명 금지 (지연 검사)
select pg_temp.expect_error($$
  update public.team_members set role = 'member' where role = 'owner' and status = 'active';
  set constraints all immediate;
$$, 'team_owner_required');

select 'ALL PASSED' as result;
