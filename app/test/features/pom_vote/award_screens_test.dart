import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';
import 'package:futsal_on/features/pom_vote/domain/award_models.dart';
import 'package:futsal_on/features/pom_vote/presentation/award_texts.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/domain/past_matches.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

// 'left' 는 경기 뒤 팀을 떠난 대상자 (팀원 목록에 없음)
const _members = [
  MemberEntry(userId: 'me', role: TeamRole.member, displayName: '나'),
  MemberEntry(userId: 'o1', role: TeamRole.owner, displayName: '팀장'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다현'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '나래'),
];

TeamSummary _team(TeamRole role) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: role,
  isRecruiting: true,
);

/// [endedAgo] 전에 끝난 경기 (음수면 아직 안 끝남)
TeamMatch _match(String id, {Duration endedAgo = const Duration(hours: 1), bool cancelled = false}) {
  final end = DateTime.now().toUtc().subtract(endedAgo);
  final start = end.subtract(const Duration(hours: 2));
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: end,
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
    cancelledAt: cancelled ? start.subtract(const Duration(hours: 3)) : null,
  );
}

AwardPollView _poll(
  String matchId, {
  AwardPollStatus status = AwardPollStatus.open,
  Duration closesIn = const Duration(hours: 20),
  Set<String> participants = const {'me', 'u1', 'u2', 'left'},
  Set<AwardCategory> voted = const {},
  Map<AwardCategory, List<String>> winners = const {},
}) {
  final now = DateTime.now().toUtc();
  return AwardPollView(
    matchId: matchId,
    teamId: 'a',
    opensAt: now.subtract(const Duration(hours: 1)),
    closesAt: now.add(closesIn),
    status: status,
    participantIds: participants,
    myVoted: voted,
    winners: winners,
  );
}

Future<TestServices> _open(
  WidgetTester tester, {
  TeamRole role = TeamRole.member,
  String userId = 'me',
  List<TeamMatch> matches = const [],
  void Function(TestServices t)? setup,
}) async {
  _tall(tester);
  final t = TestServices(teams: [_team(role)], members: {'a': _members})..currentUserId = userId;
  t.matches.items.addAll(matches);
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: userId, onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  return t;
}

Future<void> _openPast(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('past-match-$id')));
  await tester.pumpAndSettle();
}

List<String> _candidateNames(WidgetTester tester, AwardCategory c) => [
  for (final tile in tester.widgetList<ListTile>(
    find.byWidgetPredicate((w) => w is ListTile && '${w.key}'.contains('award-candidate-${c.code}-')),
  ))
    (tile.title! as Text).data!,
];

List<String> _chipTexts(WidgetTester tester, Key key) => [
  for (final c in tester.widgetList<Chip>(find.descendant(of: find.byKey(key), matching: find.byType(Chip))))
    (c.label as Text).data!,
];

void main() {
  group('지난 경기 범위 (5-1, data-model 7-5)', () {
    test('취소 안 된 최근 10경기 + 그 사이 취소된 일정, 최근 순. 더 이전 취소 일정은 빠짐', () {
      final played = [for (var i = 1; i <= 12; i++) _match('p$i', endedAgo: Duration(days: i))];
      final cancelledNew = _match('c1', endedAgo: const Duration(days: 3, hours: 12), cancelled: true);
      final cancelledOld = _match('c2', endedAgo: const Duration(days: 11), cancelled: true);
      final result = PastMatches.recent([...played, cancelledNew, cancelledOld]);
      expect(result.map((m) => m.id), ['p1', 'p2', 'p3', 'c1', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9', 'p10']);
    });

    test('10경기가 안 되면 취소된 일정도 모두', () {
      final result = PastMatches.recent([
        _match('p1', endedAgo: const Duration(days: 1)),
        _match('c1', endedAgo: const Duration(days: 20), cancelled: true),
      ]);
      expect(result.map((m) => m.id), ['p1', 'c1']);
    });
  });

  group('일정 탭 지난 경기 (5-1)', () {
    testWidgets('끝난 경기는 "지난 경기"에 최근 순, 취소된 일정은 "취소됨". 다가오는 일정은 위에 그대로', (tester) async {
      await _open(
        tester,
        matches: [
          _match('old', endedAgo: const Duration(days: 7)),
          _match('new'),
          _match('cx', endedAgo: const Duration(days: 2), cancelled: true),
          _match('next', endedAgo: const Duration(days: -2)),
        ],
      );
      expect(find.text(ScheduleTexts.pastMatches), findsOneWidget);
      expect(find.byKey(const Key('match-next')), findsOneWidget);
      expect(find.byKey(const Key('past-match-next')), findsNothing);
      final ys = [
        for (final id in ['new', 'cx', 'old']) tester.getTopLeft(find.byKey(Key('past-match-$id'))).dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      expect(
        find.descendant(of: find.byKey(const Key('past-match-cx')), matching: find.text(ScheduleTexts.cancelled)),
        findsWidgets,
      );
    });

    testWidgets('지난 경기가 없으면 안내', (tester) async {
      await _open(tester);
      expect(find.text(ScheduleTexts.noPastMatches), findsOneWidget);
    });
  });

  group('투표 화면 (5-2)', () {
    testWidgets('대상자: 마감 시각, 후보는 본인·떠난 사람 빼고 가나다순, 항목별로 확인 창 뒤 "투표 완료"', (tester) async {
      final t = await _open(tester, matches: [_match('m1')], setup: (t) => t.awards.polls['m1'] = _poll('m1'));
      await _openPast(tester, 'm1');
      final poll = t.awards.polls['m1']!;
      expect(find.text(AwardTexts.deadline(poll.closesAt)), findsOneWidget);
      expect(_candidateNames(tester, AwardCategory.pom), ['가람', '다현']);
      expect(_candidateNames(tester, AwardCategory.goalOfTheDay), ['가람', '다현']);
      // 고르기 전엔 제출 버튼 꺼짐
      expect(tester.widget<FilledButton>(find.byKey(const Key('award-submit-pom'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('award-candidate-pom-u1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('award-submit-pom')));
      await tester.pumpAndSettle();
      expect(find.text(AwardTexts.confirmVote('다현')), findsOneWidget);
      await tester.tap(find.byKey(const Key('award-confirm-pom')));
      await tester.pumpAndSettle();

      expect(t.awards.votes, [('m1', AwardCategory.pom)]);
      expect(find.text(AwardTexts.votedDone), findsOneWidget);
      expect(find.byKey(const Key('award-voted-pom')), findsOneWidget);
      // 누구를 찍었는지는 보이지 않고 후보 목록도 사라짐. 오늘의 골은 따로 그대로
      expect(_candidateNames(tester, AwardCategory.pom), isEmpty);
      expect(find.byKey(const Key('award-submit-pom')), findsNothing);
      expect(find.byKey(const Key('award-voted-goal_of_the_day')), findsNothing);
      expect(_candidateNames(tester, AwardCategory.goalOfTheDay), ['가람', '다현']);
    });

    testWidgets('확인 창에서 취소하면 보내지 않는다', (tester) async {
      final t = await _open(tester, matches: [_match('m1')], setup: (t) => t.awards.polls['m1'] = _poll('m1'));
      await _openPast(tester, 'm1');
      await tester.tap(find.byKey(const Key('award-candidate-goal_of_the_day-u2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('award-submit-goal_of_the_day')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AwardTexts.cancel));
      await tester.pumpAndSettle();
      expect(t.awards.votes, isEmpty);
      expect(t.awards.calls.where((c) => c.startsWith('cast')), isEmpty);
    });

    testWidgets('이미 낸 항목은 "투표 완료"로 잠김 (바꾸기 없음)', (tester) async {
      await _open(
        tester,
        matches: [_match('m1')],
        setup: (t) => t.awards.polls['m1'] = _poll('m1', voted: {AwardCategory.pom, AwardCategory.goalOfTheDay}),
      );
      await _openPast(tester, 'm1');
      expect(find.text(AwardTexts.voted), findsNWidgets(2));
      expect(find.byKey(const Key('award-submit-pom')), findsNothing);
      expect(find.byKey(const Key('award-submit-goal_of_the_day')), findsNothing);
    });

    testWidgets('대상자가 아니면 투표 버튼 없이 안내', (tester) async {
      await _open(
        tester,
        userId: 'u3',
        matches: [_match('m1')],
        setup: (t) => t.awards.polls['m1'] = _poll('m1'),
      );
      await _openPast(tester, 'm1');
      expect(find.byKey(const Key('award-not-participant')), findsOneWidget);
      expect(find.byKey(const Key('award-submit-pom')), findsNothing);
      expect(find.byKey(const Key('award-deadline')), findsOneWidget);
    });

    testWidgets('마감 시각이 지났는데 마감 처리 전이면 잠기고 결과 대기 안내', (tester) async {
      await _open(
        tester,
        matches: [_match('m1')],
        setup: (t) => t.awards.polls['m1'] = _poll('m1', closesIn: const Duration(minutes: -1)),
      );
      await _openPast(tester, 'm1');
      expect(find.byKey(const Key('award-closed-pending')), findsOneWidget);
      expect(find.byKey(const Key('award-submit-pom')), findsNothing);
    });

    testWidgets('서버가 거절하면 안내하고 다시 읽는다', (tester) async {
      final t = await _open(tester, matches: [_match('m1')], setup: (t) => t.awards.polls['m1'] = _poll('m1'));
      await _openPast(tester, 'm1');
      await tester.tap(find.byKey(const Key('award-candidate-pom-u2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('award-submit-pom')));
      await tester.pumpAndSettle();
      t.awards.failNext = ServerErrorCode.awardPollClosed;
      await tester.tap(find.byKey(const Key('award-confirm-pom')));
      await tester.pumpAndSettle();
      expect(find.text(AwardTexts.serverError(ServerErrorCode.awardPollClosed)), findsOneWidget);
      expect(t.awards.votes, isEmpty);
    });

    testWidgets('끝나지 않은 경기·취소된 경기는 투표를 읽지 않고 부분도 없음', (tester) async {
      final t = await _open(
        tester,
        matches: [_match('next', endedAgo: const Duration(days: -1)), _match('cx', cancelled: true)],
      );
      await tester.tap(find.byKey(const Key('match-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('award-section')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openPast(tester, 'cx');
      expect(find.byKey(const Key('award-section')), findsNothing);
      expect(t.awards.calls, isEmpty);
    });

    testWidgets('투표가 열리지 않은 지난 경기(대상 2명 미만 등)는 부분 없음', (tester) async {
      await _open(tester, matches: [_match('m1')]);
      await _openPast(tester, 'm1');
      expect(find.byKey(const Key('award-section')), findsNothing);
    });
  });

  group('결과 화면 (5-3)', () {
    testWidgets('마감 뒤 항목별 1위(공동 모두, 가나다순), 떠난 1위는 이름 빈칸 자리, 표가 없으면 "결과 없음". 득표수 버튼 숨김', (tester) async {
      await _open(
        tester,
        userId: 'u3', // 대상자가 아닌 팀원도 결과는 본다
        matches: [_match('m1')],
        setup: (t) => t.awards.polls['m1'] = _poll(
          'm1',
          status: AwardPollStatus.closed,
          closesIn: const Duration(hours: -1),
          winners: {
            AwardCategory.pom: ['u1', 'left', 'u2'],
          },
        ),
      );
      await _openPast(tester, 'm1');
      expect(_chipTexts(tester, const Key('award-winners-pom')), ['가람', '다현', AwardTexts.leftMember]);
      expect(find.byKey(const Key('award-no-result-goal_of_the_day')), findsOneWidget);
      expect(find.text(AwardTexts.noResult), findsOneWidget);
      expect(find.text(AwardTexts.voteCountButton), findsNothing);
      expect(find.byKey(const Key('award-not-participant')), findsNothing);
      expect(find.byKey(const Key('award-deadline')), findsNothing);
    });

    testWidgets('1위가 모두 떠났어도 "결과 없음"이 아니라 빈칸 자리로 보인다', (tester) async {
      await _open(
        tester,
        matches: [_match('m1')],
        setup: (t) => t.awards.polls['m1'] = _poll(
          'm1',
          status: AwardPollStatus.closed,
          closesIn: const Duration(hours: -1),
          winners: {
            AwardCategory.goalOfTheDay: ['left'],
          },
        ),
      );
      await _openPast(tester, 'm1');
      expect(_chipTexts(tester, const Key('award-winners-goal_of_the_day')), [AwardTexts.leftMember]);
      expect(find.byKey(const Key('award-no-result-goal_of_the_day')), findsNothing);
      expect(find.byKey(const Key('award-no-result-pom')), findsOneWidget);
    });

    test('득표수 보기 버튼은 1차에 누구에게도 안 보인다 (Entitlements)', () {
      const e = Entitlements();
      for (final role in TeamRole.values) {
        expect(e.showVoteCountButton(Viewer(userId: 'x', role: role)), isFalse);
      }
    });
  });

  group('알림 이동 (5단계)', () {
    for (final kind in [
      NotificationKind.awardPollOpened,
      NotificationKind.awardResultsAnnounced,
      NotificationKind.lineupConfirmed,
      NotificationKind.lineupChanged,
      NotificationKind.lineupUnconfirmed,
    ]) {
      testWidgets('${kind.code} 을 누르면 그 경기 상세로', (tester) async {
        await _open(
          tester,
          matches: [_match('m1')],
          setup: (t) {
            t.awards.polls['m1'] = _poll('m1');
            t.notifications.items = [
              AppNotification(
                id: 'n1',
                kind: kind,
                teamId: 'a',
                refType: NotificationRefType.match,
                refId: 'm1',
                title: '코코FC',
                body: '알림',
                createdAt: DateTime.now(),
              ),
            ];
          },
        );
        await tester.tap(find.byKey(const Key('notification-bell')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('notification-n1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('match-time')), findsOneWidget);
        expect(find.byKey(const Key('award-section')), findsOneWidget);
      });
    }
  });
}
