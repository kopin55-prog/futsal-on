import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/presentation/admin_tab.dart';
import 'package:futsal_on/features/membership/domain/join_decision.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../../support/big_team.dart';
import '../../support/fakes.dart';

/// 관리 탭 큰 팀 (Q-079 3번 c·f): 가입 신청 30개 여러 명 골라 한 번에 승인·거절, 팀원 관리 이름 검색.
List<IncomingJoinRequest> _requests(int n) => [
  for (var i = 1; i <= n; i++)
    IncomingJoinRequest(
      requestId: 'r$i',
      userId: 'x$i',
      displayName: '신청자$i',
      createdAt: DateTime.utc(2026, 11, 1).add(Duration(minutes: i)),
    ),
];

Future<TestServices> _open(WidgetTester tester, {TeamRole role = TeamRole.owner, String me = 'p01'}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(teams: [bigTeamSummary(role)], members: {'a': bigTeam()})..currentUserId = me;
  t.membership.incoming = _requests(30);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminTab(
          services: t.services,
          team: bigTeamSummary(role),
          viewer: Viewer(userId: me, role: role),
          onTeamChanged: () async {},
          onDissolved: () async {},
        ),
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

String _count(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('request-selection-count'))).data!;

void main() {
  group('가입 신청 여러 개 한 번에', () {
    testWidgets('체크로 고르고 [고른 사람 승인] → 확인 → 서버 한 번 호출, 모두 되면 짧은 안내', (tester) async {
      final t = await _open(tester);
      expect(find.byKey(const Key('request-r30')), findsOneWidget);
      expect(_count(tester), TeamTexts.selectedCount(0));
      expect(tester.widget<FilledButton>(find.byKey(const Key('approve-many'))).onPressed, isNull);

      await _tapKey(tester, 'request-pick-r2');
      await _tapKey(tester, 'request-pick-r5');
      // 줄을 눌러도 고른다
      await _tapKey(tester, 'request-r9');
      expect(_count(tester), TeamTexts.selectedCount(3));

      await _tapKey(tester, 'approve-many');
      expect(find.text(TeamTexts.confirmApproveMany(3)), findsOneWidget);
      await _tapKey(tester, 'confirm-ok');

      expect(t.membership.calls, ['decide-many:a:r2,r5,r9:true']);
      expect(find.text(TeamTexts.approvedMany(3)), findsOneWidget);
      expect(find.byKey(const Key('decide-many-result')), findsNothing);
      expect(find.byKey(const Key('request-r2')), findsNothing);
      expect(find.byKey(const Key('request-r3')), findsOneWidget);
      expect(_count(tester), TeamTexts.selectedCount(0));
    });

    testWidgets('정원 초과 등 일부만 되면 결과 창: 승인 수 + 못 한 이유 + 대기로 남음', (tester) async {
      final t = await _open(tester);
      t.membership.bulkOutcomes = {
        'r3': JoinDecisionOutcome.teamFull,
        'r4': JoinDecisionOutcome.teamFull,
        'r5': JoinDecisionOutcome.teamLimitReached,
        'r6': JoinDecisionOutcome.alreadyDecided,
      };
      for (final r in ['r1', 'r2', 'r3', 'r4', 'r5', 'r6']) {
        await _tapKey(tester, 'request-pick-$r');
      }
      await _tapKey(tester, 'approve-many');
      await _tapKey(tester, 'confirm-ok');

      expect(find.byKey(const Key('decide-many-result')), findsOneWidget);
      expect(find.text(TeamTexts.partialResultTitle), findsOneWidget);
      final body = tester.widget<Text>(
        find.descendant(of: find.byKey(const Key('decide-many-result')), matching: find.byType(Text)).at(1),
      ).data!;
      expect(body, contains(TeamTexts.approvedMany(2)));
      expect(body, contains(TeamTexts.skippedTeamFull(2)));
      expect(body, contains(TeamTexts.skippedTeamLimit(1)));
      expect(body, contains(TeamTexts.skippedAlreadyDecided(1)));
      expect(body, contains(TeamTexts.skippedStayPending));
      await tester.tap(find.text(TeamTexts.confirm));
      await tester.pumpAndSettle();
      // 건너뛴 신청은 그대로 남아 있다
      expect(find.byKey(const Key('request-r1')), findsNothing);
      expect(find.byKey(const Key('request-r3')), findsOneWidget);
      expect(find.byKey(const Key('request-r5')), findsOneWidget);
    });

    testWidgets('"모두 고르기" 뒤 [고른 사람 거절] → 확인 → 30개 한 번에, 취소하면 아무 일 없음', (tester) async {
      final t = await _open(tester);
      await _tapKey(tester, 'request-selection-all');
      expect(_count(tester), TeamTexts.selectedCount(30));
      expect(tester.widget<TextButton>(find.byKey(const Key('request-selection-all'))).onPressed, isNull);

      await _tapKey(tester, 'reject-many');
      expect(find.text(TeamTexts.confirmRejectMany(30)), findsOneWidget);
      await tester.tap(find.text(TeamTexts.cancel));
      await tester.pumpAndSettle();
      expect(t.membership.calls, isEmpty);
      expect(_count(tester), TeamTexts.selectedCount(30));

      await _tapKey(tester, 'reject-many');
      await _tapKey(tester, 'confirm-ok');
      expect(t.membership.calls.single, startsWith('decide-many:a:r1,r2,'));
      expect(t.membership.calls.single, endsWith(':false'));
      expect(find.text(TeamTexts.rejectedMany(30)), findsOneWidget);
      expect(find.text(TeamTexts.noRequests), findsOneWidget);
    });

    testWidgets('한 명씩 승인·거절 버튼은 그대로', (tester) async {
      final t = await _open(tester);
      await _tapKey(tester, 'approve-r1');
      await _tapKey(tester, 'reject-r2');
      expect(t.membership.calls, ['decide:r1:true', 'decide:r2:false']);
    });
  });

  group('팀원 관리 이름 검색', () {
    testWidgets('팀장: 검색으로 거르고, 없으면 안내, 지우면 모두', (tester) async {
      await _open(tester);
      await tester.ensureVisible(find.byKey(const Key('manage-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manage-p30')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('manage-search')), '김');
      await tester.pumpAndSettle();
      for (final id in bigTeamKims) {
        expect(find.byKey(Key('manage-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('manage-p02')), findsNothing);
      // 자기 자신(p01 팀장)에게는 메뉴 없음, 다른 사람은 있음
      expect(find.byKey(const Key('manage-menu-p01')), findsNothing);
      expect(find.byKey(const Key('manage-menu-p07')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('manage-search')), '없는 사람');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manage-no-match')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('manage-search')), matching: find.byKey(const Key('search-clear'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manage-p02')), findsOneWidget);
    });

    testWidgets('운영진에게는 팀원 관리(검색 포함)가 없다', (tester) async {
      await _open(tester, role: TeamRole.manager, me: 'p02');
      expect(find.byKey(const Key('manage-search')), findsNothing);
      expect(find.text(TeamTexts.membersSection), findsNothing);
    });
  });
}
