import '../../../shared/domain/text_length.dart';

enum TeamCreateError {
  nameRequired,
  nameTooLong,

  /// 팀 이름에 줄바꿈이 들어 있음 (Q-034).
  nameHasLineBreak,
}

enum LogoTextError { empty, tooLong }

/// 정기 운동일 입력 오류 (data-model.md 3-1, Q-067 4번).
enum RegularScheduleError {
  /// 시각을 넣었는데 요일이 없음
  weekdayRequired,

  /// 종료 시각만 있고 시작 시각이 없음
  startRequired,

  /// 시작과 종료가 같음 (자정 넘김은 허용: 22:00~00:30)
  sameStartEnd,
}

/// 시·분만 쓰는 시각. Flutter 의 TimeOfDay 에 기대지 않으려고 domain 에 둔다.
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  /// "HH:MM" 또는 "HH:MM:SS"
  factory ClockTime.parse(String text) {
    final parts = text.split(':');
    return ClockTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  final int hour;
  final int minute;

  /// 서버로 보내는 형식 "HH:MM"
  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  int get _minutes => hour * 60 + minute;

  @override
  int compareTo(ClockTime other) => _minutes.compareTo(other._minutes);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => hhmm;
}

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

  /// 팀 이름만 필수 (만들기·수정 공통). 정기 운동일은 [validateRegularSchedule],
  /// 로고 글자는 [validateLogoText].
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

  /// 팀 이름을 바꾼 뒤 보일 로고 글자 미리보기 (Q-036, Q-047). 저장은 서버 트리거
  /// (private.teams_before_write)가 같은 규칙으로 정하고, 이 값은 화면 미리보기에만 쓴다.
  ///
  /// 지금 로고 글자 [currentLogoText]가 바꾸기 전 이름 [oldTeamName]의 기본값과 같으면
  /// "직접 바꾼 적 없음"으로 보고 새 이름 [newTeamName]의 기본값, 다르면 그대로.
  /// 비교는 대소문자를 구분한다 (기본 로고는 대소문자 변환 없음, Q-013).
  /// 이름이 그대로면 로고도 그대로.
  static String previewLogoTextAfterRename({
    required String oldTeamName,
    required String newTeamName,
    required String currentLogoText,
  }) {
    final oldName = normalizeName(oldTeamName);
    final newName = normalizeName(newTeamName);
    if (newName == oldName) return currentLogoText;
    return currentLogoText == defaultLogoText(oldName)
        ? defaultLogoText(newName)
        : currentLogoText;
  }

  /// 팀장이 직접 바꾼 로고 글자 검증: 앞뒤 공백을 빼고 1~2자 (Q-013).
  /// 가운데 공백도 1자로 센다 ("A B"는 3자로 불가, Q-034 참고).
  /// 보이지 않는 문자는 지우고 센다 → 그것만으로 된 글자는 [LogoTextError.empty] (Q-048).
  static Set<LogoTextError> validateLogoText(String text) {
    final length = countChars(normalizeLogoText(text));
    if (length == 0) return {LogoTextError.empty};
    if (length > logoTextLength) return {LogoTextError.tooLong};
    return {};
  }

  /// 정기 운동일: 요일 → 시작 → 종료 순으로 짝이 맞아야 한다. 모두 선택 항목.
  /// 종료가 시작보다 이르면 다음 날로 본다 (자정 넘김 허용, Q-067 4번). 같으면 불가.
  static Set<RegularScheduleError> validateRegularSchedule({
    int? weekday,
    ClockTime? start,
    ClockTime? end,
  }) {
    final errors = <RegularScheduleError>{};
    if (start != null && weekday == null) {
      errors.add(RegularScheduleError.weekdayRequired);
    }
    if (end != null && start == null) {
      errors.add(RegularScheduleError.startRequired);
    }
    if (start != null && end != null && start == end) {
      errors.add(RegularScheduleError.sameStartEnd);
    }
    return errors;
  }

  /// 종료가 시작보다 이르면 자정을 넘긴 일정 (화면 표시용).
  static bool crossesMidnight(ClockTime start, ClockTime end) =>
      end.compareTo(start) < 0;

  /// 팀 해체 확인 입력이 팀 이름과 같은지 (Q-067 7번).
  /// 이름 정리 규칙(보이지 않는 문자 삭제·앞뒤 공백·연속 공백) 적용 후 영문 대소문자 무시.
  /// 서버(private.dissolve_confirmation_matches)도 같은 규칙으로 다시 검사한다.
  static bool dissolveConfirmationMatches({
    required String teamName,
    required String input,
  }) {
    final a = normalizeSingleLineName(input);
    if (a.isEmpty) return false;
    return a.toLowerCase() == normalizeSingleLineName(teamName).toLowerCase();
  }
}
