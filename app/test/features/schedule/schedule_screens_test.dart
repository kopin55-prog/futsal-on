import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/guest_badge.dart';
import 'package:futsal_on/features/schedule/presentation/match_create_screen.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/position.dart';
import 'package:futsal_on/shared/domain/venue.dart';
import 'package:futsal_on/shared/presentation/common_widgets.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다현'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '나래'),
  MemberEntry(userId: 'u4', role: TeamRole.member, displayName: '라온'),
];

TeamSummary _team(String id, String name, TeamRole role) => TeamSummary(
  id: id,
  name: name,
  teamCode: 'KOKO22',
  logoText: name.substring(0, 2),
  myRole: role,
  isRecruiting: true,
);

TeamMatch _match(
  String id, {
  String teamId = 'a',
  Duration startIn = const Duration(days: 2),
  Duration deadlineBefore = const Duration(hours: 2),
  int? capacity,
  bool cancelled = false,
  String? reason,
}) {
  final start = DateTime.now().toUtc().add(startIn);
  return TeamMatch(
    id: id,
    teamId: teamId,
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(deadlineBefore),
    capacity: capacity,
    cancelledAt: cancelled ? DateTime.now() : null,
    cancelReason: reason,
  );
}

Future<TestServices> _open(
  WidgetTester tester, {
  TeamRole role = TeamRole.member,
  String userId = 'u1',
  List<TeamMatch> matches = const [],
  void Function(TestServices t)? setup,
}) async {
  _tall(tester);
  final t = TestServices(teams: [_team('a', '코코FC', role)], members: {'a': _members})..currentUserId = userId;
  t.matches.items.addAll(matches);
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(home: TeamHomeScreen(services: t.services, userId: userId, onSignOut: () async {})),
  );
  await tester.pumpAndSettle();
  return t;
}

List<String> _chips(WidgetTester tester, String roster) => [
  for (final c in tester.widgetList<Chip>(
    find.descendant(of: find.byKey(Key('roster-$roster')), matching: find.byType(Chip)),
  ))
    (c.label as Text).data!,
];

void main() {
  group('일정 목록 (4-1)', () {
    testWidgets('첫 탭에 다가오는 일정, 취소된 일정은 "취소됨", 지난 일정은 없음. 팀원에게 추가 버튼 없음', (tester) async {
      await _open(
        tester,
        matches: [
          _match('m1'),
          _match('m2', startIn: const Duration(days: 3), cancelled: true),
          _match('old', startIn: const Duration(days: -2)),
        ],
      );
      expect(find.text(ScheduleTexts.upcoming), findsOneWidget);
      expect(find.byKey(const Key('match-m1')), findsOneWidget);
      expect(find.byKey(const Key('match-m2')), findsOneWidget);
      expect(find.byKey(const Key('match-old')), findsNothing);
      expect(find.text(ScheduleTexts.cancelled), findsWidgets);
      expect(find.byKey(const Key('schedule-add')), findsNothing);
    });

    testWidgets('운영진에게는 일정 추가 버튼 (Entitlements.manageSchedule)', (tester) async {
      await _open(tester, role: TeamRole.manager, userId: 'm1');
      expect(find.byKey(const Key('schedule-add')), findsOneWidget);
      expect(find.text(ScheduleTexts.noUpcoming), findsOneWidget);
    });
  });

  group('일정 상세·참석 투표 (4-1)', () {
    testWidgets('일시·장소·정원·마감, 미투표 → 참석, 명단 순서 (Q-073 7번)', (tester) async {
      final t = await _open(
        tester,
        matches: [_match('m1')],
        setup: (t) {
          final base = DateTime.utc(2026, 1, 1);
          t.attendance.seed('m1', 'u3', AttendanceState.attending, at: base.add(const Duration(minutes: 5)));
          t.attendance.seed('m1', 'm1', AttendanceState.attending, at: base.add(const Duration(minutes: 1)));
          t.attendance.seed('m1', 'me', AttendanceState.declined, at: base.add(const Duration(minutes: 2)));
        },
      );
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleTexts.capacity(null)), findsOneWidget);
      expect(find.text(ScheduleTexts.venueNone), findsOneWidget);
      expect(find.byKey(const Key('match-deadline')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('my-status'))).data, ScheduleTexts.notResponded);
      // 참석: 마지막으로 바꾼 시각 순 / 미투표: 가나다순
      expect(_chips(tester, 'attending'), ['운영', '나래']);
      expect(_chips(tester, 'declined'), ['나']);
      expect(_chips(tester, 'not-responded'), ['가람', '다현', '라온']);

      await tester.tap(find.byKey(const Key('rsvp-attend')));
      await tester.pumpAndSettle();
      expect(t.attendance.calls, ['respond:m1:true']);
      expect(tester.widget<Text>(find.byKey(const Key('my-status'))).data, ScheduleTexts.attending);
      // 방금 참석한 사람이 맨 뒤
      expect(_chips(tester, 'attending'), ['운영', '나래', '다현']);
      expect(_chips(tester, 'not-responded'), ['가람', '라온']);
      // 이미 참석이면 참석 버튼은 꺼지고 불참은 가능
      expect(tester.widget<FilledButton>(find.byKey(const Key('rsvp-attend'))).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('rsvp-decline'))).onPressed, isNotNull);
    });

    testWidgets('정원이 차면 "대기 n번", 대기 명단은 순번', (tester) async {
      await _open(
        tester,
        matches: [_match('m1', capacity: 1)],
        setup: (t) {
          t.attendance.seed('m1', 'u2', AttendanceState.attending);
          t.attendance.seed('m1', 'u3', AttendanceState.waitlisted);
        },
      );
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rsvp-attend')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('my-status'))).data, ScheduleTexts.state(AttendanceState.waitlisted, 2));
      expect(_chips(tester, 'waitlisted'), ['1. 나래', '2. 다현']);
      expect(find.text(ScheduleTexts.attendingCount(1, 1)), findsOneWidget);
    });

    testWidgets('마감 후 버튼 잠김', (tester) async {
      await _open(tester, matches: [_match('m1', startIn: const Duration(hours: 1))]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(const Key('rsvp-attend'))).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('rsvp-decline'))).onPressed, isNull);
      expect(find.text(ScheduleTexts.deadlinePassed), findsWidgets);
    });

    testWidgets('서버가 마감으로 거절하면 안내', (tester) async {
      final t = await _open(tester, matches: [_match('m1')]);
      t.attendance.nextFailure = const ServerFailure(ServerErrorCode.rsvpClosed);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rsvp-decline')));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleTexts.deadlinePassed), findsOneWidget);
    });

    testWidgets('취소된 일정: "취소됨 + 사유", 투표 버튼 없음 (Q-073 4번)', (tester) async {
      await _open(tester, matches: [_match('m1', cancelled: true, reason: '비 와요')]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-cancelled-banner')), findsOneWidget);
      expect(find.text(ScheduleTexts.cancelReason('비 와요')), findsOneWidget);
      expect(find.byKey(const Key('rsvp-attend')), findsNothing);
    });

    testWidgets('팀원: 게스트는 이름 + "게스트" 상자만, 운영진 버튼·포지션 없음', (tester) async {
      final t = await _open(tester, matches: [_match('m1')]);
      t.guests.byMatch['m1'] = [
        MatchGuestDetail(
          id: 'g1',
          guestNo: 1,
          positions: const [Position.forward],
          skillLevel: SkillLevel.pro,
          createdAt: DateTime.utc(2026),
        ),
      ];
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(GuestNameLabel, '게스트1'), findsOneWidget);
      expect(find.byType(GuestBadge), findsOneWidget);
      expect(find.textContaining('프로'), findsNothing);
      expect(t.guests.detailReads, 0);
      expect(find.byKey(const Key('guest-add')), findsNothing);
      expect(find.byKey(const Key('guest-remove-g1')), findsNothing);
      expect(find.byKey(const Key('match-cancel')), findsNothing);
    });
  });

  group('운영진 (4-2)', () {
    testWidgets('일정 취소: 사유 입력(선택) → 취소됨 + 사유', (tester) async {
      final t = await _open(tester, role: TeamRole.owner, userId: 'me', matches: [_match('m1')]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('match-cancel')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cancel-reason')), '구장 공사');
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(t.matches.calls, ['cancel:m1:구장 공사']);
      expect(find.text(ScheduleTexts.cancelReason('구장 공사')), findsOneWidget);
      expect(find.byKey(const Key('match-cancel')), findsNothing);
      expect(find.byKey(const Key('guest-add')), findsNothing);
    });

    testWidgets('사유 없이 취소하면 사유를 보내지 않는다', (tester) async {
      final t = await _open(tester, role: TeamRole.manager, userId: 'm1', matches: [_match('m1')]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('match-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.pumpAndSettle();
      expect(t.matches.calls, ['cancel:m1:']);
      expect(find.byKey(const Key('match-cancelled-banner')), findsOneWidget);
    });

    testWidgets('게스트 추가: 이름 비우면 "게스트N", 같은 이름은 막고, 포지션·실력은 운영진에게 보인다', (tester) async {
      final t = await _open(tester, role: TeamRole.manager, userId: 'm1', matches: [_match('m1')]);
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('guest-add')));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleTexts.guestNameHint(1)), findsOneWidget);
      await tester.tap(find.byKey(const Key('guest-position-forward')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('guest-save')));
      await tester.pumpAndSettle();
      expect(t.guests.calls, ['add:m1:']);
      expect(find.widgetWithText(GuestNameLabel, '게스트1'), findsOneWidget);
      expect(find.text('${'공격'} · ${'미정'}'), findsOneWidget);

      // "게스트+숫자" 모양 이름은 못 쓴다 (Q-074 2번) → 저장 버튼 꺼짐 + 안내
      await tester.tap(find.byKey(const Key('guest-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guest-name')), ' 게스트 7');
      await tester.pump();
      expect(find.text(ScheduleTexts.guestError(GuestInputError.reservedName)), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byKey(const Key('guest-save'))).onPressed, isNull);
      // 포지션 4번째는 선택되지 않고 안내
      for (final p in ['goalkeeper', 'defender', 'midfielder', 'winger']) {
        await tester.tap(find.byKey(Key('guest-position-$p')));
        await tester.pump();
      }
      expect(find.byKey(const Key('guest-position-hint')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('guest-name')), '용병');
      await tester.pump();
      await tester.tap(find.byKey(const Key('guest-save')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(GuestNameLabel, '용병'), findsOneWidget);
      expect(find.byType(GuestBadge), findsNWidgets(2));

      // 삭제
      await tester.tap(find.byKey(const Key('guest-remove-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest-remove-confirm')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(GuestNameLabel, '게스트1'), findsNothing);
    });

    testWidgets('게스트 12명이면 추가 버튼이 꺼진다', (tester) async {
      final t = await _open(tester, role: TeamRole.owner, userId: 'me', matches: [_match('m1')]);
      t.guests.byMatch['m1'] = [
        for (var i = 1; i <= GuestInput.maxGuestsPerMatch; i++)
          MatchGuestDetail(
            id: 'g$i',
            guestNo: i,
            positions: const [],
            skillLevel: SkillLevel.undecided,
            createdAt: DateTime.utc(2026),
          ),
      ];
      await tester.tap(find.byKey(const Key('match-m1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const Key('guest-add'))).onPressed, isNull);
    });

    testWidgets('일정 추가 화면: 마감·미투표 알림은 팀 경기 설정 값이 먼저 채워지고, 시각이 없으면 저장 안 됨', (tester) async {
      final t = await _open(
        tester,
        role: TeamRole.owner,
        userId: 'me',
        setup: (t) => t.admin.settings = MatchSettings.defaults.copyWith(rsvpDeadlineHours: 5, rsvpReminderHours: () => 6),
      );
      await tester.tap(find.byKey(const Key('schedule-add')));
      await tester.pumpAndSettle();
      expect(find.byType(MatchCreateScreen), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('match-deadline'))).controller!.text, '5');
      expect(find.text(ScheduleTexts.reminderOption(6)), findsOneWidget);
      expect(find.text(ScheduleTexts.venueLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('match-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-error-timeRequired')), findsOneWidget);
      expect(t.matches.calls, isEmpty);
    });
  });

  group('일정 추가 기본값 (Q-074 4번)', () {
    // 2026-01-10 09:00 KST
    DateTime now() => DateTime.utc(2026, 1, 10, 0, 0);
    const venue = Venue.manual(name: '코코구장', address: '서울');

    Future<TestServices> openCreate(WidgetTester tester) async {
      _tall(tester);
      final t = TestServices(teams: [_team('a', '코코FC', TeamRole.owner)], members: {'a': _members});
      const team = TeamSummary(
        id: 'a', name: '코코FC', teamCode: 'KOKO22', logoText: '코코', myRole: TeamRole.owner,
        isRecruiting: true, venue: venue,
      );
      await tester.pumpWidget(MaterialApp(home: MatchCreateScreen(services: t.services, team: team, now: now)));
      await tester.pumpAndSettle();
      return t;
    }

    Future<void> pickDefault(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('시작을 고르면 종료는 2시간 뒤, 장소는 팀 지정 풋살장으로 미리 채워 저장', (tester) async {
      final t = await openCreate(tester);
      expect(find.text('코코구장'), findsOneWidget);
      await pickDefault(tester, 'match-start-date'); // 1월 10일
      await pickDefault(tester, 'match-start-time'); // 기본 20:00
      expect(find.text('${ScheduleTexts.endTime}  22:00'), findsOneWidget);
      expect(find.text('${ScheduleTexts.endDate}  ${ScheduleTexts.date(const CalendarDate(2026, 1, 10))}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('match-save')));
      await tester.pumpAndSettle();
      final input = t.matches.lastInput!;
      expect(input.endDate, const CalendarDate(2026, 1, 10));
      expect(input.endTime.hhmm, '22:00');
      expect(input.venue?.name, '코코구장');
    });

    testWidgets('미리 채운 장소는 비울 수 있다', (tester) async {
      final t = await openCreate(tester);
      await tester.tap(find.byKey(const Key('venue-clear')));
      await tester.pump();
      expect(find.text('코코구장'), findsNothing);
      await pickDefault(tester, 'match-start-date');
      await pickDefault(tester, 'match-start-time');
      await tester.tap(find.byKey(const Key('match-save')));
      await tester.pumpAndSettle();
      expect(t.matches.lastInput!.venue, isNull);
    });
  });

  group('알림함 (4-3)', () {
    AppNotification n(String id, String team, String body, {String? teamId, NotificationRefType? ref, String? refId, bool read = false, int minutesAgo = 0}) =>
        AppNotification(
          id: id,
          kind: NotificationKind.matchCreated,
          teamId: teamId,
          refType: ref,
          refId: refId,
          title: team,
          body: body,
          createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
          readAt: read ? DateTime.now() : null,
        );

    Future<TestServices> openWithNotifications(WidgetTester tester) => _open(
      tester,
      matches: [_match('m1', cancelled: true, reason: '비 와요')],
      setup: (t) {
        t.teams.teams.add(_team('b', '비FC', TeamRole.member));
        t.notifications.items = [
          n('n1', '코코FC', '경기가 취소됐어요.', teamId: 'a', ref: NotificationRefType.match, refId: 'm1', minutesAgo: 1),
          n('n2', '비FC', '새 경기', teamId: 'b', ref: NotificationRefType.match, refId: 'gone', minutesAgo: 5),
          n('n3', '떠난팀', '예전 알림', teamId: 'z', ref: NotificationRefType.match, refId: 'x', minutesAgo: 10),
          n('n4', '코코FC', '읽은 알림', teamId: 'a', read: true, minutesAgo: 20),
        ];
      },
    );

    testWidgets('종 모양에 모든 팀 합계, 알림함은 최신순·팀 이름, 모두 읽음', (tester) async {
      final t = await openWithNotifications(tester);
      expect(tester.widget<Text>(find.byKey(const Key('notification-unread'))).data, '3');
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      final tiles = tester.widgetList<ListTile>(find.byWidgetPredicate((w) => w is ListTile && w.key.toString().contains('notification-')));
      expect([for (final tile in tiles) (tile.key! as ValueKey<String>).value], ['notification-n1', 'notification-n2', 'notification-n3', 'notification-n4']);
      expect(find.text('비FC'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notifications-read-all')));
      await tester.pumpAndSettle();
      expect(t.notifications.items.every((x) => x.isRead), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notification-unread')), findsNothing);
    });

    testWidgets('일정 알림을 누르면 읽음 + 일정 상세(취소된 일정도 사유)', (tester) async {
      final t = await openWithNotifications(tester);
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-n1')));
      await tester.pumpAndSettle();
      expect(t.notifications.items.firstWhere((x) => x.id == 'n1').isRead, isTrue);
      expect(find.text(ScheduleTexts.cancelReason('비 와요')), findsOneWidget);
    });

    testWidgets('사라진 대상·떠난 팀 알림은 읽음 처리만 하고 이동하지 않는다', (tester) async {
      final t = await openWithNotifications(tester);
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-n2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-n3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications-read-all')), findsOneWidget);
      expect(find.byKey(const Key('match-time')), findsNothing);
      expect(t.notifications.items.where((x) => x.id == 'n2' || x.id == 'n3').every((x) => x.isRead), isTrue);
    });

    testWidgets('가입 신청 알림은 그 팀 관리 탭으로', (tester) async {
      await _open(
        tester,
        role: TeamRole.owner,
        userId: 'me',
        setup: (t) {
          t.teams.teams.add(_team('b', '비FC', TeamRole.owner));
          t.notifications.items = [
            n('j1', '비FC', '가입 신청', teamId: 'b', ref: NotificationRefType.joinRequest, refId: 'r1'),
          ];
        },
      );
      await tester.tap(find.byKey(const Key('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-j1')));
      await tester.pumpAndSettle();
      expect(find.text('비FC'), findsOneWidget);
      expect(find.byKey(const Key('open-match-settings')), findsOneWidget);
      expect(find.text(TeamTexts.tabAdmin), findsOneWidget);
    });
  });
}
