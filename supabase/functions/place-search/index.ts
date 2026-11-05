// 지정 풋살장 검색 (data-model.md 3-1 venue_*, Q-032, Q-068 2번). 앱은 이 함수만 부른다.
//
// 요청: POST { "query": "강남 풋살", "page": 1 }  (로그인한 사람만, Authorization: Bearer <사용자 JWT>)
// 응답: 200 { "places": [{ placeId, name, address, category, lat, lng }], "isEnd": true }
//       400 invalid_query · 401 not_authenticated · 405 · 502 upstream_error · 500 not_configured
//
// 필요한 서버 비밀값 (supabase secrets set, 저장소에 넣지 않는다):
//   KAKAO_REST_API_KEY            카카오 로컬 검색용 REST 키
//   SUPABASE_URL, SUPABASE_ANON_KEY (Supabase 가 자동 제공, 호출자 로그인 확인용)
//
// 아직 배포하지 않았다 (Supabase 액세스 토큰 필요). 배포 전 앱은 "준비 중"으로 보고 직접 입력만 쓴다.
// 로그에 검색어·사람 ID·키를 남기지 않는다.

import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import { parseRequest, searchKakao, UpstreamError, type FetchLike } from './kakao.ts';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

export type Deps = {
  env: (name: string) => string | undefined;
  /** 호출자가 로그인한 사용자인지 (사용자 JWT 확인). */
  isSignedIn: (authHeader: string) => Promise<boolean>;
  fetchFn: FetchLike;
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ') || !(await deps.isSignedIn(authHeader))) {
    return json(401, { error: 'not_authenticated' });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'invalid_query' });
  }
  const parsed = parseRequest(body);
  if (!parsed) return json(400, { error: 'invalid_query' });

  const key = deps.env('KAKAO_REST_API_KEY');
  if (!key) return json(500, { error: 'not_configured' });

  try {
    return json(200, await searchKakao(parsed, key, deps.fetchFn));
  } catch (e) {
    if (e instanceof UpstreamError) {
      console.warn('place search upstream failed', e.message);
      return json(502, { error: 'upstream_error' });
    }
    return json(500, { error: 'internal_error' });
  }
}

const defaultDeps: Deps = {
  env: (name) => Deno.env.get(name),
  isSignedIn: async (authHeader) => {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!url || !anonKey) return false;
    const client = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data, error } = await client.auth.getUser(authHeader.slice('Bearer '.length));
    return !error && !!data.user;
  },
  fetchFn: (input, init) => fetch(input, init),
};

if (import.meta.main) {
  Deno.serve((req) => handle(req, defaultDeps));
}
