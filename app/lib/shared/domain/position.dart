/// 선호 포지션 (data-model.md v4.6 2-3·4-3). 화면 이름은 ProfileTexts.position.
///
/// 선택지: 골키퍼·수비·측면·공격·올라운더 ("중앙"은 2026-11-10 폐지, kopn 지시).
/// 서버 enum 값과 이름이 같다 (`Position.values.byName`). 화면에 보이는 순서도 이 순서다.
enum Position {
  /// 골키퍼
  goalkeeper,

  /// 수비
  defender,

  /// 측면
  winger,

  /// 공격
  forward,

  /// 올라운더: 단독 선택 (다른 포지션과 함께 고를 수 없음). 팀 나누기에서는 모든 포지션 가능으로 본다.
  allrounder,
}

/// 포지션 고르기 공통 규칙 (프로필·게스트 공통, 서버 검사와 같은 규칙).
abstract final class PositionRules {
  /// 최대 개수 (골키퍼 포함, Q-035). 게스트도 같다.
  static const int maxPositions = 3;

  /// 올라운더가 들어 있으면 그것 하나뿐인지 (v4.6 "올라운더는 단독").
  static bool allrounderAlone(Iterable<Position> positions) {
    final list = positions.toList();
    return !list.contains(Position.allrounder) || list.length == 1;
  }

  /// 지금 [selected] 상태에서 [p] 를 더할 수 없는 이유. 더할 수 있으면 null.
  static PositionAddBlock? addBlock(List<Position> selected, Position p) {
    if (selected.contains(p)) return null;
    if (p == Position.allrounder && selected.isNotEmpty) return PositionAddBlock.allrounderNeedsEmpty;
    if (selected.contains(Position.allrounder)) return PositionAddBlock.allrounderSelected;
    if (selected.length >= maxPositions) return PositionAddBlock.maxReached;
    return null;
  }
}

/// 포지션을 더할 수 없는 이유.
enum PositionAddBlock {
  /// 이미 3개 (Q-067 1번)
  maxReached,

  /// 다른 포지션을 고른 상태에서 올라운더를 누름 → 다른 포지션을 먼저 빼야 함
  allrounderNeedsEmpty,

  /// 올라운더를 고른 상태에서 다른 포지션을 누름
  allrounderSelected,
}
