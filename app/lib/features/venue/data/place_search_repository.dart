import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/domain/venue.dart';

/// 카카오맵 장소 검색 결과 한 줄.
class PlaceResult {
  const PlaceResult({
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
    this.category,
  });

  final String placeId;
  final String name;
  final String? address;
  final String? category;
  final double lat;
  final double lng;

  Venue toVenue() =>
      Venue.kakao(name: name, address: address, placeId: placeId, lat: lat, lng: lng);
}

class PlacePage {
  const PlacePage({required this.places, required this.isEnd});

  final List<PlaceResult> places;
  final bool isEnd;
}

enum PlaceSearchError {
  /// 서버 함수가 아직 없음(배포 전) 또는 서버 설정 안 됨 → "준비 중", 직접 입력만.
  unavailable,

  /// 네트워크·카카오 오류 → 다시 시도.
  failed,
}

class PlaceSearchFailure implements Exception {
  const PlaceSearchFailure(this.error);

  final PlaceSearchError error;

  @override
  String toString() => 'PlaceSearchFailure(${error.name})';
}

/// 장소 검색은 서버 함수(place-search)만 부른다. 카카오 REST 키는 앱에 없다 (Q-068 2번).
abstract interface class PlaceSearchRepository {
  /// 검색어는 1~[maxPlaceQueryLength]자. 실패는 [PlaceSearchFailure].
  Future<PlacePage> search(String query, {int page = 1});
}

/// 앱에서 받는 검색어 글자 수 상한 (서버는 100자).
const maxPlaceQueryLength = 50;

class SupabasePlaceSearchRepository implements PlaceSearchRepository {
  SupabasePlaceSearchRepository(this._client);

  static const functionName = 'place-search';

  final SupabaseClient _client;

  @override
  Future<PlacePage> search(String query, {int page = 1}) async {
    final FunctionResponse res;
    try {
      res = await _client.functions.invoke(
        functionName,
        body: {'query': query, 'page': page},
      );
    } on FunctionException catch (e) {
      // 404: 배포 전, 500 not_configured: 비밀값 없음
      final notReady = e.status == 404 ||
          (e.status == 500 && e.details is Map && (e.details as Map)['error'] == 'not_configured');
      throw PlaceSearchFailure(notReady ? PlaceSearchError.unavailable : PlaceSearchError.failed);
    } catch (_) {
      throw const PlaceSearchFailure(PlaceSearchError.failed);
    }
    return parsePlacePage(res.data);
  }
}

/// 서버 함수 응답 → [PlacePage]. 모양이 틀린 줄은 뺀다.
PlacePage parsePlacePage(Object? data) {
  if (data is! Map) throw const PlaceSearchFailure(PlaceSearchError.failed);
  final list = data['places'];
  final places = <PlaceResult>[
    if (list is List)
      for (final p in list)
        if (p is Map &&
            p['placeId'] is String &&
            p['name'] is String &&
            p['lat'] is num &&
            p['lng'] is num)
          PlaceResult(
            placeId: p['placeId'] as String,
            name: p['name'] as String,
            address: p['address'] as String?,
            category: p['category'] as String?,
            lat: (p['lat'] as num).toDouble(),
            lng: (p['lng'] as num).toDouble(),
          ),
  ];
  return PlacePage(places: places, isEnd: data['isEnd'] != false);
}
