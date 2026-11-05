// 외부 로그인 서비스 연결 해제 (회원 탈퇴, 가입 미완료 계정 정리 공통).
//
// 결정 (Q-066): 연결 해제가 실패해도 계정 삭제는 그대로 진행한다. 이 함수는 실패한 공급자 종류만 돌려준다.
// 로그에 사람 ID·토큰을 남기지 않는다 (data-model.md 11장 12번).
//
// 확인 필요 (data-model.md 12-4):
//   - 카카오: Admin 키 + 카카오 회원번호(identity.provider_id)로 연결 끊기 — 실제 동작 테스트 전
//   - 구글: 토큰 철회에는 토큰이 필요하다. 서버는 토큰을 저장하지 않으므로 방법 미정 → 건너뜀
//   - 애플: 토큰 철회 방법 미정 (M-44 / Q-065 보류) → 건너뜀
//
// 필요한 서버 비밀값: KAKAO_ADMIN_KEY (supabase secrets set, 저장소에 넣지 않는다)

export type IdentityLike = {
  id: string;
  provider: string;
  identity_data?: Record<string, unknown> | null;
};

async function unlinkKakao(kakaoUserId: string): Promise<boolean> {
  const adminKey = Deno.env.get('KAKAO_ADMIN_KEY');
  if (!adminKey) return false;
  try {
    const res = await fetch('https://kapi.kakao.com/v1/user/unlink', {
      method: 'POST',
      headers: {
        Authorization: `KakaoAK ${adminKey}`,
        'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
      },
      body: new URLSearchParams({ target_id_type: 'user_id', target_id: kakaoUserId }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/** 계정에 붙은 로그인 방법마다 연결 해제를 시도한다. 실패한 공급자 이름 목록을 돌려준다. */
export async function unlinkExternalIdentities(identities: IdentityLike[]): Promise<string[]> {
  const failures: string[] = [];
  for (const identity of identities) {
    switch (identity.provider) {
      case 'kakao': {
        // TODO(12-4 확인): 실제 동작 테스트 전
        const providerId = String(identity.identity_data?.provider_id ?? identity.id);
        if (!(await unlinkKakao(providerId))) failures.push('kakao');
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
  return failures;
}
