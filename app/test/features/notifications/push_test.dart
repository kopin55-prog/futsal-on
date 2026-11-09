import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/notifications/data/push_controller.dart';
import 'package:futsal_on/features/notifications/data/push_messaging.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';
import 'package:futsal_on/features/notifications/domain/push_message.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../../support/fakes.dart';
import '../../support/push_fakes.dart';

TeamSummary _team(String id, String name, TeamRole role) => TeamSummary(
  id: id,
  name: name,
  teamCode: 'KOKO22',
  logoText: name.substring(0, 2),
  myRole: role,
  isRecruiting: true,
);

TeamMatch _match(String id) {
  final start = DateTime.now().toUtc().add(const Duration(days: 2));
  return TeamMatch(
    id: id,
    teamId: 'a',
    source: MatchSource.manual,
    status: MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
  );
}

AppNotification _n(String id, {String? teamId = 'a', NotificationRefType? ref, String? refId, bool read = false}) =>
    AppNotification(
      id: id,
      kind: NotificationKind.matchCreated,
      teamId: teamId,
      refType: ref,
      refId: refId,
      title: '코코FC',
      body: '경기가 열렸어요!',
      createdAt: DateTime.now(),
      readAt: read ? DateTime.now() : null,
    );

void main() {
  group('PushMessage (FCM data)', () {
    test('notifier 가 넣는 칸을 읽는다', () {
      final m = PushMessage.fromData(
        {'notification_id': 'n1', 'kind': 'match_created', 'team_id': 't', 'ref_type': 'match', 'ref_id': 'm'},
        title: '코코FC',
        body: '경기가 열렸어요!',
      )!;
      expect(m.notificationId, 'n1');
      expect(m.kind, 'match_created');
      expect(m.teamId, 't');
      expect(m.refType, 'match');
      expect(m.refId, 'm');
      expect(m.inAppText, '코코FC\n경기가 열렸어요!');
    });

    test('알림함 줄 ID 가 없으면 이 앱 푸시가 아님', () {
      expect(PushMessage.fromData({}), isNull);
      expect(PushMessage.fromData({'notification_id': ''}), isNull);
      expect(PushMessage.fromData({'notification_id': 3}), isNull);
    });

    test('짧은 안내 문구: 제목·본문 중 있는 것만', () {
      expect(const PushMessage(notificationId: 'n', body: '본문').inAppText, '본문');
      expect(const PushMessage(notificationId: 'n', title: '팀').inAppText, '팀');
      expect(const PushMessage(notificationId: 'n').inAppText, '');
    });
  });

  group('PushController (5-1)', () {
    test('start: 이 기기 토큰 등록, 토큰이 바뀌면 다시 등록', () async {
      final fcm = FakePushMessaging();
      final repo = FakeDeviceTokenRepository();
      final c = PushController(messaging: fcm, tokens: repo);
      await c.start();
      expect(repo.log, ['register:tok-1']);
      fcm.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.log, ['register:tok-1', 'register:tok-2']);
    });

    test('start 를 다시 불러도(재로그인) 토큰 변경 구독은 하나', () async {
      final fcm = FakePushMessaging();
      final repo = FakeDeviceTokenRepository();
      final c = PushController(messaging: fcm, tokens: repo);
      await c.start();
      await c.start();
      repo.log.clear();
      fcm.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.log, ['register:tok-2']);
    });

    test('stop: 마지막으로 등록한 토큰을 서버에서 지우고 기기 토큰도 없앤다. 그 뒤 토큰 변경은 등록 안 함', () async {
      final fcm = FakePushMessaging();
      final repo = FakeDeviceTokenRepository();
      final c = PushController(messaging: fcm, tokens: repo);
      await c.start();
      fcm.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      await c.stop();
      expect(repo.log.last, 'remove:tok-2');
      expect(repo.tokens, {'tok-1'}); // 바뀌기 전 토큰은 서버 발송 때 등록 안 된 토큰으로 지워진다
      expect(fcm.deleted, 1);
      repo.log.clear();
      fcm.refresh.add('tok-3');
      await Future<void>.delayed(Duration.zero);
      expect(repo.log, isEmpty);
    });

    test('실패해도 예외를 밖으로 내지 않는다 (서버 오류·토큰 없음·응답 없음)', () async {
      final fcm = FakePushMessaging()..throwOnGetToken = true;
      final repo = FakeDeviceTokenRepository()..fail = true;
      final c = PushController(messaging: fcm, tokens: repo);
      await c.start();
      expect(repo.log, isEmpty);
      fcm.throwOnGetToken = false;
      await c.start();
      await c.stop();
      expect(repo.log, ['register:tok-1', 'remove:tok-1']);
      expect(fcm.deleted, 1);

      final hanging = PushController(
        messaging: _HangingMessaging(),
        tokens: FakeDeviceTokenRepository(),
        timeout: const Duration(milliseconds: 10),
      );
      await hanging.start();
      await hanging.stop();
    });

    test('NoPushMessaging: 설정 파일이 없는 환경에서는 아무것도 안 한다', () async {
      final repo = FakeDeviceTokenRepository();
      final c = PushController(messaging: const NoPushMessaging(), tokens: repo);
      await c.start();
      await c.requestPermission();
      expect(await c.takeInitialMessage(), isNull);
      await c.stop();
      expect(repo.log, isEmpty);
    });
  });

  group('홈에서 푸시 받기 (5-3)', () {
    Future<(TestServices, FakePushMessaging, FakeDeviceTokenRepository)> open(
      WidgetTester tester, {
      PushMessage? initial,
      List<String>? signOutLog,
    }) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fcm = FakePushMessaging(initial: initial);
      final repo = FakeDeviceTokenRepository();
      final t = TestServices(
        teams: [_team('a', '코코FC', TeamRole.member), _team('b', '비FC', TeamRole.owner)],
        members: {
          'a': const [MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '나')],
          'b': const [MemberEntry(userId: 'u1', role: TeamRole.owner, displayName: '나')],
        },
      )..currentUserId = 'u1';
      t.push = PushController(messaging: fcm, tokens: repo);
      t.matches.items.add(_match('m1'));
      t.notifications.items = [
        _n('n1', ref: NotificationRefType.match, refId: 'm1'),
        _n('j1', teamId: 'b', ref: NotificationRefType.joinRequest, refId: 'r1'),
        _n('z1', teamId: 'left-team', ref: NotificationRefType.match, refId: 'x'),
      ];
      await t.recent.save('u1', ['a']);
      await tester.pumpWidget(
        MaterialApp(
          home: TeamHomeScreen(
            services: t.services,
            userId: 'u1',
            onSignOut: () async => signOutLog?.add('signOut'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (t, fcm, repo);
    }

    String unread(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('notification-unread'))).data!;

    testWidgets('홈에 들어오면(로그인할 때마다) 이 기기 등록', (tester) async {
      final (_, _, repo) = await open(tester);
      expect(repo.log, ['register:tok-1']);
    });

    testWidgets('앱 사용 중 도착: 앱 안 짧은 안내 + 안 읽은 개수 갱신 (SE-09)', (tester) async {
      final (t, fcm, _) = await open(tester);
      expect(unread(tester), '3');
      t.notifications.items.add(_n('n2', ref: NotificationRefType.match, refId: 'm1'));
      fcm.foreground.add(const PushMessage(notificationId: 'n2', title: '코코FC', body: '경기가 열렸어요!'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('push-in-app')), findsOneWidget);
      expect(find.text('코코FC\n경기가 열렸어요!'), findsOneWidget);
      expect(unread(tester), '4');
      // 앱 안 안내는 읽음 처리하지 않는다
      expect(t.notifications.items.firstWhere((n) => n.id == 'n2').isRead, isFalse);
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });

    testWidgets('백그라운드에서 휴대폰 알림을 누르면 읽음 + 일정 상세 (SE-08)', (tester) async {
      final (t, fcm, _) = await open(tester);
      fcm.opened.add(const PushMessage(notificationId: 'n1'));
      await tester.pumpAndSettle();
      expect(t.notifications.items.firstWhere((n) => n.id == 'n1').isRead, isTrue);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(unread(tester), '2');
    });

    testWidgets('앱이 꺼져 있을 때 누른 알림: 팀 목록을 읽은 뒤 같은 이동 (SE-08)', (tester) async {
      final (t, _, _) = await open(tester, initial: const PushMessage(notificationId: 'n1'));
      expect(t.notifications.items.firstWhere((n) => n.id == 'n1').isRead, isTrue);
      expect(find.byKey(const Key('match-time')), findsOneWidget);
    });

    testWidgets('가입 신청 푸시는 그 팀 관리 탭, 떠난 팀·없는 알림은 이동하지 않음', (tester) async {
      final (t, fcm, _) = await open(tester);
      fcm.opened.add(const PushMessage(notificationId: 'z1'));
      await tester.pumpAndSettle();
      expect(t.notifications.items.firstWhere((n) => n.id == 'z1').isRead, isTrue);
      expect(find.byKey(const Key('match-time')), findsNothing);
      fcm.opened.add(const PushMessage(notificationId: 'nope'));
      await tester.pumpAndSettle();
      expect(find.text('코코FC'), findsOneWidget);
      fcm.opened.add(const PushMessage(notificationId: 'j1'));
      await tester.pumpAndSettle();
      expect(find.text('비FC'), findsOneWidget);
      expect(find.text(TeamTexts.tabAdmin), findsOneWidget);
    });

    testWidgets('로그아웃: 이 기기 주소를 먼저 지우고 로그아웃 (SE-03)', (tester) async {
      final log = <String>[];
      final (_, fcm, repo) = await open(tester, signOutLog: log);
      await tester.tap(find.text(TeamTexts.tabMy));
      await tester.pumpAndSettle();
      final signOut = find.byKey(const Key('sign-out'));
      await tester.ensureVisible(signOut);
      await tester.pumpAndSettle();
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(log, ['signOut']);
      expect(repo.log, ['register:tok-1', 'remove:tok-1']);
      expect(fcm.deleted, 1);
    });
  });
}

class _HangingMessaging extends NoPushMessaging {
  @override
  Future<String?> getToken() => Completer<String?>().future;

  @override
  Future<void> deleteToken() => Completer<void>().future;
}
