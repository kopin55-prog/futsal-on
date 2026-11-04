import '../../../shared/domain/text_length.dart';

enum TeamCreateError {
  nameRequired,
  nameTooLong,

  /// 팀 이름에 줄바꿈이 들어 있음 (Q-034).
  nameHasLineBreak,
}

enum LogoTextError { empty, tooLong }

/// 팀 만들기 입력 검증과 기본 로고 글자 규칙 (기획서 5장, Q-011, Q-013, Q-034, Q-036).
///
/// 로고 글자 변경 권한은 여기서 판단하지 않는다 → Entitlements의 TeamAction.editLogoText.
class TeamValidator {
  const TeamValidator._();

  /// 팀 이름 최대 글자 수 (Q-011). 팀 이름은 중복 허용.
  static const int maxNameLength = 10;

  /// 로고 글자 최대 글자 수 (기본 로고, 직접 변경 공통).
  static const int logoTextLength = 2;

  /// 저장 직전 팀 이름 정리: 앞뒤 공백 제거, 가운데 연속 공백은 하나로 (Q-034).
  static String normalizeName(String name) => normalizeSingleLineName(name);

  /// 팀 이름만 필수. 정기 운동일·풋살장·로고는 선택이며 구조 승인 후 검증 추가.
  ///
  /// 한 줄(줄바꿈 불가), 이모지·특수문자 허용. 글자 수는 [normalizeName] 결과의
  /// 보이는 글자 단위 (Q-012, Q-034).
  static Set<TeamCreateError> validateCreate({required String name}) {
    final errors = <TeamCreateError>{};
    final normalized = normalizeName(name);
    final length = countChars(normalized);
    if (length == 0) {
      errors.add(TeamCreateError.nameRequired);
    } else if (length > maxNameLength) {
      errors.add(TeamCreateError.nameTooLong);
    }
    if (containsLineBreak(normalized)) {
      errors.add(TeamCreateError.nameHasLineBreak);
    }
    return errors;
  }

  /// 로고 사진이 없을 때 쓰는 기본 로고 글자 (Q-013).
  ///
  /// 팀 이름에서 공백을 모두 뺀 앞 두 글자. 한 글자 이름이면 한 글자.
  /// 영문은 입력 그대로 (대소문자 변환 없음). 한글·영어 구분 없음.
  /// 예: "코코FC" → "코코", "FC 코코" → "FC", "A B팀" → "AB".
  /// 보이지 않는 문자도 빼고 센다 (Q-048).
  static String defaultLogoText(String teamName) => takeChars(
    removeWhitespace(removeInvisibleChars(teamName)),
    logoTextLength,
  );

  /// 저장 직전 로고 글자 정리: 팀 이름과 같은 규칙 (보이지 않는 문자 삭제,
  /// 앞뒤 공백 제거, 가운데 연속 공백 하나로. Q-034, Q-048).
  static String normalizeLogoText(String text) => normalizeSingleLineName(text);

  /// 팀장이 로고 글자를 저장할 때 logo_text_customized 값 (Q-047).
  ///
  /// 정리한 [newLogoText]가 현재 팀 이름 [teamName]의 기본 로고 글자와 같으면
  /// "직접 바꾸지 않은 것"(false) → 이후 팀 이름이 바뀌면 다시 자동 갱신된다.
  /// 다르면 true. 비교는 대소문자를 구분한다 (기본 로고는 대소문자 변환 없음, Q-013).
  static bool isLogoTextCustomized({
    required String newLogoText,
    required String teamName,
  }) => normalizeLogoText(newLogoText) != defaultLogoText(teamName);

  /// 팀 이름을 바꾼 뒤의 로고 글자 (Q-036).
  ///
  /// 팀장이 로고 글자를 직접 바꾼 적이 없으면([logoTextCustomized]가 false)
  /// 새 이름의 기본 로고 글자로 바꾸고, 바꾼 적이 있으면 [currentLogoText]를 그대로 둔다.
  /// "직접 바꾼 적이 있는지"를 어디에 기록할지는 데이터 구조 승인 후 정한다.
  static String logoTextAfterRename({
    required String newTeamName,
    required String currentLogoText,
    required bool logoTextCustomized,
  }) => logoTextCustomized ? currentLogoText : defaultLogoText(newTeamName);

  /// 팀장이 직접 바꾼 로고 글자 검증: 앞뒤 공백을 빼고 1~2자 (Q-013).
  /// 가운데 공백도 1자로 센다 ("A B"는 3자로 불가, Q-034 참고).
  /// 보이지 않는 문자는 지우고 센다 → 그것만으로 된 글자는 [LogoTextError.empty] (Q-048).
  static Set<LogoTextError> validateLogoText(String text) {
    final length = countChars(normalizeLogoText(text));
    if (length == 0) return {LogoTextError.empty};
    if (length > logoTextLength) return {LogoTextError.tooLong};
    return {};
  }
}
