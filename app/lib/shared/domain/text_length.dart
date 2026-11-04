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

/// 모든 공백(띄어쓰기·탭·줄바꿈 등)을 뺀 문자열.
String removeWhitespace(String text) => text.replaceAll(RegExp(r'\s'), '');
