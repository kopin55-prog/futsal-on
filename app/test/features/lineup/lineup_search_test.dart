import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_blocks.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_editor_screen.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_texts.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';

import '../../support/big_team.dart';
import '../../support/fakes.dart';

/// 팀 나누기 큰 팀 (Q-079 3번 e): 참석 30명, 위쪽 이름 검색으로 찾은 사람 강조 + 눌러서 메뉴로 옮기기.
TeamMatch _match() {
  final start = DateTime.now().toUtc().add(const Duration(hours: 1));
  return TeamMatch(
    id: 'm1',
    teamId: 'a',
    source: MatchSource.manual,
    status: MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
  );
}

Future<TestServices> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [bigTeamSummary(TeamRole.manager)], members: {'a': bigTeam()})..currentUserId = 'p02';
  final m = _match();
  t.matches.items.add(m);
  final base = DateTime.utc(2026, 11, 1);
  for (var i = 1; i <= 30; i++) {
    t.attendance.seed('m1', bigTeamId(i), AttendanceState.attending, at: base.add(Duration(minutes: i)));
  }
  await tester.pumpWidget(
    MaterialApp(
      home: LineupEditorScreen(
        services: t.services,
        team: bigTeamSummary(TeamRole.manager),
        viewer: const Viewer(userId: 'p02', role: TeamRole.manager),
        match: m,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 강조된(검색에 걸린) 이름들
List<String> _highlighted(WidgetTester tester) => [
  for (final c in tester.widgetList<LineupNameChip>(find.byType(LineupNameChip)))
    if (c.highlight) c.name,
];

bool _inSquad(WidgetTester tester, String personKey, int squadNo) => find
    .descendant(of: find.byKey(Key('lineup-squad-$squadNo')), matching: find.byKey(Key('lineup-person-$personKey')))
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('30명 자동 나누기 → 이름 검색 "김" → 5명 강조 + "5명 찾음", 없으면 안내, 지우면 강조 해제', (tester) async {
    await _open(tester);
    await _tapKey(tester, 'lineup-auto');
    expect(find.text(LineupTexts.poolInfo(30)), findsOneWidget);
    expect(find.text(LineupTexts.squadTitle(BibColor.red, 15)), findsOneWidget);
    expect(find.text(LineupTexts.squadTitle(BibColor.blue, 15)), findsOneWidget);
    expect(_highlighted(tester), isEmpty);

    await tester.enterText(find.byKey(const Key('lineup-search')), '김');
    await tester.pumpAndSettle();
    expect(_highlighted(tester).length, 5);
    expect(_highlighted(tester), everyElement(startsWith('김')));
    expect(find.text(LineupTexts.found(5)), findsOneWidget);
    // 명단은 그대로 (숨기지 않고 강조만)
    expect(find.byType(LineupNameChip), findsNWidgets(30));

    await tester.enterText(find.byKey(const Key('lineup-search')), '김민');
    await tester.pumpAndSettle();
    expect(_highlighted(tester), ['김민수']);

    await tester.enterText(find.byKey(const Key('lineup-search')), '없는 이름');
    await tester.pumpAndSettle();
    expect(_highlighted(tester), isEmpty);
    expect(find.text(LineupTexts.noNameMatch), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pumpAndSettle();
    expect(_highlighted(tester), isEmpty);
    expect(find.byKey(const Key('lineup-search-result')), findsNothing);
  });

  testWidgets('찾은 사람을 눌러 "파랑 팀으로/교체 블록으로" 메뉴로 옮긴다 (끌지 않고)', (tester) async {
    await _open(tester);
    await _tapKey(tester, 'lineup-auto');
    await tester.enterText(find.byKey(const Key('lineup-search')), '김민수');
    await tester.pumpAndSettle();
    const person = 'u:p01';
    final from = _inSquad(tester, person, 1) ? 0 : 1;
    final to = 1 - from;
    final fromColor = from == 0 ? BibColor.red : BibColor.blue;
    final toColor = to == 0 ? BibColor.red : BibColor.blue;

    await _tapKey(tester, 'lineup-person-$person');
    expect(find.text(LineupTexts.moveTitle('김민수')), findsOneWidget);
    // 지금 있는 팀은 메뉴에 없고, 다른 팀·교체 블록·빼기만
    expect(find.byKey(Key('move-to-$from')), findsNothing);
    expect(find.text(LineupTexts.moveTo(toColor)), findsOneWidget);
    expect(find.byKey(const Key('move-to-bench')), findsOneWidget);
    await _tapKey(tester, 'move-to-$to');

    expect(_inSquad(tester, person, to + 1), isTrue);
    expect(find.text(LineupTexts.squadTitle(fromColor, 14)), findsOneWidget);
    expect(find.text(LineupTexts.squadTitle(toColor, 16)), findsOneWidget);
    // 옮긴 뒤에도 검색 강조는 유지
    expect(_highlighted(tester), ['김민수']);

    await _tapKey(tester, 'lineup-person-$person');
    await _tapKey(tester, 'move-to-bench');
    expect(find.text(LineupTexts.benchTitle(1)), findsOneWidget);
    expect(_highlighted(tester), ['김민수']);
    expect(
      find.descendant(of: find.byKey(const Key('lineup-bench')), matching: find.byKey(const Key('lineup-person-$person'))),
      findsOneWidget,
    );
  });
}
