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
  });

  group('골키퍼 포함 총 3개까지 (Q-035)', () {
    const threeOutfield = [
      Position.defender,
      Position.midfielder,
      Position.forward,
    ];

    test('골키퍼 외 3개 + 전문 골키퍼: 하나 빼도록 안내하는 별도 오류로 저장 불가', () {
      final i = input(positions: threeOutfield, isDedicatedGk: true);
      expect(v(i), {ProfileError.dedicatedGkNeedsFreeSlot});
      expect(ProfileValidator.canCheckDedicatedGk(threeOutfield), isFalse);
    });
    test('하나 빼면 골키퍼 자동 포함으로 3개가 되어 통과', () {
      final i = input(
        positions: [Position.defender, Position.forward],
        isDedicatedGk: true,
      );
      expect(v(i), isEmpty);
      expect(i.effectivePositions, hasLength(3));
      expect(
        ProfileValidator.canCheckDedicatedGk([
          Position.defender,
          Position.forward,
        ]),
        isTrue,
      );
    });
    test('이미 골키퍼가 포함된 3개면 전문 골키퍼 체크 가능', () {
      const withGk = [Position.goalkeeper, Position.defender, Position.forward];
      expect(v(input(positions: withGk, isDedicatedGk: true)), isEmpty);
      expect(ProfileValidator.canCheckDedicatedGk(withGk), isTrue);
    });
    test('전문 골키퍼 체크 안 하면 골키퍼 외 3개 그대로 통과', () {
      expect(v(input(positions: threeOutfield)), isEmpty);
    });
    test('직접 4개 이상 고르면 기존 오류만 (전문 골키퍼 여부 무관)', () {
      final four = [...threeOutfield, Position.winger];
      expect(v(input(positions: four)), {ProfileError.tooManyPositions});
      expect(v(input(positions: four, isDedicatedGk: true)), {
        ProfileError.tooManyPositions,
      });
    });
    test('빈 선택 또는 1~2개면 언제든 체크 가능', () {
      expect(ProfileValidator.canCheckDedicatedGk([]), isTrue);
      expect(ProfileValidator.canCheckDedicatedGk([Position.winger]), isTrue);
    });
  });

  group('팀에서 쓸 이름: 한 줄, 이모지·특수문자 허용, 가운데 연속 공백 하나로 (Q-034)', () {
    test('줄바꿈이 있으면 저장 불가', () {
      expect(v(input(name: '홍\n길동')), {ProfileError.nameHasLineBreak});
      expect(v(input(name: '홍\r\n길동')), {ProfileError.nameHasLineBreak});
      expect(v(input(name: '홍 길동')), {ProfileError.nameHasLineBreak});
    });
    test('앞뒤 줄바꿈은 앞뒤 공백으로 제거되어 통과', () {
      expect(v(input(name: '\n길동\n')), isEmpty);
    });
    test('이모지·특수문자 허용', () {
      expect(v(input(name: '⚽길동★')), isEmpty);
      expect(v(input(name: '#10_길동!')), isEmpty);
    });
    test('가운데 연속 공백은 하나로 줄인 뒤 글자 수를 센다', () {
      // "가나다  라마바사" (공백 2개) → "가나다 라마바사" 8자
      expect(v(input(name: '가나다  라마바사')), isEmpty);
      expect(v(input(name: '가나다\t 　라마바사')), isEmpty);
      // 줄인 뒤에도 9자면 불가
      expect(v(input(name: '가나다  라마바사아')), {ProfileError.nameTooLong});
    });
    test('정리본 이름은 가운데 공백이 하나로 줄어 있다', () {
      expect(input(name: '  길   동  ').normalized().name, '길 동');
      expect(input(name: '길\t동').normalized().name, '길 동');
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
