/// 휴대폰으로 받은 푸시 한 건 (서버 notifier 가 보낸 FCM 메시지).
///
/// 제목·본문은 알림함 줄과 같다 (data-model.md 9-1). data 에는 누르면 이동할 대상만 들어 있다:
/// notification_id(알림함 줄 ID), kind, team_id, ref_type, ref_id. 모두 글자.
/// 이동은 알림함 줄을 다시 읽어 알림함과 같은 규칙으로 한다 (data 값만 믿고 이동하지 않는다).
class PushMessage {
  const PushMessage({
    required this.notificationId,
    this.kind,
    this.teamId,
    this.refType,
    this.refId,
    this.title,
    this.body,
  });

  final String notificationId;
  final String? kind;
  final String? teamId;
  final String? refType;
  final String? refId;
  final String? title;
  final String? body;

  /// FCM data + 알림 제목·본문 → 푸시. 알림함 줄 ID 가 없으면 이 앱이 보낸 푸시가 아니므로 null.
  static PushMessage? fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    String? text(String key) {
      final v = data[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final id = text('notification_id');
    if (id == null) return null;
    return PushMessage(
      notificationId: id,
      kind: text('kind'),
      teamId: text('team_id'),
      refType: text('ref_type'),
      refId: text('ref_id'),
      title: title,
      body: body,
    );
  }

  /// 앱 사용 중 도착했을 때 보여줄 짧은 안내 (서버 문구 그대로: 제목 = 팀 이름, 본문 = 알림 문구).
  String get inAppText {
    final t = title?.trim() ?? '';
    final b = body?.trim() ?? '';
    if (t.isEmpty) return b;
    if (b.isEmpty) return t;
    return '$t\n$b';
  }
}
