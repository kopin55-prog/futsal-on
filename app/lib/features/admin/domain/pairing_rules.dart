/// 그룹(항상 같은 팀)·라이벌(항상 다른 팀) 설정 (data-model.md 3-7, glossary).
enum PairingKind { group, rival }

class PairingRule {
  const PairingRule({
    required this.id,
    required this.kind,
    required this.enabled,
    required this.userIds,
  });

  /// 새로 만드는 중이면 null
  final String? id;
  final PairingKind kind;
  final bool enabled;
  final List<String> userIds;

  PairingRule copyWith({bool? enabled, List<String>? userIds}) => PairingRule(
    id: id,
    kind: kind,
    enabled: enabled ?? this.enabled,
    userIds: userIds ?? this.userIds,
  );
}

/// 켜진 그룹으로 이어진 두 사람이 켜진 라이벌에 함께 있음 (저장 불가).
class PairingConflict {
  const PairingConflict({required this.rivalRuleId, required this.userA, required this.userB});

  final String? rivalRuleId;
  final String userA;
  final String userB;

  @override
  bool operator ==(Object other) =>
      other is PairingConflict &&
      other.rivalRuleId == rivalRuleId &&
      other.userA == userA &&
      other.userB == userB;

  @override
  int get hashCode => Object.hash(rivalRuleId, userA, userB);

  @override
  String toString() => 'PairingConflict($rivalRuleId, $userA, $userB)';
}

/// 그룹·라이벌 저장 규칙. 서버(private.pairing_rules_consistent, save_pairing_rule)가 같은 규칙으로 다시 검사하고,
/// 이 클래스는 저장 전에 화면에서 이유를 알려주는 데 쓴다.
abstract final class PairingRules {
  /// 한 설정에 묶을 최소 인원.
  static const int minMembers = 2;

  /// 사람 수가 맞는지 (2명 이상, 중복 없음).
  static bool membersValid(List<String> userIds) =>
      userIds.length >= minMembers && userIds.toSet().length == userIds.length;

  /// [rules] 중 켜진 설정끼리의 모순. 켜진 그룹을 이어서(간접 포함) 같은 묶음이 된 두 사람이
  /// 켜진 라이벌에 함께 들어 있으면 모순이다. 같은 라이벌 안의 두 사람마다 한 건씩 돌려준다.
  static List<PairingConflict> findConflicts(Iterable<PairingRule> rules) {
    final parent = <String, String>{};
    String find(String x) {
      var root = x;
      while (parent[root] != null && parent[root] != root) {
        root = parent[root]!;
      }
      // 경로 압축
      var cur = x;
      while (parent[cur] != null && parent[cur] != root) {
        final next = parent[cur]!;
        parent[cur] = root;
        cur = next;
      }
      return root;
    }

    void union(String a, String b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    final enabled = rules.where((r) => r.enabled).toList();
    for (final r in enabled.where((r) => r.kind == PairingKind.group)) {
      for (final u in r.userIds) {
        parent.putIfAbsent(u, () => u);
      }
      for (var i = 1; i < r.userIds.length; i++) {
        union(r.userIds[0], r.userIds[i]);
      }
    }

    final conflicts = <PairingConflict>[];
    for (final r in enabled.where((r) => r.kind == PairingKind.rival)) {
      final ids = r.userIds.toSet().toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i];
          final b = ids[j];
          if (parent.containsKey(a) && parent.containsKey(b) && find(a) == find(b)) {
            conflicts.add(PairingConflict(rivalRuleId: r.id, userA: a, userB: b));
          }
        }
      }
    }
    return conflicts;
  }

  /// [current] 설정 목록에서 [changed] 를 저장(새로 만들기·고치기·켜기)했을 때의 모순.
  static List<PairingConflict> conflictsAfterSave(
    List<PairingRule> current,
    PairingRule changed,
  ) {
    final next = [
      for (final r in current)
        if (changed.id == null || r.id != changed.id) r,
      changed,
    ];
    return findConflicts(next);
  }
}
