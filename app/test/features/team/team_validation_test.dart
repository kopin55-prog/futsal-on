import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';

void main() {
  group('팀 만들기', () {
    test('팀 이름만으로 생성 가능', () {
      expect(TeamValidator.validateCreate(name: '코코FC'), isEmpty);
    });
    test('팀 이름이 비거나 공백뿐이면 불가', () {
      expect(TeamValidator.validateCreate(name: ''),
          {TeamCreateError.nameRequired});
      expect(TeamValidator.validateCreate(name: '  '),
          {TeamCreateError.nameRequired});
    });
    test('한 글자 팀 이름도 허용 (길이 제한 미정)', () {
      expect(TeamValidator.validateCreate(name: '코'), isEmpty);
    });
  });

  group('기본 로고 글자', () {
    test('기획서 예시: 코코FC → 코코', () {
      expect(TeamValidator.defaultLogoText('코코FC'), '코코');
    });
    test('기획서 예시: FC 코코 → FC', () {
      expect(TeamValidator.defaultLogoText('FC 코코'), 'FC');
    });
    test('한글·영어 구분 없음', () {
      expect(TeamValidator.defaultLogoText('Seoul United'), 'Se');
      expect(TeamValidator.defaultLogoText('A코'), 'A코');
    });
    test('앞뒤 공백은 무시', () {
      expect(TeamValidator.defaultLogoText('  코코FC'), '코코');
    });
    test('한 글자 이름은 한 글자 (처리 방식 미정)', () {
      expect(TeamValidator.defaultLogoText('코'), '코');
    });
    test('이모지는 코드포인트 단위로 잘린다', () {
      expect(TeamValidator.defaultLogoText('😀😀FC'), '😀😀');
    });
  });

  group('팀장이 바꾼 로고 글자', () {
    test('두 글자 허용', () {
      expect(TeamValidator.validateLogoText('코코'), isEmpty);
    });
    test('한 글자 허용 (가장 덜 제한적, 미정)', () {
      expect(TeamValidator.validateLogoText('코'), isEmpty);
    });
    test('빈 값 불가', () {
      expect(TeamValidator.validateLogoText(' '), {LogoTextError.empty});
    });
    test('세 글자 이상 불가', () {
      expect(TeamValidator.validateLogoText('코코F'), {LogoTextError.tooLong});
    });
  });
}
