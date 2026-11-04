/// 글자 수 세기 규칙의 단일 지점.
///
/// 현재는 유니코드 코드포인트(rune) 단위로 센다. 한글 한 글자, 영문 한 글자,
/// 대부분의 단일 이모지는 1자로 세어진다.
///
/// TODO(Q-대기): 글자 수를 어떻게 셀지 미정 (이모지 포함 여부, 결합 이모지·국기 처리).
///   사람이 보는 글자 단위(grapheme)로 세면 더 덜 제한적이지만 `characters` 패키지가
///   필요하다 (Flutter SDK에 포함돼 있으나 pubspec 추가는 승인 대상).
///   결정되면 이 함수만 바꾸면 된다.
int countChars(String text) => text.runes.length;

/// [text]의 앞에서 [count]자를 [countChars]와 같은 단위로 자른다.
String takeChars(String text, int count) =>
    String.fromCharCodes(text.runes.take(count));
