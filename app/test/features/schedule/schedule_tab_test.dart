import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/domain/schedule_list.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_tab.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/shared/domain/venue.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../support/fakes.dart';

/// 일정 탭 정식 화면 (스프린트 04 5단계, S4-13).
/// 기준 시각: 2026-11-16(월) 12:00 KST.
final _now = DateTime.utc(2026, 11, 16, 3);

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.member, displayName: '나'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '나래'),
];

const _team = TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: TeamRole.member,
  isRecruiting: true,
);

/// [kstDay] 11월 며칠, [hour] KST 시작 시각, 2시간 경기.
TeamMatch _m(String id, int kstDay, {int hour = 10, int? capacity, bool cancelled = false, String? venue, int month = 11}) {
  final start = DateTime.utc(2026, month, kstDay, hour).subtract(Kst.offset);
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
    capacity: capacity,
    venue: venue == null ? null : Venue.manual(name: venue),
    cancelledAt: cancelled ? start.subtract(const Duration(days: 1)) : null,
  );
}

Future<TestServices> _pump(
  WidgetTester tester, {
  List<TeamMatch> matches = const [],
  TeamRole role = TeamRole.member,
  void Function(TestServices t)? setup,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [_team], members: {'a': _members})..currentUserId = 'me';
  t.matches.items.addAll(matches);
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: ScheduleTab(
          services: t.services,
          team: _team,
          viewer: Viewer(userId: 'me', role: role),
          now: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

String _line(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('한 줄 문구 (S4-13 (2))', () {
    test('시각: 같은 날 / 다음날 / 이틀 넘게', () {
      expect(ScheduleTexts.rowTime(_m('a', 18)), '11/18(수) 10:00~12:00');
      expect(ScheduleTexts.rowTime(_m('b', 18, hour: 23)), '11/18(수) 23:00~다음날 01:00');
      expect(ScheduleTexts.rowAttending(9, 12), '참석 9/12');
      expect(ScheduleTexts.rowAttending(9, null), '참석 9');
      expect(ScheduleTexts.rowMine(AttendanceState.waitlisted, 2), '나: 대기 2번');
      expect(ScheduleTexts.rowMine(null, null), '나: 미투표');
    });

    test('달력: 시작한 한국 날짜에, 시작 순, 같은 일정은 한 번', () {
      final late = _m('late', 18, hour: 20);
      final early = _m('early', 18, hour: 8);
      // 한국 시간 11/19 00:30 시작 (UTC 로는 11/18)
      final midnight = TeamMatch(
        id: 'mid',
        teamId: 'a',
        source: MatchSource.manual,
        status: MatchStatus.scheduled,
        startsAt: DateTime.utc(2026, 11, 18, 15, 30),
        endsAt: DateTime.utc(2026, 11, 18, 17, 30),
        rsvpDeadlineAt: DateTime.utc(2026, 11, 18, 13),
      );
      final map = ScheduleCalendar.byDate([late, early, midnight, late]);
      expect(map[const CalendarDate(2026, 11, 18)]!.map((m) => m.id), ['early', 'late']);
      expect(map[const CalendarDate(2026, 11, 19)]!.map((m) => m.id), ['mid']);
    });
  });

  group('목록 (5-1)', () {
    testWidgets('기본은 목록·다가오는 경기. 한 줄에 장소·참석 N/정원·나:, 취소된 일정은 숫자 없이 "취소됨"', (tester) async {
      await _pump(
        tester,
        matches: [
          _m('m1', 18, capacity: 12, venue: '성수 풋살장'),
          _m('m2', 20, cancelled: true, venue: '성수 풋살장'),
          _m('m3', 25),
          _m('old', 9),
        ],
        setup: (t) {
          t.attendance.seed('m1', 'me', AttendanceState.attending);
          t.attendance.seed('m1', 'u1', AttendanceState.attending);
          t.attendance.seed('m1', 'u2', AttendanceState.declined);
          t.attendance.seed('m3', 'u1', AttendanceState.attending);
        },
      );
      expect(find.byKey(const Key('schedule-calendar')), findsNothing);
      expect(find.byKey(const Key('match-old')), findsNothing);
      final ys = [for (final id in ['m1', 'm2', 'm3']) tester.getTopLeft(find.byKey(Key('match-$id'))).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);

      expect(find.descendant(of: find.byKey(const Key('match-m1')), matching: find.text('11/18(수) 10:00~12:00')), findsOneWidget);
      expect(_line(tester, 'match-line-m1'), '성수 풋살장 · 참석 2/12 · 나: 참석');
      expect(_line(tester, 'match-line-m3'), '${ScheduleTexts.venueNone} · 참석 1 · 나: 미투표');
      expect(_line(tester, 'match-line-m2'), '성수 풋살장');
      expect(
        find.descendant(of: find.byKey(const Key('match-m2')), matching: find.text(ScheduleTexts.cancelled)),
        findsOneWidget,
      );
      // 팀원에게 일정 추가 버튼 없음
      expect(find.byKey(const Key('schedule-add')), findsNothing);
    });

    testWidgets('"지난 경기"로 바꾸면 최근 순, 대기 순번도 나: 에', (tester) async {
      await _pump(
        tester,
        matches: [_m('p1', 9, capacity: 1), _m('p2', 12), _m('next', 18)],
        setup: (t) {
          t.attendance.seed('p1', 'u1', AttendanceState.attending);
          t.attendance.seed('p1', 'me', AttendanceState.waitlisted);
        },
      );
      await tester.tap(find.byKey(const Key('schedule-range-past')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-next')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('past-match-p2'))).dy <
            tester.getTopLeft(find.byKey(const Key('past-match-p1'))).dy,
        isTrue,
      );
      expect(_line(tester, 'past-match-line-p1'), '${ScheduleTexts.venueNone} · 참석 1/1 · 나: 대기 1번');
      await tester.tap(find.byKey(const Key('schedule-range-upcoming')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-next')), findsOneWidget);
    });

    testWidgets('운영진에게 일정 추가 버튼, 일정이 없으면 안내', (tester) async {
      await _pump(tester, role: TeamRole.manager);
      expect(find.byKey(const Key('schedule-add')), findsOneWidget);
      expect(find.text(ScheduleTexts.noUpcoming), findsOneWidget);
    });

    testWidgets('줄을 누르면 일정 상세', (tester) async {
      await _pump(tester, matches: [_m('m1', 18)]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-status')), findsOneWidget);
    });
  });

  group('달력 (5-2)', () {
    testWidgets('경기 날 점(취소는 회색), 오늘 경기가 처음 보이고, 날짜를 누르면 그날 경기', (tester) async {
      final t = await _pump(
        tester,
        matches: [
          _m('today', 16, hour: 20),
          _m('m1', 18),
          _m('cx', 20, cancelled: true),
          _m('p1', 9),
        ],
      );
      await tester.tap(find.byKey(const Key('schedule-view-calendar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-calendar')), findsOneWidget);
      expect(find.text(ScheduleTexts.monthTitle(2026, 11)), findsOneWidget);
      for (final id in ['today', 'm1', 'cx', 'p1']) {
        expect(find.byKey(Key('calendar-dot-$id')), findsOneWidget, reason: id);
      }
      final ctx = tester.element(find.byKey(const Key('schedule-calendar')));
      final scheme = Theme.of(ctx).colorScheme;
      Color dot(String id) => (tester.widget<Container>(find.byKey(Key('calendar-dot-$id'))).decoration! as BoxDecoration).color!;
      expect(dot('cx'), scheme.outline);
      expect(dot('m1'), scheme.primary);

      // 처음엔 오늘(11/16) 경기
      expect(find.text(ScheduleTexts.date(const CalendarDate(2026, 11, 16))), findsOneWidget);
      expect(find.byKey(const Key('day-match-today')), findsOneWidget);

      // 11/18 누르기
      await tester.tap(find.text('18'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('day-match-m1')), findsOneWidget);
      expect(find.byKey(const Key('day-match-today')), findsNothing);

      // 경기 없는 날
      await tester.tap(find.text('17'));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleTexts.noMatchOnDay), findsOneWidget);

      // 지난 경기 날도 누르면 상세로
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('day-match-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-status')), findsOneWidget);
      expect(t.matches.items.length, 4);
    });

    testWidgets('다음 달로 넘기면 그 달 경기 점, 어두운 모드에서도 그려진다', (tester) async {
      await _pump(
        tester,
        theme: ThemeData(brightness: Brightness.dark),
        matches: [_m('dec', 2, month: 12)],
      );
      await tester.tap(find.byKey(const Key('schedule-view-calendar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-dot-dec')), findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      expect(find.text(ScheduleTexts.monthTitle(2026, 12)), findsOneWidget);
      expect(find.byKey(const Key('calendar-dot-dec')), findsOneWidget);
      expect(find.byType(TableCalendar<TeamMatch>), findsOneWidget);
    });
  });
}
