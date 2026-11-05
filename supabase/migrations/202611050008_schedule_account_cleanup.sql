-- 프로필 없는 계정 정리 예약 작업 (data-model.md 2-1). 매시 17분 실행.
create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-profileless-accounts',
  '17 * * * *',
  $$select private.cleanup_profileless_accounts()$$
);
