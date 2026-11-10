import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/injury/domain/injury_models.dart';

void main() {
  group('남은 회복 기간 W (S4-04 올림)', () {
    final today = DateTime(2026, 11, 10);
    int w(int days) => Injury.remainingWeeksBetween(today, today.add(Duration(days: days)));

    test('1~7일 = 1W, 8~14일 = 2W', () {
      expect(w(1), 1);
      expect(w(3), 1);
      expect(w(7), 1);
      expect(w(8), 2);
      expect(w(10), 2);
      expect(w(14), 2);
      expect(w(15), 3);
    });
    test('복귀일 당일·지남 = 0W (마이너스 없음)', () {
      expect(w(0), 0);
      expect(w(-5), 0);
    });
    test('표 한 줄 읽기', () {
      final i = Injury.fromRow({
        'id': 'i1',
        'user_id': 'u1',
        'started_on': '2026-11-10',
        'expected_return_on': '2026-11-20',
        'memo': '발목',
        'status': 'active',
        'recovered_at': null,
      });
      expect(i.isActive, isTrue);
      expect(i.memo, '발목');
      expect(i.remainingWeeks(today), 2);
    });
  });

  group('메모 정리·검사 (11장 14번, 2-2)', () {
    test('보이지 않는 문자·앞뒤 공백 정리, 비면 없음', () {
      expect(InjuryRules.normalizeMemo('  발목​ '), '발목');
      expect(InjuryRules.normalizeMemo('​ ㅤ'), isNull);
      expect(InjuryRules.normalizeMemo(null), isNull);
      expect(InjuryRules.validateMemo('   '), isNull);
    });
    test('20자까지, 이모지 1개 = 1자, 줄바꿈 불가', () {
      expect(InjuryRules.validateMemo('가' * 20), isNull);
      expect(InjuryRules.validateMemo('가' * 21), InjuryMemoError.tooLong);
      expect(InjuryRules.validateMemo('${'가' * 19}👨‍👩‍👧'), isNull);
      expect(InjuryRules.validateMemo('발목\n인대'), InjuryMemoError.lineBreak);
    });
  });
}
