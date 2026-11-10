-- 스프린트 01 4단계 마이그레이션(202611050016 로고 저장소, 202611050017 지정 풋살장) 동작 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (가짜 auth.users·storage.objects 를 만든다).
-- 실패하면 예외로 멈춘다. 모두 통과하면 마지막에 'ALL PASSED' 를 돌려준다.
--
-- storage.objects 는 Storage API 가 쓰는 표다. 여기서는 API 대신 같은 역할(authenticated)로 표에 직접 넣고 지워
-- 정책을 확인한다. 직접 삭제 보호 트리거는 이 트랜잭션에서만 storage.allow_delete_query 로 끈다.

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

-- 지운 줄 수 (정책에 막히면 0)
create function pg_temp.delete_logo(p_name text)
returns int
language plpgsql
as $$
declare
  n int;
begin
  delete from storage.objects where bucket_id = 'team-logos' and name = p_name;
  get diagnostics n = row_count;
  return n;
end;
$$;

create function pg_temp.update_logo(p_name text)
returns int
language plpgsql
as $q$
declare
  n int;
begin
  update storage.objects set metadata = '{}'::jsonb where bucket_id = 'team-logos' and name = p_name;
  get diagnostics n = row_count;
  return n;
end;
$q$;

create function pg_temp.can_see(p_name text)
returns boolean
language sql
as $$
  select exists (select 1 from storage.objects where bucket_id = 'team-logos' and name = p_name)
$$;

create temp table t_vars (k text primary key, v text);
grant all on t_vars to authenticated;

create function pg_temp.v(p_k text)
returns text
language sql
as $$
  select v from t_vars where k = p_k
$$;

select set_config('storage.allow_delete_query', 'true', true);

insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-4000-8000-0000000000d1', 'authenticated', 'authenticated', 'd1@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000d2', 'authenticated', 'authenticated', 'd2@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000d3', 'authenticated', 'authenticated', 'd3@test.invalid', now(), now()),
  ('00000000-0000-4000-8000-0000000000d4', 'authenticated', 'authenticated', 'd4@test.invalid', now(), now());

-- ================================================================ 버킷
select pg_temp.check((select not public and file_size_limit = 2097152
    and allowed_mime_types = array['image/jpeg', 'image/png']
  from storage.buckets where id = 'team-logos'), 'bucket private, 2MB (202611050018), jpg/png');

set local role authenticated;

select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
select public.create_profile('일번', null, array['forward']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
select public.create_profile('이번', null, array['defender']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select public.create_profile('삼번', null, array['winger']::public.play_position[], false, true, true, true, false);
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select public.create_profile('사번', null, array['winger']::public.play_position[], false, true, true, true, false);

-- ================================================================ 지정 풋살장 (팀 만들기)
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
insert into t_vars select 'team', public.create_team('코코FC', null, null, null, null,
  '{"name": " 강남 풋살파크 ", "address": "서울 강남구 1", "provider": "kakao", "place_id": "12345", "lat": 37.5, "lng": 127.0}'::jsonb)::text;
select pg_temp.check((select venue_name = '강남 풋살파크' and venue_address = '서울 강남구 1' and venue_map_provider = 'kakao'
    and venue_map_place_id = '12345' and venue_lat = 37.5 and venue_lng = 127.0
  from public.teams where id = pg_temp.v('team')::uuid), 'create with kakao venue');
-- 직접 입력 (주소 없음 가능)
insert into t_vars select 'team2', public.create_team('둘FC', null, null, null, null, '{"name": "동네 구장"}'::jsonb)::text;
select pg_temp.check((select venue_name = '동네 구장' and venue_address is null and venue_map_provider is null
    and venue_map_place_id is null and venue_lat is null
  from public.teams where id = pg_temp.v('team2')::uuid), 'create with manual venue');
-- 장소 없이 (이전처럼 이름만)
insert into t_vars select 'team3', public.create_team('셋FC')::text;
select pg_temp.check((select venue_name is null from public.teams where id = pg_temp.v('team3')::uuid), 'create without venue');
-- 잘못된 장소는 팀도 만들어지지 않는다
select pg_temp.expect_error($$select public.create_team('넷FC', null, null, null, null, '{"name": ""}'::jsonb)$$, 'invalid_venue');
select pg_temp.check((select count(*) = 0 from public.teams where name = '넷FC'), 'no team on invalid venue');

-- 팀원 구성: d1 팀장, d2 운영진, d3 팀원, d4 팀 밖
insert into t_vars select 'code', team_code from public.teams where id = pg_temp.v('team')::uuid;
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
insert into t_vars select 'r2', public.request_join(pg_temp.v('code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
insert into t_vars select 'r3', public.request_join(pg_temp.v('code'), 'code')::text;
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
select public.decide_join_request(pg_temp.v('r2')::uuid, true);
select public.decide_join_request(pg_temp.v('r3')::uuid, true);
select public.appoint_manager(pg_temp.v('team')::uuid, '00000000-0000-4000-8000-0000000000d2');

-- ================================================================ 지정 풋살장 (팀 정보 수정)
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
select public.update_team_info(pg_temp.v('team')::uuid, '코코FC', null, null, null, true,
  '{"name": "새 구장", "address": "  "}'::jsonb);
select pg_temp.check((select venue_name = '새 구장' and venue_address is null and venue_map_provider is null
    and venue_map_place_id is null and venue_lat is null and venue_lng is null
  from public.teams where id = pg_temp.v('team')::uuid), 'manager switches to manual venue (kakao fields cleared)');
select public.update_team_info(pg_temp.v('team')::uuid, '코코FC', null, null, null, true, null);
select pg_temp.check((select venue_name is null and venue_address is null from public.teams where id = pg_temp.v('team')::uuid), 'venue cleared');
-- 잘못된 값들: 아무것도 저장되지 않는다 (이름 변경 포함)
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "provider": "kakao", "place_id": "1"}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "place_id": "1"}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "lat": 1, "lng": 2}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "provider": "naver", "place_id": "1", "lat": 1, "lng": 2}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "provider": "kakao", "place_id": "1", "lat": 100, "lng": 2}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '{"name": "a", "provider": "kakao", "place_id": "1", "lat": "x", "lng": 2}'::jsonb)$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, jsonb_build_object('name', repeat('가', 201)))$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, jsonb_build_object('name', 'a', 'address', repeat('가', 301)))$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, jsonb_build_object('name', E'두\n줄'))$$, 'invalid_venue');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '바뀐FC', null, null, null, true, '"구장"'::jsonb)$$, 'invalid_venue');
select pg_temp.check((select name = '코코FC' from public.teams where id = pg_temp.v('team')::uuid), 'invalid venue saved nothing');
-- 팀원은 못 고친다
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.expect_error($$select public.update_team_info(pg_temp.v('team')::uuid, '코코FC', null, null, null, true, '{"name": "x"}'::jsonb)$$, 'not_permitted');
-- 팀 찾기 결과에는 구장 이름만 (주소·좌표 없음은 기존 함수 그대로)
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
select public.update_team_info(pg_temp.v('team')::uuid, '코코FC', null, null, null, true,
  '{"name": "강남 풋살파크", "address": "서울", "provider": "kakao", "place_id": "999", "lat": 37.1, "lng": 127.1}'::jsonb);
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.check((select venue_name = '강남 풋살파크' from public.find_team_by_code(pg_temp.v('code'))), 'search shows venue name');

-- ================================================================ 로고 사진: 올리기 (storage.objects 정책)
insert into t_vars values
  ('p1', pg_temp.v('team') || '/' || gen_random_uuid() || '.png'),
  ('p2', pg_temp.v('team') || '/' || gen_random_uuid() || '.jpg'),
  ('p3', pg_temp.v('team') || '/' || gen_random_uuid() || '.png'),
  ('other', pg_temp.v('team2') || '/' || gen_random_uuid() || '.png');

-- 팀원·팀 밖 사람은 못 올린다
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('p1'))$$, '%row-level security%');
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('p1'))$$, '%row-level security%');
-- 운영진은 자기 팀 폴더에만, 규칙에 맞는 이름으로만
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('p1'));
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('other'))$$, '%row-level security%');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('team') || '/logo.png')$$, '%row-level security%');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('team') || '/' || gen_random_uuid() || '.svg')$$, '%row-level security%');
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('team') || '/a/' || gen_random_uuid() || '.png')$$, '%row-level security%');
-- 팀장도 올릴 수 있다
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('p2'));
-- 덮어쓰기(수정) 정책 없음
select pg_temp.check(pg_temp.update_logo(pg_temp.v('p2')) = 0, 'no update policy');

-- ================================================================ 로고 사진: 팀 로고로 지정 (teams.logo_image_path)
-- 아직 로고가 아닌 파일은 팀 밖 사람·일반 팀원에게 안 보인다
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.check(not pg_temp.can_see(pg_temp.v('p1')), 'outsider cannot see unused file');
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.check(not pg_temp.can_see(pg_temp.v('p1')), 'member cannot see unused file');
-- 다른 팀 폴더·없는 파일·규칙 밖 경로는 지정 불가
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
select pg_temp.check(pg_temp.can_see(pg_temp.v('p1')), 'staff sees own team file');
select pg_temp.expect_error($$update public.teams set logo_image_path = pg_temp.v('team') || '/' || gen_random_uuid() || '.png' where id = pg_temp.v('team')::uuid$$, 'invalid_logo_image');
select pg_temp.expect_error($$update public.teams set logo_image_path = 'x/y.png' where id = pg_temp.v('team')::uuid$$, 'invalid_logo_image');
-- 운영진이 지정
update public.teams set logo_image_path = pg_temp.v('p1') where id = pg_temp.v('team')::uuid;
select pg_temp.check((select logo_image_path = pg_temp.v('p1') from public.teams where id = pg_temp.v('team')::uuid), 'logo path set');
-- 지금 로고는 로그인한 누구나 읽는다 (팀원·팀 밖 사람)
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.check(pg_temp.can_see(pg_temp.v('p1')), 'outsider sees current logo');
select pg_temp.check(not pg_temp.can_see(pg_temp.v('p2')), 'outsider still cannot see other file');
select pg_temp.check((select logo_image_path = pg_temp.v('p1') from public.find_team_by_code(pg_temp.v('code'))), 'search returns logo path');
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.check(pg_temp.can_see(pg_temp.v('p1')), 'member sees current logo');
-- 일반 팀원은 로고를 바꿀 수 없다 (칸 정책)
update public.teams set logo_image_path = null where id = pg_temp.v('team')::uuid;
select pg_temp.check((select logo_image_path = pg_temp.v('p1') from public.teams where id = pg_temp.v('team')::uuid), 'member cannot clear logo');
-- 다른 팀 로고로 다른 팀 파일 지정 불가 (team2 의 팀장 d1 이 team 의 파일을 team2 에 지정)
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
select pg_temp.expect_error($$update public.teams set logo_image_path = pg_temp.v('p2') where id = pg_temp.v('team2')::uuid$$, 'invalid_logo_image');

-- ================================================================ 로고 사진: 지우기
-- 지금 로고는 관리자도 못 지운다 (먼저 칸을 바꾼다)
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p1')) = 0, 'cannot delete current logo');
-- 팀원·팀 밖 사람은 못 지운다
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p2')) = 0, 'member cannot delete');
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p2')) = 0, 'outsider cannot delete');
-- 교체: 새 파일 지정 → 이전 파일 삭제 (운영진)
select pg_temp.login('00000000-0000-4000-8000-0000000000d2');
update public.teams set logo_image_path = pg_temp.v('p2') where id = pg_temp.v('team')::uuid;
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p1')) = 1, 'staff deletes replaced file');
-- 사진 지우기: 칸 비움 → 파일 삭제 (글자 로고로)
update public.teams set logo_image_path = null where id = pg_temp.v('team')::uuid;
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p2')) = 1, 'staff deletes removed logo file');

-- ================================================================ 남은 파일 목록 (서비스 키 전용)
reset role;
select pg_temp.check(not has_function_privilege('authenticated', 'public.list_orphan_team_logos(int)', 'execute'), 'orphan list not for app');
select pg_temp.check(not has_function_privilege('anon', 'public.list_orphan_team_logos(int)', 'execute'), 'orphan list not for anon');
select pg_temp.check(has_function_privilege('service_role', 'public.list_orphan_team_logos(int)', 'execute'), 'orphan list for service role');
set local role authenticated;

-- ================================================================ 팀 해체: 로고 칸 비움, 해체 당시 관리자가 파일을 지울 수 있다
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('p3'));
update public.teams set logo_image_path = pg_temp.v('p3') where id = pg_temp.v('team')::uuid;
select public.dissolve_team(pg_temp.v('team')::uuid, '코코FC');
reset role;
select pg_temp.check((select logo_image_path is null from public.teams where id = pg_temp.v('team')::uuid), 'dissolve clears logo path');
set local role authenticated;
-- 해체 뒤에는 아무도 올릴 수 없다
select pg_temp.expect_error($$insert into storage.objects (bucket_id, name) values ('team-logos', pg_temp.v('team') || '/' || gen_random_uuid() || '.png')$$, '%row-level security%');
-- 해체 뒤 남은 파일은 팀 밖 사람·옛 일반 팀원에게 안 보이고 지울 수도 없다
select pg_temp.login('00000000-0000-4000-8000-0000000000d4');
select pg_temp.check(not pg_temp.can_see(pg_temp.v('p3')), 'outsider cannot see dissolved team file');
select pg_temp.login('00000000-0000-4000-8000-0000000000d3');
select pg_temp.check(not pg_temp.can_see(pg_temp.v('p3')), 'ex-member cannot see dissolved team file');
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p3')) = 0, 'ex-member cannot delete');
-- 해체 당시 팀장이 지운다
select pg_temp.login('00000000-0000-4000-8000-0000000000d1');
select pg_temp.check(pg_temp.delete_logo(pg_temp.v('p3')) = 1, 'ex-owner deletes dissolved team logo');

-- ================================================================ 실행 권한
reset role;
select pg_temp.check(not has_function_privilege('anon', 'public.create_team(text, smallint, time, time, text, jsonb, text, text)', 'execute'), 'anon cannot create team');
select pg_temp.check(not has_function_privilege('anon', 'public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text, text, text)', 'execute'), 'anon cannot update team');
select pg_temp.check(has_function_privilege('authenticated', 'public.update_team_info(uuid, text, smallint, time, time, boolean, jsonb, text, text, text)', 'execute'), 'authenticated can update team');
select pg_temp.check(not has_function_privilege('authenticated', 'private.apply_team_venue(uuid, jsonb)', 'execute'), 'venue helper not callable');

select 'ALL PASSED' as result;
