import '../../../shared/domain/position.dart';
import '../../../shared/domain/text_length.dart';
import '../../admin/domain/skill_level.dart';

/// 게스트 (match_guests). 팀원 전체가 읽는 칸만 (이름). 포지션·대략 실력은 [MatchGuestDetail] (관리자만, Q-017).
class MatchGuest {
  const MatchGuest({
    required this.id,
    required this.matchId,
    required this.name,
    required this.createdAt,
    this.addedBy,
  });

  final String id;
  final String matchId;
  final String name;

  /// 추가한 관리자. 탈퇴하면 비어 있다.
  final String? addedBy;
  final DateTime createdAt;

  /// 팀원 읽기 칸 (positions 는 권한이 없어 넣으면 서버가 거절한다).
  static const columns = 'id, match_id, name, added_by, created_at';

  static MatchGuest fromRow(Map<String, dynamic> row) => MatchGuest(
    id: row['id'] as String,
    matchId: row['match_id'] as String,
    name: row['name'] as String,
    addedBy: row['added_by'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// 관리자용 게스트 정보 (서버 함수 get_match_guest_details).
class MatchGuestDetail {
  const MatchGuestDetail({
    required this.id,
    required this.name,
    required this.positions,
    required this.skillLevel,
    required this.createdAt,
    this.addedBy,
  });

  final String id;
  final String name;

  /// 선택, 최대 3개. 없으면 빈 목록.
  final List<Position> positions;

  /// 대략 실력. 고르지 않았으면 미정.
  final SkillLevel skillLevel;
  final String? addedBy;
  final DateTime createdAt;

  static MatchGuestDetail fromRow(Map<String, dynamic> row) => MatchGuestDetail(
    id: row['id'] as String,
    name: row['name'] as String,
    positions: [
      for (final p in (row['positions'] as List?) ?? const []) Position.values.byName(p as String),
    ],
    skillLevel: SkillLevel.fromServer(row['skill_level'] as String?),
    addedBy: row['added_by'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

enum GuestInputError { nameRequired, nameTooLong, nameHasLineBreak, tooManyPositions, duplicatePositions }

/// 게스트 추가 입력 (서버 함수 add_match_guest). 매번 새로 입력한다 (M-19).
///
/// 이름은 팀에서 쓸 이름과 같은 규칙 (정리 후 1~8자, Q-071 6번). 포지션은 선택, 최대 3개.
/// 대략 실력은 선택 (실력 등급 5단계, 미정이면 저장하지 않음).
/// 같은 이름·게스트 수 상한은 Q-073 7번 답을 기다리는 중이라 검사하지 않는다.
class GuestInput {
  const GuestInput({required this.name, this.positions = const [], this.skillLevel});

  static const int maxNameLength = 8;
  static const int maxPositions = 3;

  final String name;
  final List<Position> positions;
  final SkillLevel? skillLevel;

  /// 오류가 없으면 빈 집합. 서버도 같은 규칙으로 다시 거절한다.
  Set<GuestInputError> validate() {
    final errors = <GuestInputError>{};
    final normalized = normalizeSingleLineName(name);
    final length = countChars(normalized);
    if (length == 0) {
      errors.add(GuestInputError.nameRequired);
    } else if (length > maxNameLength) {
      errors.add(GuestInputError.nameTooLong);
    }
    if (containsLineBreak(normalized)) errors.add(GuestInputError.nameHasLineBreak);
    if (positions.length > maxPositions) errors.add(GuestInputError.tooManyPositions);
    if (positions.toSet().length != positions.length) errors.add(GuestInputError.duplicatePositions);
    return errors;
  }

  Map<String, Object?> toServerParams(String matchId) => {
    'p_match_id': matchId,
    'p_name': normalizeSingleLineName(name),
    'p_positions': positions.isEmpty ? null : [for (final p in positions) p.name],
    'p_skill_level': (skillLevel == null || skillLevel == SkillLevel.undecided) ? null : skillLevel!.name,
  };
}
