import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/shared/domain/text_length.dart';

void main() {
  // 보이지 않는 문자는 코드 포인트로 만들어 눈으로 확인할 수 있게 한다.
  final zwsp = String.fromCharCode(0x200B);
  final zwnj = String.fromCharCode(0x200C);
  final zwj = String.fromCharCode(0x200D);
  final wordJoiner = String.fromCharCode(0x2060);
  final bom = String.fromCharCode(0xFEFF);
  final softHyphen = String.fromCharCode(0x00AD);
  final rlo = String.fromCharCode(0x202E);
  final hangulFiller = String.fromCharCode(0x3164);
  final otherFillers = String.fromCharCodes([
    0xFFA0,
    0x115F,
    0x1160,
    0x034F,
    0x2800,
  ]);

  group('보이지 않는 문자 삭제 (Q-048)', () {
    String r(String s) => removeInvisibleChars(s);

    test('폭 없는 공백·단어 결합자·BOM·소프트 하이픈·방향 제어 문자를 지운다', () {
      expect(r('코$zwsp코FC'), '코코FC');
      expect(r('코$zwnj코${zwj}FC'), '코코FC');
      expect(r('$bom코코$wordJoiner FC$softHyphen'), '코코 FC');
      expect(r('코코${rlo}FC'), '코코FC');
    });
    test('한글 채움 문자 등 글자로 분류되지만 안 보이는 문자도 지운다', () {
      expect(r('$hangulFiller코코'), '코코');
      expect(r('코$otherFillers코'), '코코');
    });
    test('이모지 사이의 ZWJ는 남긴다 (가족·직업·무지개 깃발·피부색)', () {
      final family = ['👨', '👩', '👧', '👦'].join(zwj);
      final technologist = '🧑🏽$zwj💻';
      final rainbowFlag = '🏳️$zwj🌈';
      final heartOnFire = '❤️$zwj🔥';
      for (final e in [family, technologist, rainbowFlag, heartOnFire]) {
        expect(r(e), e);
        expect(countChars(e), 1);
        expect(countChars(r('$e코코')), 3);
      }
    });
    test('지역 깃발(태그 문자열)은 남긴다', () {
      final england = String.fromCharCodes([
        0x1F3F4, 0xE0067, 0xE0062, 0xE0065, 0xE006E, 0xE0067, 0xE007F, //
      ]);
      expect(r(england), england);
      expect(countChars(r(england)), 1);
    });
    test('이모지 사이가 아닌 ZWJ는 지운다', () {
      expect(r('코$zwj코'), '코코');
      expect(r('⚽$zwj코'), '⚽코');
      expect(r('코$zwj⚽'), '코⚽');
      expect(r('⚽$zwj'), '⚽');
      expect(r('$zwj⚽'), '⚽');
    });
    test('태그 문자가 깃발 묶음 밖에 있으면 지운다', () {
      expect(r('코${String.fromCharCodes([0xE0067, 0xE007F])}'), '코');
    });
  });

  group('한 줄 이름 정리에 보이지 않는 문자 삭제 포함 (Q-034, Q-048)', () {
    String n(String s) => normalizeSingleLineName(s);

    test('똑같아 보이는 이름은 같은 정리 결과가 된다', () {
      expect(n('코$zwsp코FC'), n('코코FC'));
    });
    test('보이지 않는 문자만으로 된 이름은 빈 문자열', () {
      expect(n('$zwsp$zwj$bom$hangulFiller'), '');
      expect(n(' $zwsp '), '');
    });
    test('보이지 않는 문자를 지운 뒤 공백을 정리한다', () {
      expect(n('$zwsp 코코 $zwsp FC '), '코코 FC');
      expect(n('코코 $wordJoiner  FC'), '코코 FC');
    });
  });
}
