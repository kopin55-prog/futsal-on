import '../../../shared/data/server_error.dart';
import '../../../shared/domain/position.dart';
import '../domain/position_picker.dart';
import '../domain/profile_validation.dart';

/// 프로필 만들기 화면 문구.
///
/// 문서에 있는 문구: 포지션 이름(data-model.md 2-3), "포지션을 하나 빼주세요"(Q-035),
/// "이름을 입력해주세요"(11장 14번), "최대 3개까지 고를 수 있어요"(Q-067 1번). 나머지는 임시 문구 — TODO(문구 미정).
abstract final class ProfileTexts {
  static String position(Position p) => switch (p) {
    Position.goalkeeper => '골키퍼',
    Position.defender => '수비',
    Position.winger => '측면',
    Position.forward => '공격',
    Position.allrounder => '올라운더',
  };

  // TODO(문구 미정): 아래 화면 제목·라벨·버튼은 임시.
  static const title = '프로필 만들기';
  static const nameLabel = '팀에서 쓸 이름';
  static const bioLabel = '한줄 자기소개 (선택)';
  static const positionsLabel = '선호 포지션 (최대 3개)';
  static const dedicatedGkLabel = '전문 골키퍼';
  static const submit = '가입 완료';
  static const editTitle = '프로필 수정';
  static const save = '저장';

  /// 4번째 포지션을 누름 (Q-067 1번 확정 문구)
  static const maxPositionsReached = '최대 3개까지 고를 수 있어요';

  // TODO(문구 미정): 올라운더 안내 3개는 임시 (Q-067 0번, 1-8).
  /// 다른 포지션을 고른 상태에서 올라운더를 누름
  static const allrounderNeedsEmpty = '올라운더는 하나만 고를 수 있어요. 다른 포지션을 먼저 빼주세요';

  /// 올라운더를 고른 상태에서 다른 포지션을 누름
  static const allrounderSelected = '올라운더를 고르면 다른 포지션은 고를 수 없어요';

  /// 올라운더를 고른 상태에서 전문 골키퍼 체크
  static const allrounderNoGk = '올라운더는 전문 골키퍼와 함께 고를 수 없어요';

  /// 포지션을 더할 수 없는 이유 → 안내 (프로필·게스트 공통)
  static String addBlock(PositionAddBlock b) => switch (b) {
    PositionAddBlock.maxReached => maxPositionsReached,
    PositionAddBlock.allrounderNeedsEmpty => allrounderNeedsEmpty,
    PositionAddBlock.allrounderSelected => allrounderSelected,
  };

  static String hint(PositionPickHint h) => switch (h) {
    PositionPickHint.maxReached => maxPositionsReached,
    PositionPickHint.removeOneForGk => error(ProfileError.dedicatedGkNeedsFreeSlot),
    PositionPickHint.allrounderNeedsEmpty => allrounderNeedsEmpty,
    PositionPickHint.allrounderSelected => allrounderSelected,
    PositionPickHint.allrounderNoGk => allrounderNoGk,
  };

  static String error(ProfileError e) => switch (e) {
    ProfileError.nameRequired => '이름을 입력해주세요',
    ProfileError.dedicatedGkNeedsFreeSlot => '포지션을 하나 빼주세요',
    // TODO(문구 미정): 아래 오류 문구는 임시.
    ProfileError.nameTooLong => '이름은 8자까지 쓸 수 있어요',
    ProfileError.nameHasLineBreak => '이름은 한 줄로 써주세요',
    ProfileError.positionsRequired => '포지션을 하나 이상 골라주세요',
    ProfileError.tooManyPositions => '포지션은 3개까지 고를 수 있어요',
    ProfileError.duplicatePositions => '같은 포지션이 두 번 들어 있어요',
    ProfileError.allrounderNotAlone => allrounderSelected,
    ProfileError.allrounderWithDedicatedGk => allrounderNoGk,
    ProfileError.bioTooLong => '자기소개는 20자까지 쓸 수 있어요',
    ProfileError.bioHasLineBreak => '자기소개는 한 줄로 써주세요',
  };

  // TODO(문구 미정): 서버 오류 임시 문구.
  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.invalidProfile => '이름이나 자기소개를 확인해 주세요',
    ServerErrorCode.invalidPositions => '포지션을 확인해 주세요',
    ServerErrorCode.age14Required ||
    ServerErrorCode.requiredConsentsMissing => '필수 동의 항목을 확인해 주세요',
    _ => '저장하지 못했어요. 다시 시도해 주세요.',
  };
}
