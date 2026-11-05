// 로컬 테스트: npx --yes deno test supabase/functions/_shared/cron_auth_test.ts
// 예약 작업 전용 비밀값 확인 (account-cleanup, team-logo-cleanup). Supabase·카카오를 부르지 않는다 (가짜 run).

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkCronSecret, CRON_SECRET_HEADER, secretsEqual } from './cron_auth.ts';
import { handle as accountCleanup } from '../account-cleanup/index.ts';
import { handle as teamLogoCleanup } from '../team-logo-cleanup/index.ts';

const SECRET = 'a'.repeat(64);

const req = (method: string, headers: Record<string, string> = {}) =>
  new Request('http://localhost/', { method, headers });

Deno.test('secretsEqual: 같은 값만 참', async () => {
  assert(await secretsEqual(SECRET, SECRET));
  assert(!(await secretsEqual(SECRET, 'a'.repeat(63))));
  assert(!(await secretsEqual(SECRET, 'b' + 'a'.repeat(63))));
  assert(!(await secretsEqual('', SECRET)));
});

Deno.test('checkCronSecret: 서버 비밀값이 없거나 짧으면 not_configured', async () => {
  const r = req('POST', { [CRON_SECRET_HEADER]: '' });
  assertEquals(await checkCronSecret(r, undefined), 'not_configured');
  assertEquals(await checkCronSecret(r, ''), 'not_configured');
  assertEquals(await checkCronSecret(r, '   '), 'not_configured');
  assertEquals(await checkCronSecret(req('POST', { [CRON_SECRET_HEADER]: 'short' }), 'short'), 'not_configured');
});

Deno.test('checkCronSecret: 헤더 없음·다른 값·Authorization 만 있으면 거절', async () => {
  assertEquals(await checkCronSecret(req('POST'), SECRET), 'not_authorized');
  assertEquals(await checkCronSecret(req('POST', { [CRON_SECRET_HEADER]: 'x' + SECRET }), SECRET), 'not_authorized');
  assertEquals(await checkCronSecret(req('POST', { Authorization: `Bearer ${SECRET}` }), SECRET), 'not_authorized');
  assertEquals(await checkCronSecret(req('POST', { [CRON_SECRET_HEADER]: SECRET }), SECRET), 'ok');
});

for (const [name, handle] of [
  ['account-cleanup', accountCleanup],
  ['team-logo-cleanup', teamLogoCleanup],
] as const) {
  const deps = (secret: string | undefined) => {
    const calls = { n: 0 };
    return {
      calls,
      deps: {
        env: (k: string) => (k === 'CRON_SECRET' ? secret : undefined),
        run: () => {
          calls.n++;
          return Promise.resolve(new Response('{"deleted":0}', { status: 200 }));
        },
      },
    };
  };

  Deno.test(`${name}: 맞는 비밀값이면 정리 실행`, async () => {
    const { calls, deps: d } = deps(SECRET);
    const res = await handle(req('POST', { [CRON_SECRET_HEADER]: SECRET }), d);
    assertEquals(res.status, 200);
    assertEquals(calls.n, 1);
  });

  Deno.test(`${name}: 틀린 비밀값·헤더 없음은 401, 실행 안 함`, async () => {
    const { calls, deps: d } = deps(SECRET);
    assertEquals((await handle(req('POST', { [CRON_SECRET_HEADER]: 'wrong' }), d)).status, 401);
    assertEquals((await handle(req('POST'), d)).status, 401);
    assertEquals((await handle(req('POST', { Authorization: `Bearer ${SECRET}` }), d)).status, 401);
    assertEquals(calls.n, 0);
  });

  Deno.test(`${name}: 서버 비밀값 미등록이면 500 not_configured, 실행 안 함`, async () => {
    const { calls, deps: d } = deps(undefined);
    const res = await handle(req('POST', { [CRON_SECRET_HEADER]: '' }), d);
    assertEquals(res.status, 500);
    assertEquals((await res.json()).error, 'not_configured');
    assertEquals(calls.n, 0);
  });

  Deno.test(`${name}: POST 아니면 405`, async () => {
    const { calls, deps: d } = deps(SECRET);
    assertEquals((await handle(req('GET', { [CRON_SECRET_HEADER]: SECRET }), d)).status, 405);
    assertEquals(calls.n, 0);
  });
}
