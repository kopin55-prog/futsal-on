import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/admin/presentation/admin_texts.dart';
import 'package:futsal_on/features/admin/presentation/skill_levels_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/big_team.dart';
import '../../support/fakes.dart';

/// 실력 등급 화면: 검색 + "미정만 보기" + 여러 명 골라 한 번에 지정 (Q-079 3번 b), 팀원 30명 기준.
Future<TestServices> _open(WidgetTester tester, {TeamRole role = TeamRole.owner, String me = 'p01'}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [bigTeamSummary(role)], members: {'a': bigTeam()})..currentUserId = me;
  // 10명은 등급 있음 → 미정 20명
  t.admin.levels = {for (var i = 1; i <= 10; i++) bigTeamId(i): SkillLevel.amateur};
  await tester.pumpWidget(
    MaterialApp(
      home: SkillLevelsScreen(
        admin: t.admin,
        teams: t.teams,
        entitlements: t.services.entitlements,
        viewer: Viewer(userId: me, role: role),
        team: bigTeamSummary(role),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

List<String> _rows(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.startsWith("[<'skill-p")),
  ))
    '${tile.key}'.replaceAll("[<'skill-", '').replaceAll("'>]", ''),
];

String _count(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('skill-selection-count'))).data!;

void main() {
  testWidgets('"미정만 보기 20" → 미정인 사람만, 검색과 함께', (tester) async {
    await _open(tester);
    expect(find.widgetWithText(ChoiceChip, '${AdminTexts.undecidedOnly} 20'), findsOneWidget);
    expect(_rows(tester).length, 30);

    await tester.tap(find.byKey(const Key('skill-filter-1')));
    await tester.pumpAndSettle();
    final shown = _rows(tester);
    expect(shown.length, 20);
    expect(shown, isNot(contains('p01')));

    await tester.enterText(find.byKey(const Key('skill-search')), '김');
    await tester.pumpAndSettle();
    // 김씨 5명 중 등급이 있는 p01·p07 을 뺀 3명
    expect(_rows(tester), unorderedEquals(['p13', 'p19', 'p25']));

    await tester.enterText(find.byKey(const Key('skill-search')), '없음');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-no-match')), findsOneWidget);
  });

  testWidgets('여러 명 체크 → [등급 한 번에 지정] → 등급 고르기 → 서버 한 번 호출, 화면 반영', (tester) async {
    final t = await _open(tester);
    expect(_count(tester), TeamTexts.selectedCount(0));
    expect(tester.widget<FilledButton>(find.byKey(const Key('skill-set-many'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('skill-pick-p11')));
    await tester.tap(find.byKey(const Key('skill-pick-p12')));
    // 줄을 눌러도 고른다
    await tester.tap(find.byKey(const Key('skill-p13')));
    await tester.pumpAndSettle();
    expect(_count(tester), TeamTexts.selectedCount(3));

    await tester.tap(find.byKey(const Key('skill-set-many')));
    await tester.pumpAndSettle();
    expect(find.text(AdminTexts.pickLevelTitle(3)), findsOneWidget);
    await tester.tap(find.byKey(const Key('skill-many-pro')));
    await tester.pumpAndSettle();

    expect(_skillCall(t), 'p11,p12,p13:pro');
    expect(find.text(AdminTexts.levelsSaved(3)), findsOneWidget);
    expect(_count(tester), TeamTexts.selectedCount(0));
    expect(find.widgetWithText(ChoiceChip, '${AdminTexts.undecidedOnly} 17'), findsOneWidget);
    expect(tester.widget<DropdownButton<SkillLevel>>(find.byKey(const Key('skill-select-p11'))).value, SkillLevel.pro);
  });

  testWidgets('"모두 고르기"는 지금 보이는 사람만 (미정만 보기 + 검색), 선택 해제', (tester) async {
    final t = await _open(tester);
    await tester.tap(find.byKey(const Key('skill-filter-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('skill-search')), '김');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-selection-all')));
    await tester.pumpAndSettle();
    expect(_count(tester), TeamTexts.selectedCount(3));
    // 다 골랐으면 "모두 고르기"는 꺼진다
    expect(tester.widget<TextButton>(find.byKey(const Key('skill-selection-all'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('skill-set-many')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-many-beginner')));
    await tester.pumpAndSettle();
    expect(_skillCall(t), 'p13,p19,p25:beginner');
    // 미정만 보기 중이라 등급이 생긴 사람은 목록에서 빠진다
    expect(_rows(tester), isEmpty);

    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-selection-all')));
    await tester.pumpAndSettle();
    expect(_count(tester), TeamTexts.selectedCount(17));
    await tester.tap(find.byKey(const Key('skill-selection-clear')));
    await tester.pumpAndSettle();
    expect(_count(tester), TeamTexts.selectedCount(0));
  });

  testWidgets('서버가 거절하면(하나라도 팀원이 아님 등) 아무것도 안 바뀌고 안내', (tester) async {
    final t = await _open(tester);
    await tester.tap(find.byKey(const Key('skill-pick-p11')));
    await tester.pumpAndSettle();
    t.admin.nextFailure = const ServerFailure(ServerErrorCode.targetNotMember);
    await tester.tap(find.byKey(const Key('skill-set-many')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-many-semipro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-error')), findsOneWidget);
    expect(t.admin.levels.containsKey('p11'), isFalse);
    expect(find.widgetWithText(ChoiceChip, '${AdminTexts.undecidedOnly} 20'), findsOneWidget);
  });

  testWidgets('"미정"으로 한 번에 되돌리면 줄이 사라진다 (미정 수가 는다)', (tester) async {
    final t = await _open(tester);
    await tester.tap(find.byKey(const Key('skill-pick-p01')));
    await tester.tap(find.byKey(const Key('skill-pick-p02')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-set-many')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-many-undecided')));
    await tester.pumpAndSettle();
    expect(_skillCall(t), 'p01,p02:undecided');
    expect(find.widgetWithText(ChoiceChip, '${AdminTexts.undecidedOnly} 22'), findsOneWidget);
  });
}

/// 여러 명 호출 한 번: "ID들(가나다순),등급" (화면은 이름 순으로 보내므로 순서는 보지 않는다)
String _skillCall(TestServices t) {
  final parts = t.admin.calls.single.split(':');
  expect(parts[0], 'skills');
  return '${(parts[1].split(',')..sort()).join(',')}:${parts[2]}';
}
