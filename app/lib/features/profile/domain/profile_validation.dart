import '../../../shared/domain/position.dart';
import '../../../shared/domain/text_length.dart';

/// 프로필 입력값 (사람당 하나, 모든 팀 공통). 저장 구조는 data-model 승인 후 정한다.
class ProfileInput {
  const ProfileInput({
    required this.name,
    required this.positions,
    this.isDedicatedGk = false,
    this.bio,
  });

  /// 팀에서 쓸 이름 (실명 또는 별명). 필수, 1~8자, 중복 허용 (Q-011).
  /// 한 줄, 이모지·특수문자 허용, 가운데 연속 공백은 하나로 (Q-034).
  final String name;

  /// 사용자가 고른 선호 포지션. 중복 불가, 순서 없음.
  /// 전문 골키퍼로 자동 포함되는 골키퍼까지 합쳐 1~3개 (Q-035).
  final List<Position> positions;

  /// 전문 골키퍼. 선택. 체크하면 선호 포지션에 골키퍼가 자동 포함된다 (Q-019).
  final bool isDedicatedGk;

  /// 한줄 자기소개. 선택, 20자 이내, 줄바꿈 불가 (Q-012).
  final String? bio;

  /// 저장에 쓰는 선호 포지션: 전문 골키퍼면 골키퍼를 자동 포함한다 (Q-019).
  ///
  /// 자동 포함으로 3개를 넘는 경우는 [ProfileValidator.validate]가
  /// [ProfileError.dedicatedGkNeedsFreeSlot]으로 막는다 (Q-035).
  List<Position> get effectivePositions =>
      isDedicatedGk && !positions.contains(Position.goalkeeper)
      ? [...positions, Position.goalkeeper]
      : positions;

  /// 저장 직전 정리본: 이름은 한 줄 이름 규칙으로 정리(Q-034), 자기소개 앞뒤 공백 제거,
  /// 빈 자기소개는 null, 전문 골키퍼면 골키퍼 자동 포함.
  ProfileInput normalized() {
    final trimmedBio = bio == null ? null : normalizeInput(bio!);
    return ProfileInput(
      name: normalizeSingleLineName(name),
      positions: effectivePositions,
      isDedicatedGk: isDedicatedGk,
      bio: (trimmedBio == null || trimmedBio.isEmpty) ? null : trimmedBio,
    );
  }
}

enum ProfileError {
  nameRequired,
  nameTooLong,

  /// 이름에 줄바꿈이 들어 있음 (Q-034).
  nameHasLineBreak,

  positionsRequired,

  /// 사용자가 직접 고른 포지션만으로 3개를 넘음.
  tooManyPositions,

  /// 골키퍼 아닌 포지션 3개를 고른 상태에서 전문 골키퍼를 체크함 → 자동 포함으로 4개가 됨.
  /// 화면에서 "포지션을 하나 빼도록" 안내하기 위한 별도 오류 (Q-035).
  dedicatedGkNeedsFreeSlot,

  duplicatePositions,
  bioTooLong,
  bioHasLineBreak,
}

class ProfileValidator {
  const ProfileValidator._();

  static const int maxNameLength = 8;
  static const int minPositions = 1;

  /// 골키퍼(자동 포함 포함) 합계 기준 최대 개수 (Q-035).
  static const int maxPositions = 3;
  static const int maxBioLength = 20;

  /// [positions]를 고른 상태에서 전문 골키퍼를 체크해도 3개를 넘지 않는지 (Q-035).
  ///
  /// 골키퍼가 이미 포함돼 있거나, 고른 포지션이 3개 미만이면 true.
  static bool canCheckDedicatedGk(List<Position> positions) =>
      positions.contains(Position.goalkeeper) ||
      positions.toSet().length < maxPositions;

  /// 오류가 없으면 빈 집합.
  ///
  /// 이름 글자 수는 한 줄 이름 정리(앞뒤 공백 제거, 가운데 연속 공백 하나로) 후의
  /// 보이는 글자 단위 (Q-011, Q-012, Q-034).
  static Set<ProfileError> validate(ProfileInput input) {
    final errors = <ProfileError>{};

    final name = normalizeSingleLineName(input.name);
    final nameLength = countChars(name);
    if (nameLength == 0) {
      errors.add(ProfileError.nameRequired);
    } else if (nameLength > maxNameLength) {
      errors.add(ProfileError.nameTooLong);
    }
    if (containsLineBreak(name)) {
      errors.add(ProfileError.nameHasLineBreak);
    }

    // 개수 하한은 자동 포함 후 기준 (전문 골키퍼만 체크해도 골키퍼 1개가 선택됨).
    if (input.effectivePositions.length < minPositions) {
      errors.add(ProfileError.positionsRequired);
    }
    // 개수 상한: 직접 고른 것만으로 넘으면 tooManyPositions,
    // 직접 고른 것은 괜찮은데 전문 골키퍼 자동 포함으로 넘으면 dedicatedGkNeedsFreeSlot.
    final selected = input.positions;
    if (selected.length > maxPositions) {
      errors.add(ProfileError.tooManyPositions);
    } else if (input.effectivePositions.length > maxPositions) {
      errors.add(ProfileError.dedicatedGkNeedsFreeSlot);
    }
    if (selected.toSet().length != selected.length) {
      errors.add(ProfileError.duplicatePositions);
    }

    final bio = input.bio;
    if (bio != null) {
      final trimmed = normalizeInput(bio);
      if (countChars(trimmed) > maxBioLength) {
        errors.add(ProfileError.bioTooLong);
      }
      if (containsLineBreak(trimmed)) {
        errors.add(ProfileError.bioHasLineBreak);
      }
    }

    return errors;
  }
}
