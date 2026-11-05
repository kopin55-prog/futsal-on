// 서버(Postgres)의 이름 정리 규칙이 앱(text_length.dart)과 같은 유니코드 범위를 쓰는지 확인한다.
// supabase/migrations/202611050001_private_schema_text_rules.sql 의 범위 표를
// Dart RegExp 유니코드 속성과 모든 코드 포인트에서 비교한다 (sprint-01.md 메모, 11장 14번).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<int> _rangesOf(String sql, String functionName) {
  final start = sql.indexOf('create function private.$functionName(');
  expect(start, isNot(-1), reason: functionName);
  final open = sql.indexOf("'{", start);
  final close = sql.indexOf("}'", open);
  return sql
      .substring(open + 2, close)
      .split(RegExp(r'[,\s]+'))
      .where((s) => s.isNotEmpty)
      .map(int.parse)
      .toList();
}

bool _inRanges(List<int> r, int cp) {
  for (var i = 0; i < r.length; i += 2) {
    if (cp >= r[i] && cp <= r[i + 1]) return true;
  }
  return false;
}

void _expectSame(List<int> ranges, bool Function(int) dart, String label) {
  final mismatches = <String>[];
  for (var cp = 0; cp <= 0x10FFFF; cp++) {
    if (cp >= 0xD800 && cp <= 0xDFFF) continue;
    if (_inRanges(ranges, cp) != dart(cp)) {
      mismatches.add(cp.toRadixString(16));
      if (mismatches.length > 10) break;
    }
  }
  expect(mismatches, isEmpty, reason: label);
}

void main() {
  final sql = File(
    '../supabase/migrations/202611050001_private_schema_text_rules.sql',
  ).readAsStringSync();

  bool prop(String name, int cp) =>
      RegExp('^\\p{$name}\$', unicode: true).hasMatch(String.fromCharCode(cp));

  final cf = RegExp(r'^\p{Cf}$', unicode: true);
  final ep = RegExp(r'^\p{Extended_Pictographic}$', unicode: true);

  test('보이지 않는 문자(Cf) 범위가 앱과 같다', () {
    _expectSame(
      _rangesOf(sql, 'is_cf'),
      (cp) => cf.hasMatch(String.fromCharCode(cp)),
      'Cf',
    );
  });

  test('이모지(Extended_Pictographic) 범위가 앱과 같다', () {
    _expectSame(
      _rangesOf(sql, 'is_ext_pict'),
      (cp) => ep.hasMatch(String.fromCharCode(cp)),
      'Extended_Pictographic',
    );
  });

  test('Dart 정규식 속성 확인 (도우미 자체 점검)', () {
    expect(prop('Cf', 0x200B), isTrue);
    expect(prop('Cf', 0x41), isFalse);
  });
}
