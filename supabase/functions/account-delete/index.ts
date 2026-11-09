// 회원 탈퇴 (data-model.md 2-5, 11장 5번). 서비스 키는 이 실행 환경에만 있다.
//
// 흐름
//   1) 호출자 JWT 로 본인 확인 (다른 사람 ID 를 받지 않는다)
//   2) public.account_deletion_blocker(uid): 팀장인 팀이 있으면 거절 (Q-037)
//   3) 계정에 붙은 로그인 방법마다 외부 서비스 연결 해제 — 실패해도 계속한다 (Q-066 2번)
//   4) public.delete_account(uid): 한 트랜잭션에서 다시 확인하고 auth.users 삭제 → 2-5 표대로 연쇄 삭제
//
// 필요한 서버 비밀값 (supabase secrets set, 저장소에 넣지 않는다):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (Supabase 가 자동 제공)
//   KAKAO_ADMIN_KEY (카카오 연결 끊기용)
//
// 이 함수는 아직 배포하지 않았다 (배포에는 Supabase 액세스 토큰이 필요).
// (알림은 202611050029 에서 연결) 팀원이 회원 탈퇴하면 그 팀 팀장·운영진에게 팀 탈퇴와 같은 알림 (Q-067 12번)

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { unlinkExternalIdentities } from '../_shared/unlink.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authHeader = req.headers.get('Authorization') ?? '';
  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1) 본인 확인
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json(401, { error: 'not_authenticated' });
  const uid = userData.user.id;

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // 2) 막는 이유 확인
  const { data: blocker, error: blockerError } = await admin.rpc('account_deletion_blocker', {
    p_user_id: uid,
  });
  if (blockerError) return json(500, { error: 'internal_error' });
  if (blocker) return json(409, { error: blocker });

  // 3) 로그인 방법마다 외부 연결 해제. 실패해도 계속한다 (Q-066 2번).
  const { data: full, error: fullError } = await admin.auth.admin.getUserById(uid);
  if (fullError || !full.user) return json(500, { error: 'internal_error' });
  const unlinkFailures = await unlinkExternalIdentities(full.user.identities ?? []);

  // 4) 데이터 삭제 (auth.users → 연쇄)
  const { error: deleteError } = await admin.rpc('delete_account', { p_user_id: uid });
  if (deleteError) {
    const code = deleteError.message === 'owner_must_transfer_or_dissolve' ? 409 : 500;
    return json(code, { error: code === 409 ? deleteError.message : 'internal_error' });
  }

  // 로그에는 사람 ID·토큰을 남기지 않는다 (11장 12번). 실패한 공급자 종류만.
  if (unlinkFailures.length > 0) console.warn('unlink failed', unlinkFailures.join(','));
  return json(200, { ok: true });
});
