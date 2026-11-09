import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/admin/presentation/admin_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '일번'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '이번'),
];

TeamSummary _team(TeamRole role, {ClockTime? start}) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: role,
  isRecruiting: true,
  schedule: RegularSchedule(weekday: start == null ? null : 3, start: start),
);

Future<TestServices> _openAdmin(
  WidgetTester tester, {
  TeamRole role = TeamRole.owner,
  String userId = 'me',
  ClockTime? start,
}) async {
  _tall(tester);
  final t = TestServices(teams: [_team(role, start: start)], members: {'a': _members});
  await tester.pumpWidget(
    MaterialApp(
      home: TeamHomeScreen(services: t.services, userId: userId, onSignOut: () async {}),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(TeamTexts.tabAdmin));
  await tester.pumpAndSettle();
  return t;
}

void main() {
  group('관리 탭 팀 설정 메뉴 (Entitlements)', () {
    testWidgets('팀장·운영진은 네 메뉴가 모두 보인다', (tester) async {
      await _openAdmin(tester);
      for (final k in ['open-team-info', 'open-match-settings', 'open-skill-levels', 'open-pairing-rules']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });
    testWidgets('운영진도 같다', (tester) async {
      await _openAdmin(tester, role: TeamRole.manager, userId: 'm1');
      for (final k in ['open-team-info', 'open-match-settings', 'open-skill-levels', 'open-pairing-rules']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });
  });

  group('내보내기는 팀장만 (Q-074 덧붙임, permissions.md)', () {
    testWidgets('팀장: 팀원 메뉴에 내보내기가 있다', (tester) async {
      await _openAdmin(tester);
      await tester.ensureVisible(find.byKey(const Key('manage-menu-u1')));
      await tester.tap(find.byKey(const Key('manage-menu-u1')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.removeMember), findsOneWidget);
    });
    testWidgets('운영진: 팀원 목록·메뉴·내보내기 버튼이 없다', (tester) async {
      await _openAdmin(tester, role: TeamRole.manager, userId: 'm1');
      expect(find.byKey(const Key('manage-u1')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('manage-menu-'),
        ),
        findsNothing,
      );
      expect(find.text(TeamTexts.removeMember), findsNothing);
    });
  });

  group('팀 정보 수정', () {
    testWidgets('팀장: 이름을 바꾸면 로고 미리보기가 따라가고, 로고 글자는 보내지 않는다 (Q-047 서버 트리거)', (tester) async {
      final t = await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-team-info')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-info-name')), ' 번개   FC ');
      await tester.pump();
      expect(
        find.descendant(of: find.byKey(const Key('team-info-logo-preview')), matching: find.text('번개')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('team-info-recruiting')));
      await tester.pump();
      expect(find.text(AdminTexts.recruitingOffNote), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-info-save')));
      await tester.pumpAndSettle();
      expect(t.admin.calls, ['info:a']);
      expect(t.admin.lastInfo!.name, '번개 FC');
      expect(t.admin.lastInfo!.isRecruiting, isFalse);
      expect(t.admin.lastInfo!.logoText, isNull);
      // 저장 후 관리 탭으로 돌아온다
      expect(find.byKey(const Key('open-team-info')), findsOneWidget);
    });

    testWidgets('팀장: 로고 글자를 바꾸면 보낸다, 3자는 막는다, 비우면 새 이름 기본값', (tester) async {
      final t = await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-team-info')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-info-logo-text')), 'ABC');
      await tester.pump();
      expect(find.text(TeamTexts.logoTooLong), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-info-save')));
      await tester.pumpAndSettle();
      expect(t.admin.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('team-info-logo-text')), '');
      await tester.enterText(find.byKey(const Key('team-info-name')), '천둥FC');
      await tester.pump();
      await tester.tap(find.byKey(const Key('team-info-save')));
      await tester.pumpAndSettle();
      expect(t.admin.lastInfo!.logoText, '천둥');
    });

    testWidgets('운영진에게는 로고 글자 칸이 없다 (Q-014)', (tester) async {
      await _openAdmin(tester, role: TeamRole.manager, userId: 'm1');
      await tester.tap(find.byKey(const Key('open-team-info')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-info-logo-text')), findsNothing);
      expect(find.byKey(const Key('team-info-logo-owner-only')), findsOneWidget);
    });

    testWidgets('이름이 비면 저장하지 않는다, 서버 오류는 안내', (tester) async {
      final t = await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-team-info')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-info-name')), '  ');
      await tester.tap(find.byKey(const Key('team-info-save')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.nameRequired), findsOneWidget);
      expect(t.admin.calls, isEmpty);

      await tester.enterText(find.byKey(const Key('team-info-name')), '코코FC');
      t.admin.nextFailure = const ServerFailure(ServerErrorCode.deadlineBeforeAutoCreate);
      await tester.tap(find.byKey(const Key('team-info-save')));
      await tester.pumpAndSettle();
      expect(find.text(AdminTexts.deadlineBeforeAutoCreate), findsOneWidget);
    });
  });

  group('경기 설정', () {
    testWidgets('대기 사용 켜고 참석 인원 → 정원으로 저장 (Q-073 7번)', (tester) async {
      final t = await _openAdmin(tester, start: const ClockTime(20, 0));
      await tester.tap(find.byKey(const Key('open-match-settings')));
      await tester.pumpAndSettle();
      // 기본: 대기 사용 꺼짐 = 정원 없음(모두 참석)
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('settings-waitlist'))).value, isFalse);
      expect(find.text(AdminTexts.useWaitlistOffNote), findsOneWidget);
      expect(find.byKey(const Key('settings-capacity')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-waitlist')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('settings-capacity')), '12');
      await tester.pump();
      expect(find.text(AdminTexts.waitlistFrom(12)), findsOneWidget);
      await tester.enterText(find.byKey(const Key('settings-deadline')), '24');
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(t.admin.savedSettings, const MatchSettings(
        capacity: 12,
        rsvpDeadlineHours: 24,
        autoCreateDaysBefore: 6,
        autoCreateTime: ClockTime(9, 0),
      ));
      expect(find.text(AdminTexts.saved), findsOneWidget);
    });

    testWidgets('미투표 알림: 기본 2시간 전, 끄기로 바꿔 저장 (Q-072 1번)', (tester) async {
      final t = await _openAdmin(tester, start: const ClockTime(20, 0));
      await tester.tap(find.byKey(const Key('open-match-settings')));
      await tester.pumpAndSettle();
      expect(find.text(AdminTexts.reminderOption(2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AdminTexts.reminderOption(null)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(t.admin.savedSettings?.rsvpReminderHours, isNull);
      expect(t.admin.savedSettings?.rsvpDeadlineHours, 2);
    });

    testWidgets('마감이 자동 생성보다 앞서면 안내하고 저장 버튼이 꺼진다', (tester) async {
      final t = await _openAdmin(tester, start: const ClockTime(20, 0));
      await tester.tap(find.byKey(const Key('open-match-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settings-auto-days')), '0');
      await tester.enterText(find.byKey(const Key('settings-deadline')), '11');
      await tester.pump();
      expect(find.byKey(const Key('settings-error-deadlineBeforeAutoCreate')), findsOneWidget);
      final save = tester.widget<FilledButton>(find.byKey(const Key('settings-save')));
      expect(save.onPressed, isNull);
      await tester.enterText(find.byKey(const Key('settings-deadline')), '10');
      await tester.pump();
      expect(find.byKey(const Key('settings-error-deadlineBeforeAutoCreate')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(t.admin.calls, ['settings:a']);
    });

    testWidgets('대기 사용을 끄면 정원 없음으로 저장', (tester) async {
      final t = await _openAdmin(tester, start: const ClockTime(20, 0));
      t.admin.settings = MatchSettings.defaults.copyWith(capacity: () => 10);
      await tester.tap(find.byKey(const Key('open-match-settings')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('settings-waitlist'))).value, isTrue);
      await tester.tap(find.byKey(const Key('settings-waitlist')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(t.admin.savedSettings?.capacity, isNull);
    });

    testWidgets('정원 0명은 막는다', (tester) async {
      await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-match-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-waitlist')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('settings-capacity')), '0');
      await tester.pump();
      expect(find.byKey(const Key('settings-error-capacityRange')), findsOneWidget);
    });
  });

  group('실력 등급', () {
    testWidgets('팀장은 본인 포함 모두의 등급을 보고 고른다, 줄이 없으면 미정', (tester) async {
      final t = await _openAdmin(tester);
      t.admin.levels = {'u1': SkillLevel.pro};
      await tester.tap(find.byKey(const Key('open-skill-levels')));
      await tester.pumpAndSettle();
      for (final m in _members) {
        expect(find.byKey(Key('skill-${m.userId}')), findsOneWidget);
      }
      expect(find.text(AdminTexts.skillLevel(SkillLevel.pro)), findsOneWidget);
      expect(find.text(AdminTexts.skillLevel(SkillLevel.undecided)), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('skill-select-u2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AdminTexts.skillLevel(SkillLevel.semipro)).last);
      await tester.pumpAndSettle();
      expect(t.admin.calls, ['skill:u2:semipro']);
    });

    testWidgets('저장 실패면 이전 등급으로 돌아가고 안내', (tester) async {
      final t = await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-skill-levels')));
      await tester.pumpAndSettle();
      t.admin.nextFailure = const ServerFailure(ServerErrorCode.notPermitted);
      await tester.tap(find.byKey(const Key('skill-select-u1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AdminTexts.skillLevel(SkillLevel.beginner)).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-error')), findsOneWidget);
      expect(find.text(AdminTexts.skillLevel(SkillLevel.beginner)), findsNothing);
    });
  });

  group('그룹·라이벌', () {
    testWidgets('그룹 저장 후, 같은 두 사람을 라이벌로 켜려 하면 이유를 알려주고 저장 버튼이 꺼진다', (tester) async {
      final t = await _openAdmin(tester);
      await tester.tap(find.byKey(const Key('open-pairing-rules')));
      await tester.pumpAndSettle();
      expect(find.text(AdminTexts.noRules), findsOneWidget);

      // 그룹: 1명만 고르면 저장 불가
      await tester.tap(find.byKey(const Key('add-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-u1')));
      await tester.pump();
      expect(find.text(AdminTexts.pickMembers), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-u2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rule-dialog-save')));
      await tester.pumpAndSettle();
      expect(t.admin.calls, ['save-rule:rule-1:group:u2,u1:true']);
      expect(find.byKey(const Key('rule-rule-1')), findsOneWidget);

      // 라이벌 u1·u2: 모순 (명단 순서: 팀원은 이름순이라 이번 → 일번)
      await tester.tap(find.byKey(const Key('add-rival')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-u1')));
      await tester.tap(find.byKey(const Key('pick-u2')));
      await tester.pump();
      expect(find.text(AdminTexts.conflict('이번', '일번')), findsOneWidget);
      final save = tester.widget<FilledButton>(find.byKey(const Key('rule-dialog-save')));
      expect(save.onPressed, isNull);

      // 끈 채로는 저장 가능
      await tester.tap(find.byKey(const Key('rule-dialog-enabled')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rule-dialog-save')));
      await tester.pumpAndSettle();
      expect(t.admin.calls.last, 'save-rule:rule-2:rival:u2,u1:false');

      // 켜기 스위치도 막는다
      await tester.tap(find.byKey(const Key('rule-enabled-rule-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pairing-error')), findsOneWidget);
      expect(t.admin.calls.where((c) => c.startsWith('enable-rule')), isEmpty);

      // 그룹을 끄면 라이벌을 켤 수 있다
      await tester.tap(find.byKey(const Key('rule-enabled-rule-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule-enabled-rule-2')));
      await tester.pumpAndSettle();
      expect(t.admin.calls.sublist(t.admin.calls.length - 2), [
        'enable-rule:rule-1:false',
        'enable-rule:rule-2:true',
      ]);
    });

    testWidgets('삭제는 확인 후, 서버 모순 거절은 안내', (tester) async {
      final t = await _openAdmin(tester);
      t.admin.rules = [
        const PairingRule(id: 'g1', kind: PairingKind.group, enabled: false, userIds: ['u1', 'u2']),
      ];
      await tester.tap(find.byKey(const Key('open-pairing-rules')));
      await tester.pumpAndSettle();
      t.admin.nextFailure = const ServerFailure(ServerErrorCode.pairingRuleConflict);
      await tester.tap(find.byKey(const Key('rule-enabled-g1')));
      await tester.pumpAndSettle();
      expect(find.text(AdminTexts.conflictGeneric), findsOneWidget);

      await tester.tap(find.byKey(const Key('rule-delete-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await tester.pumpAndSettle();
      expect(t.admin.calls.last, 'delete-rule:g1');
      expect(find.text(AdminTexts.noRules), findsOneWidget);
    });
  });
}
