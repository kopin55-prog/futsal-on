// 로컬 테스트: npx --yes deno test supabase/functions/notifier/notifier_test.ts
// notifier 의 건너뛰기 판단·FCM 응답 처리·배치 처리·호출 보호. Supabase·FCM 을 부르지 않는다 (가짜 발송).

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { CRON_SECRET_HEADER } from '../_shared/cron_auth.ts';
import { handle, processBatch } from './index.ts';
import {
  base64Url,
  buildFcmMessage,
  type ClaimedRow,
  classifyFcmResponse,
  FCM_SCOPE,
  finalStatus,
  jwtParts,
  mapLimit,
  parseServiceAccount,
  pemToDer,
  pushData,
  type SendOutcome,
  skipReason,
} from './logic.ts';

const NOW = Date.parse('2026-11-11T04:00:00Z'); // 한국 13:00

const row = (over: Partial<ClaimedRow> = {}): ClaimedRow => ({
  outbox_id: 'o1',
  notification_id: 'n1',
  kind: 'match_created',
  title: '피FC',
  body: '11월 12일(수) 10:00 경기가 열렸어요! 이번 주도 뛰어야죠, 참석 투표 부탁드려요.',
  team_id: 't1',
  ref_type: 'match',
  ref_id: 'm1',
  notified_at: '2026-11-10T17:00:00Z', // 한국 02:00
  read_at: null,
  match_status: 'scheduled',
  match_starts_at: '2026-11-12T01:00:00Z',
  match_ends_at: '2026-11-12T03:00:00Z',
  award_poll_status: null,
  award_poll_closes_at: null,
  lineup_status: null,
  recipient_active: true,
  recipient_left_at: null,
  tokens: ['tok-a'],
  ...over,
});

// ---------------------------------------------------------------- 건너뛰기 (Q-073 5번)
Deno.test('skipReason: 보낼 알림은 null', () => {
  assertEquals(skipReason(row(), NOW), null);
});

Deno.test('skipReason: 이미 읽은 알림', () => {
  assertEquals(skipReason(row({ read_at: '2026-11-11T00:00:00Z' }), NOW), 'read');
});

Deno.test('skipReason: 대상 일정 취소 (SE-14). 취소 알림 자체는 보낸다', () => {
  assertEquals(skipReason(row({ match_status: 'cancelled' }), NOW), 'match_cancelled');
  assertEquals(skipReason(row({ kind: 'match_cancelled', match_status: 'cancelled' }), NOW), null);
});

Deno.test('skipReason: 대상 일정이 이미 시작 (정각 포함). 취소 알림도 시작 뒤면 건너뜀', () => {
  assertEquals(skipReason(row({ match_starts_at: '2026-11-11T03:00:00Z' }), NOW), 'match_started');
  assertEquals(skipReason(row({ match_starts_at: '2026-11-11T04:00:00Z' }), NOW), 'match_started');
  assertEquals(skipReason(row({ match_starts_at: '2026-11-11T04:00:01Z' }), NOW), null);
  assertEquals(
    skipReason(row({ kind: 'match_cancelled', match_status: 'cancelled', match_starts_at: '2026-11-11T01:00:00Z' }), NOW),
    'match_started',
  );
  assertEquals(skipReason(row({ kind: 'waitlist_promoted', match_starts_at: '2026-11-11T01:00:00Z' }), NOW), 'match_started');
});

// ---------------------------------------------------------------- 종류별 규칙 (스프린트 03 4-7)
// 끝난 경기(한국 11월 11일 10:00~12:00)의 투표, 지금은 한국 13:00
const ended = { match_starts_at: '2026-11-11T01:00:00Z', match_ends_at: '2026-11-11T03:00:00Z' };

Deno.test('skipReason: 투표 오픈 알림은 경기가 시작·종료돼도 투표가 진행 중이면 보낸다', () => {
  const r = row({ kind: 'award_poll_opened', ...ended, award_poll_status: 'open', award_poll_closes_at: '2026-11-12T06:00:00Z' });
  assertEquals(skipReason(r, NOW), null);
});

Deno.test('skipReason: 투표 오픈 알림은 투표가 마감됐거나(정각 포함) 회차가 없으면 건너뜀', () => {
  const base = { kind: 'award_poll_opened', ...ended };
  assertEquals(skipReason(row({ ...base, award_poll_status: 'closed', award_poll_closes_at: '2026-11-12T06:00:00Z' }), NOW), 'poll_closed');
  assertEquals(skipReason(row({ ...base, award_poll_status: 'open', award_poll_closes_at: '2026-11-11T04:00:00Z' }), NOW), 'poll_closed');
  assertEquals(skipReason(row({ ...base, award_poll_status: 'open', award_poll_closes_at: '2026-11-11T03:59:59Z' }), NOW), 'poll_closed');
  assertEquals(skipReason(row({ ...base, award_poll_status: null, award_poll_closes_at: null }), NOW), 'poll_closed');
  assertEquals(
    skipReason(row({ kind: 'award_deadline_soon', ...ended, award_poll_status: 'closed', award_poll_closes_at: '2026-11-11T04:00:00Z' }), NOW),
    'poll_closed',
  );
});

Deno.test('skipReason: 결과 발표 알림은 시작·마감을 이유로 건너뛰지 않는다', () => {
  const r = row({ kind: 'award_results_announced', ...ended, award_poll_status: 'closed', award_poll_closes_at: '2026-11-11T04:00:00Z' });
  assertEquals(skipReason(r, NOW), null);
});

Deno.test('skipReason: POM 알림도 읽음·떠난 팀·기기 없음 규칙은 그대로', () => {
  const open = { kind: 'award_poll_opened', ...ended, award_poll_status: 'open', award_poll_closes_at: '2026-11-12T06:00:00Z' };
  assertEquals(skipReason(row({ ...open, read_at: '2026-11-11T03:30:00Z' }), NOW), 'read');
  assertEquals(skipReason(row({ ...open, recipient_active: false, recipient_left_at: '2026-11-11T03:30:00Z' }), NOW), 'left_team');
  const results = { kind: 'award_results_announced', ...ended, award_poll_status: 'closed' };
  assertEquals(skipReason(row({ ...results, read_at: '2026-11-11T03:30:00Z' }), NOW), 'read');
  assertEquals(skipReason(row({ ...results, recipient_active: false, recipient_left_at: '2026-11-11T03:30:00Z' }), NOW), 'left_team');
  assertEquals(skipReason(row({ ...results, tokens: [] }), NOW), 'no_device');
});

Deno.test('skipReason: 배치 미확정 알림은 경기 중이면 보내고, 끝났으면(정각 포함) 건너뜀', () => {
  const base = { kind: 'lineup_unconfirmed', match_starts_at: '2026-11-11T03:00:00Z' };
  assertEquals(skipReason(row({ ...base, match_ends_at: '2026-11-11T05:00:00Z' }), NOW), null);
  assertEquals(skipReason(row({ ...base, match_ends_at: '2026-11-11T04:00:00Z' }), NOW), 'match_ended');
  assertEquals(skipReason(row({ ...base, match_ends_at: '2026-11-11T03:30:00Z' }), NOW), 'match_ended');
});

Deno.test('skipReason: 배치 미확정 알림은 푸시 전에 배치가 확정됐으면 건너뜀, 초안·배치 없음이면 보낸다', () => {
  const base = { kind: 'lineup_unconfirmed', match_starts_at: '2026-11-11T03:00:00Z', match_ends_at: '2026-11-11T05:00:00Z' };
  assertEquals(skipReason(row({ ...base, lineup_status: 'confirmed' }), NOW), 'lineup_confirmed');
  assertEquals(skipReason(row({ ...base, lineup_status: 'draft' }), NOW), null);
  assertEquals(skipReason(row({ ...base, lineup_status: null }), NOW), null);
  // 이미 읽었으면 읽음이 먼저
  assertEquals(skipReason(row({ ...base, lineup_status: 'confirmed', read_at: '2026-11-11T03:10:00Z' }), NOW), 'read');
});

Deno.test('skipReason: 배치 확정 상태는 배치 미확정 알림에만 쓴다 (확정·변경 알림은 그대로)', () => {
  const future = { match_starts_at: '2026-11-12T01:00:00Z', match_ends_at: '2026-11-12T03:00:00Z', lineup_status: 'confirmed' };
  assertEquals(skipReason(row({ kind: 'lineup_confirmed', ...future }), NOW), null);
  assertEquals(skipReason(row({ kind: 'lineup_changed', ...future }), NOW), null);
});

Deno.test('skipReason: 그 밖의 종류는 경기 시작 규칙 그대로 (배치 확정 알림 등)', () => {
  assertEquals(skipReason(row({ kind: 'lineup_confirmed', ...ended }), NOW), 'match_started');
  assertEquals(skipReason(row({ kind: 'lineup_changed', ...ended, award_poll_status: 'open' }), NOW), 'match_started');
});

Deno.test('skipReason: 일정이 아닌 알림은 일정 조건을 보지 않는다', () => {
  assertEquals(
    skipReason(row({ kind: 'join_request_received', ref_type: 'join_request', match_status: null, match_starts_at: null }), NOW),
    null,
  );
});

Deno.test('skipReason: 알림이 생긴 뒤 팀을 떠남', () => {
  assertEquals(skipReason(row({ recipient_active: false, recipient_left_at: '2026-11-11T00:00:00Z' }), NOW), 'left_team');
});

Deno.test('skipReason: 떠난 순간에 생긴 알림(내보내기·해체)·소속 이력 없음(가입 거절)·다시 들어옴은 보낸다', () => {
  const at = '2026-11-10T17:00:00Z';
  assertEquals(
    skipReason(row({ kind: 'member_removed', ref_type: 'team', recipient_active: false, recipient_left_at: at }), NOW),
    null,
  );
  assertEquals(
    skipReason(row({ kind: 'team_dissolved', ref_type: 'team', recipient_active: false, recipient_left_at: at }), NOW),
    null,
  );
  assertEquals(
    skipReason(row({ kind: 'join_request_decided', ref_type: 'join_request', recipient_active: false, recipient_left_at: null }), NOW),
    null,
  );
  // 예전에 떠났다가 다시 신청 → 거절: 떠난 시각이 알림보다 앞
  assertEquals(
    skipReason(row({ kind: 'join_request_decided', ref_type: 'join_request', recipient_active: false, recipient_left_at: '2026-10-01T00:00:00Z' }), NOW),
    null,
  );
  // 떠났다가 다시 들어와 지금 소속
  assertEquals(skipReason(row({ recipient_active: true, recipient_left_at: '2026-11-11T00:00:00Z' }), NOW), null);
});

Deno.test('skipReason: 기기 주소가 없으면 no_device', () => {
  assertEquals(skipReason(row({ tokens: [] }), NOW), 'no_device');
  assertEquals(skipReason(row({ tokens: null }), NOW), 'no_device');
});

// ---------------------------------------------------------------- 메시지
Deno.test('buildFcmMessage: 제목·본문은 알림함 줄과 같고 data 는 이동 대상만 (I-06)', () => {
  const m = buildFcmMessage(row(), 'tok-a').message;
  assertEquals(m.token, 'tok-a');
  assertEquals(m.notification, { title: row().title, body: row().body });
  assertEquals(m.data, { notification_id: 'n1', kind: 'match_created', team_id: 't1', ref_type: 'match', ref_id: 'm1' });
  assertEquals(m.android.notification.tag, 'n1');
  for (const v of Object.values(m.data)) assertEquals(typeof v, 'string');
});

Deno.test('pushData: 대상이 없으면 빼고 넣는다', () => {
  assertEquals(pushData(row({ ref_type: null, ref_id: null, team_id: null })), { notification_id: 'n1', kind: 'match_created' });
});

// ---------------------------------------------------------------- FCM 응답
Deno.test('classifyFcmResponse', () => {
  assertEquals(classifyFcmResponse(200, { name: 'projects/x/messages/1' }), 'ok');
  assertEquals(classifyFcmResponse(404, { error: { status: 'NOT_FOUND' } }), 'unregistered');
  assertEquals(classifyFcmResponse(404, null), 'unregistered');
  assertEquals(
    classifyFcmResponse(400, { error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }),
    'unregistered',
  );
  assertEquals(classifyFcmResponse(400, { error: { details: [{ errorCode: 'INVALID_ARGUMENT' }] } }), 'error');
  assertEquals(classifyFcmResponse(401, null), 'auth');
  assertEquals(classifyFcmResponse(403, { error: { details: [{ errorCode: 'SENDER_ID_MISMATCH' }] } }), 'auth');
  assertEquals(classifyFcmResponse(429, null), 'error');
  assertEquals(classifyFcmResponse(503, null), 'error');
});

Deno.test('finalStatus: 하나라도 성공 sent, 성공 없이 오류 failed, 모두 등록 안 됨 skipped', () => {
  assertEquals(finalStatus(['unregistered', 'ok']), 'sent');
  assertEquals(finalStatus(['error', 'ok']), 'sent');
  assertEquals(finalStatus(['error', 'unregistered']), 'failed');
  assertEquals(finalStatus(['auth']), 'failed');
  assertEquals(finalStatus(['unregistered', 'unregistered']), 'skipped');
  assertEquals(finalStatus([]), 'skipped');
});

// ---------------------------------------------------------------- 배치 처리
Deno.test('processBatch: 기기마다 하나씩 보내고, 등록 안 된 토큰은 모으고, 건너뛸 줄은 보내지 않는다', async () => {
  const calls: string[] = [];
  const outcomes: Record<string, SendOutcome> = { 'tok-a': 'ok', 'tok-dead': 'unregistered', 'tok-b': 'ok', 'tok-x': 'error' };
  const send = (r: ClaimedRow, token: string) => {
    calls.push(`${r.outbox_id}:${token}`);
    return Promise.resolve(outcomes[token]);
  };
  const rows = [
    row({ outbox_id: 'two-devices', tokens: ['tok-a', 'tok-dead'] }), // I-02, I-03
    row({ outbox_id: 'read', read_at: '2026-11-11T00:00:00Z', tokens: ['tok-b'] }),
    row({ outbox_id: 'cancelled', match_status: 'cancelled', tokens: ['tok-b'] }),
    row({ outbox_id: 'no-device', tokens: [] }), // SE-20
    row({ outbox_id: 'only-dead', tokens: ['tok-dead'] }),
    row({ outbox_id: 'error', tokens: ['tok-x'] }), // SE-19
    row({ outbox_id: 'ok', tokens: ['tok-b'] }),
  ];
  const r = await processBatch(rows, send, NOW);
  assertEquals(r.results, [
    { id: 'two-devices', status: 'sent' },
    { id: 'read', status: 'skipped' },
    { id: 'cancelled', status: 'skipped' },
    { id: 'no-device', status: 'skipped' },
    { id: 'only-dead', status: 'skipped' },
    { id: 'error', status: 'failed' },
    { id: 'ok', status: 'sent' },
  ]);
  assertEquals(r.deadTokens, ['tok-dead']);
  assertEquals(calls.sort(), ['error:tok-x', 'ok:tok-b', 'only-dead:tok-dead', 'two-devices:tok-a', 'two-devices:tok-dead']);
  assertEquals(r.counts.sent, 2);
  assertEquals(r.counts.skipped, 4);
  assertEquals(r.counts.failed, 1);
  assertEquals(r.counts.skip_read, 1);
  assertEquals(r.counts.skip_match_cancelled, 1);
  assertEquals(r.counts.skip_no_device, 1);
});

Deno.test('processBatch: 발송 예외는 그 기기만 실패, 다른 사람 발송은 계속 (SE-20)', async () => {
  const send = (_r: ClaimedRow, token: string) =>
    token === 'boom' ? Promise.reject(new Error('network')) : Promise.resolve('ok' as SendOutcome);
  const r = await processBatch([row({ outbox_id: 'a', tokens: ['boom'] }), row({ outbox_id: 'b', tokens: ['fine'] })], send, NOW);
  assertEquals(r.results, [{ id: 'a', status: 'failed' }, { id: 'b', status: 'sent' }]);
});

Deno.test('processBatch: 인증 실패가 나면 남은 발송을 멈추고 failed', async () => {
  let calls = 0;
  const send = () => {
    calls++;
    return Promise.resolve('auth' as SendOutcome);
  };
  const rows = Array.from({ length: 20 }, (_, i) => row({ outbox_id: `r${i}`, tokens: ['t1', 't2'] }));
  const r = await processBatch(rows, send, NOW);
  assert(r.results.every((x) => x.status === 'failed'));
  assert(calls <= 8, `calls=${calls}`); // 동시 요청 수 이하에서 멈춤
  assertEquals(r.counts.auth_failed, 1);
  assertEquals(r.deadTokens, []);
});

Deno.test('mapLimit: 순서 유지, 동시 실행 상한', async () => {
  let running = 0;
  let peak = 0;
  const out = await mapLimit([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((r) => setTimeout(r, 5));
    running--;
    return n * 2;
  });
  assertEquals(out, [2, 4, 6, 8, 10, 12, 14]);
  assert(peak <= 3);
  assertEquals(await mapLimit([], 3, (n: number) => Promise.resolve(n)), []);
});

// ---------------------------------------------------------------- 서비스 계정·JWT
async function testKeyPem() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let bin = '';
  for (const b of der) bin += String.fromCharCode(b);
  const b64 = btoa(bin).replace(/(.{64})/g, '$1\n');
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

Deno.test('parseServiceAccount: 필요한 칸만, 모양이 틀리면 null', async () => {
  const { pem } = await testKeyPem();
  const sa = parseServiceAccount(JSON.stringify({
    type: 'service_account',
    project_id: 'futsal-on-dev',
    client_email: 'x@futsal-on-dev.iam.gserviceaccount.com',
    private_key: pem,
  }));
  assertEquals(sa?.projectId, 'futsal-on-dev');
  assertEquals(sa?.tokenUri, 'https://oauth2.googleapis.com/token');
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount(''), null);
  assertEquals(parseServiceAccount('{not json'), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: 'p', client_email: 'e' })), null);
  assertEquals(parseServiceAccount(JSON.stringify({ project_id: 'p', client_email: 'e', private_key: 'abc' })), null);
});

Deno.test('JWT: 서비스 계정 키(PEM, 한 줄 JSON 의 \\n 포함)로 서명하고 공개 키로 검증된다', async () => {
  const { pem, publicKey } = await testKeyPem();
  // 한 줄 JSON 으로 만들어도 JSON.parse 뒤에는 실제 줄바꿈이 된다 (setup_push.ps1 과 같은 모양)
  const sa = parseServiceAccount(JSON.stringify({ project_id: 'p', client_email: 'svc@p.iam', private_key: pem }))!;
  const { header, claims } = jwtParts(sa, 1_000_000);
  assertEquals(header, { alg: 'RS256', typ: 'JWT' });
  assertEquals(claims, { iss: 'svc@p.iam', scope: FCM_SCOPE, aud: 'https://oauth2.googleapis.com/token', iat: 1_000_000, exp: 1_003_600 });
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(sa.privateKey), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const data = new TextEncoder().encode('a.b');
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, data));
  assert(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, sig, data));
  // 이스케이프된 \n 이 그대로 남은 키도 읽는다
  assertEquals(pemToDer(pem.replace(/\n/g, '\\n')), pemToDer(pem));
  assertEquals(base64Url(new Uint8Array([251, 255])), '-_8');
});

// ---------------------------------------------------------------- 호출 보호 (SE-18)
const SECRET = 'c'.repeat(64);
const req = (method: string, headers: Record<string, string> = {}) => new Request('http://localhost/', { method, headers });

Deno.test('handle: 비밀값 없음 401, 다른 값 401, GET 405, 맞으면 run', async () => {
  let ran = 0;
  const deps = { env: (n: string) => (n === 'CRON_SECRET' ? SECRET : undefined), run: () => { ran++; return Promise.resolve(new Response('ok')); } };
  assertEquals((await handle(req('POST'), deps)).status, 401);
  assertEquals((await handle(req('POST', { [CRON_SECRET_HEADER]: 'd'.repeat(64) }), deps)).status, 401);
  assertEquals((await handle(req('POST', { Authorization: 'Bearer user-jwt' }), deps)).status, 401);
  assertEquals((await handle(req('GET', { [CRON_SECRET_HEADER]: SECRET }), deps)).status, 405);
  assertEquals(ran, 0);
  assertEquals((await handle(req('POST', { [CRON_SECRET_HEADER]: SECRET }), deps)).status, 200);
  assertEquals(ran, 1);
  const unconfigured = { env: () => undefined, run: deps.run };
  assertEquals((await handle(req('POST', { [CRON_SECRET_HEADER]: SECRET }), unconfigured)).status, 500);
});
