// 가입 도중 그만둔 계정 정리 (data-model.md 2-1, Q-066 3번). 예약 실행 전용.
//
// 흐름
//   1) public.list_profileless_accounts(n): 프로필 없이 24시간 지난 계정
//   2) 계정마다 카카오 연결 끊기 시도 — 실패해도 계속 (Q-066 2번과 같은 방식)
//   3) public.delete_profileless_account(uid): 그 사이 프로필이 생겼으면 지우지 않는다
//
// 호출 보호: Authorization 의 Bearer 값이 서비스 키와 같을 때만 실행한다 (예약 작업만 부른다).
//
// 아직 배포하지 않았다 (Supabase 액세스 토큰 필요). 배포 후 할 일 (lead·kopn):
//   - supabase secrets set KAKAO_ADMIN_KEY=...
//   - 예약 작업을 이 함수 호출로 바꾸는 마이그레이션 추가: cron.unschedule('cleanup-profileless-accounts') 후
//     pg_net 으로 이 함수를 매시 호출 (서비스 키는 Vault 에 두고 마이그레이션 파일에 넣지 않는다)
//   그 전까지는 기존 예약 작업(202611050008)이 연결 해제 없이 지운다.

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { unlinkExternalIdentities } from '../_shared/unlink.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

const BATCH = 100;

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  if ((req.headers.get('Authorization') ?? '') !== `Bearer ${serviceKey}`) {
    return json(401, { error: 'not_authorized' });
  }

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
});
