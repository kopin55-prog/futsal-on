// 로컬 테스트: npx --yes deno test supabase/functions/place-search/place_search_test.ts
// 카카오·Supabase 를 부르지 않는다 (가짜 fetch·로그인 확인).
//
// 실제 카카오 호출 확인(선택): KAKAO_REST_API_KEY 환경 변수가 있으면 live 테스트가 한 번 부른다.
//   (키는 출력하지 않는다. 키가 없으면 건너뛴다.)

import { assert, assertEquals } from 'jsr:@std/assert@1';
import { buildKakaoUrl, mapKakaoResponse, parseRequest, searchKakao } from './kakao.ts';
import { handle, type Deps } from './index.ts';

const sampleKakao = {
  documents: [
    {
      id: '26338954',
      place_name: '강남 풋살파크',
      category_name: '스포츠,레저 > 풋살장',
      address_name: '서울 강남구 역삼동 1',
      road_address_name: '서울 강남구 테헤란로 1',
      x: '127.0276',
      y: '37.4979',
    },
    // 도로명 주소 없음 → 지번 주소
    { id: '2', place_name: '동네 구장', address_name: '경기 성남시 1', road_address_name: '', x: '127.1', y: '37.4' },
    // 좌표 없음 → 뺀다
    { id: '3', place_name: '좌표 없음', x: '', y: '' },
    // 이름 없음 → 뺀다
    { id: '4', place_name: ' ', x: '127', y: '37' },
  ],
  meta: { is_end: false, pageable_count: 30, total_count: 30 },
};

Deno.test('parseRequest: 검색어 정리·쪽 번호 확인', () => {
  assertEquals(parseRequest({ query: '  강남   풋살 ' }), { query: '강남 풋살', page: 1 });
  assertEquals(parseRequest({ query: '풋살', page: 2 }), { query: '풋살', page: 2 });
  assertEquals(parseRequest({ query: '' }), null);
  assertEquals(parseRequest({ query: '   ' }), null);
  assertEquals(parseRequest({ query: 'a'.repeat(101) }), null);
  assertEquals(parseRequest({ query: '풋살', page: 0 }), null);
  assertEquals(parseRequest({ query: '풋살', page: 46 }), null);
  assertEquals(parseRequest({ query: '풋살', page: 1.5 }), null);
  assertEquals(parseRequest({ query: 3 }), null);
  assertEquals(parseRequest(null), null);
  assertEquals(parseRequest(['풋살']), null);
});

Deno.test('buildKakaoUrl: 검색어·쪽·크기', () => {
  const u = new URL(buildKakaoUrl({ query: '강남 풋살', page: 3 }));
  assertEquals(u.origin + u.pathname, 'https://dapi.kakao.com/v2/local/search/keyword.json');
  assertEquals(u.searchParams.get('query'), '강남 풋살');
  assertEquals(u.searchParams.get('page'), '3');
  assertEquals(u.searchParams.get('size'), '15');
});

Deno.test('mapKakaoResponse: 필요한 칸만, 잘못된 줄은 뺀다', () => {
  const r = mapKakaoResponse(sampleKakao);
  assertEquals(r.isEnd, false);
  assertEquals(r.places.length, 2);
  assertEquals(r.places[0], {
    placeId: '26338954',
    name: '강남 풋살파크',
    address: '서울 강남구 테헤란로 1',
    category: '스포츠,레저 > 풋살장',
    lat: 37.4979,
    lng: 127.0276,
  });
  assertEquals(r.places[1].address, '경기 성남시 1');
  assertEquals(mapKakaoResponse({}), { places: [], isEnd: true });
  assertEquals(mapKakaoResponse(null), { places: [], isEnd: true });
});

const fakeFetch = (status: number, body: unknown, seen?: { url?: string; auth?: string | null }) =>
  (input: string, init?: RequestInit) => {
    if (seen) {
      seen.url = input;
      seen.auth = new Headers(init?.headers).get('Authorization');
    }
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };

const deps = (over: Partial<Deps> = {}): Deps => ({
  env: (n) => (n === 'KAKAO_REST_API_KEY' ? 'test-key' : undefined),
  isSignedIn: () => Promise.resolve(true),
  fetchFn: fakeFetch(200, sampleKakao),
  ...over,
});

const post = (body: unknown, auth = 'Bearer user-jwt') =>
  new Request('http://localhost/place-search', {
    method: 'POST',
    headers: { Authorization: auth, 'Content-Type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

Deno.test('handle: 로그인한 사람의 검색 → 카카오 결과', async () => {
  const seen: { url?: string; auth?: string | null } = {};
  const res = await handle(post({ query: '강남 풋살' }), deps({ fetchFn: fakeFetch(200, sampleKakao, seen) }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.places.length, 2);
  assertEquals(seen.auth, 'KakaoAK test-key');
  assert(seen.url?.includes('query=%EA%B0%95%EB%82%A8+%ED%92%8B%EC%82%B4'));
});

Deno.test('handle: 로그인 안 했으면 401, 카카오를 부르지 않는다', async () => {
  let called = false;
  const spy = () => {
    called = true;
    return Promise.resolve(new Response('{}'));
  };
  assertEquals((await handle(post({ query: '풋살' }, ''), deps({ fetchFn: spy }))).status, 401);
  assertEquals(
    (await handle(post({ query: '풋살' }), deps({ isSignedIn: () => Promise.resolve(false), fetchFn: spy }))).status,
    401,
  );
  assertEquals(called, false);
});

Deno.test('handle: 잘못된 요청·설정·카카오 실패', async () => {
  assertEquals((await handle(new Request('http://localhost', { method: 'GET' }), deps())).status, 405);
  assertEquals((await handle(post('not json'), deps())).status, 400);
  assertEquals((await handle(post({ query: '' }), deps())).status, 400);
  assertEquals((await handle(post({ query: '풋살' }), deps({ env: () => undefined }))).status, 500);
  const res = await handle(post({ query: '풋살' }), deps({ fetchFn: fakeFetch(401, { msg: 'bad key' }) }));
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: 'upstream_error' });
  const down = await handle(post({ query: '풋살' }), deps({ fetchFn: () => Promise.reject(new Error('net')) }));
  assertEquals(down.status, 502);
});

Deno.test({
  name: 'live: 실제 카카오 키워드 검색 (KAKAO_REST_API_KEY 있을 때만)',
  ignore: !Deno.env.get('KAKAO_REST_API_KEY'),
  fn: async () => {
    const r = await searchKakao({ query: '풋살장', page: 1 }, Deno.env.get('KAKAO_REST_API_KEY')!);
    assert(r.places.length > 0, 'no places');
    const p = r.places[0];
    assert(p.placeId && p.name && Number.isFinite(p.lat) && Number.isFinite(p.lng));
    console.log('live ok:', r.places.length, 'places, first category:', p.category);
  },
});
