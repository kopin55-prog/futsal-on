import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/pom_vote/domain/award_models.dart';
import 'package:futsal_on/features/pom_vote/presentation/award_settings_screen.dart';
import 'package:futsal_on/features/pom_vote/presentation/award_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/award_fakes.dart';
import '../../support/fakes.dart';

const _team = TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: TeamRole.owner,
  isRecruiting: true,
  schedule: RegularSchedule(),
);

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '일번'),
];

Map<String, dynamic> _poll({String status = 'open'}) => {
  'match_id': 'm1',
  'team_id': 'a',
  'opens_at': '2026-11-11T03:00:00+00:00',
  'closes_at': '2026-11-12T06:00:00+00:00', // 한국 다음날 15:00
  'status': status,
};

AwardPollView _view({
  String status = 'open',
  List<String> participants = const ['me', 'u1', 'u2', 'left'],
  List<String> voted = const [],
  List<(String, String)> winners = const [],
}) => AwardPollView.fromRows(
  _poll(status: status),
  participants: [for (final p in participants) {'user_id': p}],
  myReceipts: [for (final c in voted) {'category': c}],
  winners: [for (final (c, u) in winners) {'category': c, 'user_id': u}],
);

void main() {
  final before = DateTime.utc(2026, 11, 12, 5, 59);
  final atClose = DateTime.utc(2026, 11, 12, 6);

  group('투표 모델', () {
    test('항목 코드와 서버 값이 같다', () {
      expect(AwardCategory.values.map((c) => c.code), ['pom', 'goal_of_the_day']);
      expect(AwardCategory.fromCode('goal_of_the_day'), AwardCategory.goalOfTheDay);
      expect(AwardCategory.fromCode('mvp'), isNull);
    });

    test('진행 중: open 이고 마감 전 (마감 정각부터 닫힘)', () {
      final v = _view();
      expect(v.isOpenAt(before), isTrue);
      expect(v.isOpenAt(atClose), isFalse);
      expect(_view(status: 'closed').isOpenAt(before), isFalse);
    });

    test('후보: 본인·떠난 사람 제외 (Q-075 13번 (3))', () {
      final v = _view();
      expect(v.candidates(me: 'me', currentMemberIds: {'me', 'u1', 'u2'}), {'u1', 'u2'});
    });

    test('투표 가능: 대상자·지금 팀원·안 낸 항목·진행 중. 항목마다 따로 (Q-075 13번 (1))', () {
      final v = _view(voted: ['pom']);
      expect(v.myVoted, {AwardCategory.pom});
      expect(v.canVote('me', AwardCategory.pom, isCurrentMember: true, now: before), isFalse);
      expect(v.canVote('me', AwardCategory.goalOfTheDay, isCurrentMember: true, now: before), isTrue);
      expect(v.canVote('me', AwardCategory.goalOfTheDay, isCurrentMember: false, now: before), isFalse);
      expect(v.canVote('me', AwardCategory.goalOfTheDay, isCurrentMember: true, now: atClose), isFalse);
      expect(v.canVote('x', AwardCategory.goalOfTheDay, isCurrentMember: true, now: before), isFalse, reason: '대상자 아님');
    });

    test('1위는 마감 뒤에만, 공동 1위 모두, 표가 없던 항목은 결과 없음', () {
      final closed = _view(status: 'closed', winners: [('pom', 'u1'), ('pom', 'u2')]);
      expect(closed.winnersOf(AwardCategory.pom), ['u1', 'u2']);
      expect(closed.winnersOf(AwardCategory.goalOfTheDay), isEmpty);
      expect(_view(winners: [('pom', 'u1')]).winnersOf(AwardCategory.pom), isEmpty);
    });

    test('기본 발표 시각 15:00', () {
      expect(AwardSettings.defaultAnnounceTime, const ClockTime(15, 0));
    });
  });

  group('투표 설정 권한 (Entitlements)', () {
    const e = Entitlements();
    test('팀장·운영진만', () {
      expect(e.canPerform(const Viewer(userId: 'a', role: TeamRole.owner), TeamAction.editAwardSettings), isTrue);
      expect(e.canPerform(const Viewer(userId: 'a', role: TeamRole.manager), TeamAction.editAwardSettings), isTrue);
      expect(e.canPerform(const Viewer(userId: 'a', role: TeamRole.member), TeamAction.editAwardSettings), isFalse);
      expect(e.canPerform(const Viewer(userId: 'a', role: null), TeamAction.editAwardSettings), isFalse);
    });
  });

  group('투표 설정 화면', () {
    Future<FakeAwardRepository> open(WidgetTester tester, {ClockTime? saved}) async {
      final awards = FakeAwardRepository();
      if (saved != null) awards.announceTimes['a'] = saved;
      await tester.pumpWidget(MaterialApp(home: AwardSettingsScreen(awards: awards, team: _team)));
      await tester.pumpAndSettle();
      return awards;
    }

    testWidgets('기본 15:00 을 보여 주고 저장하면 그 시각을 보낸다', (tester) async {
      final awards = await open(tester);
      expect(find.text(AwardTexts.announceButton('15:00')), findsOneWidget);
      await tester.tap(find.byKey(const Key('award-settings-save')));
      await tester.pumpAndSettle();
      expect(awards.announceTimes['a'], const ClockTime(15, 0));
    });

    testWidgets('저장된 시각(새벽 포함)을 불러온다', (tester) async {
      await open(tester, saved: const ClockTime(3, 30));
      expect(find.text(AwardTexts.announceButton('03:30')), findsOneWidget);
    });

    testWidgets('서버가 거절하면 안내를 보여 준다', (tester) async {
      final awards = await open(tester);
      awards.failNext = ServerErrorCode.notPermitted;
      await tester.tap(find.byKey(const Key('award-settings-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('award-settings-error')), findsOneWidget);
    });
  });

  group('관리 탭 메뉴', () {
    testWidgets('팀장: 투표 설정 메뉴 → 화면 → 저장', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = TestServices(teams: [_team], members: {'a': _members});
      await tester.pumpWidget(
        MaterialApp(home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {})),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.tabAdmin));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-award-settings')));
      await tester.tap(find.byKey(const Key('open-award-settings')));
      await tester.pumpAndSettle();
      expect(find.text(AwardTexts.awardSettings), findsOneWidget);
      await tester.tap(find.byKey(const Key('award-settings-save')));
      await tester.pumpAndSettle();
      expect(t.awards.announceTimes['a'], const ClockTime(15, 0));
      expect(find.text(AwardTexts.saved), findsOneWidget);
    });
  });
}
