/// 글자 수 세기와 입력 정리 규칙의 단일 지점 (Q-012).
///
/// 글자 수는 눈에 보이는 글자(grapheme) 단위로 센다. 한글 한 글자, 영문 한 글자,
/// 결합 이모지(가족·피부색·국기 등) 하나가 모두 1자다.
library;

import 'package:characters/characters.dart';

/// [text]의 보이는 글자 수.
int countChars(String text) => text.characters.length;

/// [text]의 앞에서 [count]자를 [countChars]와 같은 단위로 자른다.
String takeChars(String text, int count) =>
    text.characters.take(count).toString();

/// 저장·검증 전 공통 정리: 앞뒤 공백 제거.
String normalizeInput(String text) => text.trim();

/// 줄바꿈 문자가 들어 있는지 (줄바꿈 불가 항목 검증용).
bool containsLineBreak(String text) => _lineBreak.hasMatch(text);

final RegExp _lineBreak = RegExp('[\r\n  ]');

/// 한 줄 이름(팀 이름·팀에서 쓸 이름) 정리 (Q-034).
///
/// 앞뒤 공백을 빼고, 가운데의 공백(띄어쓰기·탭·전각 공백 등) 연속은 띄어쓰기 하나로 줄인다.
/// 줄바꿈은 줄이지 않고 남긴다 → 검증에서 [containsLineBreak]로 막는다.
/// 이름의 글자 수는 이 정리 결과로 센다. 이모지·특수문자는 제한하지 않는다.
///
/// 공백 정리 전에 보이지 않는 문자를 먼저 지운다 ([removeInvisibleChars], Q-048).
/// 그래서 보이지 않는 문자만으로 된 이름은 빈 문자열이 되어 "비어 있음" 오류가 된다.
String normalizeSingleLineName(String text) => normalizeInput(
  removeInvisibleChars(text),
).replaceAll(_inlineWhitespaceRun, ' ');

/// 눈에 보이지 않는 문자를 지운다 (Q-048).
///
/// 지우는 것:
/// - 모든 형식 문자(유니코드 Cf): 폭 없는 공백 U+200B, ZWNJ U+200C, ZWJ U+200D,
///   단어 결합자 U+2060, BOM U+FEFF, 소프트 하이픈 U+00AD, 방향 제어 문자
///   (U+200E/F, U+202A~E, U+2066~9) 등
/// - 글자로 분류되지만 보이지 않는 채움 문자: 한글 채움 문자 U+3164·U+FFA0·
///   U+115F·U+1160, 결합 자소 결합자 U+034F, 점자 빈칸 U+2800
///
/// 남기는 것 (이모지가 깨지지 않도록):
/// - 이모지와 이모지 사이의 ZWJ (가족·직업·무지개 깃발 등).
///   앞 이모지 뒤에 이모지 표현 선택자(U+FE0E/U+FE0F)나 피부색이 붙어 있어도 된다.
/// - 검은 깃발(U+1F3F4) 뒤 태그 문자열 (잉글랜드·스코틀랜드 등 지역 깃발).
/// 그 밖의 위치(글자 사이, 맨 앞·뒤, 한쪽만 이모지인 경우)의 ZWJ는 지운다.
String removeInvisibleChars(String text) =>
    text.replaceAllMapped(_invisibleOrKept, (m) => m[1] ?? m[2] ?? '');

final RegExp _invisibleOrKept = RegExp(
  // 1) 지역 깃발 태그 묶음: 그대로 둔다.
  r'(\u{1F3F4}[\u{E0020}-\u{E007E}]+\u{E007F})'
  // 2) 이모지 사이 ZWJ: 그대로 둔다.
  r'|((?<=\p{Extended_Pictographic}[\u{FE0E}\u{FE0F}\u{1F3FB}-\u{1F3FF}]*)'
  r'\u{200D}(?=\p{Extended_Pictographic}))'
  // 3) 나머지 보이지 않는 문자: 지운다.
  r'|[\p{Cf}\u{034F}\u{115F}\u{1160}\u{2800}\u{3164}\u{FFA0}]',
  unicode: true,
);

/// 줄바꿈([_lineBreak]의 문자)을 제외한 공백 문자의 연속.
final RegExp _inlineWhitespaceRun = RegExp(r'[^\S\r\n  ]+');

/// 모든 공백(띄어쓰기·탭·줄바꿈 등)을 뺀 문자열.
String removeWhitespace(String text) => text.replaceAll(RegExp(r'\s'), '');
