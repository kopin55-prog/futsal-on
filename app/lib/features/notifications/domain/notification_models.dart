/// 알림 종류 (data-model.md 9장 `kind`, 서버 public.notification_kind 와 같은 목록).
///
/// 1차에 실제로 생기는 종류와 다음 스프린트에 붙을 종류(배치·POM·부상 복귀, 2차 월말 리포트)를 모두 둔다.
/// 서버에 새 종류가 생겨 앱이 모르면 [unknown] 으로 읽는다 (앱을 업데이트하지 않은 사람도 알림함이 깨지지 않게).
enum NotificationKind {
  matchCreated('match_created'),
  rsvpDeadlineSoon('rsvp_deadline_soon'),
  waitlistPromoted('waitlist_promoted'),
  matchCancelled('match_cancelled'),
  lineupConfirmed('lineup_confirmed'),
  lineupChanged('lineup_changed'),
  awardPollOpened('award_poll_opened'),
  awardDeadlineSoon('award_deadline_soon'),
  joinRequestReceived('join_request_received'),
  joinRequestDecided('join_request_decided'),
  memberLeft('member_left'),
  teamDissolved('team_dissolved'),
  injuryReturnCheck('injury_return_check'),
  managerAssigned('manager_assigned'),
  managerUnassigned('manager_unassigned'),
  ownershipReceived('ownership_received'),
  memberRemoved('member_removed'),
  memberJoined('member_joined'),
  memberAccountDeleted('member_account_deleted'),
  joinRequestAutoDeclined('join_request_auto_declined'),
  monthlyReport('monthly_report'),

  /// 앱이 모르는 종류.
  unknown('');

  const NotificationKind(this.code);

  final String code;

  static NotificationKind fromServer(String? value) =>
      NotificationKind.values.firstWhere((e) => e != unknown && e.code == value, orElse: () => unknown);
}

/// 누르면 이동할 대상의 종류 (notifications.ref_type). 외래 키가 아니라 대상이 없어졌을 수 있다 (Q-041).
enum NotificationRefType {
  match('match'),
  team('team'),
  joinRequest('join_request');

  const NotificationRefType(this.code);

  final String code;

  static NotificationRefType? fromServer(String? value) {
    for (final t in values) {
      if (t.code == value) return t;
    }
    return null;
  }
}

/// 알림함 한 줄 (notifications, 본인 것만 읽힘).
///
/// 제목은 팀 이름, 본문은 보낸 시점의 문구(서버가 만든 그대로). 푸시 문구도 같다 (9-1).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.teamId,
    this.refType,
    this.refId,
    this.readAt,
  });

  final String id;
  final NotificationKind kind;

  /// 관련 팀. 떠난 팀이면 눌러도 이동하지 않는다 (Q-041, 화면은 4단계).
  final String? teamId;
  final NotificationRefType? refType;
  final String? refId;
  final String title;
  final String body;

  /// 알림이 생긴 시각 = 알림함에 보이는 시각.
  final DateTime createdAt;

  /// 읽은 시각. 비어 있으면 안 읽음. 안 읽음으로 되돌리기는 없다 (Q-071 10번).
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// 표에서 읽는 칸. 문구에 이름이 든 사람(actor_id)은 화면에 쓰지 않으므로 읽지 않는다.
  static const columns = 'id, kind, team_id, ref_type, ref_id, title, body, created_at, read_at';

  static AppNotification fromRow(Map<String, dynamic> row) => AppNotification(
    id: row['id'] as String,
    kind: NotificationKind.fromServer(row['kind'] as String?),
    teamId: row['team_id'] as String?,
    refType: NotificationRefType.fromServer(row['ref_type'] as String?),
    refId: row['ref_id'] as String?,
    title: row['title'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    readAt: row['read_at'] == null ? null : DateTime.parse(row['read_at'] as String),
  );
}
