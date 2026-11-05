// 회원 탈퇴 (data-model.md 2-5, 11장 5번). 서비스 키는 이 실행 환경에만 있다.
//
// 흐름
//   1) 호출자 JWT 로 본인 확인 (다른 사람 ID 를 받지 않는다)
//   2) public.account_deletion_blocker(uid): 팀장인 팀이 있으면 거절 (Q-037)
//   3) 계정에 붙은 로그인 방법마다 외부 서비스 연결 해제
//   4) public.delete_account(uid): 한 트랜잭션에서 다시 확인하고 auth.users 삭제 → 2-5 표대로 연쇄 삭제
//
// 필요한 서버 비밀값 (supabase secrets set, 저장소에 넣지 않는다):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (Supabase 가 자동 제공)
//   KAKAO_ADMIN_KEY (카카오 연결 끊기용)
//
// 확인 필요 (data-model.md 12-4, lead 보고):
//   - 카카오: Admin 키 + 카카오 회원번호(identity.provider_id)로 연결 끊기가 되는지 실제 테스트 전
//   - 구글: 토큰 철회에는 토큰이 필요하다. 서버는 토큰을 저장하지 않으므로 방법 미정 → 지금은 건너뜀
//   - 애플: 토큰 철회 방법 미정 (M-44 / Q-065 보류) → 지금은 건너뜀
//   - 연결 해제 실패 시 탈퇴를 멈출지 계속할지 미정 → 지금은 실패를 기록만 하고 계속한다
// 이 함수는 아직 배포하지 않았다 (배포에는 Supabase 액세스 토큰이 필요).

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

async function unlinkKakao(kakaoUserId: string): Promise<boolean> {
  const adminKey = Deno.env.get('KAKAO_ADMIN_KEY');
  if (!adminKey) return false;
  const res = await fetch('https://kapi.kakao.com/v1/user/unlink', {
    method: 'POST',
    headers: {
      Authorization: `KakaoAK ${adminKey}`,
      'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
    },
    body: new URLSearchParams({ target_id_type: 'user_id', target_id: kakaoUserId }),
  });
  return res.ok;
}

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

  // 3) 로그인 방법마다 외부 연결 해제
  const { data: full, error: fullError } = await admin.auth.admin.getUserById(uid);
  if (fullError || !full.user) return json(500, { error: 'internal_error' });
  const unlinkFailures: string[] = [];
  for (const identity of full.user.identities ?? []) {
    switch (identity.provider) {
      case 'kakao': {
        // TODO(12-4 확인): 실제 동작 테스트 전
        const providerId = String(identity.identity_data?.provider_id ?? identity.id);
        if (!(await unlinkKakao(providerId))) unlinkFailures.push('kakao');
        break;
      }
      case 'google':
        // TODO(12-4 확인): 토큰 없이 철회할 방법 미정
        break;
      case 'apple':
        // TODO(M-44 / Q-065): 애플 토큰 철회 방법 미정
        break;
    }
  }

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
