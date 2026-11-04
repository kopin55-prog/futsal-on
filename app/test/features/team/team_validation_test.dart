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

  group('팀 이름: 한 줄, 이모지·특수문자 허용, 가운데 연속 공백 하나로 (Q-034)', () {
    test('줄바꿈이 있으면 저장 불가', () {
      expect(create('코코\nFC'), {TeamCreateError.nameHasLineBreak});
      expect(create('코코\r\nFC'), {TeamCreateError.nameHasLineBreak});
    });
    test('앞뒤 줄바꿈은 제거되어 통과', () {
      expect(create('\n코코FC\n'), isEmpty);
    });
    test('이모지·특수문자 허용', () {
      expect(create('⚽코코FC'), isEmpty);
      expect(create('코코FC★#1!'), isEmpty);
    });
    test('가운데 연속 공백은 하나로 줄인 뒤 글자 수를 센다', () {
      expect(create('가나다라마   바사아자'), isEmpty); // 줄이면 10자
      expect(create('가나다라마\t　바사아자'), isEmpty);
      expect(create('가나다라마  바사아자차'), {TeamCreateError.nameTooLong});
    });
    test('정리된 팀 이름', () {
      expect(TeamValidator.normalizeName('  FC   코코  '), 'FC 코코');
    });
    test('줄바꿈과 글자 수 초과는 함께 알려준다', () {
      expect(create('가나다라마\n바사아자차카'), {
        TeamCreateError.nameTooLong,
        TeamCreateError.nameHasLineBreak,
      });
    });
  });

  group('팀 이름 변경 시 로고 글자 (Q-036)', () {
    String after(String newName, String current, {required bool customized}) =>
        TeamValidator.logoTextAfterRename(
          newTeamName: newName,
          currentLogoText: current,
          logoTextCustomized: customized,
        );

    test('직접 바꾼 적이 없으면 새 이름 앞 두 글자로 바뀐다', () {
      expect(after('번개FC', '코코', customized: false), '번개');
      expect(after('FC 번개', '코코', customized: false), 'FC');
      expect(after('⚽번개', '코코', customized: false), '⚽번');
      expect(after('번', '코코', customized: false), '번');
    });
    test('직접 바꾼 적이 있으면 그대로 둔다', () {
      expect(after('번개FC', 'KK', customized: true), 'KK');
      expect(after('번개FC', '코', customized: true), '코');
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
