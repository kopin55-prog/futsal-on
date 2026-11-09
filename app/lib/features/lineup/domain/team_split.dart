import 'dart:math';

import '../../../shared/domain/position.dart';
import '../../admin/domain/pairing_rules.dart';
import '../../admin/domain/skill_level.dart';
import 'lineup_models.dart';
import 'skill_score.dart';

/// 팀 나누기 계산 (스프린트 03 2-1~2-3, 기획서 9장, Q-075).
///
/// 순수 함수(서버·화면 없음). 운영진 기기에서 계산한다: 입력(실력 등급·선호 포지션·전문 GK·그룹/라이벌·
/// 게스트 포지션·실력)은 모두 관리자만 읽는 정보라 공개 범위가 넓어지지 않는다.
/// 결과 [TeamSplitPlan] 에는 사람과 경고만 있고 실력 등급·점수는 없다 (Q-075 5번).
///
/// 우선순위 (앞이 항상 이긴다):
///   1. 전문 GK 를 팀마다 고르게 (팀보다 많으면 한 팀에 2명 + 경고)
///   2. 그룹은 같은 팀 (켜진 그룹, 온 사람끼리. 다 못 넣으면 최대한 + 경고)
///   3. 라이벌은 다른 팀 (못 나누면 경고)
///   4. 선호 포지션 고르게: 포지션마다 팀별 인원 차이 1 이하를 목표 (일반 선호 포지션 골키퍼는 여기에만)
///   5. 실력 합계 고르게 (점수는 [SkillScore], 미정은 아마추어로 계산)
///   6. 미정 인원 고르게
/// 게스트는 그룹·라이벌·전문 GK 대상이 아니다 (실력·포지션 계산에는 들어감).
///
/// 남는 사람 (Q-075 4번): 참석을 가장 늦게 누른 사람부터 교체 블록 (게스트는 참석자보다 늦은 것으로 봄,
/// 전문 GK 는 제외). 모자라면 팀마다 고르게 나누고 "N명 모자라요" 경고.
///
/// 같은 입력이면 같은 첫 배치 (고정 시드). 재조합은 [TeamSplitShuffler].

/// 계산 대상 한 사람.
class SplitCandidate {
  const SplitCandidate({
    required this.person,
    required this.skill,
    required this.positions,
    required this.attendedAt,
    this.isDedicatedGk = false,
  });

  final LineupPerson person;
  final SkillLevel skill;

  /// 선호 포지션 (게스트는 비어 있을 수 있음).
  final Set<Position> positions;

  /// 전문 골키퍼. 게스트는 계산에서 항상 아님으로 본다.
  final bool isDedicatedGk;

  /// 남는 사람 고르기 기준. 팀원: 참석을 누른(마지막으로 바꾼) 시각, 게스트: 추가한 시각.
  final DateTime attendedAt;

  bool get countsAsDedicatedGk => isDedicatedGk && !person.isGuest;
}

class TeamSplitInput {
  const TeamSplitInput({
    required this.candidates,
    required this.teamCount,
    required this.playersPerTeam,
    this.rules = const [],
  });

  final List<SplitCandidate> candidates;

  /// 그룹·라이벌 설정 (꺼진 설정은 무시).
  final List<PairingRule> rules;
  final int teamCount;
  final int playersPerTeam;
}

/// 배치 경고 (사람 이름·등급 없음, 2-2).
enum SplitWarningKind { dedicatedGkOverTeams, groupSplit, rivalSameTeam, benchRemaining, playersShort }

class SplitWarning {
  const SplitWarning(this.kind, [this.count = 0]);

  final SplitWarningKind kind;

  /// 교체 N명 / N명 모자람의 N. 그 밖에는 0.
  final int count;

  /// 서버에 저장하는 종류 (필수 조건 3가지만).
  LineupWarningKind? get stored => switch (kind) {
    SplitWarningKind.dedicatedGkOverTeams => LineupWarningKind.dedicatedGkOverTeams,
    SplitWarningKind.groupSplit => LineupWarningKind.groupSplit,
    SplitWarningKind.rivalSameTeam => LineupWarningKind.rivalSameTeam,
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is SplitWarning && other.kind == kind && other.count == count;

  @override
  int get hashCode => Object.hash(kind, count);

  @override
  String toString() => count == 0 ? kind.name : '${kind.name}($count)';
}

/// 계산 결과: 팀 블록별 명단 + 교체 블록 + 경고. 실력·점수는 담지 않는다.
class TeamSplitPlan {
  const TeamSplitPlan({required this.squads, required this.bench, required this.warnings});

  /// 팀 블록 순서대로 (조끼 색은 이 순서로 자동 배정).
  final List<List<LineupPerson>> squads;
  final List<LineupPerson> bench;
  final Set<SplitWarning> warnings;

  Set<LineupWarningKind> get storedWarnings => {for (final w in warnings) ?w.stored};

  /// 같은 배치인지 비교하는 값 (팀 순서·팀 안 순서와 무관).
  String get signature {
    final teams = [
      for (final s in squads) ([for (final p in s) p.key]..sort()).join(','),
    ]..sort();
    return '${teams.join('|')}#${([for (final p in bench) p.key]..sort()).join(',')}';
  }
}

/// 재조합 (2-3, Q-075 7번 (2)): 같은 입력에서 다음으로 좋은 배치를 차례로 돌려준다.
/// 같은 배치는 연달아 나오지 않는다(후보가 하나뿐일 때만 예외). 후보를 다 보면 처음 배치로 돌아가고
/// [wrapped] 가 참이 된다 → 화면이 "모든 조합을 봤어요" 안내.
class TeamSplitShuffler {
  TeamSplitShuffler(TeamSplitInput input) : plans = TeamSplitter.plans(input);

  /// 좋은 순서. 필수 조건(GK·그룹·라이벌)을 지키는 정도가 첫 배치와 같은 것만 들어 있다.
  final List<TeamSplitPlan> plans;
  int _index = 0;
  bool _wrapped = false;

  TeamSplitPlan get current => plans[_index];

  /// 마지막 [next] 가 처음 배치로 돌아왔는지.
  bool get wrapped => _wrapped;

  TeamSplitPlan next() {
    _index++;
    _wrapped = _index >= plans.length;
    if (_wrapped) _index = 0;
    return current;
  }
}

abstract final class TeamSplitter {
  /// 무작위 시작 횟수. 많을수록 좋은 배치를 찾을 가능성이 높고 느려진다.
  static const int restarts = 24;

  /// 재조합 후보 최대 개수.
  static const int poolLimit = 30;

  /// 첫 배치.
  static TeamSplitPlan split(TeamSplitInput input) => plans(input).first;

  /// 좋은 순서의 배치 후보 (1개 이상).
  static List<TeamSplitPlan> plans(TeamSplitInput input) => _Solver(input).solve();

  /// 직접 옮긴 배치 등 주어진 배치의 경고 (3단계 화면용). [squads] 는 팀 블록별 명단.
  static Set<SplitWarning> evaluateWarnings(
    TeamSplitInput input,
    List<List<LineupPerson>> squads,
    List<LineupPerson> bench,
  ) {
    final byPerson = {for (final c in input.candidates) c.person: c};
    final teamOf = <String, int>{};
    for (var t = 0; t < squads.length; t++) {
      for (final p in squads[t]) {
        teamOf[p.key] = t;
      }
    }
    final placed = squads.fold<int>(0, (n, s) => n + s.length);
    final warnings = <SplitWarning>{};
    final gkPerTeam = List.filled(squads.length, 0);
    for (var t = 0; t < squads.length; t++) {
      for (final p in squads[t]) {
        if (byPerson[p]?.countsAsDedicatedGk ?? false) gkPerTeam[t]++;
      }
    }
    if (gkPerTeam.any((n) => n >= 2)) warnings.add(const SplitWarning(SplitWarningKind.dedicatedGkOverTeams));
    for (final group in _groupComponents(input.rules)) {
      final teams = {for (final u in group) ?teamOf['u:$u']};
      if (teams.length > 1) {
        warnings.add(const SplitWarning(SplitWarningKind.groupSplit));
        break;
      }
    }
    if (_rivalPairsSameTeam(input.rules, (u) => teamOf['u:$u']) > 0) {
      warnings.add(const SplitWarning(SplitWarningKind.rivalSameTeam));
    }
    if (bench.isNotEmpty) warnings.add(SplitWarning(SplitWarningKind.benchRemaining, bench.length));
    final short = squads.length * input.playersPerTeam - placed;
    if (short > 0) warnings.add(SplitWarning(SplitWarningKind.playersShort, short));
    return warnings;
  }

  /// 켜진 그룹을 이어서(한 사람이 두 그룹에 있으면 합침) 만든 묶음 (팀원 ID).
  static List<List<String>> _groupComponents(List<PairingRule> rules) {
    final parent = <String, String>{};
    String find(String x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    for (final r in rules.where((r) => r.enabled && r.kind == PairingKind.group)) {
      for (final u in r.userIds) {
        parent.putIfAbsent(u, () => u);
      }
      for (var i = 1; i < r.userIds.length; i++) {
        final a = find(r.userIds[0]);
        final b = find(r.userIds[i]);
        if (a != b) parent[a] = b;
      }
    }
    final groups = <String, List<String>>{};
    for (final u in parent.keys) {
      groups.putIfAbsent(find(u), () => []).add(u);
    }
    return [for (final g in groups.values) g..sort()]..sort((a, b) => a.first.compareTo(b.first));
  }

  static int _rivalPairsSameTeam(List<PairingRule> rules, int? Function(String userId) teamOf) {
    var n = 0;
    for (final r in rules.where((r) => r.enabled && r.kind == PairingKind.rival)) {
      final ids = r.userIds.toSet().toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = teamOf(ids[i]);
          if (a != null && a == teamOf(ids[j])) n++;
        }
      }
    }
    return n;
  }
}

/// 비용: 앞 칸부터 비교 (작을수록 좋음). 0~2 칸 = 필수 조건.
typedef _Cost = List<int>;

int _compareCost(_Cost a, _Cost b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

bool _sameHard(_Cost a, _Cost b) => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

class _Solver {
  _Solver(this.input);

  final TeamSplitInput input;

  late final int teams = input.teamCount;
  late final List<SplitCandidate> players; // 팀 블록에 들어갈 사람 (키 순)
  late final List<LineupPerson> bench;
  late final List<int> sizes; // 팀별 인원

  // 사람별 계산 재료 (players 순서)
  late final List<bool> isGk;
  late final List<int> score;
  late final List<bool> undecided;
  late final List<int> posMask; // 비트 = Position.index
  late final List<List<int>> groups; // players 인덱스 묶음 (2명 이상 온 그룹만)
  late final List<List<int>> rivalPairs; // players 인덱스 쌍

  // _cost 계산용 버퍼
  late final List<int> _gk = List.filled(teams, 0);
  late final List<int> _skill = List.filled(teams, 0);
  late final List<int> _und = List.filled(teams, 0);
  late final List<int> _count = List.filled(teams, 0);
  late final List<List<int>> _pos = List.generate(Position.values.length, (_) => List.filled(teams, 0));

  List<TeamSplitPlan> solve() {
    _prepare();
    final rng = Random(_seed());
    final found = <String, (_Cost, List<int>)>{};

    void keep(List<int> assign) {
      final plan = _signature(assign);
      found.putIfAbsent(plan, () => (_cost(assign), List.of(assign)));
    }

    final n = players.length;
    for (var r = 0; r < TeamSplitter.restarts; r++) {
      final assign = _randomStart(rng);
      _localSearch(assign, rng);
      keep(assign);
      if (n == 0) break;
    }

    // 후보가 적으면 좋은 배치의 이웃(한 쌍 바꾸기)도 넣어 재조합 거리를 만든다.
    final seeds = found.values.toList()..sort((a, b) => _compareCost(a.$1, b.$1));
    final bestHard = seeds.first.$1;
    for (final (_, assign) in seeds.take(5)) {
      if (found.length >= TeamSplitter.poolLimit * 2) break;
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          if (assign[i] == assign[j]) continue;
          final next = List.of(assign);
          next[i] = assign[j];
          next[j] = assign[i];
          if (_sameHard(_cost(next), bestHard)) keep(next);
        }
      }
    }

    final ordered = found.entries.toList()
      ..sort((a, b) {
        final c = _compareCost(a.value.$1, b.value.$1);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final best = ordered.first.value.$1;
    return [
      for (final e in ordered.where((e) => _sameHard(e.value.$1, best)).take(TeamSplitter.poolLimit))
        _toPlan(e.value.$2),
    ];
  }

  // ---------------------------------------------------------------------------
  // 준비: 남는 사람 고르기, 팀별 인원, 계산 재료
  // ---------------------------------------------------------------------------
  void _prepare() {
    final all = [...input.candidates]..sort((a, b) => a.person.compareTo(b.person));
    final capacity = teams * input.playersPerTeam;
    final benchCount = max(0, all.length - capacity);

    // 늦게 온 순서: 게스트(늦게 추가한 순) → 팀원(늦게 누른 순). 전문 GK 는 맨 마지막.
    int lateFirst(SplitCandidate a, SplitCandidate b) {
      if (a.person.isGuest != b.person.isGuest) return a.person.isGuest ? -1 : 1;
      final t = b.attendedAt.compareTo(a.attendedAt);
      return t != 0 ? t : b.person.compareTo(a.person);
    }

    final benchOrder = [
      ...all.where((c) => !c.countsAsDedicatedGk).toList()..sort(lateFirst),
      ...all.where((c) => c.countsAsDedicatedGk).toList()..sort(lateFirst),
    ];
    final benched = benchOrder.take(benchCount).map((c) => c.person).toSet();
    bench = [for (final c in benchOrder.take(benchCount)) c.person];
    players = [for (final c in all) if (!benched.contains(c.person)) c];

    final base = players.length ~/ teams;
    final extra = players.length % teams;
    sizes = [for (var t = 0; t < teams; t++) base + (t < extra ? 1 : 0)];

    isGk = [for (final c in players) c.countsAsDedicatedGk];
    score = [for (final c in players) SkillScore.of(c.skill)];
    undecided = [for (final c in players) c.skill == SkillLevel.undecided];
    posMask = [
      for (final c in players) c.positions.fold(0, (m, p) => m | (1 << p.index)),
    ];

    final indexOfUser = <String, int>{
      for (var i = 0; i < players.length; i++)
        if (!players[i].person.isGuest) players[i].person.userId!: i,
    };
    groups = [
      for (final g in TeamSplitter._groupComponents(input.rules))
        [for (final u in g) ?indexOfUser[u]],
    ].where((g) => g.length >= 2).toList();
    final pairs = <List<int>>[];
    for (final r in input.rules.where((r) => r.enabled && r.kind == PairingKind.rival)) {
      final ids = [for (final u in r.userIds.toSet()) ?indexOfUser[u]]..sort();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          pairs.add([ids[i], ids[j]]);
        }
      }
    }
    rivalPairs = pairs;
  }

  /// 같은 입력 → 같은 시드 (입력 순서와 무관).
  int _seed() {
    var h = 17;
    for (final c in players) {
      for (final unit in c.person.key.codeUnits) {
        h = (h * 31 + unit) & 0x3fffffff;
      }
    }
    return (h ^ (teams * 7919) ^ input.playersPerTeam) & 0x3fffffff;
  }

  // ---------------------------------------------------------------------------
  // 비용
  // ---------------------------------------------------------------------------
  _Cost _cost(List<int> assign) {
    final n = players.length;
    // 계산마다 새로 만들지 않고 다시 쓴다 (탐색 중 수십만 번 불림)
    final gk = _gk..fillRange(0, teams, 0);
    final skill = _skill..fillRange(0, teams, 0);
    final und = _und..fillRange(0, teams, 0);
    final pos = _pos;
    for (final row in pos) {
      row.fillRange(0, teams, 0);
    }
    for (var i = 0; i < n; i++) {
      final t = assign[i];
      if (isGk[i]) gk[t]++;
      skill[t] += score[i];
      if (undecided[i]) und[t]++;
      final m = posMask[i];
      if (m != 0) {
        for (var p = 0; p < pos.length; p++) {
          if (m & (1 << p) != 0) pos[p][t]++;
        }
      }
    }

    // 1. 전문 GK: 팀별 인원 제곱 합 (고르게 나뉠수록 작음)
    var cGk = 0;
    for (final g in gk) {
      cGk += g * g;
    }

    // 2. 그룹: 가장 많이 모인 팀 밖에 있는 인원
    var cGroup = 0;
    final count = _count;
    for (final g in groups) {
      count.fillRange(0, teams, 0);
      var most = 0;
      for (final i in g) {
        most = max(most, ++count[assign[i]]);
      }
      cGroup += g.length - most;
    }

    // 3. 라이벌: 같은 팀에 있는 쌍
    var cRival = 0;
    for (final p in rivalPairs) {
      if (assign[p[0]] == assign[p[1]]) cRival++;
    }

    // 4. 포지션: 포지션마다 (팀별 최대 - 최소 - 1) 의 양수 부분 합. 차이 1 이하면 고른 것으로 본다.
    var cPos = 0;
    for (final row in pos) {
      var lo = row[0], hi = row[0];
      for (final v in row) {
        lo = min(lo, v);
        hi = max(hi, v);
      }
      cPos += max(0, hi - lo - 1);
    }

    return [cGk, cGroup, cRival, cPos, _spread(skill), _spread(und)];
  }

  /// 팀별 값이 고른 정도 (분산 × 팀 수², 정수).
  int _spread(List<int> values) {
    var sum = 0, sq = 0;
    for (final v in values) {
      sum += v;
      sq += v * v;
    }
    return teams * sq - sum * sum;
  }

  // ---------------------------------------------------------------------------
  // 탐색: 무작위 시작 + 한 쌍 바꾸기 / 인원 많은 팀 → 적은 팀 옮기기
  // ---------------------------------------------------------------------------
  List<int> _randomStart(Random rng) {
    final order = List.generate(players.length, (i) => i)..shuffle(rng);
    final assign = List.filled(players.length, 0);
    var k = 0;
    for (var t = 0; t < teams; t++) {
      for (var s = 0; s < sizes[t]; s++) {
        assign[order[k++]] = t;
      }
    }
    return assign;
  }

  void _localSearch(List<int> assign, Random rng) {
    final n = players.length;
    if (n < 2) return;
    var current = _cost(assign);
    final teamSize = List.filled(teams, 0);
    for (final t in assign) {
      teamSize[t]++;
    }
    final pairs = <int>[for (var i = 0; i < n; i++) for (var j = i + 1; j < n; j++) i * n + j];
    var improved = true;
    while (improved) {
      improved = false;
      pairs.shuffle(rng);
      for (final code in pairs) {
        final i = code ~/ n, j = code % n;
        final ti = assign[i], tj = assign[j];
        if (ti == tj) continue;
        // 한 쌍 바꾸기
        assign[i] = tj;
        assign[j] = ti;
        var next = _cost(assign);
        if (_compareCost(next, current) < 0) {
          current = next;
          improved = true;
          continue;
        }
        assign[i] = ti;
        assign[j] = tj;
        // 옮기기: 인원 차이가 1 인 두 팀 사이 (팀별 인원 구성은 그대로)
        for (final (a, from, to) in [(i, ti, tj), (j, tj, ti)]) {
          if (teamSize[from] != teamSize[to] + 1) continue;
          assign[a] = to;
          next = _cost(assign);
          if (_compareCost(next, current) < 0) {
            current = next;
            teamSize[from]--;
            teamSize[to]++;
            improved = true;
            break;
          }
          assign[a] = from;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 결과
  // ---------------------------------------------------------------------------
  String _signature(List<int> assign) {
    final buckets = List.generate(teams, (_) => <String>[]);
    for (var i = 0; i < players.length; i++) {
      buckets[assign[i]].add(players[i].person.key);
    }
    return ([for (final b in buckets) (b..sort()).join(',')]..sort()).join('|');
  }

  TeamSplitPlan _toPlan(List<int> assign) {
    final buckets = List.generate(teams, (_) => <LineupPerson>[]);
    for (var i = 0; i < players.length; i++) {
      buckets[assign[i]].add(players[i].person);
    }
    for (final b in buckets) {
      b.sort();
    }
    // 팀 순서를 정해 같은 배치가 늘 같은 모양이 되게 (인원 많은 팀 먼저, 그다음 첫 사람 키)
    buckets.sort((a, b) {
      if (a.length != b.length) return b.length.compareTo(a.length);
      if (a.isEmpty) return 0;
      return a.first.compareTo(b.first);
    });
    // 모자란 인원 = 팀 수 × 팀당 인원 - 팀 블록 인원 (evaluateWarnings 가 셈)
    return TeamSplitPlan(
      squads: buckets,
      bench: List.unmodifiable(bench),
      warnings: TeamSplitter.evaluateWarnings(input, buckets, bench),
    );
  }
}
