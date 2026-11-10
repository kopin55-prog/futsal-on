import '../../../shared/domain/position.dart';
import 'profile_validation.dart';

/// 선호 포지션·전문 골키퍼 고르기 규칙 (프로필 만들기·수정 공통).
///
/// - 골키퍼 포함 최대 3개. 4번째를 누르면 선택되지 않고 안내 (Q-035, Q-067 1번).
/// - 올라운더는 단독 (v4.6): 다른 포지션을 고른 상태에서 올라운더를 누르거나, 올라운더를 고른 상태에서
///   다른 포지션을 누르면 선택되지 않고 안내.
/// - 전문 골키퍼 체크: 골키퍼 자동 선택, 체크된 동안 골키퍼는 해제할 수 없음 (Q-019, Q-067 16번).
///   골키퍼 아닌 포지션 3개를 고른 상태면 체크를 막고 "포지션을 하나 빼주세요" (Q-035).
///   올라운더를 고른 상태면 체크를 막고 안내 (전문 GK 는 골키퍼가 필요, decisions 2026-11-10 lead 정리).
/// - 전문 골키퍼 체크를 풀면 골키퍼 선택은 그대로 남는다 (본인이 따로 해제, Q-067 16번).
enum PositionPickHint {
  /// 4번째 포지션을 누름 (Q-067 1번)
  maxReached,

  /// 골키퍼 아닌 3개 상태에서 전문 골키퍼 체크 (Q-035)
  removeOneForGk,

  /// 다른 포지션을 고른 상태에서 올라운더를 누름
  allrounderNeedsEmpty,

  /// 올라운더를 고른 상태에서 다른 포지션을 누름
  allrounderSelected,

  /// 올라운더를 고른 상태에서 전문 골키퍼 체크
  allrounderNoGk,
}

class PositionPicker {
  PositionPicker({Iterable<Position> positions = const [], this.isDedicatedGk = false})
    : _positions = [...positions];

  final List<Position> _positions;
  bool isDedicatedGk;

  List<Position> get positions => List.unmodifiable(_positions);

  bool isSelected(Position p) => _positions.contains(p);

  /// 이 칩을 지금 누를 수 있는지. 전문 골키퍼면 골키퍼 칩은 잠긴다.
  bool isLocked(Position p) => isDedicatedGk && p == Position.goalkeeper;

  /// 칩을 눌렀을 때. 막히면 안내를 돌려준다.
  PositionPickHint? toggle(Position p) {
    if (_positions.contains(p)) {
      if (isLocked(p)) return null;
      _positions.remove(p);
      return null;
    }
    final block = PositionRules.addBlock(_positions, p);
    if (block != null) {
      return switch (block) {
        PositionAddBlock.maxReached => PositionPickHint.maxReached,
        PositionAddBlock.allrounderNeedsEmpty => PositionPickHint.allrounderNeedsEmpty,
        PositionAddBlock.allrounderSelected => PositionPickHint.allrounderSelected,
      };
    }
    _positions.add(p);
    return null;
  }

  /// 전문 골키퍼 체크·해제. 막히면 안내를 돌려준다.
  PositionPickHint? setDedicatedGk(bool value) {
    if (!value) {
      isDedicatedGk = false;
      return null;
    }
    if (_positions.contains(Position.allrounder)) {
      return PositionPickHint.allrounderNoGk;
    }
    if (!ProfileValidator.canCheckDedicatedGk(_positions)) {
      return PositionPickHint.removeOneForGk;
    }
    if (!_positions.contains(Position.goalkeeper)) {
      _positions.add(Position.goalkeeper);
    }
    isDedicatedGk = true;
    return null;
  }
}
