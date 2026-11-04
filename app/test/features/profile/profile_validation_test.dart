import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/profile/domain/profile_validation.dart';
import 'package:futsal_on/shared/domain/position.dart';

void main() {
  ProfileInput input({
    String name = '홍길동',
    List<Position> positions = const [Position.defender],
    bool isDedicatedGk = false,
    String? bio,
  }) => ProfileInput(
    name: name,
    positions: positions,
    isDedicatedGk: isDedicatedGk,
    bio: bio,
  );

  Set<ProfileError> v(ProfileInput i) => ProfileValidator.validate(i);

  test('필수 항목만 채우면 통과', () {
    expect(v(input()), isEmpty);
  });

  group('팀에서 쓸 이름: 1~8자 (Q-011)', () {
    test('빈 이름, 공백만 있는 이름은 저장 불가', () {
      expect(v(input(name: '')), {ProfileError.nameRequired});
      expect(v(input(name: '   ')), {ProfileError.nameRequired});
    });
    test('1자와 8자 허용, 9자부터 불가', () {
      expect(v(input(name: '김')), isEmpty);
      expect(v(input(name: '가' * 8)), isEmpty);
      expect(v(input(name: '가' * 9)), {ProfileError.nameTooLong});
    });
    test('앞뒤 공백은 세지 않는다', () {
      expect(v(input(name: '  ${'가' * 8}  ')), isEmpty);
    });
    test('결합 이모지는 1자로 센다 (Q-012)', () {
      expect(v(input(name: '👍🏽' * 8)), isEmpty);
      expect(v(input(name: '👍🏽' * 9)), {ProfileError.nameTooLong});
    });
  });

  group('선호 포지션', () {
    test('없으면 저장 불가', () {
      expect(v(input(positions: [])), {ProfileError.positionsRequired});
    });
    test('1~3개 허용', () {
      expect(v(input(positions: [Position.goalkeeper])), isEmpty);
      expect(
        v(
          input(
            positions: [Position.goalkeeper, Position.winger, Position.forward],
          ),
        ),
        isEmpty,
      );
    });
    test('4개 이상은 저장 불가', () {
      expect(
        v(
          input(
            positions: [
              Position.goalkeeper,
              Position.defender,
              Position.midfielder,
              Position.winger,
            ],
          ),
        ),
        {ProfileError.tooManyPositions},
      );
    });
    test('중복은 저장 불가', () {
      expect(v(input(positions: [Position.forward, Position.forward])), {
        ProfileError.duplicatePositions,
      });
    });
    test('다섯 포지션 모두 선택지로 존재', () {
      expect(Position.values, hasLength(5));
    });
  });

  group('전문 골키퍼 → 골키퍼 자동 포함 (Q-019)', () {
    test('체크하면 선호 포지션에 골키퍼가 들어간다', () {
      final i = input(positions: [Position.defender], isDedicatedGk: true);
      expect(
        i.effectivePositions,
        unorderedEquals([Position.defender, Position.goalkeeper]),
      );
      expect(i.normalized().positions, i.effectivePositions);
      expect(v(i), isEmpty);
    });
    test('이미 골키퍼가 있으면 그대로', () {
      final i = input(positions: [Position.goalkeeper], isDedicatedGk: true);
      expect(i.effectivePositions, [Position.goalkeeper]);
    });
    test('전문 골키퍼만 체크하고 포지션을 안 골라도 골키퍼 1개로 통과', () {
      expect(v(input(positions: [], isDedicatedGk: true)), isEmpty);
    });
    test('체크 안 하면 자동 포함 없음', () {
      expect(input().effectivePositions, [Position.defender]);
    });
    test('골키퍼 외 3개 + 전문 골키퍼: 처리 미정, 저장 불가 오류로 막지 않음', () {
      // 확정 규칙이 아님 (TODO(Q-대기)). 결정되면 이 테스트를 바꾼다.
      final i = input(
        positions: [Position.defender, Position.midfielder, Position.forward],
        isDedicatedGk: true,
      );
      expect(v(i), isEmpty);
      expect(i.effectivePositions, hasLength(4));
    });
  });

  group('한줄 자기소개: 20자, 줄바꿈 불가 (Q-012)', () {
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
    test('이모지는 보이는 글자 하나 = 1자', () {
      expect(v(input(bio: '⚽' * 20)), isEmpty);
      expect(v(input(bio: '😀' * 21)), {ProfileError.bioTooLong});
      expect(v(input(bio: '👨‍👩‍👧‍👦' * 20)), isEmpty);
      expect(v(input(bio: '🇰🇷' * 20)), isEmpty);
      expect(v(input(bio: '👍🏽' * 21)), {ProfileError.bioTooLong});
    });
    test('줄바꿈은 불가 (앞뒤 줄바꿈은 공백으로 제거)', () {
      expect(v(input(bio: '안녕\n하세요')), {ProfileError.bioHasLineBreak});
      expect(v(input(bio: '안녕\r\n하세요')), {ProfileError.bioHasLineBreak});
      expect(v(input(bio: '\n안녕하세요\n')), isEmpty);
    });
  });

  test('저장 직전 정리: 앞뒤 공백 제거, 빈 자기소개는 null', () {
    final n = input(name: '  길동 ', bio: '   ').normalized();
    expect(n.name, '길동');
    expect(n.bio, isNull);
    expect(input(bio: ' 안녕 ').normalized().bio, '안녕');
  });

  test('여러 오류를 한 번에 돌려준다', () {
    expect(v(input(name: '', positions: [], bio: '가' * 21)), {
      ProfileError.nameRequired,
      ProfileError.positionsRequired,
      ProfileError.bioTooLong,
    });
  });
}
