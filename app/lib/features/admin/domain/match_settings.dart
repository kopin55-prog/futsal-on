import '../../team/domain/team_validation.dart';

/// 경기 설정 입력 오류 (data-model.md 3-2).
enum MatchSettingsError {
  /// 정원이 1~[MatchSettings.maxCapacity] 밖
  capacityRange,

  /// 마감 시간이 0~[MatchSettings.maxDeadlineHours] 밖
  deadlineRange,

  /// 자동 생성 날짜가 0~[MatchSettings.maxAutoCreateDaysBefore] 밖
  autoCreateDaysRange,

  /// 참석 투표 마감 시각이 일정 자동 생성 시각보다 앞서거나 같음 (3-2 저장 규칙)
  deadlineBeforeAutoCreate,
}

/// 팀의 경기 설정 (team_settings 한 줄).
class MatchSettings {
  const MatchSettings({
    required this.capacity,
    required this.rsvpDeadlineHours,
    required this.autoCreateDaysBefore,
    required this.autoCreateTime,
  });

  /// 새 팀 기본값: 정원 없음, 경기 2시간 전 마감 (Q-066), 6일 전 09:00 자동 생성.
  static const defaults = MatchSettings(
    capacity: null,
    rsvpDeadlineHours: 2,
    autoCreateDaysBefore: 6,
    autoCreateTime: ClockTime(9, 0),
  );

  /// 내부 상한 (서버 검사와 같음. 정원 상한은 팀 최대 인원 100명, Q-067 5번).
  static const int maxCapacity = 100;
  static const int maxDeadlineHours = 720;
  static const int maxAutoCreateDaysBefore = 30;

  /// 정원. null 이면 "정원 없음". 값이 있으면 넘는 인원은 대기 순번.
  final int? capacity;

  /// 참석 투표 마감 = 경기 시작 몇 시간 전
  final int rsvpDeadlineHours;

  /// 일정 자동 생성 = 경기 며칠 전
  final int autoCreateDaysBefore;

  /// 일정 자동 생성 시각 (한국 시간)
  final ClockTime autoCreateTime;

  bool get hasCapacity => capacity != null;

  MatchSettings copyWith({
    int? Function()? capacity,
    int? rsvpDeadlineHours,
    int? autoCreateDaysBefore,
    ClockTime? autoCreateTime,
  }) => MatchSettings(
    capacity: capacity == null ? this.capacity : capacity(),
    rsvpDeadlineHours: rsvpDeadlineHours ?? this.rsvpDeadlineHours,
    autoCreateDaysBefore: autoCreateDaysBefore ?? this.autoCreateDaysBefore,
    autoCreateTime: autoCreateTime ?? this.autoCreateTime,
  );

  @override
  bool operator ==(Object other) =>
      other is MatchSettings &&
      other.capacity == capacity &&
      other.rsvpDeadlineHours == rsvpDeadlineHours &&
      other.autoCreateDaysBefore == autoCreateDaysBefore &&
      other.autoCreateTime == autoCreateTime;

  @override
  int get hashCode =>
      Object.hash(capacity, rsvpDeadlineHours, autoCreateDaysBefore, autoCreateTime);
}

/// 경기 설정 검사. 서버(update_team_settings, private.team_settings_deadline_ok)가 같은 규칙으로 다시 검사한다.
abstract final class MatchSettingsValidator {
  /// 마감 시각이 자동 생성 시각보다 뒤인지.
  ///
  /// 경기 시작 [regularStart] 기준으로, 자동 생성은 (며칠 전, 시각), 마감은 (몇 시간 전).
  /// 자동 생성은 정기 운동 시작 시각이 있을 때만 일어나므로 시작 시각이 없으면 검사할 것이 없다.
  /// 같은 시각이면 불가.
  static bool deadlineAfterAutoCreate({
    required ClockTime? regularStart,
    required int rsvpDeadlineHours,
    required int autoCreateDaysBefore,
    required ClockTime autoCreateTime,
  }) {
    if (regularStart == null) return true;
    final autoCreateMinutesBeforeStart = autoCreateDaysBefore * 24 * 60 +
        _minutes(regularStart) -
        _minutes(autoCreateTime);
    return autoCreateMinutesBeforeStart > rsvpDeadlineHours * 60;
  }

  static int _minutes(ClockTime t) => t.hour * 60 + t.minute;

  static Set<MatchSettingsError> validate(
    MatchSettings s, {
    required ClockTime? regularStart,
  }) {
    final errors = <MatchSettingsError>{};
    final cap = s.capacity;
    if (cap != null && (cap < 1 || cap > MatchSettings.maxCapacity)) {
      errors.add(MatchSettingsError.capacityRange);
    }
    final deadlineOk =
        s.rsvpDeadlineHours >= 0 && s.rsvpDeadlineHours <= MatchSettings.maxDeadlineHours;
    if (!deadlineOk) errors.add(MatchSettingsError.deadlineRange);
    final daysOk = s.autoCreateDaysBefore >= 0 &&
        s.autoCreateDaysBefore <= MatchSettings.maxAutoCreateDaysBefore;
    if (!daysOk) errors.add(MatchSettingsError.autoCreateDaysRange);
    if (deadlineOk &&
        daysOk &&
        !deadlineAfterAutoCreate(
          regularStart: regularStart,
          rsvpDeadlineHours: s.rsvpDeadlineHours,
          autoCreateDaysBefore: s.autoCreateDaysBefore,
          autoCreateTime: s.autoCreateTime,
        )) {
      errors.add(MatchSettingsError.deadlineBeforeAutoCreate);
    }
    return errors;
  }
}
