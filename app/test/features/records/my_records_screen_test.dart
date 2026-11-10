import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/records/domain/my_records.dart';
import 'package:futsal_on/features/records/presentation/records_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/fakes.dart';
import '../../support/tabs.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

TeamSeasonRecord _r(String team, String name, int season, {bool member = true, bool dissolved = false, int att = 0, int pom = 0, int goal = 0, int el = 0, int resp = 0}) =>
    TeamSeasonRecord(
      teamId: team,
      teamName: name,
      logoText: name.substring(0, 1),
      isMember: member,
      isDissolved: dissolved,
      season: season,
      attendance: att,
      pom: pom,
      goalOfTheDay: goal,
      voteEligible: el,
      voteResponded: resp,
    );

Future<TestServices> _open(WidgetTester tester, {void Function(TestServices t)? setup}) async {
  _tall(tester);
  final t = TestServices(
    teams: [
      const TeamSummary(id: 'a', name: '코코FC', teamCode: 'KOKO22', logoText: '코코', myRole: TeamRole.member, isRecruiting: true),
    ],
    members: {
      'a': const [MemberEntry(userId: 'me', role: TeamRole.member, displayName: '나')],
    },
  )..currentUserId = 'me';
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  await openTab(tester, TeamTexts.tabMy);
  return t;
}

String _cardText(WidgetTester tester, String cardKey) => [
  for (final w in tester.widgetList<Text>(find.descendant(of: find.byKey(Key(cardKey)), matching: find.byType(Text))))
    w.data ?? '',
].join('|');

void main() {
  testWidgets('내 기록 탭: 누적 기본, 전체 합산 + 팀별(지금 팀 먼저, 떠난 팀·해체된 팀 표시), 기존 항목 그대로', (tester) async {
    await _open(
      tester,
      setup: (t) => t.records.rows.addAll([
        _r('a', '코코FC', 2025, att: 3, pom: 1, el: 3, resp: 2),
        _r('a', '코코FC', 2026, att: 5, goal: 2, el: 4, resp: 3),
        _r('b', '가나FC', 2026, member: false, att: 1),
        _r('e', '다라FC', 2026, member: false, dissolved: true, att: 2, pom: 1),
      ]),
    );
    expect(find.byKey(const Key('my-records')), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('records-season-all'))).selected, isTrue);
    expect(find.byKey(const Key('records-season-2026')), findsOneWidget);
    expect(find.byKey(const Key('records-season-2025')), findsOneWidget);
    expect(find.byKey(const Key('records-season-2024')), findsNothing);

    final total = _cardText(tester, 'records-total');
    expect(total, contains(RecordsTexts.times(11))); // 출석 3+5+1+2
    expect(total, contains(RecordsTexts.times(2))); // POM, 오늘의 골
    expect(total, contains('71%')); // 5/7

    expect(_cardText(tester, 'records-team-b'), contains(RecordsTexts.leftTeam));
    expect(_cardText(tester, 'records-team-b'), contains(RecordsTexts.noRecordPercent));
    expect(_cardText(tester, 'records-team-e'), contains(RecordsTexts.dissolvedTeam));
    expect(_cardText(tester, 'records-team-a'), isNot(contains(RecordsTexts.leftTeam)));
    final ys = [for (final k in ['a', 'b', 'e']) tester.getTopLeft(find.byKey(Key('records-team-$k'))).dy];
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);

    // 기존 항목 (프로필 수정·팀 식별코드·팀 탈퇴·로그아웃·회원 탈퇴)
    for (final k in ['edit-profile', 'my-team-code', 'leave-team', 'sign-out', 'delete-account']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('시즌을 고르면 그 시즌 숫자만, 그 시즌 기록이 없는 팀은 빠짐', (tester) async {
    await _open(
      tester,
      setup: (t) => t.records.rows.addAll([
        _r('a', '코코FC', 2025, att: 3, el: 3, resp: 2),
        _r('a', '코코FC', 2026, att: 5, el: 4, resp: 3),
        _r('b', '가나FC', 2026, member: false, att: 1),
      ]),
    );
    await tester.tap(find.byKey(const Key('records-season-2025')));
    await tester.pumpAndSettle();
    expect(_cardText(tester, 'records-total'), contains(RecordsTexts.times(3)));
    expect(_cardText(tester, 'records-total'), contains('67%')); // 2/3 반올림
    expect(find.byKey(const Key('records-team-b')), findsNothing);
  });

  testWidgets('기록이 없으면 안내, 실패하면 다시 시도', (tester) async {
    final t = await _open(tester, setup: (t) => t.records.nextFailure = const ServerFailure(ServerErrorCode.unknown));
    expect(find.text(RecordsTexts.retry), findsOneWidget);
    await tester.tap(find.text(RecordsTexts.retry));
    await tester.pumpAndSettle();
    expect(t.records.calls, 2);
    expect(find.byKey(const Key('my-records-empty')), findsOneWidget);
  });
}
