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

  /// 팀에서 쓸 이름 (실명 또는 별명). 필수.
  final String name;

  /// 선호 포지션. 1~3개, 중복 불가, 순서 없음.
  final List<Position> positions;

  /// 전문 골키퍼. 선택.
  final bool isDedicatedGk;

  /// 한줄 자기소개. 선택, 20자 이내.
  final String? bio;
}

enum ProfileError {
  nameRequired,
  positionsRequired,
  tooManyPositions,
  duplicatePositions,
  bioTooLong,
}

class ProfileValidator {
  const ProfileValidator._();

  static const int minPositions = 1;
  static const int maxPositions = 3;
  static const int maxBioLength = 20;

  /// 오류가 없으면 빈 집합.
  static Set<ProfileError> validate(ProfileInput input) {
    final errors = <ProfileError>{};

    // TODO(Q-대기): 이름 길이 제한, 허용 문자(이모지·특수문자) 미정 → 제한 없음.
    // TODO(Q-대기): 공백만 입력한 이름은 "비어 있음"으로 본다 (필수 항목 의미상).
    //   앞뒤 공백을 저장 시 잘라낼지는 미정.
    if (input.name.trim().isEmpty) {
      errors.add(ProfileError.nameRequired);
    }

    final positions = input.positions;
    if (positions.length < minPositions) {
      errors.add(ProfileError.positionsRequired);
    }
    if (positions.length > maxPositions) {
      errors.add(ProfileError.tooManyPositions);
    }
    if (positions.toSet().length != positions.length) {
      errors.add(ProfileError.duplicatePositions);
    }

    final bio = input.bio;
    // TODO(Q-대기): 자기소개 글자 수에 앞뒤 공백을 포함할지 미정 → 가장 덜 제한적으로
    //   앞뒤 공백을 빼고 센다. 줄바꿈 허용 여부도 미정 (현재 제한 없음).
    if (bio != null && countChars(bio.trim()) > maxBioLength) {
      errors.add(ProfileError.bioTooLong);
    }

    // TODO(Q-대기): 전문 골키퍼 체크 시 선호 포지션에 골키퍼가 꼭 있어야 하는지 미정
    //   → 현재 제약 없음.

    return errors;
  }
}
