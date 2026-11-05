import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/profile/domain/position_picker.dart';
import 'package:futsal_on/shared/domain/position.dart';

void main() {
  group('포지션 최대 3개 (Q-035, Q-067 1번)', () {
    test('3개까지 고를 수 있다', () {
      final p = PositionPicker();
      expect(p.toggle(Position.defender), isNull);
      expect(p.toggle(Position.midfielder), isNull);
      expect(p.toggle(Position.forward), isNull);
      expect(p.positions.length, 3);
    });
    test('4번째는 선택되지 않고 안내', () {
      final p = PositionPicker(
        positions: [Position.defender, Position.midfielder, Position.forward],
      );
      expect(p.toggle(Position.winger), PositionPickHint.maxReached);
      expect(p.isSelected(Position.winger), isFalse);
      expect(p.positions.length, 3);
    });
    test('하나 빼면 다시 고를 수 있다', () {
      final p = PositionPicker(
        positions: [Position.defender, Position.midfielder, Position.forward],
      );
      p.toggle(Position.forward);
      expect(p.toggle(Position.winger), isNull);
      expect(p.isSelected(Position.winger), isTrue);
    });
    test('골키퍼도 3개 안에 포함', () {
      final p = PositionPicker(
        positions: [Position.goalkeeper, Position.midfielder, Position.forward],
      );
      expect(p.toggle(Position.winger), PositionPickHint.maxReached);
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
        positions: [Position.defender, Position.midfielder, Position.forward],
      );
      expect(p.setDedicatedGk(true), PositionPickHint.removeOneForGk);
      expect(p.isDedicatedGk, isFalse);
      expect(p.isSelected(Position.goalkeeper), isFalse);
    });
    test('골키퍼 포함 3개면 체크 가능', () {
      final p = PositionPicker(
        positions: [Position.goalkeeper, Position.midfielder, Position.forward],
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
}
