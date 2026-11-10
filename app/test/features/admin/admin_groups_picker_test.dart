import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/presentation/admin_texts.dart';
import 'package:futsal_on/features/admin/presentation/pairing_rule_edit_screen.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/domain/name_search.dart';

import '../../support/fakes.dart';

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '일번'),
];

TeamSummary _team(TeamRole role) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: role,
  isRecruiting: true,
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _openAdmin(WidgetTester tester, TeamRole role, String userId) async {
  _tall(tester);
  final t = TestServices(teams: [_team(role)], members: {'a': _members});
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: userId, onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(TeamTexts.tabAdmin));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(Key(key))).dy;

/// 사람 고르기 화면을 바로 띄운다. 저장하면 [onSaved].
Future<void> _pumpPicker(
  WidgetTester tester, {
  required List<MemberEntry> members,
  PairingRule initial = const PairingRule(id: null, kind: PairingKind.group, enabled: true, userIds: []),
  String? Function(PairingRule)? conflict,
  void Function(PairingRule?)? onSaved,
}) async {
  _tall(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final r = await Navigator.of(context).push<PairingRule>(
                MaterialPageRoute(
                  builder: (_) => PairingRuleEditScreen(
                    initial: initial,
                    members: members,
                    conflictMessage: conflict ?? (_) => null,
                  ),
                ),
              );
              onSaved?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

List<String> _visiblePicks(WidgetTester tester) => [
  for (final tile in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)))
    (tile.title! as Text).data!,
];

void main() {
  group('관리 탭 묶음 (6-2, 기획서 11장)', () {
    testWidgets('팀장: "팀장·운영진"(가입 신청 → 초대 → 팀 설정) 아래 "팀장만"(팀원 관리·해체)', (tester) async {
      await _openAdmin(tester, TeamRole.owner, 'me');
      expect(find.byKey(const Key('admin-group-staff')), findsOneWidget);
      expect(find.byKey(const Key('admin-group-owner')), findsOneWidget);
      expect(_y(tester, 'admin-group-staff') < _y(tester, 'issue-invite'), isTrue);
      expect(find.text(TeamTexts.requestsSection), findsOneWidget);
      expect(tester.getTopLeft(find.text(TeamTexts.requestsSection)).dy < _y(tester, 'issue-invite'), isTrue);
      expect(_y(tester, 'issue-invite') < _y(tester, 'open-skill-levels'), isTrue);
      // 팀 설정 순서: 실력 등급 → 경기 설정 → 투표 설정 → 그룹·라이벌 → 팀 정보·모집
      final settings = ['open-skill-levels', 'open-match-settings', 'open-award-settings', 'open-pairing-rules', 'open-team-info'];
      for (var i = 1; i < settings.length; i++) {
        expect(_y(tester, settings[i - 1]) < _y(tester, settings[i]), isTrue, reason: settings[i]);
      }
      expect(find.text(AdminTexts.teamInfoMenu), findsOneWidget);
      // 2차 리포트 메뉴는 숨김
      expect(find.byKey(const Key('open-team-report')), findsNothing);
      // 팀원 관리에 이름 검색 칸(스크롤 가능)이 생겨 바깥 목록을 지정한다 (Q-079 3번 f)
      await tester.scrollUntilVisible(find.byKey(const Key('dissolve-team')), 200, scrollable: find.byType(Scrollable).first);
      expect(_y(tester, 'admin-group-owner') < _y(tester, 'manage-u1'), isTrue);
      expect(_y(tester, 'manage-u1') < _y(tester, 'dissolve-team'), isTrue);
    });

    testWidgets('운영진: "팀장만" 묶음은 통째로 안 보인다', (tester) async {
      await _openAdmin(tester, TeamRole.manager, 'm1');
      expect(find.byKey(const Key('admin-group-staff')), findsOneWidget);
      expect(find.byKey(const Key('admin-group-owner')), findsNothing);
      expect(find.text(AdminTexts.groupOwner), findsNothing);
      expect(find.byKey(const Key('dissolve-team')), findsNothing);
      expect(find.text(TeamTexts.membersSection), findsNothing);
    });
  });

  group('이름 검색 규칙 (6-4)', () {
    test('기존 이름 검색과 같은 정리: 보이지 않는 문자·앞뒤 공백 제거, 가운데 공백 하나로, 대소문자 무시, 포함', () {
      expect(NameSearch.matches('김 철수', '  김​   철 '), isTrue);
      expect(NameSearch.matches('Tom Kim', 'tom'), isTrue);
      expect(NameSearch.matches('철수', '수'), isTrue);
      expect(NameSearch.matches('철수', '영'), isFalse);
      expect(NameSearch.matches('철수', '   '), isTrue);
    });
  });

  group('그룹·라이벌 사람 고르기 (6-4)', () {
    final many = [
      for (var i = 0; i < 100; i++)
        MemberEntry(
          userId: 'p$i',
          role: i == 0 ? TeamRole.owner : TeamRole.member,
          displayName: '${['하', '가', '마', '나', '다'][i % 5]}선수${i.toString().padLeft(3, '0')}',
        ),
    ];

    testWidgets('목록은 가나다순, 일부 글자로 바로 걸러지고, 없으면 안내', (tester) async {
      await _pumpPicker(tester, members: many);
      expect(_visiblePicks(tester).first, '가선수001');
      final visible = _visiblePicks(tester);
      expect(visible, [...visible]..sort());

      await tester.enterText(find.byKey(const Key('pick-search')), '099');
      await tester.pump();
      expect(_visiblePicks(tester), ['다선수099']);

      await tester.enterText(find.byKey(const Key('pick-search')), ' 마 선수 ');
      await tester.pump();
      expect(find.byKey(const Key('pick-no-match')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pick-search')), '마선수01');
      await tester.pump();
      expect(_visiblePicks(tester), ['마선수012', '마선수017']);

      await tester.tap(find.byKey(const Key('pick-search-clear')));
      await tester.pump();
      expect(_visiblePicks(tester).first, '가선수001');
    });

    testWidgets('100명: 고른 사람은 검색 칸 아래 이름표로 모이고 X 로 빼기, 검색을 바꿔도 남는다. 저장은 가나다순', (tester) async {
      PairingRule? saved;
      await _pumpPicker(tester, members: many, onSaved: (r) => saved = r);
      expect(find.text(AdminTexts.pickedCount(0)), findsOneWidget);
      expect(find.text(AdminTexts.pickMembers), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pick-search')), '099');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pick-p99')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('pick-search')), '가선수001');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pick-p1')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('pick-search')), '나선수003');
      await tester.pump();
      await tester.tap(find.byKey(const Key('pick-p3')));
      await tester.pump();

      expect(find.text(AdminTexts.pickedCount(3)), findsOneWidget);
      for (final id in ['p99', 'p1', 'p3']) {
        expect(find.byKey(Key('picked-$id')), findsOneWidget, reason: id);
      }
      // 이름표는 검색 칸 아래
      expect(_y(tester, 'pick-search') < _y(tester, 'picked-p1'), isTrue);
      // 목록 체크 표시
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('pick-p3'))).value, isTrue);

      // X 로 빼기
      await tester.tap(find.descendant(of: find.byKey(const Key('picked-p3')), matching: find.byTooltip(AdminTexts.unpick)));
      await tester.pump();
      expect(find.byKey(const Key('picked-p3')), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('pick-p3'))).value, isFalse);

      // 긴 목록 스크롤
      await tester.tap(find.byKey(const Key('pick-search-clear')));
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const Key('pick-p95')), 300, scrollable: find.descendant(of: find.byKey(const Key('pick-list')), matching: find.byType(Scrollable)));
      expect(find.byKey(const Key('pick-p95')), findsOneWidget);

      await tester.tap(find.byKey(const Key('rule-dialog-save')));
      await tester.pumpAndSettle();
      // 가선수001(p1) → 다선수099(p99)
      expect(saved!.userIds, ['p1', 'p99']);
    });

    testWidgets('고치기: 원래 고른 사람(지금 팀원만)이 이름표·체크로, 모순이면 저장이 꺼진다', (tester) async {
      await _pumpPicker(
        tester,
        members: _members,
        initial: const PairingRule(id: 'r1', kind: PairingKind.rival, enabled: true, userIds: ['u1', 'gone']),
        conflict: (r) => r.userIds.length >= 2 ? AdminTexts.conflict('운영', '일번') : null,
      );
      expect(find.byKey(const Key('picked-u1')), findsOneWidget);
      expect(find.byKey(const Key('picked-gone')), findsNothing);
      await tester.tap(find.byKey(const Key('pick-m1')));
      await tester.pump();
      expect(find.byKey(const Key('rule-dialog-conflict')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('rule-dialog-save'))).onPressed, isNull);
    });
  });
}
