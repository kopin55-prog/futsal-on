-- 스프린트 01 마무리 마이그레이션(202611050018: 로고 저장소 2MB, 정리 예약 작업 → 서버 함수 호출) 확인 스크립트.
-- 반드시 트랜잭션 안에서 실행하고 끝에 롤백한다 (Vault 에 가짜 값을 넣고 pg_net 요청을 대기 표에 쌓는다.
-- 롤백하면 요청은 실제로 나가지 않는다). 실패하면 예외로 멈춘다. 모두 통과하면 'ALL PASSED'.

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

-- 1) 로고 저장소 상한
select pg_temp.check(
  (select file_size_limit from storage.buckets where id = 'team-logos') = 2097152,
  'team-logos limit 2MB');
select pg_temp.check(
  (select allowed_mime_types from storage.buckets where id = 'team-logos') = array['image/jpeg', 'image/png'],
  'team-logos mime types unchanged');

-- 2) 예약 작업
select pg_temp.check(not exists (select 1 from cron.job where jobname = 'cleanup-profileless-accounts'),
  'old direct-delete job removed');
select pg_temp.check(
  (select command from cron.job where jobname = 'account-cleanup') = $c$select private.call_cron_function('account-cleanup')$c$
  and (select schedule from cron.job where jobname = 'account-cleanup') = '17 * * * *',
  'account-cleanup job');
select pg_temp.check(
  (select command from cron.job where jobname = 'team-logo-cleanup') = $c$select private.call_cron_function('team-logo-cleanup')$c$
  and (select schedule from cron.job where jobname = 'team-logo-cleanup') = '43 18 * * *',
  'team-logo-cleanup job daily');

-- 3) 권한: 앱 역할은 호출 함수를 실행할 수 없다
-- (net 스키마 표·함수 권한은 supabase_admin 소유라 여기서 바꾸지 않는다. 마이그레이션 주석 참고)
select pg_temp.check(not has_function_privilege('anon', 'private.call_cron_function(text)', 'execute'), 'anon cannot call');
select pg_temp.check(not has_function_privilege('authenticated', 'private.call_cron_function(text)', 'execute'), 'authenticated cannot call');
select pg_temp.check(not has_function_privilege('service_role', 'private.call_cron_function(text)', 'execute'), 'service_role cannot call');

set local role authenticated;
select pg_temp.expect_error($$select private.call_cron_function('account-cleanup')$$, 'permission denied%');
reset role;

-- 4) 알 수 없는 함수 이름은 거절
select pg_temp.expect_error($$select private.call_cron_function('account-delete')$$, 'unknown_function');

-- 5) Vault 값이 없으면 조용히 건너뜀 (이 트랜잭션 안에서만 지운다. 롤백됨)
delete from vault.secrets where name in ('cron_secret', 'project_url');
select pg_temp.check(private.call_cron_function('account-cleanup') is null, 'skip without vault values');
select vault.create_secret('https://example.invalid/', 'project_url');
select pg_temp.check(private.call_cron_function('account-cleanup') is null, 'skip without cron_secret');
select vault.create_secret('   ', 'cron_secret');
select pg_temp.check(private.call_cron_function('account-cleanup') is null, 'skip with blank cron_secret');

-- 6) 값이 있으면 x-cron-secret 헤더로 요청을 쌓는다 (롤백되므로 실제로 나가지 않음)
select vault.update_secret((select id from vault.secrets where name = 'cron_secret'), 'test-cron-secret-value');
create temp table t_req as select private.call_cron_function('team-logo-cleanup') as id;
select pg_temp.check((select id from t_req) is not null, 'request queued');
select pg_temp.check(
  (select q.url from net.http_request_queue q where q.id = (select id from t_req))
    = 'https://example.invalid/functions/v1/team-logo-cleanup',
  'url built from vault project_url');
select pg_temp.check(
  (select q.method from net.http_request_queue q where q.id = (select id from t_req)) = 'POST',
  'POST');
select pg_temp.check(
  (select q.headers ->> 'x-cron-secret' from net.http_request_queue q where q.id = (select id from t_req))
    = 'test-cron-secret-value',
  'secret sent in header');
select pg_temp.check(
  (select not (q.headers ? 'Authorization') from net.http_request_queue q where q.id = (select id from t_req)),
  'no Authorization header (no service key)');

select 'ALL PASSED' as result;
