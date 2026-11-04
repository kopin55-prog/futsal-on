import '../../../shared/domain/text_length.dart';

enum TeamCreateError { nameRequired, nameTooLong }

enum LogoTextError { empty, tooLong }

/// 팀 만들기 입력 검증과 기본 로고 글자 규칙 (기획서 5장, Q-011, Q-013).
///
/// 글자 수는 앞뒤 공백을 뺀 보이는 글자 단위 (Q-012).
/// 로고 글자 변경 권한은 여기서 판단하지 않는다 → Entitlements의 TeamAction.editLogoText.
class TeamValidator {
  const TeamValidator._();

  /// 팀 이름 최대 글자 수 (Q-011). 팀 이름은 중복 허용.
  static const int maxNameLength = 10;

  /// 로고 글자 최대 글자 수 (기본 로고, 직접 변경 공통).
  static const int logoTextLength = 2;

  /// 팀 이름만 필수. 정기 운동일·풋살장·로고는 선택이며 구조 승인 후 검증 추가.
  ///
  /// TODO(Q-대기): 팀 이름의 허용 문자(이모지·특수문자)와 줄바꿈 허용 여부 미정
  ///   → 현재 제한 없음.
  static Set<TeamCreateError> validateCreate({required String name}) {
    final length = countChars(normalizeInput(name));
    if (length == 0) return {TeamCreateError.nameRequired};
    if (length > maxNameLength) return {TeamCreateError.nameTooLong};
    return {};
  }

  /// 로고 사진이 없을 때 쓰는 기본 로고 글자 (Q-013).
  ///
  /// 팀 이름에서 공백을 모두 뺀 앞 두 글자. 한 글자 이름이면 한 글자.
  /// 영문은 입력 그대로 (대소문자 변환 없음). 한글·영어 구분 없음.
  /// 예: "코코FC" → "코코", "FC 코코" → "FC", "A B팀" → "AB".
  static String defaultLogoText(String teamName) =>
      takeChars(removeWhitespace(teamName), logoTextLength);

  /// 팀장이 직접 바꾼 로고 글자 검증: 앞뒤 공백을 빼고 1~2자 (Q-013).
  static Set<LogoTextError> validateLogoText(String text) {
    final length = countChars(normalizeInput(text));
    if (length == 0) return {LogoTextError.empty};
    if (length > logoTextLength) return {LogoTextError.tooLong};
    return {};
  }
}
