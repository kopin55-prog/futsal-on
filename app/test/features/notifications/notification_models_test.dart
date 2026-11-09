import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';

import '../../support/fakes.dart';

Map<String, dynamic> _row(String id, {String kind = 'match_created', String? readAt, String created = '2026-11-09T01:00:00+00:00'}) => {
  'id': id,
  'kind': kind,
  'team_id': 't1',
  'ref_type': 'match',
  'ref_id': 'm1',
  'title': '피FC',
  'body': '11월 12일(목) 19:00 경기가 열렸어요!',
  'created_at': created,
  'read_at': readAt,
};

void main() {
  final schema = File('../supabase/migrations/202611050028_notifications.sql').readAsStringSync();

  group('알림 모델', () {
    test('한 줄 읽기', () {
      final n = AppNotification.fromRow(_row('n1'));
      expect(n.kind, NotificationKind.matchCreated);
      expect(n.refType, NotificationRefType.match);
      expect(n.refId, 'm1');
      expect(n.title, '피FC');
      expect(n.isRead, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 11, 9, 1));
      final r = AppNotification.fromRow(_row('n2', readAt: '2026-11-09T02:00:00+00:00'));
      expect(r.isRead, isTrue);
    });

    test('모르는 종류·대상은 깨지지 않는다', () {
      final n = AppNotification.fromRow({..._row('n1', kind: 'future_kind'), 'ref_type': null, 'ref_id': null, 'team_id': null});
      expect(n.kind, NotificationKind.unknown);
      expect(n.refType, isNull);
      expect(NotificationKind.fromServer(''), NotificationKind.unknown);
    });

    test('종류 목록은 서버 enum 과 같다', () {
      final block = RegExp(r'create type public\.notification_kind as enum \(([^)]*)\)').firstMatch(schema)!.group(1)!;
      final server = RegExp(r"'([a-z_]+)'").allMatches(block).map((m) => m.group(1)!).toList();
      final app = [for (final k in NotificationKind.values) if (k != NotificationKind.unknown) k.code];
      expect(app, server);
    });

    test('대상 종류는 서버 규칙과 같다', () {
      for (final t in NotificationRefType.values) {
        expect(schema.contains("'${t.code}'"), isTrue, reason: t.code);
      }
    });

    test('select 칸은 서버 알림함 표에 있는 칸만, 이름 든 사람 칸은 읽지 않음', () {
      final cols = AppNotification.columns.split(',').map((e) => e.trim()).toList();
      for (final c in cols) {
        expect(schema.contains(RegExp('^  $c ', multiLine: true)), isTrue, reason: c);
      }
      expect(cols.contains('actor_id'), isFalse);
      expect(cols.contains('dedupe_key'), isFalse);
    });
  });

  group('알림함 저장소 흉내', () {
    test('최신순, 안 읽은 수, 하나 읽음, 모두 읽음', () async {
      final repo = FakeNotificationRepository(
        items: [
          AppNotification.fromRow(_row('a', created: '2026-11-09T01:00:00+00:00')),
          AppNotification.fromRow(_row('b', created: '2026-11-09T03:00:00+00:00')),
          AppNotification.fromRow(_row('c', created: '2026-11-09T02:00:00+00:00', readAt: '2026-11-09T02:30:00+00:00')),
        ],
      );
      expect((await repo.listNotifications()).map((n) => n.id), ['b', 'c', 'a']);
      expect(await repo.unreadCount(), 2);
      final firstRead = (await repo.listNotifications()).firstWhere((n) => n.id == 'c').readAt;
      await repo.markRead('a');
      expect(await repo.unreadCount(), 1);
      expect(await repo.markAllRead(), 1);
      expect(await repo.unreadCount(), 0);
      expect((await repo.listNotifications()).firstWhere((n) => n.id == 'c').readAt, firstRead);
    });
  });
}
