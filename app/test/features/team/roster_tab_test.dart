import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/roster_tab.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../../support/fakes.dart';

/// 팀원 탭 (스프린트 04 6-1, S4-14). 기준: 2026-11-16 KST.
final _now = DateTime.utc(2026, 11, 16, 3);

// 일부러 섞어 둔 순서 (서버 순서에 기대지 않는다)
const _members = [
  MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '하늘', bio: '왼발잡이'),
  MemberEntry(userId: 'm2', role: TeamRole.manager, displayName: '철수'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'own', role: TeamRole.owner, displayName: '팀장님'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '민수'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '나래'),
];

TeamSummary _team(TeamRole role) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: role,
  isRecruiting: true,
);

Future<TestServices> _pump(
  WidgetTester tester, {
  TeamRole role = TeamRole.member,
  String me = 'u1',
  void Function(TestServices t)? setup,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [_team(role)], members: {'a': _members})..currentUserId = me;
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: RosterTab(
          services: t.services,
          team: _team(role),
          viewer: Viewer(userId: me, role: role),
          now: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

List<String> _order(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.startsWith("[<'member-") && !'${w.key}'.contains('injury')),
  ))
    '${tile.key}'.replaceAll("[<'member-", '').replaceAll("'>]", ''),
];

void main() {
  testWidgets('위에 "팀원 N명", 팀장 → 운영진 → 팀원, 각각 가나다순', (tester) async {
    await _pump(tester);
    expect(find.text(TeamTexts.memberCount(6)), findsOneWidget);
    expect(_order(tester), ['own', 'm1', 'm2', 'u1', 'u2', 'u3']);
    expect(find.text('왼발잡이'), findsOneWidget);
  });

  testWidgets('부상 중이면 이름 옆 "부상 2W"(올림), 메모는 목록에 없고 프로필 보기에만', (tester) async {
    await _pump(
      tester,
      setup: (t) {
        // 10일 남음 → 2W, 복귀일 지남 → 0W
        t.injuries.seedActive('m2', expectedReturnOn: DateTime.utc(2026, 11, 26), memo: '발목 염좌');
        t.injuries.seedActive('u2', expectedReturnOn: DateTime.utc(2026, 11, 10));
      },
    );
    expect(
      find.descendant(of: find.byKey(const Key('member-injury-m2')), matching: find.text(TeamTexts.injuryMark(2))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('member-injury-u2')), matching: find.text(TeamTexts.injuryMark(0))),
      findsOneWidget,
    );
    expect(find.byKey(const Key('member-injury-u1')), findsNothing);
    expect(find.text('발목 염좌'), findsNothing);

    await tester.tap(find.byKey(const Key('member-m2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-profile-injury')), findsOneWidget);
    expect(find.text('발목 염좌'), findsOneWidget);
  });

  testWidgets('선호 포지션·실력 등급은 목록에 없다 (관리자가 봐도)', (tester) async {
    await _pump(tester, role: TeamRole.owner, me: 'own');
    expect(find.byKey(const Key('member-prefs')), findsNothing);
    for (final w in ['비기너', '아마추어', '세미프로', '프로', '골키퍼', '공격', '수비']) {
      expect(find.text(w), findsNothing, reason: w);
    }
  });

  testWidgets('어두운 모드에서도 그려진다', (tester) async {
    await _pump(
      tester,
      theme: ThemeData(brightness: Brightness.dark),
      setup: (t) => t.injuries.seedActive('u3', expectedReturnOn: DateTime.utc(2026, 11, 20)),
    );
    expect(find.text(TeamTexts.injuryMark(1)), findsOneWidget);
  });
}
