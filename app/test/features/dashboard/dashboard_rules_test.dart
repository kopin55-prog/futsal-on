import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/dashboard/domain/dashboard_models.dart';
import 'package:futsal_on/features/injury/domain/injury_models.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';

final _now = DateTime.utc(2026, 11, 18, 1, 30); // 한국 10:30

TeamMatch _m(String id, {required int startHour, int days = 0, int lengthHours = 2, bool cancelled = false, int deadlineHours = 2}) {
  final start = DateTime.utc(2026, 11, 18 + days, startHour);
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.auto,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(Duration(hours: lengthHours)),
    rsvpDeadlineAt: start.subtract(Duration(hours: deadlineHours)),
  );
}

Lineup _lineup({required bool confirmed, List<String> red = const [], List<String> blue = const [], List<String> bench = const []}) => Lineup(
  id: 'L',
  matchId: 'm',
  teamCount: 2,
  playersPerTeam: 5,
  status: confirmed ? LineupStatus.confirmed : LineupStatus.draft,
  warnings: const {},
  version: 1,
  updatedAt: 'x',
  confirmedAt: confirmed ? DateTime.utc(2026) : null,
  squads: [
    LineupSquad(id: 'q1', squadNo: 1, bibColor: BibColor.red, people: [for (final u in red) LineupPerson.member(u)]),
    LineupSquad(id: 'q2', squadNo: 2, bibColor: BibColor.blue, people: [for (final u in blue) LineupPerson.member(u)]),
  ],
  bench: [for (final u in bench) LineupPerson.member(u)],
);

void main() {
  group('다음 경기 (S4-02 (1))', () {
    test('진행 중인 경기가 있으면 그 경기 (다음 주 일정보다 먼저)', () {
      final playing = _m('now', startHour: 1); // 10:00~12:00 한국
      final nextWeek = _m('next', startHour: 1, days: 7);
      expect(DashboardRules.nextMatch([nextWeek, playing], _now)?.id, 'now');
      expect(DashboardRules.isInProgress(playing, _now), isTrue);
      expect(DashboardRules.isInProgress(nextWeek, _now), isFalse);
    });

    test('끝난 경기·취소된 일정은 건너뛴다, 없으면 null', () {
      final ended = _m('ended', startHour: 0, lengthHours: 1); // 09:00~10:00 끝남
      final cancelled = _m('cancel', startHour: 5, cancelled: true);
      final later = _m('later', startHour: 1, days: 2);
      expect(DashboardRules.nextMatch([ended, cancelled, later], _now)?.id, 'later');
      expect(DashboardRules.nextMatch([ended, cancelled], _now), isNull);
    });
  });

  group('지난 경기 (S4-03)', () {
    test('가장 최근에 끝난, 취소되지 않은 경기', () {
      final old = _m('old', startHour: 1, days: -7);
      final recent = _m('recent', startHour: 1, days: -1);
      final cancelledRecent = _m('c', startHour: 5, days: -1, cancelled: true);
      final playing = _m('now', startHour: 1);
      expect(DashboardRules.lastFinishedMatch([old, recent, cancelledRecent, playing], _now)?.id, 'recent');
      expect(DashboardRules.lastFinishedMatch([playing], _now), isNull);
    });
  });

  group('팀 나누기 대기 (S4-05)', () {
    test('참석 마감 뒤·경기 종료 전·배치 미확정만', () {
      final open = _m('open', startHour: 3); // 마감 10:00 지남, 12:00 시작
      final beforeDeadline = _m('before', startHour: 1, days: 2);
      final ended = _m('ended', startHour: 0, lengthHours: 1);
      final cancelled = _m('c', startHour: 3, cancelled: true);
      expect(DashboardRules.needsLineup(open, null, _now), isTrue);
      expect(DashboardRules.needsLineup(open, _lineup(confirmed: false), _now), isTrue);
      expect(DashboardRules.needsLineup(open, _lineup(confirmed: true), _now), isFalse);
      expect(DashboardRules.needsLineup(beforeDeadline, null, _now), isFalse);
      expect(DashboardRules.needsLineup(ended, null, _now), isFalse);
      expect(DashboardRules.needsLineup(cancelled, null, _now), isFalse);
    });
  });

  group('확정 배치에서 내 자리 (S4-02 (4))', () {
    final l = _lineup(confirmed: true, red: ['a', 'me'], blue: ['b'], bench: ['c']);
    test('팀 블록 / 교체 블록 / 배치에 없음', () {
      expect((DashboardRules.mySlot(l, 'me') as MySquadSlot).squad.bibColor, BibColor.red);
      expect(DashboardRules.mySlot(l, 'c'), isA<MyBenchSlot>());
      expect(DashboardRules.mySlot(l, 'x'), isA<NotInLineup>());
    });
  });

  group('부상자 라인업 (S4-04)', () {
    final today = DateTime.utc(2026, 11, 18);
    Injury inj(String user, int daysLeft, {bool active = true}) => Injury(
      id: 'i-$user',
      userId: user,
      startedOn: today.subtract(const Duration(days: 3)),
      expectedReturnOn: today.add(Duration(days: daysLeft)),
      isActive: active,
    );
    const members = [
      MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다'),
      MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가'),
      MemberEntry(userId: 'u3', role: TeamRole.manager, displayName: '나'),
      MemberEntry(userId: 'u4', role: TeamRole.member, displayName: '라'),
    ];

    test('남은 기간 짧은 순(올림), 같으면 이름 가나다순. 지금 팀원이 아닌 사람·지난 부상은 없음', () {
      final list = DashboardRules.injuredLineup(
        members,
        [inj('u1', 10), inj('u2', 10), inj('u3', 3), inj('u4', -2), inj('gone', 1), inj('u9', 1, active: false)],
        today,
      );
      expect([for (final i in list) i.member.userId], ['u4', 'u3', 'u2', 'u1']);
      expect([for (final i in list) i.remainingWeeks], [0, 1, 2, 2]);
    });

    test('부상자가 없으면 빈 목록 (칸 숨김)', () {
      expect(DashboardRules.injuredLineup(members, const [], today), isEmpty);
    });

    test('오늘 날짜는 한국 날짜', () {
      // UTC 11/17 16:00 = 한국 11/18 01:00
      expect(DashboardRules.todayKst(DateTime.utc(2026, 11, 17, 16)), DateTime.utc(2026, 11, 18));
    });
  });

}
