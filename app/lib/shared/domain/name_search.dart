import 'text_length.dart';

/// 이름 검색 (화면 안에서 바로 거르기, 스프린트 04 6-4).
///
/// 정리 규칙은 기존 이름 검색(팀 이름 검색 search_teams, Q-034·Q-048)과 같다:
/// 보이지 않는 문자를 지우고, 앞뒤 공백을 빼고, 가운데 공백 연속은 하나로 줄인 뒤, 대소문자 구분 없이 "포함"으로 찾는다.
/// 팀 이름 검색과 달리 최소 글자 수는 없다(일부 글자로 바로 걸러짐). 빈 검색어면 모두.
abstract final class NameSearch {
  /// 검색어·이름 정리 결과 (비교용 키).
  static String key(String text) => normalizeSingleLineName(text).toLowerCase();

  /// [name] 이 검색어 키 [queryKey] 를 포함하는지.
  static bool matchesKey(String nameKey, String queryKey) => queryKey.isEmpty || nameKey.contains(queryKey);

  static bool matches(String name, String query) => matchesKey(key(name), key(query));
}
