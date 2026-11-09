import '../../admin/domain/pairing_rules.dart';
import '../../admin/domain/skill_level.dart';
import '../../schedule/domain/attendance_models.dart';
import '../../schedule/domain/guest_models.dart';
import '../../schedule/domain/match_models.dart';
import '../../team/domain/team_models.dart';
import 'bib_color.dart';
import 'lineup_models.dart';
import 'team_split.dart';

/// 배치를 만들거나 고칠 수 있는 시점 (Q-075 1번: 참석 마감 뒤 ~ 경기 종료 전, 취소된 일정 불가).
/// 권한(누가)이 아니라 시점(언제)이라 entitlements 가 아닌 여기서 판단한다. 서버가 같은 규칙으로 다시 거절한다.
enum LineupWindow {
  /// 참석 마감 전
  beforeDeadline,

  /// 만들기·확정·고치기 가능
  open,

  /// 경기 종료 뒤 (Q-061 3번)
  ended,

  /// 취소된 일정
  cancelled;

  static LineupWindow of(TeamMatch m, DateTime now) {
    if (m.isCancelled) return LineupWindow.cancelled;
    if (!now.isBefore(m.endsAt)) return LineupWindow.ended;
    if (now.isBefore(m.rsvpDeadlineAt)) return LineupWindow.beforeDeadline;
    return LineupWindow.open;
  }
}

/// 팀 수·팀당 인원 범위 (서버 save_lineup 과 같음, decisions 2026-11-09 lead 정리).
abstract final class LineupLimits {
  static const minTeams = 2;
  static final maxTeams = BibColor.values.length; // 11
  static const minPlayers = 1;
  static const maxPlayers = 50;

  /// 처음 값 (Q-075 7번 (4)): 지난 경기에 쓴 값, 없으면 2팀 · 인원÷2 (올림).
  /// [poolCount] = 자동으로 배치에 들어가는 인원 (참석자 + 게스트).
  static ({int teams, int players}) defaults({({int teams, int players})? last, required int poolCount}) {
    if (last != null) {
      return (
        teams: last.teams.clamp(minTeams, maxTeams),
        players: last.players.clamp(minPlayers, maxPlayers),
      );
    }
    return (teams: minTeams, players: ((poolCount + 1) ~/ 2).clamp(minPlayers, maxPlayers));
  }
}

/// 배치 계산 재료: 이 일정에 배치할 수 있는 사람 전부와 계산용 정보 (운영진 기기 안에서만 씀).
///
/// - 자동으로 들어가는 사람 [autoPeople] = 참석자 + 게스트.
/// - 운영진이 [팀원 추가]로 넣을 수 있는 사람 = 그 밖의 현재 팀원 (대기·불참·미투표, Q-075 2번).
/// 실력 등급·포지션·전문 GK 는 계산에만 쓰고 화면에 내보내지 않는다.
class LineupPool {
  LineupPool._(this.candidates, this.autoPeople, this.rules, this.states);

  /// 사람별 계산 정보 (현재 팀원 전원 + 게스트).
  final Map<LineupPerson, SplitCandidate> candidates;

  /// 참석자 + 게스트.
  final Set<LineupPerson> autoPeople;

  /// 그룹·라이벌 설정.
  final List<PairingRule> rules;

  /// 팀원의 참석 응답 상태 (없으면 미투표). [팀원 추가] 목록 표시용.
  final Map<String, AttendanceState?> states;

  static LineupPool build({
    required List<MemberEntry> members,
    required List<AttendanceResponse> responses,
    required List<MatchGuestDetail> guests,
    required Map<String, SkillLevel> skills,
    required Map<String, PlayPrefs> prefs,
    required List<PairingRule> rules,
  }) {
    final byUser = {for (final r in responses) r.userId: r};
    final candidates = <LineupPerson, SplitCandidate>{};
    final auto = <LineupPerson>{};
    final states = <String, AttendanceState?>{};
    final epoch = DateTime.utc(2000);
    for (final m in members) {
      final person = LineupPerson.member(m.userId);
      final r = byUser[m.userId];
      final p = prefs[m.userId];
      states[m.userId] = r?.state;
      candidates[person] = SplitCandidate(
        person: person,
        skill: skills[m.userId] ?? SkillLevel.undecided,
        positions: {...?p?.positions},
        isDedicatedGk: p?.isDedicatedGk ?? false,
        attendedAt: r?.updatedAt ?? epoch,
      );
      if (r?.state == AttendanceState.attending) auto.add(person);
    }
    for (final g in guests) {
      final person = LineupPerson.guest(g.id);
      candidates[person] = SplitCandidate(
        person: person,
        skill: g.skillLevel,
        positions: g.positions.toSet(),
        attendedAt: g.createdAt,
      );
      auto.add(person);
    }
    return LineupPool._(candidates, auto, rules, states);
  }

  /// [people] 중 계산할 수 있는 사람으로 만든 계산 입력.
  TeamSplitInput input(Iterable<LineupPerson> people, {required int teams, required int players}) =>
      TeamSplitInput(
        candidates: [for (final p in people) ?candidates[p]],
        teamCount: teams,
        playersPerTeam: players,
        rules: rules,
      );
}

/// 화면에서 고치는 중인 팀 블록 하나.
class BoardSquad {
  BoardSquad(this.color, [List<LineupPerson>? people]) : people = people ?? [];

  BibColor color;
  final List<LineupPerson> people;
}

/// 화면에서 고치는 중인 배치 (저장 전). 팀 블록·교체 블록·조끼 색을 들고 있고, 서버 저장 형식으로 바꾼다.
/// 실력·등급·GK 정보는 없다.
class LineupBoard {
  LineupBoard({required this.playersPerTeam, required this.squads, List<LineupPerson>? bench})
    : bench = bench ?? [];

  final int playersPerTeam;
  final List<BoardSquad> squads;
  final List<LineupPerson> bench;

  int get teamCount => squads.length;

  static LineupBoard fromLineup(Lineup l) => LineupBoard(
    playersPerTeam: l.playersPerTeam,
    squads: [for (final q in l.squads) BoardSquad(q.bibColor, [...q.people])],
    bench: [...l.bench],
  );

  /// 계산 결과로 만든다. [colors] 가 팀 수와 같으면 그 색을 그대로 쓰고(다시 나눠도 조끼 색 유지), 아니면 자동 배정 순서.
  /// [extraBench] = 계산에 넣지 않고 교체 블록에 두는 사람 (직접 추가한 팀원 등).
  static LineupBoard fromPlan(
    TeamSplitPlan plan, {
    required int playersPerTeam,
    List<BibColor>? colors,
    List<LineupPerson> extraBench = const [],
  }) {
    final palette = colors != null && colors.length == plan.squads.length
        ? colors
        : BibColor.defaults(plan.squads.length);
    return LineupBoard(
      playersPerTeam: playersPerTeam,
      squads: [
        for (var i = 0; i < plan.squads.length; i++) BoardSquad(palette[i], [...plan.squads[i]]),
      ],
      bench: [...plan.bench, ...extraBench.where((p) => !plan.bench.contains(p))],
    );
  }

  LineupBoard copy() => LineupBoard(
    playersPerTeam: playersPerTeam,
    squads: [for (final q in squads) BoardSquad(q.color, [...q.people])],
    bench: [...bench],
  );

  /// 배치에 있는 사람 전부 (팀 블록 + 교체 블록).
  List<LineupPerson> get people => [for (final q in squads) ...q.people, ...bench];

  bool contains(LineupPerson p) => bench.contains(p) || squads.any((q) => q.people.contains(p));

  /// 그 사람이 있는 팀 블록 번호(0부터). 교체 블록이거나 없으면 null.
  int? squadOf(LineupPerson p) {
    for (var i = 0; i < squads.length; i++) {
      if (squads[i].people.contains(p)) return i;
    }
    return null;
  }

  void _take(LineupPerson p) {
    bench.remove(p);
    for (final q in squads) {
      q.people.remove(p);
    }
  }

  /// 옮기기. [toSquad] 가 null 이면 교체 블록. 같은 곳이면 아무것도 안 함 (false).
  bool move(LineupPerson p, int? toSquad) {
    final inBench = bench.contains(p);
    final from = squadOf(p);
    if (!inBench && from == null) return false;
    if (toSquad == null ? inBench : from == toSquad) return false;
    _take(p);
    if (toSquad == null) {
      bench.add(p);
    } else {
      squads[toSquad].people.add(p);
    }
    return true;
  }

  /// 배치에서 빼기 (못 온 사람, Q-046).
  bool remove(LineupPerson p) {
    if (!contains(p)) return false;
    _take(p);
    return true;
  }

  /// [팀원 추가]: 교체 블록에 넣는다 (Q-075 2번).
  bool addToBench(LineupPerson p) {
    if (contains(p)) return false;
    bench.add(p);
    return true;
  }

  /// [squad] 말고 다른 팀 블록이 쓰는 조끼 색 (한 배치 안 중복 불가).
  Set<BibColor> colorsUsedByOthers(int squad) => {
    for (var i = 0; i < squads.length; i++)
      if (i != squad) squads[i].color,
  };

  /// 조끼 색 바꾸기. 다른 팀이 쓰는 색이면 거절 (false).
  bool setColor(int squad, BibColor color) {
    if (colorsUsedByOthers(squad).contains(color)) return false;
    squads[squad].color = color;
    return true;
  }

  /// 지금 배치의 경고 (사람 이름·등급 없음).
  Set<SplitWarning> warnings(LineupPool pool) => TeamSplitter.evaluateWarnings(
    pool.input(people, teams: teamCount, players: playersPerTeam),
    [for (final q in squads) q.people],
    bench,
  );

  /// 계산 결과와 팀 블록 구성이 같은지 (팀 순서·조끼 색·교체 블록과 무관).
  bool sameTeamsAs(TeamSplitPlan plan) {
    String norm(Iterable<Iterable<LineupPerson>> teams) =>
        ([for (final t in teams) ([for (final p in t) p.key]..sort()).join(',')]..sort()).join('|');
    return norm([for (final q in squads) q.people]) == norm(plan.squads);
  }

  /// 저장할 내용이 같은지 비교하는 값 (팀 블록 순서·조끼 색 포함, 블록 안 순서는 무관).
  String get signature {
    String keys(Iterable<LineupPerson> ps) => ([for (final p in ps) p.key]..sort()).join(',');
    return [
      'n$playersPerTeam',
      for (final q in squads) '${q.color.serverValue}:${keys(q.people)}',
      'bench:${keys(bench)}',
    ].join('|');
  }

  LineupDraft toDraft(Set<LineupWarningKind> warnings) => LineupDraft(
    playersPerTeam: playersPerTeam,
    squads: [for (final q in squads) LineupSquadDraft(bibColor: q.color, people: List.unmodifiable(q.people))],
    bench: List.unmodifiable(bench),
    warnings: warnings,
  );
}

/// 배치를 보여줄 때 이름순 정렬 (가나다순, 같으면 키 순). 실력·포지션 순서가 드러나지 않게 화면은 항상 이것을 쓴다.
List<LineupPerson> sortByName(Iterable<LineupPerson> people, String Function(LineupPerson) nameOf) =>
    [...people]..sort((a, b) {
      final c = nameOf(a).compareTo(nameOf(b));
      return c != 0 ? c : a.compareTo(b);
    });
