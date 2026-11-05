import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/venue/data/place_search_repository.dart';
import 'package:futsal_on/shared/domain/venue.dart';

void main() {
  group('Venue (data-model.md 3-1 venue_*)', () {
    test('카카오 결과는 지도 정보를 모두 보낸다', () {
      const v = Venue.kakao(name: '강남 풋살파크', address: '서울', placeId: '12', lat: 37.5, lng: 127.0);
      expect(v.toServerJson(), {
        'name': '강남 풋살파크',
        'address': '서울',
        'provider': 'kakao',
        'place_id': '12',
        'lat': 37.5,
        'lng': 127.0,
      });
      expect(v.isFromMap, isTrue);
    });

    test('직접 입력은 이름·주소만', () {
      const v = Venue.manual(name: '동네 구장');
      expect(v.toServerJson(), {'name': '동네 구장', 'address': null});
      expect(v.isFromMap, isFalse);
    });

    test('표의 칸에서 읽기: 이름이 없으면 없음, 지도 정보가 빠지면 직접 입력으로', () {
      expect(Venue.fromRow({'venue_name': null}), isNull);
      expect(
        Venue.fromRow({
          'venue_name': '강남',
          'venue_address': '서울',
          'venue_map_provider': 'kakao',
          'venue_map_place_id': '12',
          'venue_lat': 37,
          'venue_lng': 127.5,
        }),
        const Venue.kakao(name: '강남', address: '서울', placeId: '12', lat: 37, lng: 127.5),
      );
      expect(
        Venue.fromRow({'venue_name': '동네', 'venue_map_provider': null}),
        const Venue.manual(name: '동네'),
      );
    });
  });

  group('parsePlacePage (서버 함수 place-search 응답)', () {
    test('맞는 줄만, isEnd 기본 true', () {
      final page = parsePlacePage({
        'places': [
          {'placeId': '1', 'name': 'A', 'address': '주소', 'category': '풋살장', 'lat': 37.1, 'lng': 127},
          {'placeId': '2', 'name': 'B', 'lat': 'x', 'lng': 127},
          {'name': 'C', 'lat': 1, 'lng': 2},
          'nope',
        ],
        'isEnd': false,
      });
      expect(page.isEnd, isFalse);
      expect(page.places.single.placeId, '1');
      expect(page.places.single.lng, 127.0);
      expect(page.places.single.toVenue(),
          const Venue.kakao(name: 'A', address: '주소', placeId: '1', lat: 37.1, lng: 127));
      expect(parsePlacePage({'places': []}).isEnd, isTrue);
    });

    test('모양이 틀리면 실패', () {
      expect(() => parsePlacePage('x'), throwsA(isA<PlaceSearchFailure>()));
      expect(() => parsePlacePage(null), throwsA(isA<PlaceSearchFailure>()));
    });
  });
}
