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

  group('팀 이름 변경 시 로고 글자 미리보기 (Q-036, Q-047, 서버 트리거와 같은 규칙)', () {
    String after(String oldName, String newName, String current) =>
        TeamValidator.previewLogoTextAfterRename(
          oldTeamName: oldName,
          newTeamName: newName,
          currentLogoText: current,
        );

    test('지금 로고가 바꾸기 전 이름의 기본값이면 새 이름 앞 두 글자', () {
      expect(after('코코FC', '번개FC', '코코'), '번개');
      expect(after('코코FC', 'FC 번개', '코코'), 'FC');
      expect(after('코코FC', '⚽번개', '코코'), '⚽번');
      expect(after('코코FC', '번', '코코'), '번');
    });
    test('기본값과 다르면(직접 바꾼 로고) 그대로', () {
      expect(after('코코FC', '번개FC', 'KK'), 'KK');
      expect(after('코코FC', '번개FC', '코'), '코');
    });
    test('대소문자가 다르면 직접 바꾼 것으로 본다', () {
      expect(after('FC 코코', '번개', 'fc'), 'fc');
    });
    test('이름 정리 후 같으면 바뀌지 않은 것', () {
      expect(after('코코FC', '  코코FC ', 'KK'), 'KK');
      expect(after('코코FC', '  코코FC ', '코코'), '코코');
    });
    test('기본값으로 되돌린 로고는 다음 이름 변경 때 다시 따라간다', () {
      // 팀장이 "KK"로 바꿈 → 이름을 바꿔도 유지
      var logo = after('코코FC', '번개FC', 'KK');
      expect(logo, 'KK');
      // 지금 이름 기본값 "번개"로 되돌림 → 다음 변경 때 새 이름을 따른다
      logo = after('번개FC', '천둥FC', '번개');
      expect(logo, '천둥');
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

  // 보이지 않는 문자는 코드 포인트로 만든다.
  final zwsp = String.fromCharCode(0x200B);
  final zwj = String.fromCharCode(0x200D);
  final softHyphen = String.fromCharCode(0x00AD);
  final hangulFiller = String.fromCharCode(0x3164);

  group('보이지 않는 문자 삭제: 팀 이름 (Q-048)', () {
    test('보이지 않는 문자만으로 된 이름은 비어 있음 오류', () {
      expect(create(zwsp), {TeamCreateError.nameRequired});
      expect(create(' $zwsp$hangulFiller '), {TeamCreateError.nameRequired});
    });
    test('보이지 않는 문자는 지우고 글자 수를 센다', () {
      expect(create('${'가' * 10}$zwsp$softHyphen'), isEmpty);
      expect(TeamValidator.normalizeName('코$zwsp코FC'), '코코FC');
    });
    test('이모지 사이 ZWJ는 남아 결합 이모지가 1자로 유지된다', () {
      final family = ['👨', '👩', '👧'].join(zwj);
      expect(TeamValidator.normalizeName('${family}FC'), '${family}FC');
      expect(create(family * 10), isEmpty);
    });
    test('기본 로고 글자도 보이지 않는 문자를 빼고 만든다', () {
      expect(TeamValidator.defaultLogoText('$zwsp코$zwsp코FC'), '코코');
    });
  });

  group('직접 바꾼 로고 글자 정리 (Q-048)', () {
    Set<LogoTextError> v(String t) => TeamValidator.validateLogoText(t);

    test('보이지 않는 문자만이면 비어 있음 오류', () {
      expect(v(zwsp), {LogoTextError.empty});
      expect(v('$hangulFiller$zwj'), {LogoTextError.empty});
    });
    test('보이지 않는 문자는 세지 않는다', () {
      expect(v('코$zwsp코'), isEmpty);
      expect(TeamValidator.normalizeLogoText(' 코$zwsp코 '), '코코');
    });
  });
}
