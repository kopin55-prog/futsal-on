import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/notification_models.dart';

/// 알림함 (data-model.md 9-2). 본인 알림만 읽힌다(권한 규칙). 만들기는 서버만.
///
/// 모든 팀의 알림을 한 곳에, 최신순 (Q-071 10번). 30일 지난 알림은 서버 정리 작업이 지운다 (Q-041).
/// 본인은 읽음 표시만 할 수 있고, 읽은 시각은 서버 시각으로 기록된다. 개별 삭제·안 읽음 되돌리기는 없다.
/// 실패는 모두 [ServerFailure].
abstract interface class NotificationRepository {
  /// 내 알림, 최신순.
  Future<List<AppNotification>> listNotifications({int limit = 200});

  /// 안 읽은 알림 수 (모든 팀 합계).
  Future<int> unreadCount();

  /// 하나 읽음. 이미 읽은 알림이면 아무것도 바뀌지 않는다.
  Future<void> markRead(String notificationId);

  /// 모두 읽음. 새로 읽음 처리한 수를 돌려준다.
  Future<int> markAllRead();
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> listNotifications({int limit = 200}) => guardServer(() async {
    final rows = await _client
        .from('notifications')
        .select(AppNotification.columns)
        .order('created_at', ascending: false)
        .order('id')
        .limit(limit);
    return [for (final r in rows) AppNotification.fromRow(r)];
  });

  @override
  Future<int> unreadCount() => guardServer(
    () async => await _client.rpc<int>('count_unread_notifications'),
  );

  @override
  Future<void> markRead(String notificationId) => guardServer(() async {
    // 값은 서버가 자기 시각으로 바꿔 적는다 (기기 시계와 무관).
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .isFilter('read_at', null);
  });

  @override
  Future<int> markAllRead() => guardServer(
    () async => await _client.rpc<int>('mark_all_notifications_read'),
  );
}
