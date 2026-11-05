// 남은 로고 사진 파일 정리 (data-model.md 3-1 끝 줄, 13장 S-10, 3-8). 예약 실행 전용.
//
// 앱은 로고를 바꾸거나 지우거나 팀을 해체하면 이전 파일을 바로 지운다. 그 사이 앱이 꺼지거나 네트워크가 끊겨
// 남은 파일(어느 팀의 지금 로고도 아니고 1시간 지난 파일)을 이 함수가 Storage API 로 지운다.
// (storage.objects 는 SQL 로 직접 지울 수 없다.)
//
// 호출 보호: x-cron-secret 헤더가 서버 비밀값 CRON_SECRET 과 같을 때만 실행한다 (_shared/cron_auth.ts).
//   예약 작업(202611050018, 하루 1번 UTC 18:43)이 Vault 의 cron_secret 을 보낸다. service_role 키는 DB 에 두지 않는다.
//   배포: supabase functions deploy team-logo-cleanup --no-verify-jwt (예약 작업은 JWT 를 보내지 않는다)
// 필요한 서버 비밀값: CRON_SECRET (supabase secrets set)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동 제공 (함수 안 관리 권한용)

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
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

  const { data: rows, error } = await admin.rpc('list_orphan_team_logos', { p_limit: BATCH });
  if (error) return json(500, { error: 'internal_error' });

  const names = ((rows ?? []) as { name: string }[]).map((r) => r.name);
  if (names.length === 0) return json(200, { deleted: 0 });

  const { data: removed, error: rmError } = await admin.storage.from('team-logos').remove(names);
  if (rmError) return json(500, { error: 'internal_error' });

  // 파일 경로는 남기지 않고 개수만.
  return json(200, { deleted: removed?.length ?? 0 });
}

if (import.meta.main) {
  Deno.serve((req) => handle(req, { env: (name) => Deno.env.get(name), run: runCleanup }));
}
