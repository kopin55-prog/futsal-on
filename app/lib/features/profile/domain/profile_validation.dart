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
  final String name;

  /// 사용자가 고른 선호 포지션. 1~3개, 중복 불가, 순서 없음.
  final List<Position> positions;

  /// 전문 골키퍼. 선택. 체크하면 선호 포지션에 골키퍼가 자동 포함된다 (Q-019).
  final bool isDedicatedGk;

  /// 한줄 자기소개. 선택, 20자 이내, 줄바꿈 불가 (Q-012).
  final String? bio;

  /// 저장에 쓰는 선호 포지션: 전문 골키퍼면 골키퍼를 자동 포함한다 (Q-019).
  ///
  /// TODO(Q-대기): 이미 골키퍼 외 3개를 고른 상태에서 전문 골키퍼를 체크하면
  ///   자동 포함 후 4개가 된다. 이때 처리(체크 막기·하나 빼기·4개 허용 등)가 미정이라
  ///   저장 불가 오류로 막지 않고 4개 그대로 돌려준다.
  List<Position> get effectivePositions =>
      isDedicatedGk && !positions.contains(Position.goalkeeper)
      ? [...positions, Position.goalkeeper]
      : positions;

  /// 저장 직전 정리본: 이름·자기소개 앞뒤 공백 제거, 빈 자기소개는 null,
  /// 전문 골키퍼면 골키퍼 자동 포함.
  ProfileInput normalized() {
    final trimmedBio = bio == null ? null : normalizeInput(bio!);
    return ProfileInput(
      name: normalizeInput(name),
      positions: effectivePositions,
      isDedicatedGk: isDedicatedGk,
      bio: (trimmedBio == null || trimmedBio.isEmpty) ? null : trimmedBio,
    );
  }
}

enum ProfileError {
  nameRequired,
  nameTooLong,
  positionsRequired,
  tooManyPositions,
  duplicatePositions,
  bioTooLong,
  bioHasLineBreak,
}

class ProfileValidator {
  const ProfileValidator._();

  static const int maxNameLength = 8;
  static const int minPositions = 1;
  static const int maxPositions = 3;
  static const int maxBioLength = 20;

  /// 오류가 없으면 빈 집합. 글자 수는 앞뒤 공백을 뺀 보이는 글자 단위 (Q-011, Q-012).
  static Set<ProfileError> validate(ProfileInput input) {
    final errors = <ProfileError>{};

    // TODO(Q-대기): 이름의 허용 문자(이모지·특수문자)와 줄바꿈 허용 여부 미정
    //   → 현재 제한 없음 (Q-012의 줄바꿈 불가는 자기소개·부상 메모 대상).
    final nameLength = countChars(normalizeInput(input.name));
    if (nameLength == 0) {
      errors.add(ProfileError.nameRequired);
    } else if (nameLength > maxNameLength) {
      errors.add(ProfileError.nameTooLong);
    }

    // 개수 하한은 자동 포함 후 기준 (전문 골키퍼만 체크해도 골키퍼 1개가 선택됨).
    if (input.effectivePositions.length < minPositions) {
      errors.add(ProfileError.positionsRequired);
    }
    // 개수 상한은 사용자가 직접 고른 것 기준. 자동 포함으로 넘치는 경우는
    // ProfileInput.effectivePositions 의 미정 사항 참고.
    final selected = input.positions;
    if (selected.length > maxPositions) {
      errors.add(ProfileError.tooManyPositions);
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
