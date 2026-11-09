import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_board.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/domain/team_split.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/shared/domain/position.dart';

const u1 = LineupPerson.member('u1');
const u2 = LineupPerson.member('u2');
const u3 = LineupPerson.member('u3');
const u4 = LineupPerson.member('u4');
const g1 = LineupPerson.guest('g1');

TeamMatch _match({required Duration startIn, Duration deadlineBefore = const Duration(hours: 2), bool cancelled = false}) {
  final start = DateTime.utc(2026, 11, 9, 12).add(startIn);
  return TeamMatch(
    id: 'm',
    teamId: 'a',
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(deadlineBefore),
  );
}

AttendanceResponse _resp(String user, AttendanceState state, int minute) {
  final t = DateTime.utc(2026, 11, 1, 0, minute);
  return AttendanceResponse(id: 'r$user', matchId: 'm', userId: user, state: state, respondedAt: t, updatedAt: t);
}

LineupPool _pool({List<PairingRule> rules = const []}) => LineupPool.build(
  members: const [
    MemberEntry(userId: 'u1', role: TeamRole.owner, displayName: '가'),
    MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '나'),
    MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '다'),
    MemberEntry(userId: 'u4', role: TeamRole.member, displayName: '라'),
    MemberEntry(userId: 'u5', role: TeamRole.member, displayName: '마'),
  ],
  responses: [
    _resp('u1', AttendanceState.attending, 1),
    _resp('u2', AttendanceState.attending, 2),
    _resp('u3', AttendanceState.attending, 3),
    _resp('u4', AttendanceState.declined, 4),
  ],
  guests: [
    MatchGuestDetail(
      id: 'g1',
      guestNo: 1,
      positions: const [Position.forward],
      skillLevel: SkillLevel.pro,
      createdAt: DateTime.utc(2026, 11, 2),
    ),
  ],
  skills: const {'u1': SkillLevel.pro},
  prefs: const {'u2': PlayPrefs(positions: [Position.goalkeeper], isDedicatedGk: true)},
  rules: rules,
);

void main() {
  group('만들 수 있는 시점 (Q-075 1번)', () {
    final now = DateTime.utc(2026, 11, 9, 12);
    test('마감 전 / 마감 뒤~종료 전 / 종료 뒤 / 취소', () {
      expect(LineupWindow.of(_match(startIn: const Duration(hours: 3)), now), LineupWindow.beforeDeadline);
      expect(LineupWindow.of(_match(startIn: const Duration(hours: 1)), now), LineupWindow.open);
      // 경기 중(시작 뒤 종료 전)도 가능
      expect(LineupWindow.of(_match(startIn: const Duration(hours: -1)), now), LineupWindow.open);
      // 종료 정각부터 불가
      expect(LineupWindow.of(_match(startIn: const Duration(hours: -2)), now), LineupWindow.ended);
      expect(LineupWindow.of(_match(startIn: const Duration(hours: 1), cancelled: true), now), LineupWindow.cancelled);
      // 마감 정각부터 가능
      expect(LineupWindow.of(_match(startIn: const Duration(hours: 2)), now), LineupWindow.open);
    });
  });

  group('팀 수·팀당 인원 처음 값 (Q-075 7번 (4))', () {
    test('지난 경기에 쓴 값이 있으면 그 값', () {
      expect(LineupLimits.defaults(last: (teams: 3, players: 5), poolCount: 20), (teams: 3, players: 5));
    });
    test('없으면 2팀 · 인원÷2 올림', () {
      expect(LineupLimits.defaults(poolCount: 13), (teams: 2, players: 7));
      expect(LineupLimits.defaults(poolCount: 12), (teams: 2, players: 6));
      expect(LineupLimits.defaults(poolCount: 0), (teams: 2, players: 1));
      expect(LineupLimits.defaults(poolCount: 200), (teams: 2, players: 50));
    });
    test('범위 2~11팀', () {
      expect(LineupLimits.maxTeams, 11);
      expect(LineupLimits.defaults(last: (teams: 30, players: 0), poolCount: 1), (teams: 11, players: 1));
    });
  });

  group('계산 재료', () {
    test('자동으로 들어가는 사람 = 참석자 + 게스트, 나머지 팀원은 추가 후보', () {
      final pool = _pool();
      expect(pool.autoPeople, {u1, u2, u3, g1});
      expect(pool.candidates.keys, containsAll([u4, const LineupPerson.member('u5')]));
      expect(pool.states['u4'], AttendanceState.declined);
      expect(pool.states['u5'], isNull);
      expect(pool.candidates[u2]!.countsAsDedicatedGk, isTrue);
      expect(pool.candidates[u1]!.skill, SkillLevel.pro);
      expect(pool.candidates[u3]!.skill, SkillLevel.undecided);
      expect(pool.candidates[g1]!.skill, SkillLevel.pro);
    });
  });

  group('배치 고치기', () {
    LineupBoard board() => LineupBoard(
      playersPerTeam: 2,
      squads: [
        BoardSquad(BibColor.red, [u1, u2]),
        BoardSquad(BibColor.blue, [u3, g1]),
      ],
    );

    test('팀 ↔ 팀 ↔ 교체 옮기기, 같은 곳이면 변화 없음', () {
      final b = board();
      expect(b.move(u1, 1), isTrue);
      expect(b.squads[1].people, [u3, g1, u1]);
      expect(b.move(u1, 1), isFalse);
      expect(b.move(u1, null), isTrue);
      expect(b.bench, [u1]);
      expect(b.squadOf(u1), isNull);
      expect(b.move(u1, 0), isTrue);
      expect(b.bench, isEmpty);
      expect(b.move(u4, 0), isFalse, reason: '배치에 없는 사람');
    });

    test('팀원 추가는 교체 블록, 빼기', () {
      final b = board();
      expect(b.addToBench(u4), isTrue);
      expect(b.addToBench(u4), isFalse);
      expect(b.bench, [u4]);
      expect(b.remove(u4), isTrue);
      expect(b.contains(u4), isFalse);
    });

    test('조끼 색: 다른 팀이 쓰는 색은 못 고름 (중복 불가)', () {
      final b = board();
      expect(b.colorsUsedByOthers(0), {BibColor.blue});
      expect(b.setColor(0, BibColor.blue), isFalse);
      expect(b.setColor(0, BibColor.noBib), isTrue);
      expect(b.squads[0].color, BibColor.noBib);
    });

    test('계산 결과로 만들기: 자동 배정 색, 같은 팀 수면 색 유지, 직접 추가한 사람은 교체에', () {
      const plan = TeamSplitPlan(squads: [[u1], [u2], [u3]], bench: [g1], warnings: {});
      final b = LineupBoard.fromPlan(plan, playersPerTeam: 1, extraBench: [u4]);
      expect([for (final q in b.squads) q.color], [BibColor.red, BibColor.blue, BibColor.yellow]);
      expect(b.bench, [g1, u4]);
      final kept = LineupBoard.fromPlan(
        plan,
        playersPerTeam: 1,
        colors: [BibColor.noBib, BibColor.red, BibColor.white],
      );
      expect([for (final q in kept.squads) q.color], [BibColor.noBib, BibColor.red, BibColor.white]);
      expect(kept.sameTeamsAs(const TeamSplitPlan(squads: [[u3], [u1], [u2]], bench: [], warnings: {})), isTrue);
    });

    test('경고: 라이벌 같은 팀·교체 N명·N명 모자람 (이름·등급 없음)', () {
      final pool = _pool(
        rules: const [PairingRule(id: 'r', kind: PairingKind.rival, enabled: true, userIds: ['u1', 'u3'])],
      );
      final b = board()
        ..move(u3, 0)
        ..remove(g1);
      final w = b.warnings(pool);
      expect(w, contains(const SplitWarning(SplitWarningKind.rivalSameTeam)));
      expect(w, contains(const SplitWarning(SplitWarningKind.playersShort, 1)));
      b.addToBench(u4);
      expect(b.warnings(pool), contains(const SplitWarning(SplitWarningKind.benchRemaining, 1)));
    });

    test('저장 형식·비교 값: 블록 안 순서는 무관, 색·교체는 반영', () {
      final a = board();
      final b = LineupBoard(
        playersPerTeam: 2,
        squads: [
          BoardSquad(BibColor.red, [u2, u1]),
          BoardSquad(BibColor.blue, [g1, u3]),
        ],
      );
      expect(a.signature, b.signature);
      b.setColor(1, BibColor.green);
      expect(a.signature, isNot(b.signature));
      final draft = a.toDraft({LineupWarningKind.rivalSameTeam});
      expect(draft.teamCount, 2);
      expect(draft.squads[1].people, [u3, g1]);
      expect(draft.warnings, {LineupWarningKind.rivalSameTeam});
    });

    test('이름 가나다순 정렬', () {
      final names = {'u1': '하늘', 'u2': '가람', 'u3': '나래'};
      expect(sortByName([u1, u2, u3], (p) => names[p.userId]!), [u2, u3, u1]);
    });
  });

  group('배치 보기 권한 (entitlements 한 곳)', () {
    const e = Entitlements();
    test('운영진은 초안도, 팀원은 확정된 배치만, 팀 밖은 못 봄', () {
      const staff = Viewer(userId: 'a', role: TeamRole.manager);
      const member = Viewer(userId: 'b', role: TeamRole.member);
      const outsider = Viewer(userId: 'c', role: null);
      expect(e.canView(staff, const LineupInfo(confirmed: false)), isTrue);
      expect(e.canView(member, const LineupInfo(confirmed: false)), isFalse);
      expect(e.canView(member, const LineupInfo(confirmed: true)), isTrue);
      expect(e.canView(outsider, const LineupInfo(confirmed: true)), isFalse);
      expect(e.canPerform(member, TeamAction.manageLineup), isFalse);
      expect(e.canPerform(staff, TeamAction.manageLineup), isTrue);
    });
  });
}
