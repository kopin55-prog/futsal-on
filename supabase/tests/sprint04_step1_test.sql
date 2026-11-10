-- 스프린트 04 1단계 마이그레이션(202611050058~202611050060: 부상 표 2개, 부상 동의 나중에·철회,
-- is_injured_at 교체) 동작 확인 스크립트. 1-7(탈퇴·해체와 부상)도 함께 확인한다.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- 부상 등록 함수(1-3)는 아직 없으므로 부상·이력 줄은 서버 권한(postgres)으로 표에 직접 넣어 준비한다.

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
  select ('00000000-0000-4000-8000-0000000041' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- 오늘(한국 날짜) + p_days
create function pg_temp.kday(p_days int)
returns date
language sql
as $$
  select (now() at time zone 'Asia/Seoul')::date + p_days
$$;

-- 지금 로그인한 사람이 볼 수 있는 p_n 의 부상 줄 수 / 이력 줄 수
create function pg_temp.seen_injuries(p_n int)
returns int
language sql
as $$
  select count(*)::int from public.injuries where user_id = pg_temp.u(p_n)
$$;

create function pg_temp.seen_events(p_n int)
returns int
language sql
as $$
  select count(*)::int from public.injury_events e join public.injuries i on i.id = e.injury_id
   where i.user_id = pg_temp.u(p_n)
$$;

-- 서버 권한으로 본 실제 줄 수 (security definer 가 아닌 postgres 로 실행할 때 사용)
create function pg_temp.all_injuries(p_n int)
returns int
language sql
as $$
  select count(*)::int from public.injuries where user_id = pg_temp.u(p_n)
$$;

create function pg_temp.all_events(p_n int)
returns int
language sql
as $$
  select count(*)::int from public.injury_events e join public.injuries i on i.id = e.injury_id
   where i.user_id = pg_temp.u(p_n)
$$;

-- 부상 줄 만들기 (서버 권한). 키 이름으로 t_vars 에 저장
create function pg_temp.injury(p_key text, p_n int, p_started date, p_return date, p_memo text,
                               p_recovered_at timestamptz default null)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into public.injuries (user_id, started_on, expected_return_on, memo, status, recovered_at)
  values (pg_temp.u(p_n), p_started, p_return, p_memo,
          case when p_recovered_at is null then 'active'::public.injury_status else 'recovered'::public.injury_status end,
          p_recovered_at)
  returning id into v_id;
  insert into public.injury_events (injury_id, kind, via) values (v_id, 'reported', 'self');
  insert into t_vars values (p_key, v_id::text);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 준비
--   팀 P: u1 팀장, u2·u3·u5·u6 팀원
--   팀 Q: u4 팀장, u2·u7 팀원  (u2 는 두 팀 소속)
--   u8: 팀 없음 (다른 사람), u9: 로그인 계정만 있고 프로필 없음
--   부상 동의(가입 때): u2·u5·u6·u7. 동의 안 함: u1·u3·u4·u8
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'i41' || n || '@test.invalid', now(), now()
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
insert into t_vars select 'P', public.create_team('부상FC')::text;
insert into t_vars select 'codeP', team_code from public.teams where id = pg_temp.vid('P');
select pg_temp.login(pg_temp.u(4));
insert into t_vars select 'Q', public.create_team('회복FC')::text;
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

update public.team_members set joined_at = timestamptz '2020-01-01 00:00+09'
 where team_id in (pg_temp.vid('P'), pg_temp.vid('Q'));

-- ================================================================ 1-1 부상 표 2개
-- 구조: RLS, 앱 쓰기 권한 없음, 무작위 uuid
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.injuries'::regclass), 'injuries RLS on');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.injury_events'::regclass), 'injury_events RLS on');
select pg_temp.check(not has_table_privilege('authenticated', 'public.injuries', 'insert')
  and not has_table_privilege('authenticated', 'public.injuries', 'update')
  and not has_table_privilege('authenticated', 'public.injuries', 'delete')
  and not has_table_privilege('authenticated', 'public.injury_events', 'insert')
  and not has_table_privilege('authenticated', 'public.injury_events', 'update')
  and not has_table_privilege('authenticated', 'public.injury_events', 'delete'), 'no app writes');
select pg_temp.check(not has_table_privilege('anon', 'public.injuries', 'select')
  and not has_table_privilege('anon', 'public.injury_events', 'select'), 'anon no select');
select pg_temp.check((select column_default = 'gen_random_uuid()' from information_schema.columns
  where table_schema = 'public' and table_name = 'injuries' and column_name = 'id'), 'injuries random uuid');
select pg_temp.check((select column_default = 'gen_random_uuid()' from information_schema.columns
  where table_schema = 'public' and table_name = 'injury_events' and column_name = 'id'), 'injury_events random uuid');

-- u2: 진행 중 부상(메모 "발목") + 지난 부상(연장·회복 이력)
select pg_temp.injury('i2a', 2, pg_temp.kday(-3), pg_temp.kday(11), '  발목  ');
select pg_temp.injury('i2old', 2, pg_temp.kday(-60), pg_temp.kday(-46), '무릎', now() - interval '40 days');
insert into public.injury_events (injury_id, kind, weeks_added, via)
values (pg_temp.vid('i2old'), 'extended', 1, 'self'), (pg_temp.vid('i2old'), 'recovered', null, 'self');
select pg_temp.check(substr(pg_temp.v('i2a'), 15, 1) = '4', 'uuid v4');
select pg_temp.check((select memo = '발목' from public.injuries where id = pg_temp.vid('i2a')), 'memo trimmed');

-- 한 사람당 진행 중 1건
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on) values (pg_temp.u(2), pg_temp.kday(0), pg_temp.kday(7))$$,
  'duplicate key%injuries_one_active_per_user%');
-- 회복한 부상은 여러 건 가능
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at)
values (pg_temp.u(2), pg_temp.kday(-90), pg_temp.kday(-83), 'recovered', now() - interval '80 days');
delete from public.injuries where user_id = pg_temp.u(2) and started_on = pg_temp.kday(-90);

-- 메모 규칙 (11장 14번)
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
    values (pg_temp.u(2), pg_temp.kday(0), pg_temp.kday(7), 'recovered', now(), E'발목\n인대')$$, '%injuries_memo_valid%');
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
    values (pg_temp.u(2), pg_temp.kday(0), pg_temp.kday(7), 'recovered', now(), E'발목\t인대')$$, '%injuries_memo_valid%');
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
    values (pg_temp.u(2), pg_temp.kday(0), pg_temp.kday(7), 'recovered', now(), repeat('가', 161))$$, '%injuries_memo_valid%');
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
values (pg_temp.u(2), pg_temp.kday(-120), pg_temp.kday(-113), 'recovered', now() - interval '100 days', repeat('가', 160));
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
values (pg_temp.u(2), pg_temp.kday(-130), pg_temp.kday(-123), 'recovered', now() - interval '110 days', '   ');
select pg_temp.check((select memo is null from public.injuries where user_id = pg_temp.u(2) and started_on = pg_temp.kday(-130)), 'blank memo -> null');
insert into public.injuries (user_id, started_on, expected_return_on, status, recovered_at, memo)
values (pg_temp.u(2), pg_temp.kday(-140), pg_temp.kday(-133), 'recovered', now() - interval '120 days', '😀👨‍👩‍👧');
delete from public.injuries where user_id = pg_temp.u(2) and started_on in (pg_temp.kday(-120), pg_temp.kday(-130), pg_temp.kday(-140));

-- 상태·회복 시각, 기간, 이력 검사
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on, status) values (pg_temp.u(3), pg_temp.kday(0), pg_temp.kday(7), 'recovered')$$,
  '%injuries_recovered_at_matches_status%');
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on, recovered_at) values (pg_temp.u(3), pg_temp.kday(0), pg_temp.kday(7), now())$$,
  '%injuries_recovered_at_matches_status%');
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on) values (pg_temp.u(3), pg_temp.kday(0), pg_temp.kday(-1))$$,
  '%injuries_return_after_start%');
select pg_temp.expect_error(
  $$insert into public.injury_events (injury_id, kind, via) values (pg_temp.vid('i2a'), 'extended', 'self')$$,
  '%injury_events_weeks_only_extended%');
select pg_temp.expect_error(
  $$insert into public.injury_events (injury_id, kind, weeks_added, via) values (pg_temp.vid('i2a'), 'reported', 1, 'self')$$,
  '%injury_events_weeks_only_extended%');
select pg_temp.expect_error(
  $$insert into public.injury_events (injury_id, kind, weeks_added, via) values (pg_temp.vid('i2a'), 'extended', 0, 'self')$$,
  '%injury_events_weeks_positive%');
-- 이력 via 값: return_vote, return_check 도 저장 가능
insert into public.injury_events (injury_id, kind, weeks_added, via) values (pg_temp.vid('i2a'), 'extended', 2, 'return_check');
insert into public.injury_events (injury_id, kind, via) values (pg_temp.vid('i2a'), 'recovered', 'return_vote');
delete from public.injury_events where injury_id = pg_temp.vid('i2a') and kind <> 'reported';

-- 사람 칸·started_on 은 고치지 못함 (트리거)
update public.injuries set user_id = pg_temp.u(3), started_on = pg_temp.kday(-5) where id = pg_temp.vid('i2a');
select pg_temp.check((select user_id = pg_temp.u(2) and started_on = pg_temp.kday(-3) from public.injuries where id = pg_temp.vid('i2a')), 'user_id/started_on fixed');

-- 일정 삭제 시 return_check_sent_for 비움, 부상은 남음 (7-5)
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at)
  values (pg_temp.vid('P'), 'auto', now() + interval '3 days', now() + interval '3 days 2 hours', now() + interval '2 days')
  returning id)
insert into t_vars select 'mDel', id::text from x;
update public.injuries set return_check_sent_for = pg_temp.vid('mDel') where id = pg_temp.vid('i2a');
delete from public.matches where id = pg_temp.vid('mDel');
select pg_temp.check((select return_check_sent_for is null from public.injuries where id = pg_temp.vid('i2a')), 'match delete clears return_check_sent_for');

-- 읽기 권한
set local role authenticated;
-- 본인: 전부 (진행 중 + 지난 것), 이력 전부
select pg_temp.login(pg_temp.u(2));
select pg_temp.check(pg_temp.seen_injuries(2) = 2, 'self sees all injuries');
select pg_temp.check(pg_temp.seen_events(2) = 4, 'self sees all events');
-- 팀 P 팀원(u1, u3): 진행 중인 것만, 메모 포함. 이력 0
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(2) = 1, 'teammate P sees active only');
select pg_temp.check((select memo = '발목' and status = 'active' from public.injuries where user_id = pg_temp.u(2)), 'teammate sees memo');
select pg_temp.check(pg_temp.seen_events(2) = 0, 'teammate sees no events');
select pg_temp.check((select count(*) = 0 from public.injury_events), 'teammate events 0');
select pg_temp.login(pg_temp.u(3));
select pg_temp.check(pg_temp.seen_injuries(2) = 1, 'teammate P (no own consent) sees active');
-- 팀 Q 팀원(u4, u7): 두 팀 모두에서 보임
select pg_temp.login(pg_temp.u(7));
select pg_temp.check(pg_temp.seen_injuries(2) = 1, 'teammate Q sees active');
-- 다른 사람(u8): 0
select pg_temp.login(pg_temp.u(8));
select pg_temp.check((select count(*) = 0 from public.injuries), 'other user sees 0 injuries');
select pg_temp.check((select count(*) = 0 from public.injury_events), 'other user sees 0 events');
-- 앱 직접 쓰기 불가
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error(
  $$insert into public.injuries (user_id, started_on, expected_return_on) values (pg_temp.u(2), pg_temp.kday(0), pg_temp.kday(7))$$,
  'permission denied%');
select pg_temp.expect_error($$update public.injuries set memo = '손목' where user_id = pg_temp.u(2)$$, 'permission denied%');
select pg_temp.expect_error($$delete from public.injuries where user_id = pg_temp.u(2)$$, 'permission denied%');
select pg_temp.expect_error(
  $$insert into public.injury_events (injury_id, kind, via) values (pg_temp.vid('i2a'), 'recovered', 'self')$$,
  'permission denied%');
reset role;
-- 비로그인
set local role anon;
select pg_temp.login(null);
select pg_temp.expect_error($$select count(*) from public.injuries$$, 'permission denied%');
select pg_temp.expect_error($$select count(*) from public.injury_events$$, 'permission denied%');
reset role;

-- S-07 이중 장치: 동의가 철회됐는데 기록이 아직 남은 순간에도 팀원에게 안 보임
update public.user_consents set withdrawn_at = now()
 where user_id = pg_temp.u(2) and consent_type = 'injury_info' and withdrawn_at is null;
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(2) = 0, 'S-07: withdrawn consent hides from teammate');
select pg_temp.login(pg_temp.u(2));
select pg_temp.check(pg_temp.seen_injuries(2) = 2, 'S-07: self still sees own');
reset role;
update public.user_consents set withdrawn_at = null
 where user_id = pg_temp.u(2) and consent_type = 'injury_info';

-- ================================================================ 1-4 is_injured_at 교체
-- u5: 10일 전부터 진행 중. u6: 20일 전 등록, 30분 전 회복
select pg_temp.injury('i5', 5, pg_temp.kday(-10), pg_temp.kday(4), null);
select pg_temp.injury('i6', 6, pg_temp.kday(-20), pg_temp.kday(-6), null, now() - interval '30 minutes');
insert into public.injury_events (injury_id, kind, via) values (pg_temp.vid('i6'), 'recovered', 'self');

select pg_temp.check(private.is_injured_at(pg_temp.u(5), now()), 'active injury now');
select pg_temp.check(private.is_injured_at(pg_temp.u(5), (pg_temp.kday(-10)::timestamp + interval '1 minute') at time zone 'Asia/Seoul'),
  'start day 00:01 KST');
select pg_temp.check(not private.is_injured_at(pg_temp.u(5), (pg_temp.kday(-10)::timestamp - interval '1 minute') at time zone 'Asia/Seoul'),
  'day before start 23:59 KST');
select pg_temp.check(private.is_injured_at(pg_temp.u(6), now() - interval '1 hour'), 'recovered later: injured before recovery');
select pg_temp.check(not private.is_injured_at(pg_temp.u(6), now()), 'recovered: not injured now');
select pg_temp.check(not private.is_injured_at(pg_temp.u(6), (pg_temp.kday(-21)::timestamp + interval '12 hours') at time zone 'Asia/Seoul'),
  'recovered: not injured before start');
select pg_temp.check(not private.is_injured_at(pg_temp.u(3), now()), 'no injury');
select pg_temp.check(private.is_injured_at(pg_temp.u(2), now()), 'u2 active');
-- 실행 권한은 그대로 (앱 사용자·service_role 불가)
select pg_temp.check(not has_function_privilege('authenticated', 'private.is_injured_at(uuid, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'private.is_injured_at(uuid, timestamptz)', 'execute')
  and not has_function_privilege('service_role', 'private.is_injured_at(uuid, timestamptz)', 'execute'), 'is_injured_at privileges kept');

-- (a) 미투표 알림: 그 시각 부상자(u2, u5)는 받지 않음. 회복한 u6 은 받음. 팀 P 미투표자: u1, u3, u6
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at)
  values (pg_temp.vid('P'), 'auto', now() + interval '6 hours', now() + interval '8 hours', now() + interval '4 hours', now() - interval '1 minute')
  returning id)
insert into t_vars select 'mRemind', id::text from x;
select private.send_rsvp_reminders(now());
select pg_temp.check((select string_agg(right(user_id::text, 1), ',' order by user_id::text) = '1,3,6'
  from public.notifications where kind = 'rsvp_deadline_soon' and ref_id = pg_temp.vid('mRemind')), 'reminder skips injured');

-- (b) 경기 시작 때 참여율: 마감 시각 부상자는 응답 +1
--   u1 마감 전 응답, u2·u5 마감 시각 부상 중, u6 마감(1시간 전) 뒤 30분 전에 회복 → 마감 시각엔 부상 중, u3 아무것도 아님
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at)
  values (pg_temp.vid('P'), 'auto', now() - interval '1 minute', now() + interval '2 hours', now() - interval '1 hour')
  returning id)
insert into t_vars select 'mClose', id::text from x;
insert into public.attendance_responses (match_id, user_id, state, responded_at)
values (pg_temp.vid('mClose'), pg_temp.u(1), 'attending', now() - interval '2 hours');
select private.close_out_attendance_vote(pg_temp.vid('mClose'));
select pg_temp.check((select string_agg(right(user_id::text, 1) || ':' || attendance_vote_eligible || '/' || attendance_vote_responded,
                                        ',' order by user_id::text)
                        = '1:1/1,2:1/1,3:1/0,5:1/1,6:1/1'
                        from public.monthly_vote_participation where team_id = pg_temp.vid('P')), 'participation counts injured as responded');

-- ================================================================ 1-2 부상 동의 나중에·철회
set local role authenticated;
-- 동의 안 한 u3: 나중에 동의 → 새 줄 (현재 버전)
select pg_temp.login(pg_temp.u(3));
select public.agree_injury_consent();
select pg_temp.check((select count(*) = 1 from public.user_consents
  where consent_type = 'injury_info' and withdrawn_at is null and consent_version = 'injury_info-2026-11-05'), 'late consent row');
-- 이미 있으면 거절
select pg_temp.expect_error($$select public.agree_injury_consent()$$, 'injury_consent_exists');
-- 약관·개인정보 동의는 철회 불가
select pg_temp.expect_error($$select public.withdraw_consent('terms')$$, 'consent_not_withdrawable');
select pg_temp.expect_error($$select public.withdraw_consent('privacy')$$, 'consent_not_withdrawable');
select pg_temp.expect_error($$select public.withdraw_consent(null)$$, 'consent_not_withdrawable');
select pg_temp.check((select count(*) = 2 from public.user_consents where consent_type in ('terms', 'privacy') and withdrawn_at is null), 'terms/privacy intact');
-- 표 직접 쓰기 불가
select pg_temp.expect_error($$update public.user_consents set withdrawn_at = now()$$, 'permission denied%');
select pg_temp.expect_error($$insert into public.user_consents (user_id, consent_type, consent_version) values (auth.uid(), 'injury_info', 'injury_info-x')$$, 'permission denied%');

-- u2 철회: 동의 줄에 withdrawn_at, 부상 기록 전부·이력 삭제
select pg_temp.login(pg_temp.u(2));
select public.withdraw_consent('injury_info');
select pg_temp.check((select count(*) = 1 from public.user_consents where consent_type = 'injury_info' and withdrawn_at is not null), 'withdrawn_at set');
select pg_temp.check(pg_temp.seen_injuries(2) = 0 and pg_temp.seen_events(2) = 0, 'self sees 0 after withdraw');
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(2) = 0, 'teammate P sees 0 after withdraw');
select pg_temp.login(pg_temp.u(7));
select pg_temp.check(pg_temp.seen_injuries(2) = 0, 'teammate Q sees 0 after withdraw');
reset role;
select pg_temp.check(pg_temp.all_injuries(2) = 0, 'injuries deleted (server)');
select pg_temp.check((select count(*) = 0 from public.injury_events where injury_id in (pg_temp.vid('i2a'), pg_temp.vid('i2old'))), 'events deleted (server)');
select pg_temp.check(not private.is_injured_at(pg_temp.u(2), now()), 'withdrawn: not injured');
-- 다른 사람 부상은 그대로
select pg_temp.check(pg_temp.all_injuries(5) = 1 and pg_temp.all_injuries(6) = 1, 'others untouched');

set local role authenticated;
select pg_temp.login(pg_temp.u(2));
-- 유효한 동의가 없으면 다시 철회 거절
select pg_temp.expect_error($$select public.withdraw_consent('injury_info')$$, 'injury_consent_not_found');
-- 다시 동의: 새 줄, 이전 철회 줄은 그대로, 지운 기록은 안 돌아옴
select public.agree_injury_consent();
select pg_temp.check((select count(*) = 2 from public.user_consents where consent_type = 'injury_info'), 'old withdrawn row kept + new row');
select pg_temp.check((select count(*) = 1 from public.user_consents where consent_type = 'injury_info' and withdrawn_at is null), 'one active consent');
select pg_temp.check(pg_temp.seen_injuries(2) = 0, 'deleted records do not return');

-- 프로필 없는 호출자 거절
select pg_temp.login(pg_temp.u(9));
select pg_temp.expect_error($$select public.agree_injury_consent()$$, 'profile_required');
select pg_temp.expect_error($$select public.withdraw_consent('injury_info')$$, 'profile_required');
-- 로그인 안 됨
select set_config('request.jwt.claims', '', true);
select pg_temp.expect_error($$select public.agree_injury_consent()$$, 'not_authenticated');
select pg_temp.expect_error($$select public.withdraw_consent('injury_info')$$, 'not_authenticated');
reset role;
set local role anon;
select pg_temp.expect_error($$select public.agree_injury_consent()$$, 'permission denied%');
select pg_temp.expect_error($$select public.withdraw_consent('injury_info')$$, 'permission denied%');
reset role;

-- ================================================================ 1-7 탈퇴·해체와 부상
-- 팀 탈퇴: u5 가 팀 P 를 떠남 → 부상은 그대로, 팀 P 팀원에게 안 보임
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(5) = 1, 'before leave: teammate sees u5');
select pg_temp.login(pg_temp.u(5));
select public.leave_team(pg_temp.vid('P'));
select pg_temp.check(pg_temp.seen_injuries(5) = 1, 'after leave: self still sees');
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(5) = 0, 'after leave: former teammate sees 0');
reset role;
select pg_temp.check(pg_temp.all_injuries(5) = 1 and pg_temp.all_events(5) = 1, 'leave keeps injury and events');

-- 내보내기: u4 가 팀 Q 에서 u7 을 내보냄
select pg_temp.injury('i7', 7, pg_temp.kday(-2), pg_temp.kday(12), '햄스트링');
set local role authenticated;
select pg_temp.login(pg_temp.u(4));
select pg_temp.check(pg_temp.seen_injuries(7) = 1, 'before remove: owner sees u7');
select public.remove_member(pg_temp.vid('Q'), pg_temp.u(7));
select pg_temp.check(pg_temp.seen_injuries(7) = 0, 'after remove: owner sees 0');
select pg_temp.login(pg_temp.u(7));
select pg_temp.check(pg_temp.seen_injuries(7) = 1, 'after remove: self still sees');
reset role;
select pg_temp.check(pg_temp.all_injuries(7) = 1, 'remove keeps injury');

-- 최근 10경기 정리로 일정이 지워지면 return_check_sent_for 만 비고 부상은 남음 (팀 Q, 끝난 경기 11개)
insert into t_vars values ('base', (date_trunc('hour', now()) - interval '14 days')::text);
with x as (
  insert into public.matches (team_id, source, starts_at, ends_at, rsvp_deadline_at, closed_out_at)
  select pg_temp.vid('Q'), 'auto', pg_temp.v('base')::timestamptz + make_interval(days => i),
         pg_temp.v('base')::timestamptz + make_interval(days => i) + interval '2 hours',
         pg_temp.v('base')::timestamptz + make_interval(days => i) - interval '2 hours',
         pg_temp.v('base')::timestamptz + make_interval(days => i) + interval '2 hours 1 minute'
    from generate_series(0, 10) i
  returning id, starts_at)
insert into t_vars select 'q' || extract(day from (starts_at - pg_temp.v('base')::timestamptz))::int, id::text from x;
update public.injuries set return_check_sent_for = pg_temp.vid('q0') where id = pg_temp.vid('i7');
update public.injuries set return_check_sent_for = pg_temp.vid('q10') where id = pg_temp.vid('i5');
select pg_temp.check(private.prune_team_matches(pg_temp.vid('Q')) = 1, 'prune deletes oldest');
select pg_temp.check(not exists (select 1 from public.matches where id = pg_temp.vid('q0')), 'q0 pruned');
select pg_temp.check((select return_check_sent_for is null and status = 'active' from public.injuries where id = pg_temp.vid('i7')),
  'prune clears return_check_sent_for, injury kept');
select pg_temp.check((select return_check_sent_for = pg_temp.vid('q10') from public.injuries where id = pg_temp.vid('i5')),
  'kept match reference intact');

-- 해체: 팀 P 해체 → u3 부상은 그대로, 옛 팀원(u1)에게 안 보임
select pg_temp.injury('i3', 3, pg_temp.kday(-1), pg_temp.kday(6), null);
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.check(pg_temp.seen_injuries(3) = 1, 'before dissolve: teammate sees u3');
select public.dissolve_team(pg_temp.vid('P'), '부상FC');
select pg_temp.check(pg_temp.seen_injuries(3) = 0, 'after dissolve: former teammate sees 0');
select pg_temp.login(pg_temp.u(3));
select pg_temp.check(pg_temp.seen_injuries(3) = 1, 'after dissolve: self still sees');
reset role;
select pg_temp.check(pg_temp.all_injuries(3) = 1 and pg_temp.all_injuries(6) = 1, 'dissolve keeps injuries');

-- 회원 탈퇴: u6 → 부상·이력·동의 줄 모두 삭제
select pg_temp.check(pg_temp.all_events(6) = 2 and (select count(*) = 3 from public.user_consents where user_id = pg_temp.u(6)), 'u6 data before delete');
select public.delete_account(pg_temp.u(6));
select pg_temp.check(pg_temp.all_injuries(6) = 0, 'account deletion removes injuries');
select pg_temp.check((select count(*) = 0 from public.injury_events where injury_id = pg_temp.vid('i6')), 'account deletion removes events');
select pg_temp.check((select count(*) = 0 from public.user_consents where user_id = pg_temp.u(6)), 'account deletion removes consents');

-- ================================================================ 함수 속성
select pg_temp.check((select bool_and(coalesce(array_to_string(proconfig, ','), '') like '%search_path=""%')
  from pg_proc where prosecdef and proname in (
    'has_valid_injury_consent', 'agree_injury_consent', 'withdraw_consent', 'is_injured_at')), 'definer search_path fixed');
select pg_temp.check((select count(*) = 4 from pg_proc where prosecdef and proname in (
    'has_valid_injury_consent', 'agree_injury_consent', 'withdraw_consent', 'is_injured_at')), 'all definer functions present');
select pg_temp.check(has_function_privilege('authenticated', 'public.agree_injury_consent()', 'execute')
  and has_function_privilege('authenticated', 'public.withdraw_consent(public.consent_type)', 'execute')
  and not has_function_privilege('anon', 'public.agree_injury_consent()', 'execute')
  and not has_function_privilege('anon', 'public.withdraw_consent(public.consent_type)', 'execute')
  and not has_function_privilege('anon', 'private.has_valid_injury_consent(uuid)', 'execute'), 'function privileges');

select 'ALL PASSED' as result;
