// 카카오 로컬 키워드 장소 검색 (Q-032, Q-068 2번). REST 키는 서버 비밀값으로만 쓴다.
// 순수 함수만 둔다 (index.ts 와 테스트가 같이 쓴다).

export const KAKAO_KEYWORD_URL = 'https://dapi.kakao.com/v2/local/search/keyword.json';

/** 한 번에 돌려줄 결과 수 (카카오 최대 15). */
export const PAGE_SIZE = 15;

/** 카카오가 허용하는 마지막 쪽 번호. */
export const MAX_PAGE = 45;

/** 검색어 글자 수 상한 (보이는 글자 기준이 아니라 코드 포인트 기준. 앱은 50자로 막는다). */
export const MAX_QUERY_LENGTH = 100;

export type PlaceSearchRequest = { query: string; page: number };

export type Place = {
  placeId: string;
  name: string;
  /** 도로명 주소, 없으면 지번 주소. 둘 다 없으면 null. */
  address: string | null;
  category: string | null;
  lat: number;
  lng: number;
};

export type PlaceSearchResult = { places: Place[]; isEnd: boolean };

/** 요청 본문 확인. 잘못되면 null. */
export function parseRequest(body: unknown): PlaceSearchRequest | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return null;
  const b = body as Record<string, unknown>;
  if (typeof b.query !== 'string') return null;
  const query = b.query.replace(/\s+/g, ' ').trim();
  if (query.length === 0 || [...query].length > MAX_QUERY_LENGTH) return null;
  let page = 1;
  if (b.page !== undefined && b.page !== null) {
    if (typeof b.page !== 'number' || !Number.isInteger(b.page)) return null;
    if (b.page < 1 || b.page > MAX_PAGE) return null;
    page = b.page;
  }
  return { query, page };
}

export function buildKakaoUrl(req: PlaceSearchRequest): string {
  const u = new URL(KAKAO_KEYWORD_URL);
  u.searchParams.set('query', req.query);
  u.searchParams.set('page', String(req.page));
  u.searchParams.set('size', String(PAGE_SIZE));
  return u.toString();
}

const text = (v: unknown): string | null => {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t.length === 0 ? null : t;
};

/** 카카오 응답 → 앱에 줄 모양. 좌표·장소 번호·이름이 없는 줄은 뺀다. */
export function mapKakaoResponse(json: unknown): PlaceSearchResult {
  const root = (json ?? {}) as { documents?: unknown; meta?: { is_end?: unknown } };
  const docs = Array.isArray(root.documents) ? root.documents : [];
  const places: Place[] = [];
  for (const d of docs as Record<string, unknown>[]) {
    const placeId = text(d?.id);
    const name = text(d?.place_name);
    // 카카오: x = 경도, y = 위도 (문자열)
    // 빈 문자열은 Number('') = 0 이 되므로 먼저 거른다.
    const lng = text(d?.x) === null ? NaN : Number(d?.x);
    const lat = text(d?.y) === null ? NaN : Number(d?.y);
    if (!placeId || !name || !Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
    places.push({
      placeId: placeId.slice(0, 100),
      name: name.slice(0, 200),
      address: (text(d?.road_address_name) ?? text(d?.address_name))?.slice(0, 300) ?? null,
      category: text(d?.category_name),
      lat,
      lng,
    });
  }
  const isEnd = root.meta?.is_end === false ? false : true;
  return { places, isEnd };
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export class UpstreamError extends Error {}

/** 카카오 호출. 실패하면 [UpstreamError]. 키·검색어는 오류 메시지에 넣지 않는다. */
export async function searchKakao(
  req: PlaceSearchRequest,
  restKey: string,
  fetchFn: FetchLike = fetch,
): Promise<PlaceSearchResult> {
  let res: Response;
  try {
    res = await fetchFn(buildKakaoUrl(req), {
      headers: { Authorization: `KakaoAK ${restKey}` },
    });
  } catch {
    throw new UpstreamError('kakao_unreachable');
  }
  if (!res.ok) {
    await res.body?.cancel();
    throw new UpstreamError(`kakao_status_${res.status}`);
  }
  return mapKakaoResponse(await res.json());
}
