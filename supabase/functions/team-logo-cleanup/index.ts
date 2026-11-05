// 남은 로고 사진 파일 정리 (data-model.md 3-1 끝 줄, 13장 S-10, 3-8). 예약 실행 전용.
//
// 앱은 로고를 바꾸거나 지우거나 팀을 해체하면 이전 파일을 바로 지운다. 그 사이 앱이 꺼지거나 네트워크가 끊겨
// 남은 파일(어느 팀의 지금 로고도 아니고 1시간 지난 파일)을 이 함수가 Storage API 로 지운다.
// (storage.objects 는 SQL 로 직접 지울 수 없다.)
//
// 호출 보호: Authorization 의 Bearer 값이 서비스 키와 같을 때만 실행한다 (예약 작업만 부른다).
// 필요한 서버 비밀값: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (Supabase 가 자동 제공). 추가 비밀값 없음.
//
// 아직 배포하지 않았다 (Supabase 액세스 토큰 필요). 배포 후 할 일 (lead·kopn):
//   - 예약 작업 추가: pg_cron + pg_net 으로 하루 1번 이 함수 호출 (서비스 키는 Vault 에 두고 마이그레이션에 넣지 않는다)

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

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

  const { data: rows, error } = await admin.rpc('list_orphan_team_logos', { p_limit: BATCH });
  if (error) return json(500, { error: 'internal_error' });

  const names = ((rows ?? []) as { name: string }[]).map((r) => r.name);
  if (names.length === 0) return json(200, { deleted: 0 });

  const { data: removed, error: rmError } = await admin.storage.from('team-logos').remove(names);
  if (rmError) return json(500, { error: 'internal_error' });

  // 파일 경로는 남기지 않고 개수만.
  return json(200, { deleted: removed?.length ?? 0 });
});
