/// 장소 (data-model.md 3-1 `venue_*`). 팀 지정 풋살장과 일정 장소(4-1)가 같은 모양을 쓴다.
///
/// - 카카오맵 검색으로 고르면 [provider] = kakao, [placeId]·[lat]·[lng] 가 모두 있다 (Q-032).
/// - 직접 입력이면 이름·주소만 있고 나머지는 비운다 (기획서 5장 "없으면 직접 입력").
enum MapProvider { kakao }

class Venue {
  const Venue.manual({required this.name, this.address})
    : provider = null,
      placeId = null,
      lat = null,
      lng = null;

  const Venue.kakao({
    required this.name,
    required String this.placeId,
    required double this.lat,
    required double this.lng,
    this.address,
  }) : provider = MapProvider.kakao;

  final String name;
  final String? address;
  final MapProvider? provider;
  final String? placeId;
  final double? lat;
  final double? lng;

  /// 이름 상한 (venue_name 1~200자, 서버 검사와 같다).
  static const maxNameLength = 200;

  /// 주소 상한 (venue_address 300자).
  static const maxAddressLength = 300;

  bool get isFromMap => provider != null;

  /// 서버 함수(create_team·update_team_info)의 `p_venue` 값.
  Map<String, Object?> toServerJson() => {
    'name': name,
    'address': address,
    if (provider != null) ...{
      'provider': provider!.name,
      'place_id': placeId,
      'lat': lat,
      'lng': lng,
    },
  };

  /// teams 표의 venue_* 칸에서. 이름이 없으면 null (지정 풋살장 없음).
  static Venue? fromRow(Map<String, dynamic> row) {
    final name = row['venue_name'] as String?;
    if (name == null) return null;
    final address = row['venue_address'] as String?;
    final provider = row['venue_map_provider'] as String?;
    final placeId = row['venue_map_place_id'] as String?;
    final lat = (row['venue_lat'] as num?)?.toDouble();
    final lng = (row['venue_lng'] as num?)?.toDouble();
    if (provider == MapProvider.kakao.name && placeId != null && lat != null && lng != null) {
      return Venue.kakao(name: name, address: address, placeId: placeId, lat: lat, lng: lng);
    }
    return Venue.manual(name: name, address: address);
  }

  @override
  bool operator ==(Object other) =>
      other is Venue &&
      other.name == name &&
      other.address == address &&
      other.provider == provider &&
      other.placeId == placeId &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(name, address, provider, placeId, lat, lng);
}
