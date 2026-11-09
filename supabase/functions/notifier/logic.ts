// notifier 의 판단 로직 (순수 함수). Supabase·FCM 을 부르지 않으므로 Deno 단위 테스트로 확인한다 (notifier_test.ts).
//
// 건너뛰기 (Q-071 11번, Q-073 5번): 푸시만 건너뛰고 알림함 줄은 남긴다 (status = skipped).
//   - read          이미 읽은 알림
//   - match_cancelled 대상 일정이 취소됨 (일정 취소 알림 자체는 제외: 취소를 알리는 알림이므로)
//   - match_started 대상 일정이 이미 시작함
//   - left_team     받는 사람이 알림이 생긴 뒤 그 팀을 떠남 (지금 소속이 아니고, 마지막으로 떠난 시각이 알림보다 뒤)
//                   → 내보내진 본인 알림·해체 알림(떠난 순간 = 알림 시각)·가입 거절 알림(소속 이력 없음)은 건너뛰지 않는다
//   - no_device     기기 주소가 하나도 없음 (보낼 곳이 없음)
//
// FCM 응답 (HTTP v1):
//   - 200                         → ok
//   - 404 또는 errorCode UNREGISTERED → unregistered (그 기기 주소 삭제, data-model 2-4)
//   - 401·403(인증)               → auth (이번 실행의 남은 발송을 멈춘다)
//   - 그 밖 (400·429·5xx·네트워크) → error
// 대기열 줄 최종 상태: 한 기기라도 성공 → sent / 성공 없이 오류가 있으면 → failed / 모두 등록 안 된 토큰 → skipped

/** claim_push_batch 가 돌려주는 한 줄 (snake_case 그대로). */
export type ClaimedRow = {
  outbox_id: string;
  notification_id: string;
  kind: string;
  title: string;
  body: string;
  team_id: string | null;
  ref_type: string | null;
  ref_id: string | null;
  notified_at: string;
  read_at: string | null;
  match_status: string | null;
  match_starts_at: string | null;
  recipient_active: boolean;
  recipient_left_at: string | null;
  tokens: string[] | null;
};

export type SkipReason = 'read' | 'match_cancelled' | 'match_started' | 'left_team' | 'no_device';

const time = (iso: string | null): number | null => {
  if (!iso) return null;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? null : t;
};

/** 푸시를 건너뛸 이유 (없으면 null). [now] 는 밀리초. */
export function skipReason(row: ClaimedRow, now: number): SkipReason | null {
  if (row.read_at) return 'read';

  if (row.ref_type === 'match') {
    if (row.match_status === 'cancelled' && row.kind !== 'match_cancelled') return 'match_cancelled';
    const starts = time(row.match_starts_at);
    if (starts !== null && starts <= now) return 'match_started';
  }

  if (row.team_id && !row.recipient_active) {
    const left = time(row.recipient_left_at);
    const notified = time(row.notified_at);
    if (left !== null && notified !== null && left > notified) return 'left_team';
  }

  if (!row.tokens || row.tokens.length === 0) return 'no_device';
  return null;
}

/**
 * 푸시를 눌렀을 때 앱이 이동할 대상 (FCM data 는 모두 글자). 알림함 줄과 같은 정보만 넣는다.
 * 비밀·민감 정보(토큰, 실력 등급, 다른 사람 ID 등)는 넣지 않는다.
 */
export function pushData(row: ClaimedRow): Record<string, string> {
  const data: Record<string, string> = {
    notification_id: row.notification_id,
    kind: row.kind,
  };
  if (row.team_id) data.team_id = row.team_id;
  if (row.ref_type && row.ref_id) {
    data.ref_type = row.ref_type;
    data.ref_id = row.ref_id;
  }
  return data;
}

/** FCM HTTP v1 messages:send 요청 본문. 제목·본문은 알림함 줄과 같다 (9-1). */
export function buildFcmMessage(row: ClaimedRow, token: string) {
  return {
    message: {
      token,
      notification: { title: row.title, body: row.body },
      data: pushData(row),
      android: {
        priority: 'HIGH',
        // 같은 알림이 혹시 두 번 와도 휴대폰에는 한 줄만 보이게
        notification: { tag: row.notification_id },
      },
    },
  };
}

export type SendOutcome = 'ok' | 'unregistered' | 'auth' | 'error';

/** FCM 응답 → 결과. [body] 는 JSON 으로 읽은 응답 본문(못 읽었으면 null). */
export function classifyFcmResponse(status: number, body: unknown): SendOutcome {
  if (status >= 200 && status < 300) return 'ok';
  if (status === 404) return 'unregistered';
  if (fcmErrorCode(body) === 'UNREGISTERED') return 'unregistered';
  if (status === 401 || status === 403) return 'auth';
  return 'error';
}

/** FCM 오류 본문의 details[].errorCode (FcmError). */
export function fcmErrorCode(body: unknown): string | null {
  if (!body || typeof body !== 'object') return null;
  const error = (body as { error?: unknown }).error;
  if (!error || typeof error !== 'object') return null;
  const details = (error as { details?: unknown }).details;
  if (!Array.isArray(details)) return null;
  for (const d of details) {
    if (d && typeof d === 'object' && typeof (d as { errorCode?: unknown }).errorCode === 'string') {
      return (d as { errorCode: string }).errorCode;
    }
  }
  return null;
}

export type FinalStatus = 'sent' | 'skipped' | 'failed';

/** 한 알림(받는 사람의 모든 기기)의 결과를 대기열 상태로. */
export function finalStatus(outcomes: SendOutcome[]): FinalStatus {
  if (outcomes.some((o) => o === 'ok')) return 'sent';
  if (outcomes.some((o) => o === 'error' || o === 'auth')) return 'failed';
  return 'skipped';
}

// ---------------------------------------------------------------------------
// 서비스 계정 (서버 비밀값 FIREBASE_SERVICE_ACCOUNT, JSON 문자열)
// ---------------------------------------------------------------------------

export type ServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
  tokenUri: string;
};

export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
export const GOOGLE_TOKEN_URI = 'https://oauth2.googleapis.com/token';

/** 비밀값 JSON → 필요한 칸. 빠졌거나 모양이 틀리면 null (값은 어디에도 출력하지 않는다). */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw || !raw.trim()) return null;
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!json || typeof json !== 'object') return null;
  const o = json as Record<string, unknown>;
  const str = (k: string) => (typeof o[k] === 'string' && (o[k] as string).length > 0 ? (o[k] as string) : null);
  const projectId = str('project_id');
  const clientEmail = str('client_email');
  const privateKey = str('private_key');
  if (!projectId || !clientEmail || !privateKey || !privateKey.includes('PRIVATE KEY')) return null;
  return { projectId, clientEmail, privateKey, tokenUri: str('token_uri') ?? GOOGLE_TOKEN_URI };
}

/** OAuth 토큰 요청용 JWT 의 머리·내용 (서명 전). [nowSec] 는 초. */
export function jwtParts(sa: ServiceAccount, nowSec: number) {
  return {
    header: { alg: 'RS256', typ: 'JWT' },
    claims: {
      iss: sa.clientEmail,
      scope: FCM_SCOPE,
      aud: sa.tokenUri,
      iat: nowSec,
      exp: nowSec + 3600,
    },
  };
}

export function base64Url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export const base64UrlJson = (value: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(value)));

/** PEM(PKCS#8) → DER 바이트. */
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, '')
    .replace(/-----END [A-Z ]+-----/g, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** 여러 작업을 최대 [limit]개씩 동시에. 순서대로 결과를 돌려준다. */
export async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(Math.max(limit, 1), items.length) }, worker));
  return results;
}
