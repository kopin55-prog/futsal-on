import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';

void main() {
  Set<TeamCreateError> create(String name) =>
      TeamValidator.validateCreate(name: name);

  group('팀 만들기: 팀 이름 1~10자 (Q-011)', () {
    test('팀 이름만으로 생성 가능', () {
      expect(create('코코FC'), isEmpty);
    });
    test('팀 이름이 비거나 공백뿐이면 불가', () {
      expect(create(''), {TeamCreateError.nameRequired});
      expect(create('  '), {TeamCreateError.nameRequired});
    });
    test('1자와 10자 허용, 11자부터 불가', () {
      expect(create('코'), isEmpty);
      expect(create('가' * 10), isEmpty);
      expect(create('가' * 11), {TeamCreateError.nameTooLong});
    });
    test('앞뒤 공백은 세지 않는다, 가운데 공백은 센다', () {
      expect(create('  ${'가' * 10}  '), isEmpty);
      expect(create('가나다라마 바사아자'), isEmpty); // 10자 (공백 포함)
      expect(create('가나다라마 바사아자차'), {TeamCreateError.nameTooLong});
    });
    test('결합 이모지는 1자로 센다 (Q-012)', () {
      expect(create('👨‍👩‍👧‍👦' * 10), isEmpty);
      expect(create('🇰🇷' * 11), {TeamCreateError.nameTooLong});
    });
  });

  group('기본 로고 글자 (Q-013)', () {
    String logo(String name) => TeamValidator.defaultLogoText(name);

    test('기획서 예시: 코코FC → 코코, FC 코코 → FC', () {
      expect(logo('코코FC'), '코코');
      expect(logo('FC 코코'), 'FC');
    });
    test('공백을 모두 뺀 앞 두 글자', () {
      expect(logo('A B팀'), 'AB');
      expect(logo('  코 코FC'), '코코');
    });
    test('한 글자 이름이면 한 글자', () {
      expect(logo('코'), '코');
      expect(logo(' 코 '), '코');
    });
    test('영문은 입력 그대로 (대소문자 변환 없음)', () {
      expect(logo('seoul United'), 'se');
      expect(logo('FCseoul'), 'FC');
      expect(logo('A코'), 'A코');
    });
    test('이모지는 보이는 글자 단위로 자른다', () {
      expect(logo('😀😀FC'), '😀😀');
      expect(logo('👨‍👩‍👧FC'), '👨‍👩‍👧F');
    });
  });

  group('직접 바꾼 로고 글자: 1~2자 (Q-013)', () {
    Set<LogoTextError> v(String t) => TeamValidator.validateLogoText(t);

    test('한 글자, 두 글자 허용', () {
      expect(v('코'), isEmpty);
      expect(v('코코'), isEmpty);
      expect(v(' 코코 '), isEmpty);
    });
    test('빈 값 불가', () {
      expect(v(''), {LogoTextError.empty});
      expect(v(' '), {LogoTextError.empty});
    });
    test('세 글자 이상 불가', () {
      expect(v('코코F'), {LogoTextError.tooLong});
      expect(v('A B'), {LogoTextError.tooLong});
    });
    test('결합 이모지 두 개는 2자', () {
      expect(v('🇰🇷👍🏽'), isEmpty);
    });
  });
}
