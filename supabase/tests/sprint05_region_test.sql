-- 팀 활동 지역(202611050067, data-model v4.7, Q-079 4번) 동작 확인 스크립트.
--   - teams.region_sido·region_sigungu: 선택, 시·군·구는 시·도 없이 불가, 한 줄 이름 글자 검사
--   - create_team·update_team_info 에서 받기 (정리 후 빈 값 = 없음), 칸 직접 수정 불가
--   - search_teams 지역 필터(시·도, 시·군·구, 둘 다 선택) + 결과에 지역만 추가, 최소 2자·상한 20 유지
--   - find_team_by_code 결과에 지역, 주소·좌표 계속 비공개
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

create function pg_temp.code(p_k text)
returns text
language sql
security definer
as $$
  select team_code from public.teams where id = (select v::uuid from t_vars where k = p_k)
$$;

create function pg_temp.u(p_n int)
returns uuid
language sql
as $$
  select ('00000000-0000-4000-8000-0000000055' || lpad(p_n::text, 2, '0'))::uuid
$$;

-- ---------------------------------------------------------------------------
-- 표 모양
-- ---------------------------------------------------------------------------
select pg_temp.check((select count(*) = 2 from information_schema.columns
                       where table_schema = 'public' and table_name = 'teams'
                         and column_name in ('region_sido', 'region_sigungu') and is_nullable = 'YES'),
                     'two optional region columns');
select pg_temp.check(not has_column_privilege('authenticated', 'public.teams', 'region_sido', 'UPDATE')
                     and not has_column_privilege('authenticated', 'public.teams', 'region_sigungu', 'UPDATE'),
                     'no direct column update on region');
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.teams'::regclass), 'teams RLS on');
select pg_temp.check((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where (n.nspname, p.proname) in (('public', 'create_team'), ('public', 'update_team_info'),
                                                        ('public', 'search_teams'), ('public', 'find_team_by_code'),
                                                        ('private', 'apply_team_region'))),
                     'security definer with empty search_path');
select pg_temp.check(not has_function_privilege('anon', 'public.search_teams(text, text, text)', 'execute'), 'anon cannot search');

-- ---------------------------------------------------------------------------
-- 준비: u1 팀장(팀 여러 개), u2 운영진, u3 팀원, u4 다른 사람
-- ---------------------------------------------------------------------------
insert into auth.users (id, aud, role, email, created_at, updated_at)
select pg_temp.u(n), 'authenticated', 'authenticated', 'r55' || n || '@test.invalid', now(), now()
  from generate_series(1, 4) n;

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.create_profile('일', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(2));
select public.create_profile('이', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(3));
select public.create_profile('삼', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login(pg_temp.u(4));
select public.create_profile('사', null, array['forward']::public.play_position[], false, true, true, true, false);

-- ---------------------------------------------------------------------------
-- 1. 팀 만들기
-- ---------------------------------------------------------------------------
select pg_temp.login(pg_temp.u(1));
insert into t_vars select 'A', public.create_team('지역테스트A', null, null, null, null,
  '{"name":"성수 구장","address":"서울 성동구 성수이로 1","provider":"kakao","place_id":"p1","lat":37.5,"lng":127.05}'::jsonb,
  '서울', '성동구')::text;
-- 앞뒤·연속 공백 정리
insert into t_vars select 'B', public.create_team('지역테스트B', null, null, null, null, null, '  경기 ', ' 성남시   분당구 ')::text;
-- 시·도만
insert into t_vars select 'C', public.create_team('지역테스트C', null, null, null, null, null, '서울', null)::text;
-- 지역 없음 (기존 호출 모양)
insert into t_vars select 'D', public.create_team('지역테스트D')::text;
-- 빈 칸은 없음
insert into t_vars select 'E', public.create_team('지역테스트E', null, null, null, null, null, '   ', '')::text;
-- 같은 이름, 다른 지역
insert into t_vars select 'F', public.create_team('지역테스트A', null, null, null, null, null, '부산', '해운대구')::text;
reset role;

select pg_temp.check((select region_sido = '서울' and region_sigungu = '성동구' from public.teams where id = pg_temp.vid('A')), 'create with region');
select pg_temp.check((select region_sido = '경기' and region_sigungu = '성남시 분당구' from public.teams where id = pg_temp.vid('B')), 'normalized');
select pg_temp.check((select region_sido = '서울' and region_sigungu is null from public.teams where id = pg_temp.vid('C')), 'sido only');
select pg_temp.check((select region_sido is null and region_sigungu is null from public.teams where id = pg_temp.vid('D')), 'no region (old call)');
select pg_temp.check((select region_sido is null and region_sigungu is null from public.teams where id = pg_temp.vid('E')), 'blank = none');

set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select pg_temp.expect_error($$select public.create_team('지역오류', null, null, null, null, null, null, '성동구')$$, 'invalid_region');
select pg_temp.expect_error($$select public.create_team('지역오류', null, null, null, null, null, E'서\n울', null)$$, 'invalid_region');
select pg_temp.expect_error($$select public.create_team('지역오류', null, null, null, null, null, '서울', E'성동\t구' || chr(7))$$, 'invalid_region');
select pg_temp.expect_error($$select public.create_team('지역오류', null, null, null, null, null, repeat('가', 11), null)$$, 'invalid_region');
select pg_temp.expect_error($$select public.create_team('지역오류', null, null, null, null, null, '서울', repeat('가', 21))$$, 'invalid_region');
-- 실패한 만들기는 팀을 남기지 않는다
select pg_temp.check((select count(*) = 0 from public.teams where name = '지역오류'), 'failed create leaves no team');

-- 팀원 u2(운영진)·u3(팀원) 넣기
reset role;
insert into public.team_members (team_id, user_id, role, status) values
  (pg_temp.vid('A'), pg_temp.u(2), 'manager', 'active'),
  (pg_temp.vid('A'), pg_temp.u(3), 'member', 'active');

-- ---------------------------------------------------------------------------
-- 2. 팀 정보 수정 (운영진 가능, 항상 현재 값)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select public.update_team_info(pg_temp.vid('A'), '지역테스트A', null, null, null, true, null, null, '서울', '광진구');
reset role;
select pg_temp.check((select region_sido = '서울' and region_sigungu = '광진구' from public.teams where id = pg_temp.vid('A')), 'manager updates region');

set local role authenticated;
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$select public.update_team_info(pg_temp.vid('A'), '지역테스트A', null, null, null, true, null, null, null, '광진구')$$, 'invalid_region');
-- 팀원·남은 고칠 수 없다
select pg_temp.login(pg_temp.u(3));
select pg_temp.expect_error($$select public.update_team_info(pg_temp.vid('A'), '지역테스트A', null, null, null, true, null, null, '부산', null)$$, 'not_permitted');
-- 표 직접 수정은 칸 권한이 없어 막힌다
select pg_temp.login(pg_temp.u(2));
select pg_temp.expect_error($$update public.teams set region_sido = '부산' where id = pg_temp.vid('A')$$, 'permission denied%');
-- 팀원은 자기 팀 지역을 읽을 수 있다
select pg_temp.login(pg_temp.u(3));
select pg_temp.check((select region_sigungu = '광진구' from public.teams where id = pg_temp.vid('A')), 'member reads region');
reset role;

-- 지움 (null 을 보내면 없음)
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.update_team_info(pg_temp.vid('C'), '지역테스트C', null, null, null, true, null);
reset role;
select pg_temp.check((select region_sido is null from public.teams where id = pg_temp.vid('C')), 'update clears region');
set local role authenticated;
select pg_temp.login(pg_temp.u(1));
select public.update_team_info(pg_temp.vid('C'), '지역테스트C', null, null, null, true, null, null, '서울', null);
reset role;

-- ---------------------------------------------------------------------------
-- 3. 팀 이름 검색 + 지역 필터 (다른 사람 u4)
-- ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.login(pg_temp.u(4));
select pg_temp.check((select count(*) = 6 from public.search_teams('지역테스트')), 'no filter: all');
select pg_temp.check((select count(*) = 6 from public.search_teams('지역테스트', null, null)), 'null filter: all');
select pg_temp.check((select count(*) = 2 from public.search_teams('지역테스트', '서울')), 'sido filter');
select pg_temp.check((select count(*) = 2 from public.search_teams('지역테스트', ' 서울 ', '')), 'sido filter normalized, blank sigungu');
select pg_temp.check((select count(*) = 1 from public.search_teams('지역테스트', '서울', '광진구') where team_code = pg_temp.code('A')), 'sido+sigungu filter');
select pg_temp.check((select count(*) = 0 from public.search_teams('지역테스트', '서울', '성동구')), 'old sigungu gone');
select pg_temp.check((select count(*) = 1 from public.search_teams('지역테스트', '경기', '성남시 분당구')), 'two-word sigungu');
select pg_temp.check((select count(*) = 1 from public.search_teams('지역테스트A', '부산')
                       where region_sido = '부산' and region_sigungu = '해운대구'), 'same name narrowed by region');
select pg_temp.check((select count(*) = 0 from public.search_teams('지역테스트', '제주')), 'no team in region');
select pg_temp.check((select region_sido = '서울' and region_sigungu = '광진구' from public.search_teams('지역테스트A', '서울')), 'result has region');
select pg_temp.expect_error($$select * from public.search_teams('지역테스트', null, '광진구')$$, 'invalid_region');
select pg_temp.expect_error($$select * from public.search_teams('지역테스트', '', '광진구')$$, 'invalid_region');
select pg_temp.expect_error($$select * from public.search_teams('지', '서울')$$, 'invalid_search_query');
select pg_temp.check((select count(*) = 0 from public.search_teams('%%', '서울')), 'escape kept');
-- 결과 칸: 주소·좌표·장소 번호·만든 사람·내부 ID 없음
reset role;
select pg_temp.check((select array_agg(a order by a) from unnest(
                        (select proargnames from pg_proc where oid = 'public.search_teams(text, text, text)'::regprocedure)) a)
                     @> array['region_sido', 'region_sigungu']
                     and not exists (select 1 from unnest(
                        (select proargnames from pg_proc where oid = 'public.search_teams(text, text, text)'::regprocedure)) a
                        where a in ('id', 'venue_address', 'venue_lat', 'venue_lng', 'venue_map_place_id', 'created_by')),
                     'search returns region only, no address');
-- 상한 20
set local role authenticated;
select pg_temp.login(pg_temp.u(4));
select public.create_team('상한지역' || g, null, null, null, null, null, '대전', '유성구') from generate_series(1, 10) g;
reset role;
insert into public.teams (name, team_code, logo_text, region_sido, region_sigungu)
select '상한지역x' || g, private.new_team_code(), '상한', '대전', '유성구' from generate_series(1, 15) g;
set local role authenticated;
select pg_temp.login(pg_temp.u(4));
select pg_temp.check((select count(*) = 20 from public.search_teams('상한지역', '대전', '유성구')), 'limit 20 kept');
-- 해체 팀 제외
reset role;
update public.teams set dissolved_at = now() where id = pg_temp.vid('F');
set local role authenticated;
select pg_temp.login(pg_temp.u(4));
select pg_temp.check((select count(*) = 0 from public.search_teams('지역테스트', '부산')), 'dissolved excluded');

-- ---------------------------------------------------------------------------
-- 4. 식별코드 찾기 결과에 지역
-- ---------------------------------------------------------------------------
select pg_temp.check((select region_sido = '서울' and region_sigungu = '광진구' from public.find_team_by_code(lower(pg_temp.code('A')))), 'code result has region');
select pg_temp.check((select region_sido is null from public.find_team_by_code(pg_temp.code('D'))), 'code result empty region');
reset role;
select pg_temp.check(not exists (select 1 from unnest(
                        (select proargnames from pg_proc where oid = 'public.find_team_by_code(text)'::regprocedure)) a
                        where a in ('id', 'venue_address', 'venue_lat', 'venue_lng', 'venue_map_place_id', 'created_by')),
                     'code result no address');

-- ---------------------------------------------------------------------------
-- 5. 표 검사 (서버 함수 밖에서도)
-- ---------------------------------------------------------------------------
select pg_temp.expect_error($$update public.teams set region_sido = null where id = pg_temp.vid('A')$$, '%teams_region_sigungu_needs_sido%');
select pg_temp.expect_error($$update public.teams set region_sido = ' 서울' where id = pg_temp.vid('A')$$, '%teams_region_sido_valid%');

select 'ALL PASSED' as result;
