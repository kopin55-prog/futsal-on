// 예약 작업 전용 호출 확인 (account-cleanup, team-logo-cleanup 공통).
//
// 예약 작업(pg_cron + pg_net, 마이그레이션 202611050018)은 Vault 의 cron_secret 값을 x-cron-secret 헤더로 보낸다.
// 함수는 그 값이 서버 비밀값 CRON_SECRET 과 같을 때만 동작한다. service_role 키는 DB 에 두지 않는다.
// 비교는 두 값의 SHA-256 을 끝까지 비교해 걸리는 시간이 내용·길이에 따라 달라지지 않게 한다.
// 이 함수들은 verify_jwt 를 끄고 배포한다 (예약 작업은 JWT 를 보내지 않는다).

export const CRON_SECRET_HEADER = 'x-cron-secret';

/** 비밀값이 이보다 짧으면 설정이 잘못된 것으로 보고 모두 거절한다. */
const MIN_SECRET_LENGTH = 32;

async function sha256(text: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
}

/** 상수 시간 비교. */
export async function secretsEqual(a: string, b: string): Promise<boolean> {
  const [ha, hb] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < ha.length; i++) diff |= ha[i] ^ hb[i];
  return diff === 0;
}

export type CronAuthResult = 'ok' | 'not_configured' | 'not_authorized';

/** expected 는 서버 비밀값 CRON_SECRET (없으면 not_configured). */
export async function checkCronSecret(req: Request, expected: string | undefined): Promise<CronAuthResult> {
  const secret = (expected ?? '').trim();
  if (secret.length < MIN_SECRET_LENGTH) return 'not_configured';
  const given = req.headers.get(CRON_SECRET_HEADER) ?? '';
  return (await secretsEqual(given, secret)) ? 'ok' : 'not_authorized';
}

export const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

/** 405 / 401 / 500 응답 또는 통과(null). */
export async function guardCronRequest(req: Request, expected: string | undefined): Promise<Response | null> {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  const result = await checkCronSecret(req, expected);
  if (result === 'not_configured') return json(500, { error: 'not_configured' });
  if (result === 'not_authorized') return json(401, { error: 'not_authorized' });
  return null;
}
