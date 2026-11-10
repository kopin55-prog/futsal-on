import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/profile/domain/position_picker.dart';
import 'package:futsal_on/shared/domain/position.dart';

void main() {
  group('포지션 최대 3개 (Q-035, Q-067 1번)', () {
    test('3개까지 고를 수 있다', () {
      final p = PositionPicker();
      expect(p.toggle(Position.defender), isNull);
      expect(p.toggle(Position.winger), isNull);
      expect(p.toggle(Position.forward), isNull);
      expect(p.positions.length, 3);
    });
    test('4번째는 선택되지 않고 안내', () {
      final p = PositionPicker(
        positions: [Position.defender, Position.winger, Position.forward],
      );
      expect(p.toggle(Position.goalkeeper), PositionPickHint.maxReached);
      expect(p.isSelected(Position.goalkeeper), isFalse);
      expect(p.positions.length, 3);
    });
    test('하나 빼면 다시 고를 수 있다', () {
      final p = PositionPicker(
        positions: [Position.defender, Position.winger, Position.forward],
      );
      p.toggle(Position.forward);
      expect(p.toggle(Position.goalkeeper), isNull);
      expect(p.isSelected(Position.goalkeeper), isTrue);
    });
    test('골키퍼도 3개 안에 포함', () {
      final p = PositionPicker(
        positions: [Position.goalkeeper, Position.winger, Position.forward],
      );
      expect(p.toggle(Position.defender), PositionPickHint.maxReached);
    });
  });

  group('전문 골키퍼 (Q-019, Q-035, Q-067 16번)', () {
    test('체크하면 골키퍼 자동 선택', () {
      final p = PositionPicker(positions: [Position.forward]);
      expect(p.setDedicatedGk(true), isNull);
      expect(p.isDedicatedGk, isTrue);
      expect(p.positions, [Position.forward, Position.goalkeeper]);
    });
    test('이미 골키퍼가 있으면 그대로', () {
      final p = PositionPicker(positions: [Position.goalkeeper]);
      p.setDedicatedGk(true);
      expect(p.positions, [Position.goalkeeper]);
    });
    test('골키퍼 아닌 3개면 막고 "하나 빼주세요"', () {
      final p = PositionPicker(
        positions: [Position.defender, Position.winger, Position.forward],
      );
      expect(p.setDedicatedGk(true), PositionPickHint.removeOneForGk);
      expect(p.isDedicatedGk, isFalse);
      expect(p.isSelected(Position.goalkeeper), isFalse);
    });
    test('골키퍼 포함 3개면 체크 가능', () {
      final p = PositionPicker(
        positions: [Position.goalkeeper, Position.winger, Position.forward],
      );
      expect(p.setDedicatedGk(true), isNull);
    });
    test('체크된 동안 골키퍼는 해제할 수 없음', () {
      final p = PositionPicker()..setDedicatedGk(true);
      expect(p.isLocked(Position.goalkeeper), isTrue);
      expect(p.isLocked(Position.forward), isFalse);
      p.toggle(Position.goalkeeper);
      expect(p.isSelected(Position.goalkeeper), isTrue);
    });
    test('체크를 풀면 골키퍼 선택은 남고, 그 뒤 직접 해제 가능', () {
      final p = PositionPicker()..setDedicatedGk(true);
      p.setDedicatedGk(false);
      expect(p.isDedicatedGk, isFalse);
      expect(p.isSelected(Position.goalkeeper), isTrue);
      expect(p.isLocked(Position.goalkeeper), isFalse);
      p.toggle(Position.goalkeeper);
      expect(p.isSelected(Position.goalkeeper), isFalse);
    });
  });

  group('올라운더 단독 (v4.6, decisions 2026-11-10)', () {
    test('올라운더만 고를 수 있다', () {
      final p = PositionPicker();
      expect(p.toggle(Position.allrounder), isNull);
      expect(p.positions, [Position.allrounder]);
    });
    test('올라운더를 고른 상태에서 다른 포지션은 막고 안내', () {
      final p = PositionPicker(positions: [Position.allrounder]);
      for (final other in Position.values.where((x) => x != Position.allrounder)) {
        expect(p.toggle(other), PositionPickHint.allrounderSelected);
      }
      expect(p.positions, [Position.allrounder]);
    });
    test('다른 포지션을 고른 상태에서 올라운더는 막고 안내', () {
      final p = PositionPicker(positions: [Position.forward]);
      expect(p.toggle(Position.allrounder), PositionPickHint.allrounderNeedsEmpty);
      expect(p.isSelected(Position.allrounder), isFalse);
    });
    test('올라운더를 빼면 다른 포지션을 고를 수 있다', () {
      final p = PositionPicker(positions: [Position.allrounder]);
      expect(p.toggle(Position.allrounder), isNull);
      expect(p.toggle(Position.defender), isNull);
      expect(p.positions, [Position.defender]);
    });
    test('올라운더 상태에서 전문 골키퍼 체크는 막고 안내, 골키퍼 자동 선택 없음', () {
      final p = PositionPicker(positions: [Position.allrounder]);
      expect(p.setDedicatedGk(true), PositionPickHint.allrounderNoGk);
      expect(p.isDedicatedGk, isFalse);
      expect(p.positions, [Position.allrounder]);
    });
    test('전문 골키퍼 상태(골키퍼 잠김)에서 올라운더는 막힘', () {
      final p = PositionPicker()..setDedicatedGk(true);
      expect(p.toggle(Position.allrounder), PositionPickHint.allrounderNeedsEmpty);
      expect(p.positions, [Position.goalkeeper]);
    });
  });
}
