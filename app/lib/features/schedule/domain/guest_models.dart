import '../../../shared/domain/position.dart';
import '../../../shared/domain/text_length.dart';
import '../../admin/domain/skill_level.dart';

/// 게스트 표시 이름: 이름이 없으면 "게스트{번호}" (Q-073 2번, 서버 private.guest_display_name 과 같음).
String guestDisplayName(String? name, int guestNo) => name ?? '$guestDefaultNamePrefix$guestNo';

/// 이름을 비운 게스트의 기본 이름 앞부분 (서버와 같은 글자).
const guestDefaultNamePrefix = '게스트';

/// 게스트 (match_guests). 팀원 전체가 읽는 칸만 (번호·이름). 포지션·대략 실력은 [MatchGuestDetail] (관리자만, Q-017).
class MatchGuest {
  const MatchGuest({
    required this.id,
    required this.matchId,
    required this.guestNo,
    required this.createdAt,
    this.name,
    this.addedBy,
  });

  final String id;
  final String matchId;

  /// 그 일정 안 게스트 번호 (1부터 추가 순서, 붙은 뒤 바뀌지 않음).
  final int guestNo;

  /// 적은 이름. 비우면 null → 화면에는 [displayName] ("게스트N").
  final String? name;

  /// 추가한 관리자. 탈퇴하면 비어 있다.
  final String? addedBy;
  final DateTime createdAt;

  String get displayName => guestDisplayName(name, guestNo);

  /// 팀원 읽기 칸 (positions 는 권한이 없어 넣으면 서버가 거절한다).
  static const columns = 'id, match_id, guest_no, name, added_by, created_at';

  static MatchGuest fromRow(Map<String, dynamic> row) => MatchGuest(
    id: row['id'] as String,
    matchId: row['match_id'] as String,
    guestNo: row['guest_no'] as int,
    name: row['name'] as String?,
    addedBy: row['added_by'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// 관리자용 게스트 정보 (서버 함수 get_match_guest_details).
class MatchGuestDetail {
  const MatchGuestDetail({
    required this.id,
    required this.guestNo,
    required this.positions,
    required this.skillLevel,
    required this.createdAt,
    this.name,
    this.addedBy,
  });

  final String id;
  final int guestNo;
  final String? name;

  /// 선택, 최대 3개. 없으면 빈 목록.
  final List<Position> positions;

  /// 대략 실력. 고르지 않았으면 미정.
  final SkillLevel skillLevel;
  final String? addedBy;
  final DateTime createdAt;

  String get displayName => guestDisplayName(name, guestNo);

  static MatchGuestDetail fromRow(Map<String, dynamic> row) => MatchGuestDetail(
    id: row['id'] as String,
    guestNo: row['guest_no'] as int,
    name: row['name'] as String?,
    positions: [
      for (final p in (row['positions'] as List?) ?? const []) Position.values.byName(p as String),
    ],
    skillLevel: SkillLevel.fromServer(row['skill_level'] as String?),
    addedBy: row['added_by'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

enum GuestInputError {
  nameTooLong,
  nameHasLineBreak,
  tooManyPositions,
  duplicatePositions,

  /// 같은 일정 안에 같은 표시 이름("게스트N" 포함)이 있음 (Q-073 3번)
  duplicateName,

  /// 한 일정 게스트 최대 [GuestInput.maxGuestsPerMatch]명 (Q-073 3번)
  tooManyGuests,
}

/// 게스트 추가 입력 (서버 함수 add_match_guest). 매번 새로 입력한다 (M-19).
///
/// 이름은 선택 (Q-073 2번): 비우면 "게스트N", 적으면 팀에서 쓸 이름과 같은 규칙(정리 후 1~8자).
/// 포지션은 선택, 최대 3개. 대략 실력은 선택 (실력 등급 5단계, 미정이면 저장하지 않음).
/// 한 일정 최대 12명, 같은 일정 안 같은 표시 이름 불가 (Q-073 3번). 서버도 같은 규칙으로 다시 거절한다.
class GuestInput {
  const GuestInput({this.name = '', this.positions = const [], this.skillLevel});

  static const int maxNameLength = 8;
  static const int maxPositions = 3;
  static const int maxGuestsPerMatch = 12;

  final String name;
  final List<Position> positions;
  final SkillLevel? skillLevel;

  /// 정리한 이름. 비우면 null.
  String? get normalizedName {
    final n = normalizeSingleLineName(name);
    return n.isEmpty ? null : n;
  }

  /// 이 일정에 지금 있는 게스트가 [existing] 일 때 새 게스트에게 붙을 번호 (서버: 가장 큰 번호 + 1).
  static int nextGuestNo(Iterable<MatchGuest> existing) =>
      existing.fold<int>(0, (max, g) => g.guestNo > max ? g.guestNo : max) + 1;

  /// 오류가 없으면 빈 집합. [existing] 을 주면 인원·같은 이름도 검사한다.
  Set<GuestInputError> validate({Iterable<MatchGuest>? existing}) {
    final errors = <GuestInputError>{};
    final normalized = normalizedName;
    if (normalized != null) {
      if (countChars(normalized) > maxNameLength) errors.add(GuestInputError.nameTooLong);
      if (containsLineBreak(normalized)) errors.add(GuestInputError.nameHasLineBreak);
    }
    if (positions.length > maxPositions) errors.add(GuestInputError.tooManyPositions);
    if (positions.toSet().length != positions.length) errors.add(GuestInputError.duplicatePositions);
    if (existing != null) {
      final list = existing.toList();
      if (list.length >= maxGuestsPerMatch) errors.add(GuestInputError.tooManyGuests);
      final display = guestDisplayName(normalized, nextGuestNo(list));
      if (list.any((g) => g.displayName == display)) errors.add(GuestInputError.duplicateName);
    }
    return errors;
  }

  Map<String, Object?> toServerParams(String matchId) => {
    'p_match_id': matchId,
    'p_name': normalizedName,
    'p_positions': positions.isEmpty ? null : [for (final p in positions) p.name],
    'p_skill_level': (skillLevel == null || skillLevel == SkillLevel.undecided) ? null : skillLevel!.name,
  };
}
