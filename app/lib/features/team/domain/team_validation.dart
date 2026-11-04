import '../../../shared/domain/text_length.dart';

enum TeamCreateError {
  nameRequired,
}

enum LogoTextError {
  empty,
  tooLong,
}

/// 팀 만들기 입력 검증과 기본 로고 글자 규칙 (기획서 5장).
class TeamValidator {
  const TeamValidator._();

  /// 기본 로고 글자 수.
  static const int logoTextLength = 2;

  /// 팀 이름만 필수. 정기 운동일·풋살장·로고는 선택이며 구조 승인 후 검증 추가.
  static Set<TeamCreateError> validateCreate({required String name}) {
    // TODO(Q-대기): 팀 이름 길이 제한, 허용 문자, 팀 이름 중복 허용 여부 미정 → 제한 없음.
    // TODO(Q-대기): 공백만 입력한 팀 이름은 "비어 있음"으로 본다.
    if (name.trim().isEmpty) return {TeamCreateError.nameRequired};
    return {};
  }

  /// 로고 사진이 없을 때 쓰는 기본 로고 글자: 팀 이름 앞 두 글자.
  ///
  /// 예: "코코FC" → "코코", "FC 코코" → "FC" (팀장이 "코코"로 바꿀 수 있음).
  /// 한글·영어 구분 없음.
  ///
  /// TODO(Q-대기): 다음 경우의 처리가 미정이라 가장 단순하게 "앞뒤 공백을 뺀 이름의
  ///   앞 두 글자 그대로"를 쓴다.
  ///   - 앞 두 글자 사이에 공백이 있는 경우 ("A B팀" → "A ")
  ///   - 특수문자·이모지로 시작하는 경우
  ///   - 영문 대소문자 변환 여부
  ///   - 팀 이름이 한 글자인 경우 (현재 한 글자만 표시)
  static String defaultLogoText(String teamName) =>
      takeChars(teamName.trim(), logoTextLength);

  /// 팀장이 직접 바꾼 로고 글자 검증.
  ///
  /// TODO(Q-대기): 직접 입력 시 정확히 두 글자여야 하는지, 한 글자도 되는지 미정
  ///   → 가장 덜 제한적으로 1~2글자 허용. 공백 포함 여부도 미정 (제한 없음).
  /// TODO(Q-대기): 기획서 5장은 "팀장이 변경"이지만 permissions.md는 팀 정보 수정을
  ///   팀장·운영진 모두에게 허용 → 로고 글자 변경 권한 주체 확인 필요.
  ///   현재 권한 판단은 Entitlements의 TeamAction.editTeamInfo(팀장·운영진)를 따른다.
  static Set<LogoTextError> validateLogoText(String text) {
    final length = countChars(text.trim());
    if (length == 0) return {LogoTextError.empty};
    if (length > logoTextLength) return {LogoTextError.tooLong};
    return {};
  }
}
