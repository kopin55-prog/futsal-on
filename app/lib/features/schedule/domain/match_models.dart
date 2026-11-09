import '../../../shared/domain/venue.dart';
import '../../team/domain/team_validation.dart';

/// 일정이 생긴 방법 (data-model.md 4-1 `source`).
enum MatchSource {
  auto,
  manual;

  static MatchSource fromServer(String value) =>
      MatchSource.values.firstWhere((e) => e.name == value);
}

/// 일정 상태 (예정 / 취소). 되돌리기 없음 (Q-071 3번).
enum MatchStatus {
  scheduled,
  cancelled;

  static MatchStatus fromServer(String value) =>
      MatchStatus.values.firstWhere((e) => e.name == value);
}

/// 일정 한 건 (matches 한 줄). 시각은 서버가 준 절대 시각이고, 표시는 한국 시간으로 한다 (Q-027 M-18).
class TeamMatch {
  const TeamMatch({
    required this.id,
    required this.teamId,
    required this.source,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.rsvpDeadlineAt,
    this.rsvpReminderAt,
    this.capacity,
    this.venue,
    this.cancelledAt,
    this.cancelReason,
  });

  final String id;
  final String teamId;
  final MatchSource source;
  final MatchStatus status;
  final DateTime startsAt;
  final DateTime endsAt;

  /// 참석 투표 마감. 마감 정각부터는 응답 불가.
  final DateTime rsvpDeadlineAt;

  /// 미투표 알림 시각. null 이면 알림 없음 (끄기 또는 생성 때 이미 지남).
  final DateTime? rsvpReminderAt;

  /// 생성 당시 정원. null 이면 정원 없음.
  final int? capacity;
  final Venue? venue;
  final DateTime? cancelledAt;

  /// 취소 사유 (선택, 팀원 전체에게 보임, Q-072 5번)
  final String? cancelReason;

  bool get isCancelled => status == MatchStatus.cancelled;

  /// 관리자가 취소할 수 있는 상태인지 (권한 판단은 core/entitlements 에서 따로 한다).
  bool canBeCancelledAt(DateTime now) => !isCancelled && now.isBefore(startsAt);

  /// 서버 select 칸 목록 (matches 표, 팀원 읽기).
  static const columns =
      'id, team_id, source, status, starts_at, ends_at, rsvp_deadline_at, rsvp_reminder_at, capacity, '
      'venue_name, venue_address, venue_lat, venue_lng, venue_map_provider, venue_map_place_id, '
      'cancelled_at, cancel_reason';

  static TeamMatch fromRow(Map<String, dynamic> row) => TeamMatch(
    id: row['id'] as String,
    teamId: row['team_id'] as String,
    source: MatchSource.fromServer(row['source'] as String),
    status: MatchStatus.fromServer(row['status'] as String),
    startsAt: DateTime.parse(row['starts_at'] as String),
    endsAt: DateTime.parse(row['ends_at'] as String),
    rsvpDeadlineAt: DateTime.parse(row['rsvp_deadline_at'] as String),
    rsvpReminderAt: _time(row['rsvp_reminder_at']),
    capacity: row['capacity'] as int?,
    venue: Venue.fromRow(row),
    cancelledAt: _time(row['cancelled_at']),
    cancelReason: row['cancel_reason'] as String?,
  );

  static DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);
}

/// 날짜만 (한국 시간 기준 달력 날짜).
class CalendarDate {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// 서버로 보내는 형식 "YYYY-MM-DD"
  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is CalendarDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// 일정 직접 추가 입력 (서버 함수 create_match).
///
/// - 시작·종료는 날짜와 시각 (자정 넘김은 종료 날짜로 표현). 종료가 시작과 같거나 이르면 서버가 거절.
/// - 마감·미투표 알림은 일정마다 고른다 (Q-072 1번). null 이면 팀 경기 설정 값.
///   미투표 알림 끄기는 [reminderOff].
/// - 정원은 항상 팀 경기 설정을 복사하므로 입력이 없다.
class MatchInput {
  const MatchInput({
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    this.venue,
    this.rsvpDeadlineHours,
    this.rsvpReminderHours,
  });

  /// [rsvpReminderHours] 에 넣으면 이 일정은 미투표 알림을 보내지 않는다.
  static const int reminderOff = 0;

  final CalendarDate startDate;
  final ClockTime startTime;
  final CalendarDate endDate;
  final ClockTime endTime;
  final Venue? venue;
  final int? rsvpDeadlineHours;
  final int? rsvpReminderHours;

  Map<String, Object?> toServerParams(String teamId) => {
    'p_team_id': teamId,
    'p_start_date': startDate.iso,
    'p_start_time': startTime.hhmm,
    'p_end_date': endDate.iso,
    'p_end_time': endTime.hhmm,
    'p_venue': venue?.toServerJson(),
    'p_rsvp_deadline_hours': rsvpDeadlineHours,
    'p_rsvp_reminder_hours': rsvpReminderHours,
  };
}
