/// 참석 투표 응답 상태 (data-model.md 4-2 `state`). 줄이 없으면 "미투표"이고, 미투표로 되돌리기는 없다 (Q-071 5번).
enum AttendanceState {
  attending,
  waitlisted,
  declined;

  static AttendanceState fromServer(String value) =>
      AttendanceState.values.firstWhere((e) => e.name == value);
}

/// 참석 투표 응답 한 줄 (attendance_responses, 그 팀 팀원 전체가 읽음).
class AttendanceResponse {
  const AttendanceResponse({
    required this.id,
    required this.matchId,
    required this.userId,
    required this.state,
    required this.respondedAt,
    required this.updatedAt,
    this.waitlistedAt,
    this.promotedAt,
  });

  final String id;
  final String matchId;
  final String userId;
  final AttendanceState state;

  /// 대기 순번 기준 (먼저 누른 순). 대기일 때만 있다.
  final DateTime? waitlistedAt;

  /// 대기에서 참석으로 자동 전환된 시각.
  final DateTime? promotedAt;

  /// 처음 응답한 시각.
  final DateTime respondedAt;

  /// 마지막으로 바뀐 시각 (본인 변경·자동 참석 모두).
  final DateTime updatedAt;

  static const columns = 'id, match_id, user_id, state, waitlisted_at, promoted_at, responded_at, updated_at';

  static AttendanceResponse fromRow(Map<String, dynamic> row) => AttendanceResponse(
    id: row['id'] as String,
    matchId: row['match_id'] as String,
    userId: row['user_id'] as String,
    state: AttendanceState.fromServer(row['state'] as String),
    waitlistedAt: _time(row['waitlisted_at']),
    promotedAt: _time(row['promoted_at']),
    respondedAt: DateTime.parse(row['responded_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  static DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);
}

/// 한 일정의 응답 모음. 대기 순번은 서버와 같은 기준(waitlisted_at, 같으면 id)으로 센다.
///
/// 명단 순서 (Q-073 7번): 참석·불참은 마지막으로 바꾼 시각 순(대기에서 자동 참석도 참석이 된 시각 = updated_at),
/// 대기는 순번, 미투표는 이름 가나다순 ([notRespondedSorted]).
class AttendanceRoster {
  AttendanceRoster(Iterable<AttendanceResponse> responses)
    : _byUser = {for (final r in responses) r.userId: r},
      waitlist = [
        for (final r in responses)
          if (r.state == AttendanceState.waitlisted) r,
      ]..sort(_waitlistOrder);

  final Map<String, AttendanceResponse> _byUser;

  /// 대기 명단, 순번 순.
  final List<AttendanceResponse> waitlist;

  static int _waitlistOrder(AttendanceResponse a, AttendanceResponse b) {
    final byTime = a.waitlistedAt!.compareTo(b.waitlistedAt!);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  /// 그 사람의 응답. null 이면 미투표.
  AttendanceResponse? responseOf(String userId) => _byUser[userId];

  /// 대기 몇 번인지 (1부터). 대기가 아니면 null.
  int? waitlistPosition(String userId) {
    final i = waitlist.indexWhere((r) => r.userId == userId);
    return i < 0 ? null : i + 1;
  }

  /// 참석 인원 (게스트는 세지 않음, 정원과 별도).
  int get attendingCount =>
      _byUser.values.where((r) => r.state == AttendanceState.attending).length;

  /// 참석 명단, 마지막으로 바꾼 시각 순 (같으면 id 순).
  List<AttendanceResponse> get attending => _ofState(AttendanceState.attending);

  /// 불참 명단, 마지막으로 바꾼 시각 순 (같으면 id 순).
  List<AttendanceResponse> get declined => _ofState(AttendanceState.declined);

  List<AttendanceResponse> _ofState(AttendanceState state) => [
    for (final r in _byUser.values)
      if (r.state == state) r,
  ]..sort((a, b) {
      final byTime = a.updatedAt.compareTo(b.updatedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  /// 미투표 명단: [members] (userId → 이름) 중 응답 없는 사람, 이름 가나다순 (같으면 userId 순).
  List<String> notRespondedSorted(Map<String, String> members) =>
      notRespondedAmong(members.keys)..sort((a, b) {
        final byName = members[a]!.compareTo(members[b]!);
        return byName != 0 ? byName : a.compareTo(b);
      });

  /// 응답하지 않은 사람 (미투표 명단 재료). [memberIds] 는 지금 팀원.
  List<String> notRespondedAmong(Iterable<String> memberIds) =>
      [for (final id in memberIds) if (!_byUser.containsKey(id)) id];
}
