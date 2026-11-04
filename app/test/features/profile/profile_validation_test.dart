import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/profile/domain/profile_validation.dart';
import 'package:futsal_on/shared/domain/position.dart';

void main() {
  ProfileInput input({
    String name = '홍길동',
    List<Position> positions = const [Position.defender],
    String? bio,
  }) =>
      ProfileInput(name: name, positions: positions, bio: bio);

  Set<ProfileError> v(ProfileInput i) => ProfileValidator.validate(i);

  test('필수 항목만 채우면 통과', () {
    expect(v(input()), isEmpty);
  });

  group('이름', () {
    test('빈 이름은 저장 불가', () {
      expect(v(input(name: '')), {ProfileError.nameRequired});
    });
    test('공백만 있는 이름은 저장 불가', () {
      expect(v(input(name: '   ')), {ProfileError.nameRequired});
    });
    test('한 글자 이름, 긴 이름 모두 허용 (길이 제한 미정)', () {
      expect(v(input(name: '김')), isEmpty);
      expect(v(input(name: '가' * 100)), isEmpty);
    });
  });

  group('선호 포지션', () {
    test('없으면 저장 불가', () {
      expect(v(input(positions: [])), {ProfileError.positionsRequired});
    });
    test('1~3개 허용', () {
      expect(v(input(positions: [Position.goalkeeper])), isEmpty);
      expect(
          v(input(positions: [
            Position.goalkeeper,
            Position.winger,
            Position.forward
          ])),
          isEmpty);
    });
    test('4개 이상은 저장 불가', () {
      expect(
        v(input(positions: [
          Position.goalkeeper,
          Position.defender,
          Position.midfielder,
          Position.winger,
        ])),
        {ProfileError.tooManyPositions},
      );
    });
    test('중복은 저장 불가', () {
      expect(v(input(positions: [Position.forward, Position.forward])),
          {ProfileError.duplicatePositions});
    });
    test('다섯 포지션 모두 선택지로 존재', () {
      expect(Position.values, hasLength(5));
    });
  });

  group('한줄 자기소개', () {
    test('없어도 됨', () {
      expect(v(input(bio: null)), isEmpty);
      expect(v(input(bio: '')), isEmpty);
    });
    test('20자까지 허용, 21자부터 불가', () {
      expect(v(input(bio: '가' * 20)), isEmpty);
      expect(v(input(bio: '가' * 21)), {ProfileError.bioTooLong});
      expect(v(input(bio: 'a' * 20)), isEmpty);
    });
    test('앞뒤 공백은 세지 않는다', () {
      expect(v(input(bio: '  ${'가' * 20}  ')), isEmpty);
    });
    test('단일 이모지는 1자로 센다 (코드포인트 기준)', () {
      expect(v(input(bio: '⚽' * 20)), isEmpty);
      expect(v(input(bio: '😀' * 20)), isEmpty);
      expect(v(input(bio: '😀' * 21)), {ProfileError.bioTooLong});
    });
  });

  test('여러 오류를 한 번에 돌려준다', () {
    expect(
      v(input(name: '', positions: [], bio: '가' * 21)),
      {
        ProfileError.nameRequired,
        ProfileError.positionsRequired,
        ProfileError.bioTooLong,
      },
    );
  });
}
