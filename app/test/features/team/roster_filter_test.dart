import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/team/domain/member_filter.dart';
import 'package:futsal_on/features/team/presentation/roster_tab.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../../support/big_team.dart';
import '../../support/fakes.dart';

/// 팀원 탭 이름 검색 + 필터 칩 (Q-079 3번 a), 팀원 30명 기준. 기준: 2026-11-16 KST.
final _now = DateTime.utc(2026, 11, 16, 3);

Future<TestServices> _pump(
  WidgetTester tester, {
  TeamRole role = TeamRole.owner,
  String me = 'p01',
  void Function(TestServices t)? setup,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [bigTeamSummary(role)], members: {'a': bigTeam()})..currentUserId = me;
  // 부상 2명(p05·p13 김도윤), 실력 등급 10명 → 미정 20명
  t.injuries.seedActive('p05', expectedReturnOn: DateTime.utc(2026, 11, 26));
  t.injuries.seedActive('p13', expectedReturnOn: DateTime.utc(2026, 11, 20));
  t.admin.levels = {for (var i = 1; i <= 10; i++) bigTeamId(i): SkillLevel.amateur};
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RosterTab(
          services: t.services,
          team: bigTeamSummary(role),
          viewer: Viewer(userId: me, role: role),
          now: () => _now,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

/// 지금 보이는 팀원 카드의 ID (보이는 줄만 그려지므로 결과가 적을 때만 센다)
List<String> _shownIds(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.startsWith("[<'member-")),
  ))
    '${tile.key}'.replaceAll("[<'member-", '').replaceAll("'>]", ''),
];

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void main() {
  group('filterMembers (순수 규칙)', () {
    final members = bigTeam();
    test('검색어 정리: 공백·대소문자 무시, 일부 글자로 포함 검색', () {
      expect(filterMembers(members, filter: MemberFilter.all, query: ' 김 ').map((m) => m.userId), bigTeamKims);
      expect(filterMembers(members, filter: MemberFilter.all, query: '민수').length, 6);
      expect(filterMembers(members, filter: MemberFilter.all, query: '없는이름'), isEmpty);
      expect(filterMembers(members, filter: MemberFilter.all).length, 30);
    });

    test('운영진 칩 = 팀장·운영진, 부상 칩 = 보이는 부상자, 검색과 함께 적용', () {
      expect(filterMembers(members, filter: MemberFilter.staff).map((m) => m.userId), ['p01', 'p02', 'p03']);
      expect(filterMembers(members, filter: MemberFilter.staff, query: '이').map((m) => m.userId), ['p02']);
      expect(filterMembers(members, filter: MemberFilter.injured, injuredIds: {'p05', 'p13'}).length, 2);
      expect(filterMembers(members, filter: MemberFilter.injured), isEmpty);
    });

    test('실력 미정 = 줄이 없거나 미정. 등급을 볼 수 없으면(null) 아무도 안 나온다', () {
      final levels = {'p01': SkillLevel.pro, 'p02': SkillLevel.undecided};
      final shown = filterMembers(members, filter: MemberFilter.skillUndecided, skillLevels: levels);
      expect(shown.length, 29);
      expect(shown.any((m) => m.userId == 'p01'), isFalse);
      expect(shown.any((m) => m.userId == 'p02'), isTrue);
      expect(filterMembers(members, filter: MemberFilter.skillUndecided, skillLevels: null), isEmpty);
    });
  });

  group('팀원 탭 30명', () {
    testWidgets('팀장: 칩 4개(전체·운영진 3·부상 2·실력 미정 20), 칩을 누르면 그 사람들만', (tester) async {
      await _pump(tester);
      expect(find.text(TeamTexts.memberCount(30)), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, TeamTexts.filterAll), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterStaff} 3'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterInjured} 2'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterSkillUndecided} 20'), findsOneWidget);

      await _tapChip(tester, '${TeamTexts.filterStaff} 3');
      expect(_shownIds(tester), unorderedEquals(['p01', 'p02', 'p03']));

      await _tapChip(tester, '${TeamTexts.filterInjured} 2');
      expect(_shownIds(tester), unorderedEquals(['p05', 'p13']));
      expect(find.byKey(const Key('member-injury-p05')), findsOneWidget);

      await _tapChip(tester, '${TeamTexts.filterSkillUndecided} 20');
      final undecided = _shownIds(tester);
      expect(undecided, isNot(contains('p01')));
      expect(undecided, contains('p11'));
      // 등급 이름은 목록 어디에도 없다 (Q-017)
      expect(find.text('아마추어'), findsNothing);
    });

    testWidgets('이름 검색: 일부 글자로 바로 걸러지고, 칩과 함께 적용, 없으면 안내', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(const Key('roster-search')), '김');
      await tester.pumpAndSettle();
      expect(_shownIds(tester), unorderedEquals(bigTeamKims));

      await _tapChip(tester, '${TeamTexts.filterInjured} 2');
      expect(_shownIds(tester), ['p13']);

      await tester.enterText(find.byKey(const Key('roster-search')), '없는 사람');
      await tester.pumpAndSettle();
      expect(_shownIds(tester), isEmpty);
      expect(find.byKey(const Key('roster-no-match')), findsOneWidget);
      expect(find.text(TeamTexts.noMemberMatch), findsOneWidget);
      // "팀원 30명"은 그대로 (전체 수)
      expect(find.text(TeamTexts.memberCount(30)), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-clear')));
      await tester.pumpAndSettle();
      expect(_shownIds(tester), unorderedEquals(['p05', 'p13']));
    });

    testWidgets('팀원에게는 "실력 미정" 칩이 없다 (Entitlements, Q-017)', (tester) async {
      await _pump(tester, role: TeamRole.member, me: 'p10');
      expect(find.widgetWithText(ChoiceChip, TeamTexts.filterAll), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterStaff} 3'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterInjured} 2'), findsOneWidget);
      expect(find.textContaining(TeamTexts.filterSkillUndecided), findsNothing);
    });

    testWidgets('운영진도 "실력 미정" 칩을 본다', (tester) async {
      await _pump(tester, role: TeamRole.manager, me: 'p02');
      expect(find.widgetWithText(ChoiceChip, '${TeamTexts.filterSkillUndecided} 20'), findsOneWidget);
    });
  });
}
