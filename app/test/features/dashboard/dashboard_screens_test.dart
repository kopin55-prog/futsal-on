import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/admin/presentation/admin_tab.dart';
import 'package:futsal_on/features/dashboard/presentation/dashboard_texts.dart';
import 'package:futsal_on/features/injury/presentation/injury_texts.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_editor_screen.dart';
import 'package:futsal_on/features/pom_vote/domain/award_models.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/match_detail_screen.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/roster_tab.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../../support/fakes.dart';
import '../../support/tabs.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _members = [
  MemberEntry(userId: 'o', role: TeamRole.owner, displayName: '팀장'),
  MemberEntry(userId: 'me', role: TeamRole.member, displayName: '나'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다현'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u3', role: TeamRole.manager, displayName: '나래'),
];

TeamSummary _team(TeamRole role) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  myRole: role,
  isRecruiting: true,
);

TeamMatch _match(
  String id, {
  Duration startIn = const Duration(days: 3),
  Duration length = const Duration(hours: 2),
  Duration deadlineBefore = const Duration(hours: 2),
  bool cancelled = false,
  int? capacity = 12,
}) {
  final start = DateTime.now().toUtc().add(startIn);
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.auto,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(length),
    rsvpDeadlineAt: start.subtract(deadlineBefore),
    capacity: capacity,
  );
}

DateTime _todayKst() {
  final d = Kst.dateOf(DateTime.now());
  return DateTime.utc(d.year, d.month, d.day);
}

AwardPollView _poll(
  String matchId, {
  bool closed = false,
  Duration closesIn = const Duration(hours: 20),
  Set<String> participants = const {'me', 'u1', 'u2', 'o'},
  Set<AwardCategory> myVoted = const {},
  Map<AwardCategory, List<String>> winners = const {},
}) => AwardPollView(
  matchId: matchId,
  teamId: 'a',
  opensAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
  closesAt: DateTime.now().toUtc().add(closesIn),
  status: closed ? AwardPollStatus.closed : AwardPollStatus.open,
  participantIds: participants,
  myVoted: myVoted,
  winners: winners,
);

Future<TestServices> _open(
  WidgetTester tester, {
  TeamRole role = TeamRole.member,
  void Function(TestServices t)? setup,
}) async {
  _tall(tester);
  final t = TestServices(teams: [_team(role)], members: {'a': _members})..currentUserId = 'me';
  t.injuries.today = _todayKst();
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  return t;
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('탭 (S4-01)', () {
    testWidgets('앱을 열면 홈. 순서는 홈·일정·팀원·관리·내 기록, 팀원에게는 관리 탭 없음', (tester) async {
      await _open(tester, role: TeamRole.owner);
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
      final labels = [
        for (final d in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination))) d.label,
      ];
      expect(labels, [DashboardTexts.tabHome, ScheduleTexts.tabSchedule, TeamTexts.tabMembers, TeamTexts.tabAdmin, TeamTexts.tabMy]);
    });

    testWidgets('팀원 탭 순서', (tester) async {
      await _open(tester);
      final labels = [
        for (final d in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination))) d.label,
      ];
      expect(labels, [DashboardTexts.tabHome, ScheduleTexts.tabSchedule, TeamTexts.tabMembers, TeamTexts.tabMy]);
    });
  });

  group('헤더 (4-2)', () {
    testWidgets('팀 로고·이름·팀원 수(팀장·운영진 포함)', (tester) async {
      await _open(tester);
      expect(find.descendant(of: find.byKey(const Key('dash-header')), matching: find.text('코코FC')), findsOneWidget);
      expect(_text(tester, 'dash-member-count'), DashboardTexts.memberCount(5));
    });
  });

  group('다음 경기 카드 (4-3, S4-02)', () {
    testWidgets('일정·내 상태·참석 현황 숫자, 누르면 일정 상세', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.addAll([_match('later', startIn: const Duration(days: 10)), _match('m1')]);
          t.attendance.seed('m1', 'u1', AttendanceState.attending);
          t.attendance.seed('m1', 'u2', AttendanceState.declined);
        },
      );
      expect(_text(tester, 'dash-my-status'), ScheduleTexts.notResponded);
      expect(
        _text(tester, 'dash-counts'),
        DashboardTexts.counts(attending: 1, capacity: 12, waitlist: 0, notResponded: 3),
      );
      expect(find.byKey(const Key('dash-in-progress')), findsNothing);

      await tester.tap(find.byKey(const Key('dash-next')));
      await tester.pumpAndSettle();
      expect(find.byType(MatchDetailScreen), findsOneWidget);
      expect(tester.widget<MatchDetailScreen>(find.byType(MatchDetailScreen)).matchId, 'm1');
    });

    testWidgets('카드에서 바로 참석·불참 (상세로 가지 않음)', (tester) async {
      final t = await _open(tester, setup: (t) => t.matches.items.add(_match('m1')));
      await tester.tap(find.byKey(const Key('dash-attend')));
      await tester.pumpAndSettle();
      expect(find.byType(MatchDetailScreen), findsNothing);
      expect(t.attendance.byMatch['m1']!.single.state, AttendanceState.attending);
      expect(_text(tester, 'dash-my-status'), ScheduleTexts.attending);

      await tester.tap(find.byKey(const Key('dash-decline')));
      await tester.pumpAndSettle();
      expect(t.attendance.byMatch['m1']!.single.state, AttendanceState.declined);
    });

    testWidgets('부상 중이면 내 상태 "부상 중", [참석]은 복귀 확인 창 (취소 = 그대로, 확인 = 참석 + 해제)', (tester) async {
      final t = await _open(
        tester,
        setup: (t) {
          t.matches.items.add(_match('m1'));
          t.injuries.seedActive('me', expectedReturnOn: _todayKst());
        },
      );
      expect(_text(tester, 'dash-my-status'), DashboardTexts.injured);
      await tester.tap(find.byKey(const Key('dash-attend')));
      await tester.pumpAndSettle();
      expect(find.text(InjuryTexts.returnConfirmTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('return-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(t.attendance.byMatch['m1'] ?? const [], isEmpty);
      expect(t.injuries.active.containsKey('me'), isTrue);

      await tester.tap(find.byKey(const Key('dash-attend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('return-confirm-ok')));
      await tester.pumpAndSettle();
      expect(t.attendance.byMatch['m1']!.single.state, AttendanceState.attending);
      expect(t.injuries.active.containsKey('me'), isFalse);
      expect(_text(tester, 'dash-my-status'), ScheduleTexts.attending);
    });

    testWidgets('진행 중인 경기는 "진행 중", 취소된 일정은 건너뜀, 마감 뒤에는 버튼 없음', (tester) async {
      await _open(
        tester,
        setup: (t) => t.matches.items.addAll([
          _match('cancelled', startIn: const Duration(minutes: -30), cancelled: true),
          _match('playing', startIn: const Duration(minutes: -30)),
          _match('next-week', startIn: const Duration(days: 7)),
        ]),
      );
      expect(find.byKey(const Key('dash-in-progress')), findsOneWidget);
      expect(find.byKey(const Key('dash-attend')), findsNothing);
      expect(find.byKey(const Key('dash-deadline-passed')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dash-next')));
      await tester.pumpAndSettle();
      expect(tester.widget<MatchDetailScreen>(find.byType(MatchDetailScreen)).matchId, 'playing');
    });

    testWidgets('일정이 없으면 안내, [일정 추가]는 관리자에게만', (tester) async {
      await _open(tester, setup: (t) => t.matches.items.add(_match('c', cancelled: true)));
      expect(find.text(DashboardTexts.noNext), findsOneWidget);
      expect(find.byKey(const Key('dash-add-match')), findsNothing);
    });

    testWidgets('관리자에게는 [일정 추가]', (tester) async {
      await _open(tester, role: TeamRole.manager);
      expect(find.text(DashboardTexts.noNext), findsOneWidget);
      expect(find.byKey(const Key('dash-add-match')), findsOneWidget);
    });

    testWidgets('배치 확정: 내 팀 블록(조끼 색, 이름 가나다순, 게스트 상자). 다른 팀 이름은 카드에 없음', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.add(_match('m1', startIn: const Duration(hours: 1)));
          t.guests.byMatch['m1'] = [
            MatchGuestDetail(id: 'g1', guestNo: 1, name: '손님', positions: const [], skillLevel: SkillLevel.undecided, createdAt: DateTime.utc(2026)),
          ];
          t.lineups.seed(
            'm1',
            const LineupDraft(
              playersPerTeam: 3,
              squads: [
                LineupSquadDraft(
                  bibColor: BibColor.yellow,
                  people: [LineupPerson.member('u1'), LineupPerson.member('me'), LineupPerson.guest('g1')],
                ),
                LineupSquadDraft(bibColor: BibColor.blue, people: [LineupPerson.member('u2'), LineupPerson.member('o')]),
              ],
              bench: [],
            ),
            confirmed: true,
          );
        },
      );
      final block = find.byKey(const Key('dash-my-squad'));
      expect(block, findsOneWidget);
      expect(find.descendant(of: block, matching: find.text('나')), findsOneWidget);
      expect(find.descendant(of: block, matching: find.text('다현')), findsOneWidget);
      expect(find.descendant(of: block, matching: find.text(ScheduleTexts.guest)), findsOneWidget);
      expect(find.text('가람'), findsNothing);
      // 가나다순: 나 → 다현 → 손님
      final xs = [
        for (final k in ['u:me', 'u:u1', 'g:g1']) tester.getTopLeft(find.byKey(Key('dash-lineup-person-$k'))).dx,
      ];
      expect(xs[0] < xs[1] && xs[1] < xs[2], isTrue);
    });

    testWidgets('배치에 없으면 "이번 경기 배치에 없어요" + [전체 배치 보기] → 일정 상세', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.add(_match('m1', startIn: const Duration(hours: 1)));
          t.lineups.seed(
            'm1',
            const LineupDraft(
              playersPerTeam: 1,
              squads: [
                LineupSquadDraft(bibColor: BibColor.red, people: [LineupPerson.member('u1')]),
                LineupSquadDraft(bibColor: BibColor.blue, people: [LineupPerson.member('u2')]),
              ],
              bench: [],
            ),
            confirmed: true,
          );
        },
      );
      expect(find.text(DashboardTexts.notInLineup), findsOneWidget);
      await tester.tap(find.byKey(const Key('dash-view-lineup')));
      await tester.pumpAndSettle();
      expect(find.byType(MatchDetailScreen), findsOneWidget);
    });

    testWidgets('초안 배치는 카드에 없음 (팀원은 서버도 안 줌, 관리자도 홈 카드에는 확정만)', (tester) async {
      for (final role in [TeamRole.member, TeamRole.manager]) {
        await _open(
          tester,
          role: role,
          setup: (t) {
            t.matches.items.add(_match('m1', startIn: const Duration(hours: 1)));
            t.lineups.hideDrafts = role == TeamRole.member;
            t.lineups.seed(
              'm1',
              const LineupDraft(
                playersPerTeam: 1,
                squads: [
                  LineupSquadDraft(bibColor: BibColor.red, people: [LineupPerson.member('me')]),
                  LineupSquadDraft(bibColor: BibColor.blue, people: [LineupPerson.member('u2')]),
                ],
                bench: [],
              ),
            );
          },
        );
        expect(find.byKey(const Key('dash-my-squad')), findsNothing);
        expect(find.byKey(const Key('dash-not-in-lineup')), findsNothing);
      }
    });
  });

  group('지난 경기 POM·오늘의 골 (4-4, S4-03)', () {
    testWidgets('투표 중: "투표 중 · 발표 시각" + 대상자에게 [투표하기] → 결과·투표 화면(일정 상세)', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.add(_match('p1', startIn: const Duration(hours: -5)));
          t.awards.polls['p1'] = _poll('p1');
        },
      );
      expect(find.byKey(const Key('dash-award-voting')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dash-award-vote')));
      await tester.pumpAndSettle();
      expect(tester.widget<MatchDetailScreen>(find.byType(MatchDetailScreen)).matchId, 'p1');
    });

    testWidgets('대상자가 아니거나 다 냈으면 [투표하기] 없음', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.add(_match('p1', startIn: const Duration(hours: -5)));
          t.awards.polls['p1'] = _poll('p1', participants: const {'u1', 'u2'});
        },
      );
      expect(find.byKey(const Key('dash-award-voting')), findsOneWidget);
      expect(find.byKey(const Key('dash-award-vote')), findsNothing);
    });

    testWidgets('발표 뒤: 공동 1위 모두(가나다순), 떠난 1위는 빈칸 자리, 표가 없으면 "결과 없음". 카드를 누르면 그 경기', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.addAll([
            _match('old', startIn: const Duration(days: -8)),
            _match('p1', startIn: const Duration(days: -1)),
            _match('cancelled', startIn: const Duration(hours: -5), cancelled: true),
          ]);
          t.awards.polls['old'] = _poll('old', closed: true, winners: {AwardCategory.pom: ['o']});
          t.awards.polls['p1'] = _poll(
            'p1',
            closed: true,
            closesIn: const Duration(hours: -1),
            winners: {AwardCategory.pom: ['u1', 'left', 'u2']},
          );
        },
      );
      expect(_text(tester, 'dash-award-pom'), '가람, 다현, ${DashboardTexts.leftMember}');
      expect(_text(tester, 'dash-award-goal_of_the_day'), DashboardTexts.noResult);
      await tester.tap(find.byKey(const Key('dash-award')));
      await tester.pumpAndSettle();
      expect(tester.widget<MatchDetailScreen>(find.byType(MatchDetailScreen)).matchId, 'p1');
    });

    testWidgets('가장 최근 경기에 투표가 안 열렸으면 칸을 숨긴다 (그 전 결과도 안 보임)', (tester) async {
      await _open(
        tester,
        setup: (t) {
          t.matches.items.addAll([
            _match('old', startIn: const Duration(days: -8)),
            _match('p1', startIn: const Duration(days: -1)),
          ]);
          t.awards.polls['old'] = _poll('old', closed: true, winners: {AwardCategory.pom: ['o']});
        },
      );
      expect(find.byKey(const Key('dash-award')), findsNothing);
    });
  });

  group('부상자 라인업 (4-5, S4-04)', () {
    testWidgets('이름·남은 W·메모, 짧은 순 → 이름순. 동의 철회한 사람 없음. 누르면 팀원 탭', (tester) async {
      await _open(
        tester,
        setup: (t) {
          final today = _todayKst();
          t.injuries.seedActive('u1', expectedReturnOn: today.add(const Duration(days: 10)), memo: '발목');
          t.injuries.seedActive('u2', expectedReturnOn: today.add(const Duration(days: 3)));
          t.injuries.seedActive('u3', expectedReturnOn: today.subtract(const Duration(days: 1)));
          // 동의 철회(기록도 지워지지만, 동의 없는 줄은 서버가 주지 않는 것 확인)
          t.injuries.seedActive('o', expectedReturnOn: today.add(const Duration(days: 3)));
          t.injuries.consented.remove('o');
        },
      );
      final card = find.byKey(const Key('dash-injured'));
      expect(find.descendant(of: card, matching: find.text(DashboardTexts.injuredTitle(3))), findsOneWidget);
      final ys = [
        for (final u in ['u3', 'u2', 'u1']) tester.getTopLeft(find.byKey(Key('dash-injured-$u'))).dy,
      ];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      expect(find.byKey(const Key('dash-injured-o')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('dash-injured-u1')), matching: find.text('2W')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('dash-injured-u1')), matching: find.text('발목')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('dash-injured-u3')), matching: find.text('0W')), findsOneWidget);

      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(RosterTab), findsOneWidget);
    });

    testWidgets('부상자가 없으면 칸 숨김', (tester) async {
      await _open(tester);
      expect(find.byKey(const Key('dash-injured')), findsNothing);
    });
  });

  group('처리할 일 (4-6, S4-05)', () {
    void requests(TestServices t) => t.membership.incoming.addAll([
      IncomingJoinRequest(requestId: 'r1', userId: 'x1', displayName: '신청1', createdAt: DateTime.utc(2026)),
      IncomingJoinRequest(requestId: 'r2', userId: 'x2', displayName: '신청2', createdAt: DateTime.utc(2026)),
    ]);

    testWidgets('관리자: 가입 신청 N건 → 관리 탭, 관리 탭 아이콘에 숫자', (tester) async {
      await _open(tester, role: TeamRole.manager, setup: requests);
      expect(find.byKey(const Key('dash-todos')), findsOneWidget);
      expect(find.text(DashboardTexts.joinRequests(2)), findsOneWidget);
      expect(tester.widget<Badge>(find.byKey(const Key('admin-tab-badge'))).isLabelVisible, isTrue);
      expect(find.descendant(of: find.byKey(const Key('admin-tab-badge')), matching: find.text('2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dash-todo-join')));
      await tester.pumpAndSettle();
      expect(find.byType(AdminTab), findsOneWidget);
      expect(find.byKey(const Key('request-r1')), findsOneWidget);
    });

    testWidgets('관리자: 팀 나누기 대기(마감 뒤·종료 전·미확정) → 그 경기 배치 화면. 확정된 경기는 없음', (tester) async {
      await _open(
        tester,
        role: TeamRole.owner,
        setup: (t) {
          t.matches.items.addAll([
            _match('open', startIn: const Duration(hours: 1)), // 마감 지남
            _match('confirmed', startIn: const Duration(hours: 1, minutes: 30)),
            _match('before', startIn: const Duration(days: 2)), // 마감 전
          ]);
          t.lineups.seed(
            'confirmed',
            const LineupDraft(
              playersPerTeam: 1,
              squads: [
                LineupSquadDraft(bibColor: BibColor.red, people: [LineupPerson.member('u1')]),
                LineupSquadDraft(bibColor: BibColor.blue, people: [LineupPerson.member('u2')]),
              ],
              bench: [],
            ),
            confirmed: true,
          );
        },
      );
      expect(find.byKey(const Key('dash-todo-lineup-open')), findsOneWidget);
      expect(find.byKey(const Key('dash-todo-lineup-confirmed')), findsNothing);
      expect(find.byKey(const Key('dash-todo-lineup-before')), findsNothing);
      expect(find.byKey(const Key('dash-todo-join')), findsNothing);
      expect(tester.widget<Badge>(find.byKey(const Key('admin-tab-badge'))).isLabelVisible, isFalse);

      await tester.tap(find.byKey(const Key('dash-todo-lineup-open')));
      await tester.pumpAndSettle();
      expect(find.byType(LineupEditorScreen), findsOneWidget);
      expect(tester.widget<LineupEditorScreen>(find.byType(LineupEditorScreen)).match.id, 'open');
    });

    testWidgets('팀원 화면에는 처리할 일·가입 신청 수가 없다', (tester) async {
      await _open(
        tester,
        setup: (t) {
          requests(t);
          t.matches.items.add(_match('open', startIn: const Duration(hours: 1)));
        },
      );
      expect(find.byKey(const Key('dash-todos')), findsNothing);
      expect(find.text(DashboardTexts.joinRequests(2)), findsNothing);
      expect(find.byKey(const Key('admin-tab-badge')), findsNothing);
    });

    testWidgets('처리할 일이 없으면 칸 숨김', (tester) async {
      await _open(tester, role: TeamRole.owner);
      expect(find.byKey(const Key('dash-todos')), findsNothing);
    });
  });

  group('관리 탭 2차 자리', () {
    testWidgets('출석·참여 리포트 메뉴는 1차에 안 보인다', (tester) async {
      await _open(tester, role: TeamRole.owner);
      await openTab(tester, TeamTexts.tabAdmin);
      expect(find.byType(AdminTab), findsOneWidget);
      expect(find.byKey(const Key('open-team-info')), findsOneWidget);
      expect(find.byKey(const Key('open-team-report')), findsNothing);
    });
  });
}
