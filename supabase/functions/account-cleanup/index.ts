// 가입 도중 그만둔 계정 정리 (data-model.md 2-1, Q-066 3번). 예약 실행 전용.
//
// 흐름
//   1) public.list_profileless_accounts(n): 프로필 없이 24시간 지난 계정
//   2) 계정마다 카카오 연결 끊기 시도 — 실패해도 계속 (Q-066 2번과 같은 방식)
//   3) public.delete_profileless_account(uid): 그 사이 프로필이 생겼으면 지우지 않는다
//
// 호출 보호: x-cron-secret 헤더가 서버 비밀값 CRON_SECRET 과 같을 때만 실행한다 (_shared/cron_auth.ts).
//   예약 작업(202611050018, 매시 17분)이 Vault 의 cron_secret 을 보낸다. service_role 키는 DB 에 두지 않는다.
//   배포: supabase functions deploy account-cleanup --no-verify-jwt (예약 작업은 JWT 를 보내지 않는다)
// 필요한 서버 비밀값: CRON_SECRET, KAKAO_ADMIN_KEY (supabase secrets set)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동 제공 (함수 안 관리 권한용)

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { unlinkExternalIdentities } from '../_shared/unlink.ts';
import { guardCronRequest, json } from '../_shared/cron_auth.ts';

const BATCH = 100;

export type Deps = {
  env: (name: string) => string | undefined;
  /** 실제 정리 (비밀값 확인을 통과했을 때만 부른다). */
  run: () => Promise<Response>;
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const rejected = await guardCronRequest(req, deps.env('CRON_SECRET'));
  if (rejected) return rejected;
  return await deps.run();
}

async function runCleanup(): Promise<Response> {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json(500, { error: 'not_configured' });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  const { data: rows, error } = await admin.rpc('list_profileless_accounts', { p_limit: BATCH });
  if (error) return json(500, { error: 'internal_error' });

  let deleted = 0;
  let unlinkFailed = 0;
  for (const row of (rows ?? []) as { user_id: string }[]) {
    const { data: full } = await admin.auth.admin.getUserById(row.user_id);
    if (full?.user) {
      const failures = await unlinkExternalIdentities(full.user.identities ?? []);
      if (failures.length > 0) unlinkFailed++;
    }
    const { data: ok, error: delError } = await admin.rpc('delete_profileless_account', {
      p_user_id: row.user_id,
    });
    if (!delError && ok === true) deleted++;
  }

  // 사람 ID 는 남기지 않고 개수만.
  if (unlinkFailed > 0) console.warn('unlink failed count', unlinkFailed);
  return json(200, { deleted });
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (name) => Deno.env.get(name), run: runCleanup }));
}
