import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/match_detail_screen.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';

import '../../support/big_team.dart';
import '../../support/fakes.dart';

/// 일정 상세 참석 현황 탭 (Q-079 3번 d), 팀원 30명: 참석 12 · 대기 3 · 불참 5 · 미투표 10.
TeamMatch _match() {
  final start = DateTime.now().toUtc().add(const Duration(days: 2));
  return TeamMatch(
    id: 'm1',
    teamId: 'a',
    source: MatchSource.manual,
    status: MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
    capacity: 12,
  );
}

Future<TestServices> _open(WidgetTester tester, {TeamRole role = TeamRole.member, String me = 'p30'}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [bigTeamSummary(role)], members: {'a': bigTeam()})..currentUserId = me;
  final m = _match();
  t.matches.items.add(m);
  final base = DateTime.utc(2026, 11, 1);
  for (var i = 1; i <= 12; i++) {
    t.attendance.seed('m1', bigTeamId(i), AttendanceState.attending, at: base.add(Duration(minutes: i)));
  }
  for (var i = 13; i <= 15; i++) {
    t.attendance.seed('m1', bigTeamId(i), AttendanceState.waitlisted, at: base.add(Duration(minutes: i)));
  }
  for (var i = 16; i <= 20; i++) {
    t.attendance.seed('m1', bigTeamId(i), AttendanceState.declined, at: base.add(Duration(minutes: i)));
  }
  await tester.pumpWidget(
    MaterialApp(
      home: MatchDetailScreen(
        services: t.services,
        team: bigTeamSummary(role),
        viewer: Viewer(userId: me, role: role),
        matchId: m.id,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

List<String> _names(WidgetTester tester, String roster) => [
  for (final c in tester.widgetList<Chip>(
    find.descendant(of: find.byKey(Key('roster-$roster')), matching: find.byType(Chip)),
  ))
    (c.label as Text).data!,
];

Future<void> _tab(WidgetTester tester, int i) async {
  await tester.ensureVisible(find.byKey(Key('attendance-tab-$i')));
  await tester.tap(find.byKey(Key('attendance-tab-$i')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('칩 4개에 숫자, 처음엔 참석 명단만, 다른 명단은 칩을 눌러야 보인다', (tester) async {
    await _open(tester);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.attending} 12'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.waitlisted} 3'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.declined} 5'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.notResponded} 10'), findsOneWidget);

    expect(_names(tester, 'attending').length, 12);
    expect(find.byKey(const Key('roster-waitlisted')), findsNothing);
    expect(find.byKey(const Key('roster-not-responded')), findsNothing);

    await _tab(tester, 1);
    expect(_names(tester, 'waitlisted'), ['1. 김도윤', '2. 이도윤', '3. 박도윤']);
    expect(find.byKey(const Key('roster-attending')), findsNothing);

    await _tab(tester, 2);
    expect(_names(tester, 'declined').length, 5);
  });

  testWidgets('미투표 탭: 응답 없는 10명이 이름 가나다순으로 한눈에', (tester) async {
    await _open(tester);
    await _tab(tester, 3);
    final names = _names(tester, 'not-responded');
    expect(names.length, 10);
    expect(names, [...names]..sort());
    // 응답한 사람은 없다
    expect(names, isNot(contains('김민수')));
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.notResponded} 10'), findsOneWidget);
  });

  testWidgets('내가 참석하면 참석 13 · 미투표 9 로 숫자가 바뀌고, 빈 명단은 "아직 없어요"', (tester) async {
    await _open(tester);
    await _tab(tester, 3);
    expect(_names(tester, 'not-responded'), contains('강지호'));
    await tester.ensureVisible(find.byKey(const Key('rsvp-attend')));
    await tester.tap(find.byKey(const Key('rsvp-attend')));
    await tester.pumpAndSettle();
    // 정원 12명이 차서 대기 4번
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.waitlisted} 4'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.notResponded} 9'), findsOneWidget);
    // 보던 탭(미투표)은 유지된다
    expect(_names(tester, 'not-responded'), isNot(contains('강지호')));
  });

  testWidgets('아무도 응답하지 않은 일정: 참석 0 과 "아직 없어요", 미투표 30', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final t = TestServices(teams: [bigTeamSummary(TeamRole.member)], members: {'a': bigTeam()})..currentUserId = 'p30';
    t.matches.items.add(_match());
    await tester.pumpWidget(
      MaterialApp(
        home: MatchDetailScreen(
          services: t.services,
          team: bigTeamSummary(TeamRole.member),
          viewer: const Viewer(userId: 'p30', role: TeamRole.member),
          matchId: 'm1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.attending} 0'), findsOneWidget);
    expect(find.byKey(const Key('roster-attending-empty')), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '${ScheduleTexts.notResponded} 30'), findsOneWidget);
  });
}
