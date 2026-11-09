// 푸시 발송 (스프린트 02 5-2, data-model.md 9-1). 예약 실행 전용.
//
// 흐름 (한 번 실행)
//   1) public.claim_push_batch(BATCH): send_at 이 지난 pending 줄을 잠그며 잡는다 (잡은 줄은 바로 pending 에서 빠짐 → 중복 발송 없음)
//   2) 줄마다 건너뛰기 판단(logic.ts skipReason) → 건너뛰면 skipped
//   3) 아니면 그 사람의 모든 기기로 하나씩 FCM HTTP v1 발송 (제목·본문 = 알림함 줄, data = 누르면 이동할 대상)
//   4) public.finish_push_batch(결과, 등록 안 된 토큰): 상태·처리 시각 기록, 등록 안 된 기기 주소 삭제
//   알림함 줄은 건드리지 않는다 (실패해도 알림함은 그대로).
//
// 호출 보호: x-cron-secret 헤더가 서버 비밀값 CRON_SECRET 과 같을 때만 실행 (_shared/cron_auth.ts).
//   예약 작업(202611050036, 매분, 보낼 줄이 있을 때만)이 Vault 의 cron_secret 을 보낸다.
//   배포: supabase functions deploy notifier --no-verify-jwt (supabase/scripts/setup_push.ps1)
// 필요한 서버 비밀값: CRON_SECRET, FIREBASE_SERVICE_ACCOUNT (서비스 계정 JSON 문자열)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동 제공
// 로그에는 개수만 남긴다 (토큰·사람 ID·문구 없음).

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { guardCronRequest, json } from '../_shared/cron_auth.ts';
import {
  base64Url,
  base64UrlJson,
  buildFcmMessage,
  type ClaimedRow,
  classifyFcmResponse,
  finalStatus,
  type FinalStatus,
  jwtParts,
  mapLimit,
  parseServiceAccount,
  pemToDer,
  type SendOutcome,
  type ServiceAccount,
  skipReason,
} from './logic.ts';

/** 한 번 실행에 처리하는 대기열 줄 수 상한. 남은 줄은 다음 분에. */
export const BATCH = 100;

/** FCM 동시 요청 수. */
const CONCURRENCY = 8;

export type Deps = {
  env: (name: string) => string | undefined;
  /** 실제 발송 (비밀값 확인을 통과했을 때만 부른다). */
  run: () => Promise<Response>;
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const rejected = await guardCronRequest(req, deps.env('CRON_SECRET'));
  if (rejected) return rejected;
  return await deps.run();
}

export type BatchResult = {
  results: { id: string; status: FinalStatus }[];
  deadTokens: string[];
  counts: Record<string, number>;
};

/**
 * 잡은 줄들을 처리한다 (발송 함수만 바꿔 끼우면 테스트 가능).
 * [send] 가 'auth' 를 한 번 돌려주면 남은 발송은 하지 않고 failed 로 둔다 (자격 증명 문제는 다음 실행도 같으므로).
 */
export async function processBatch(
  rows: ClaimedRow[],
  send: (row: ClaimedRow, token: string) => Promise<SendOutcome>,
  now: number,
): Promise<BatchResult> {
  const counts: Record<string, number> = { sent: 0, skipped: 0, failed: 0 };
  const deadTokens = new Set<string>();
  let authFailed = false;

  const guardedSend = async (row: ClaimedRow, token: string): Promise<SendOutcome> => {
    if (authFailed) return 'auth';
    let outcome: SendOutcome;
    try {
      outcome = await send(row, token);
    } catch {
      outcome = 'error';
    }
    if (outcome === 'auth') authFailed = true;
    return outcome;
  };

  const results = await mapLimit(rows, CONCURRENCY, async (row) => {
    const reason = skipReason(row, now);
    if (reason) {
      counts[`skip_${reason}`] = (counts[`skip_${reason}`] ?? 0) + 1;
      return { id: row.outbox_id, status: 'skipped' as FinalStatus };
    }
    const outcomes: SendOutcome[] = [];
    for (const token of row.tokens ?? []) {
      const o = await guardedSend(row, token);
      if (o === 'unregistered') deadTokens.add(token);
      outcomes.push(o);
    }
    return { id: row.outbox_id, status: finalStatus(outcomes) };
  });

  for (const r of results) counts[r.status]++;
  if (authFailed) counts.auth_failed = 1;
  return { results, deadTokens: [...deadTokens], counts };
}

// ---------------------------------------------------------------------------
// FCM (HTTP v1) — OAuth 토큰은 서비스 계정 키로 만든 JWT 를 구글에 바꿔 받는다 (외부 라이브러리 없음)
// ---------------------------------------------------------------------------

let cachedToken: { value: string; expiresAt: number; email: string } | null = null;

async function accessToken(sa: ServiceAccount): Promise<string | null> {
  const nowMs = Date.now();
  if (cachedToken && cachedToken.email === sa.clientEmail && cachedToken.expiresAt - 60_000 > nowMs) {
    return cachedToken.value;
  }
  const { header, claims } = jwtParts(sa, Math.floor(nowMs / 1000));
  const unsigned = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey(
      'pkcs8',
      pemToDer(sa.privateKey),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
  } catch {
    return null;
  }
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const res = await fetch(sa.tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${base64Url(signature)}`,
    }),
  });
  if (!res.ok) {
    await res.body?.cancel();
    return null;
  }
  const body = (await res.json()) as { access_token?: string; expires_in?: number };
  if (!body.access_token) return null;
  cachedToken = {
    value: body.access_token,
    expiresAt: nowMs + (body.expires_in ?? 3600) * 1000,
    email: sa.clientEmail,
  };
  return body.access_token;
}

function fcmSender(sa: ServiceAccount, bearer: string) {
  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.projectId)}/messages:send`;
  return async (row: ClaimedRow, token: string): Promise<SendOutcome> => {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` },
      body: JSON.stringify(buildFcmMessage(row, token)),
    });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      body = null;
    }
    return classifyFcmResponse(res.status, body);
  };
}

async function runNotifier(): Promise<Response> {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const sa = parseServiceAccount(Deno.env.get('FIREBASE_SERVICE_ACCOUNT'));
  // 서비스 계정이 없으면 줄을 잡지 않는다 (pending 그대로, 비밀값 등록 후 다음 실행에 발송)
  if (!url || !serviceKey || !sa) return json(500, { error: 'not_configured' });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  const { data, error } = await admin.rpc('claim_push_batch', { p_limit: BATCH });
  if (error) return json(500, { error: 'internal_error' });
  const rows = (data ?? []) as ClaimedRow[];
  if (rows.length === 0) return json(200, { claimed: 0 });

  // 잡은 뒤 OAuth 실패 → 보낼 줄은 failed (잡은 줄은 이미 failed 상태), 건너뛸 줄은 skipped 로 적는다
  const bearer = await accessToken(sa).catch(() => null);
  const send = bearer ? fcmSender(sa, bearer) : async () => 'auth' as SendOutcome;

  const batch = await processBatch(rows, send, Date.now());

  const { error: finishError } = await admin.rpc('finish_push_batch', {
    p_results: batch.results,
    p_dead_tokens: batch.deadTokens,
  });
  if (finishError) {
    console.warn('finish failed', { claimed: rows.length });
    return json(500, { error: 'internal_error' });
  }

  if (!bearer) console.warn('fcm auth failed');
  console.log('notifier', { claimed: rows.length, ...batch.counts, dead_tokens: batch.deadTokens.length });
  return json(200, { claimed: rows.length, ...batch.counts });
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (name) => Deno.env.get(name), run: runNotifier }));
}
