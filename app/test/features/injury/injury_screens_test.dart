import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/auth/presentation/auth_texts.dart';
import 'package:futsal_on/features/injury/domain/injury_models.dart';
import 'package:futsal_on/features/injury/presentation/injury_report_screen.dart';
import 'package:futsal_on/features/injury/presentation/injury_texts.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/presentation/common_widgets.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _members = [
  MemberEntry(userId: 'o', role: TeamRole.owner, displayName: '팀장'),
  MemberEntry(userId: 'me', role: TeamRole.member, displayName: '나'),
];

TeamSummary _team() => const TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: TeamRole.member,
  isRecruiting: true,
);

TeamMatch _match(String id, {Duration startIn = const Duration(days: 3), Duration deadlineBefore = const Duration(hours: 2)}) {
  final start = DateTime.now().toUtc().add(startIn);
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.auto,
    status: MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(deadlineBefore),
    capacity: 12,
  );
}

/// 오늘(한국 날짜)을 UTC 자정 값으로 (부상 날짜 칸과 같은 모양)
DateTime _todayKst() {
  final d = Kst.dateOf(DateTime.now());
  return DateTime.utc(d.year, d.month, d.day);
}

Future<TestServices> _open(WidgetTester tester, {void Function(TestServices t)? setup, bool myTab = true}) async {
  _tall(tester);
  final t = TestServices(teams: [_team()], members: {'a': _members})..currentUserId = 'me';
  t.injuries.today = _todayKst();
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  if (myTab) {
    await tester.tap(find.text(TeamTexts.tabMy));
    await tester.pumpAndSettle();
  }
  return t;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('부상 동의·등록 (2-1·2-2)', () {
    testWidgets('동의가 없으면 동의 화면(consent-texts 문구), 동의 안 하면 등록 화면으로 안 감', (tester) async {
      final t = await _open(tester);
      expect(find.byKey(const Key('injury-withdraw')), findsNothing);
      await _tap(tester, 'injury-report');
      expect(find.text(ConsentTexts.injuryTitle), findsOneWidget);
      for (final (label, value) in ConsentTexts.injuryTable) {
        expect(find.text(label), findsOneWidget);
        expect(find.text(value), findsOneWidget);
      }
      expect(find.text(ConsentTexts.injuryWithdrawNote), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(InjuryReportScreen), findsNothing);
      expect(t.injuries.calls, isEmpty);
      expect(find.byKey(const Key('injury-report')), findsOneWidget);
    });

    testWidgets('동의 → 등록 화면 → 기간·메모 등록 → 내 부상 카드, 동의 철회 메뉴가 생김', (tester) async {
      final t = await _open(tester);
      await _tap(tester, 'injury-report');
      await _tap(tester, 'injury-consent-agree');
      expect(t.injuries.calls, ['agree']);
      expect(find.byType(InjuryReportScreen), findsOneWidget);
      await _tap(tester, 'injury-weeks-4');
      await tester.enterText(find.byKey(const Key('injury-memo')), '  발목​ ');
      await tester.pump();
      await _tap(tester, 'injury-report-submit');
      expect(t.injuries.calls, ['agree', 'report:4:발목']);
      expect(find.text(InjuryTexts.remaining(4)), findsOneWidget);
      expect(find.byKey(const Key('injury-memo-text')), findsOneWidget);
      expect(find.text('발목'), findsOneWidget);
      expect(find.byKey(const Key('injury-withdraw')), findsOneWidget);
    });

    testWidgets('이미 동의했으면 동의 화면 없이 바로 등록 화면, 메모 없이 등록', (tester) async {
      final t = await _open(tester, setup: (t) => t.injuries.consented.add('me'));
      await _tap(tester, 'injury-report');
      expect(find.text(ConsentTexts.injuryTitle), findsNothing);
      await _tap(tester, 'injury-report-submit');
      expect(t.injuries.calls, ['report:${InjuryRules.defaultWeeks}:']);
      expect(find.text(InjuryTexts.remaining(InjuryRules.defaultWeeks)), findsOneWidget);
    });

    testWidgets('메모 21자는 등록 불가, 이모지 1개 = 1자', (tester) async {
      await _open(tester, setup: (t) => t.injuries.consented.add('me'));
      await _tap(tester, 'injury-report');
      await tester.enterText(find.byKey(const Key('injury-memo')), '가' * 21);
      await tester.pump();
      expect(find.text(InjuryTexts.memoError(InjuryMemoError.tooLong)), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byKey(const Key('injury-report-submit'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('injury-memo')), '${'가' * 19}👨‍👩‍👧');
      await tester.pump();
      expect(find.text(InjuryTexts.memoError(InjuryMemoError.tooLong)), findsNothing);
      expect(find.text('20/20'), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byKey(const Key('injury-report-submit'))).onPressed, isNotNull);
    });
  });

  group('등록 직후 참석 안내 (S4-08)', () {
    testWidgets('참석으로 되어 있는 경기가 있으면 안내, [불참으로 바꾸기]는 마감 전 경기만', (tester) async {
      final t = await _open(
        tester,
        setup: (t) {
          t.injuries.consented.add('me');
          t.matches.items.addAll([
            _match('open'),
            _match('closed', startIn: const Duration(hours: 1), deadlineBefore: const Duration(hours: 2)),
          ]);
          t.attendance.seed('open', 'me', AttendanceState.attending);
          t.attendance.seed('closed', 'me', AttendanceState.attending);
        },
      );
      await _tap(tester, 'injury-report');
      await _tap(tester, 'injury-report-submit');
      expect(find.byKey(const Key('injury-attending-dialog')), findsOneWidget);
      expect(find.text(InjuryTexts.stillAttendingTitle), findsOneWidget);
      expect(find.text(InjuryTexts.closedMatchesNote), findsOneWidget);
      await _tap(tester, 'injury-change-decline');
      expect(t.attendance.calls, ['respond:open:false']);
      expect(t.attendance.byMatch['open']!.single.state, AttendanceState.declined);
      expect(t.attendance.byMatch['closed']!.single.state, AttendanceState.attending);
      expect(find.text(InjuryTexts.remaining(InjuryRules.defaultWeeks)), findsOneWidget);
    });

    testWidgets('[그대로 두기]면 응답이 바뀌지 않고, 참석 경기가 없으면 안내도 없음', (tester) async {
      final t = await _open(
        tester,
        setup: (t) {
          t.injuries.consented.add('me');
          t.matches.items.add(_match('open'));
          t.attendance.seed('open', 'me', AttendanceState.waitlisted);
        },
      );
      await _tap(tester, 'injury-report');
      await _tap(tester, 'injury-report-submit');
      await _tap(tester, 'injury-keep-attending');
      expect(t.attendance.calls, isEmpty);

      // 회복 후 다시 등록: 이번에는 불참 응답만 있음 → 안내 없음
      await _tap(tester, 'injury-recover');
      t.attendance.byMatch['open']!.clear();
      t.attendance.seed('open', 'me', AttendanceState.declined);
      await _tap(tester, 'injury-report');
      await _tap(tester, 'injury-report-submit');
      expect(find.byKey(const Key('injury-attending-dialog')), findsNothing);
    });
  });

  group('내 부상 카드 (2-3)', () {
    testWidgets('남은 W·메모 + 연장·메모 수정·회복', (tester) async {
      final t = await _open(
        tester,
        setup: (t) => t.injuries.seedActive('me', expectedReturnOn: _todayKst().add(const Duration(days: 10)), memo: '발목'),
      );
      expect(find.text(InjuryTexts.remaining(2)), findsOneWidget); // 10일 남음 = 2W (S4-04 올림)
      expect(find.text('발목'), findsOneWidget);

      await _tap(tester, 'injury-extend-1');
      expect(t.injuries.calls, ['extend:1']);
      expect(find.text(InjuryTexts.remaining(3)), findsOneWidget);
      await _tap(tester, 'injury-extend-2');
      expect(find.text(InjuryTexts.remaining(5)), findsOneWidget);

      await _tap(tester, 'injury-edit-memo');
      await tester.enterText(find.byKey(const Key('injury-memo')), '발목 인대');
      await tester.pump();
      await _tap(tester, 'injury-memo-save');
      expect(t.injuries.calls.last, 'memo:발목 인대');
      expect(find.text('발목 인대'), findsOneWidget);

      await _tap(tester, 'injury-recover');
      expect(t.injuries.calls.last, 'recover');
      expect(find.byKey(const Key('injury-remaining')), findsNothing);
      expect(find.byKey(const Key('injury-report')), findsOneWidget);
      // 동의는 그대로 → 철회 메뉴 유지
      expect(find.byKey(const Key('injury-withdraw')), findsOneWidget);
    });

    testWidgets('복귀일이 지났으면 0W (마이너스 없음, 자동 해제 없음)', (tester) async {
      await _open(
        tester,
        setup: (t) => t.injuries.seedActive('me', expectedReturnOn: _todayKst().subtract(const Duration(days: 3))),
      );
      expect(find.text(InjuryTexts.remaining(0)), findsOneWidget);
      expect(find.byKey(const Key('injury-recover')), findsOneWidget);
    });
  });

  group('부상 정보 동의 철회 (2-4)', () {
    testWidgets('확인 창 → 철회하면 부상 카드가 사라지고, 다시 [부상 등록]은 동의 화면부터', (tester) async {
      final t = await _open(
        tester,
        setup: (t) => t.injuries.seedActive('me', expectedReturnOn: _todayKst().add(const Duration(days: 7))),
      );
      await _tap(tester, 'injury-withdraw');
      expect(find.text(InjuryTexts.withdrawConfirm), findsOneWidget);
      await _tap(tester, 'injury-withdraw-confirm');
      expect(t.injuries.calls, ['withdraw']);
      expect(t.injuries.active, isEmpty);
      expect(find.byKey(const Key('injury-remaining')), findsNothing);
      expect(find.byKey(const Key('injury-withdraw')), findsNothing);
      await _tap(tester, 'injury-report');
      expect(find.text(ConsentTexts.injuryTitle), findsOneWidget);
    });

    testWidgets('확인 창에서 취소하면 그대로', (tester) async {
      final t = await _open(
        tester,
        setup: (t) => t.injuries.seedActive('me', expectedReturnOn: _todayKst().add(const Duration(days: 7))),
      );
      await _tap(tester, 'injury-withdraw');
      await tester.tap(find.text(InjuryTexts.cancel));
      await tester.pumpAndSettle();
      expect(t.injuries.calls, isEmpty);
      expect(find.byKey(const Key('injury-remaining')), findsOneWidget);
    });
  });

  group('참석 버튼 복귀 확인 창 (2-5)', () {
    Future<TestServices> openDetail(WidgetTester tester, {bool injured = true}) async {
      final t = await _open(
        tester,
        myTab: false,
        setup: (t) {
          t.matches.items.add(_match('m1'));
          if (injured) t.injuries.seedActive('me', expectedReturnOn: _todayKst());
        },
      );
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      return t;
    }

    testWidgets('부상 중 [참석] → "부상에서 복귀하셨나요?" 취소하면 응답·부상 그대로, 확인하면 참석 + 해제', (tester) async {
      final t = await openDetail(tester);
      await _tap(tester, 'rsvp-attend');
      expect(find.text(InjuryTexts.returnConfirmTitle), findsOneWidget);
      await _tap(tester, 'return-confirm-cancel');
      expect(t.attendance.byMatch['m1'] ?? const [], isEmpty);
      expect(t.injuries.active.containsKey('me'), isTrue);

      await _tap(tester, 'rsvp-attend');
      await _tap(tester, 'return-confirm-ok');
      expect(t.attendance.calls, ['respond:m1:true', 'respond:m1:true', 'respond:m1:true:vote']);
      expect(t.attendance.byMatch['m1']!.single.state, AttendanceState.attending);
      expect(t.injuries.active.containsKey('me'), isFalse);
    });

    testWidgets('부상 중 [불참]은 확인 창 없이, 부상 유지', (tester) async {
      final t = await openDetail(tester);
      await _tap(tester, 'rsvp-decline');
      expect(find.byKey(const Key('return-confirm-dialog')), findsNothing);
      expect(t.attendance.byMatch['m1']!.single.state, AttendanceState.declined);
      expect(t.injuries.active.containsKey('me'), isTrue);
    });

    testWidgets('부상이 없으면 확인 창 없이 참석', (tester) async {
      final t = await openDetail(tester, injured: false);
      await _tap(tester, 'rsvp-attend');
      expect(find.byKey(const Key('return-confirm-dialog')), findsNothing);
      expect(t.attendance.calls, ['respond:m1:true']);
    });
  });

  group('복귀 확인 알림을 눌렀을 때 (2-6)', () {
    AppNotification returnCheck(String matchId) => AppNotification(
      id: 'rc1',
      kind: NotificationKind.injuryReturnCheck,
      teamId: 'a',
      refType: NotificationRefType.match,
      refId: matchId,
      title: '코코FC',
      body: InjuryTexts.returnCheckBody,
      createdAt: DateTime.now(),
    );

    Future<TestServices> openFromNotification(
      WidgetTester tester, {
      TeamMatch? match,
      bool injured = true,
      AttendanceState? responded,
    }) async {
      final m = match ?? _match('m1');
      final t = await _open(
        tester,
        myTab: false,
        setup: (t) {
          t.matches.items.add(m);
          if (injured) t.injuries.seedActive('me', expectedReturnOn: _todayKst());
          if (responded != null) t.attendance.seed(m.id, 'me', responded);
          t.notifications.items = [returnCheck(m.id)];
        },
      );
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-rc1')));
      await tester.pumpAndSettle();
      return t;
    }

    testWidgets('일정 상세 위에 창: [참석할게요] → 참석 + 해제 (via return_check)', (tester) async {
      final t = await openFromNotification(tester);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
      expect(find.byKey(const Key('return-check-dialog')), findsOneWidget);
      expect(find.text(InjuryTexts.returnCheckBody), findsWidgets);
      await _tap(tester, 'return-check-attend');
      expect(t.attendance.calls, ['respond:m1:true:notification']);
      expect(t.injuries.active.containsKey('me'), isFalse);
      expect(find.byKey(const Key('return-check-dialog')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('my-status'))).data, ScheduleTexts.state(AttendanceState.attending, null));
    });

    testWidgets('[아직 회복 중 +1W]·[+2W] → 연장 (via return_check), 응답 그대로', (tester) async {
      final t = await openFromNotification(tester);
      expect(find.text(InjuryTexts.returnCheckExtend(1)), findsOneWidget);
      expect(find.text(InjuryTexts.returnCheckExtend(2)), findsOneWidget);
      await _tap(tester, 'return-check-extend-2');
      expect(t.injuries.calls, ['extend:2:return_check']);
      expect(t.attendance.calls, isEmpty);
      expect(t.injuries.active['me']!.expectedReturnOn, _todayKst().add(const Duration(days: 14)));
    });

    testWidgets('[닫기] → 부상·응답 그대로', (tester) async {
      final t = await openFromNotification(tester);
      await _tap(tester, 'return-check-close');
      expect(t.injuries.calls, isEmpty);
      expect(t.attendance.calls, isEmpty);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
    });

    testWidgets('참석 마감이 지났으면 [참석할게요] 대신 "마감됐어요"', (tester) async {
      await openFromNotification(
        tester,
        match: _match('m1', startIn: const Duration(hours: 1), deadlineBefore: const Duration(hours: 2)),
      );
      expect(find.byKey(const Key('return-check-attend')), findsNothing);
      expect(find.text(InjuryTexts.returnCheckClosed), findsOneWidget);
      expect(find.byKey(const Key('return-check-extend-1')), findsOneWidget);
    });

    testWidgets('이미 회복했거나 그 일정에 응답했으면 창 없이 일정 상세만', (tester) async {
      await openFromNotification(tester, injured: false);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
      expect(find.byKey(const Key('return-check-dialog')), findsNothing);
    });

    testWidgets('부상 중이어도 그 일정에 이미 불참 응답했으면 창 없음', (tester) async {
      await openFromNotification(tester, responded: AttendanceState.declined);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
      expect(find.byKey(const Key('return-check-dialog')), findsNothing);
    });

    testWidgets('지워진 일정이면 이동하지 않음 (Q-041)', (tester) async {
      final t = await _open(
        tester,
        myTab: false,
        setup: (t) {
          t.injuries.seedActive('me', expectedReturnOn: _todayKst());
          t.notifications.items = [returnCheck('gone')];
        },
      );
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-rc1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-time')), findsNothing);
      expect(find.byKey(const Key('return-check-dialog')), findsNothing);
      expect(t.notifications.items.single.isRead, isTrue);
    });
  });

  test('Entitlements 한 곳에서: 다른 사람 버튼 없음', () {
    const e = Entitlements();
    const viewer = Viewer(userId: 'me', role: TeamRole.member);
    expect(e.canManageInjury(viewer, subjectUserId: 'other'), isFalse);
  });
}

