-- 스프린트 01 마무리 (docs/decisions.md lead 정리 행: 로고 저장소 2MB, 예약 작업 전용 비밀값)
--
-- 1) team-logos 버킷 파일 상한 10MB → 2MB (앱은 512px PNG 하나로 저장. 사용자가 고르는 원본 10MB 검사는 앱에서 그대로)
-- 2) 정리 예약 작업 2개를 서버 함수 호출로 바꾼다
--    - 가입 미완료 계정 정리: DB 직접 삭제(202611050008) → account-cleanup 호출 (카카오 연결 해제 먼저 시도, Q-066)
--    - 남은 로고 파일 정리: team-logo-cleanup 하루 1번 호출
--
-- 호출 보호: service_role 키는 DB(Vault 포함)에 두지 않는다. 예약 작업 전용 무작위 비밀값을 Vault 에 두고
-- pg_net 으로 함수를 부를 때 x-cron-secret 헤더로 보낸다. 함수는 같은 값이 서버 비밀값 CRON_SECRET 과
-- 같을 때만 동작한다.
--
-- Vault 이름 (값은 이 파일·저장소에 넣지 않는다. lead 가 등록):
--   cron_secret   예약 작업 전용 무작위 비밀값 (함수 비밀값 CRON_SECRET 과 같은 값)
--   project_url   https://<project-ref>.supabase.co  (개발·운영 프로젝트마다 다르므로 파일에 쓰지 않는다)
-- 둘 중 하나라도 없으면 호출하지 않고 조용히 건너뛴다.

-- 1) 로고 저장소 상한 2MB
update storage.buckets
   set file_size_limit = 2097152
 where id = 'team-logos';

-- 2) pg_net
create extension if not exists pg_net with schema extensions;

-- 참고: pg_net 요청 대기 표(net.http_request_queue)에는 보낼 헤더(비밀값)가 요청이 나갈 때까지 잠시 남는다.
-- net 스키마의 표·함수는 supabase_admin 이 PUBLIC 에 준 권한이라 이 마이그레이션(postgres)으로는 회수할 수 없다.
-- net 스키마는 API(PostgREST·GraphQL)에 노출되지 않으므로 앱 사용자는 읽을 수 없다. 대시보드에서 "Exposed schemas"에
-- net 을 넣지 않는다.

create function private.call_cron_function(p_function text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_url text;
begin
  -- 예약 작업이 부를 수 있는 함수만
  if p_function not in ('account-cleanup', 'team-logo-cleanup') then
    raise exception 'unknown_function';
  end if;

  select s.decrypted_secret into v_secret
    from vault.decrypted_secrets s
   where s.name = 'cron_secret'
   limit 1;
  select s.decrypted_secret into v_url
    from vault.decrypted_secrets s
   where s.name = 'project_url'
   limit 1;

  v_secret := nullif(btrim(v_secret), '');
  v_url := nullif(rtrim(btrim(v_url), '/'), '');
  if v_secret is null or v_url is null then
    return null;  -- 아직 등록 전: 건너뜀
  end if;

  return net.http_post(
    url := v_url || '/functions/v1/' || p_function,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function private.call_cron_function(text) from public, anon, authenticated, service_role;

-- 기존 DB 직접 삭제 예약 작업 해제 (private.cleanup_profileless_accounts 함수는 남겨 둔다. 예약 실행만 멈춤)
select cron.unschedule(jobid)
  from cron.job
 where jobname in ('cleanup-profileless-accounts', 'account-cleanup', 'team-logo-cleanup');

-- 가입 미완료 계정 정리: 매시 17분 (기존과 같은 주기)
select cron.schedule(
  'account-cleanup',
  '17 * * * *',
  $$select private.call_cron_function('account-cleanup')$$
);

-- 남은 로고 파일 정리: 하루 1번 (UTC 18:43 = 한국 03:43)
select cron.schedule(
  'team-logo-cleanup',
  '43 18 * * *',
  $$select private.call_cron_function('team-logo-cleanup')$$
);
