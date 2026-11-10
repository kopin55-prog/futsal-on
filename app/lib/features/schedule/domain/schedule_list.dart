import 'attendance_models.dart';
import 'match_models.dart';

/// 일정 탭 한 줄 재료 (스프린트 04 5-1, S4-13).
/// 예) "11/18(수) 10:00~12:00 · 성수 풋살장 · 참석 9/12 · 나: 참석". 취소된 일정은 숫자 대신 "취소됨".
class ScheduleRow {
  const ScheduleRow({
    required this.match,
    required this.attendingCount,
    required this.myState,
    this.myWaitPosition,
  });

  /// 응답 목록에서 만든다. [me] 는 보는 사람.
  factory ScheduleRow.of(TeamMatch match, Iterable<AttendanceResponse> responses, String me) {
    final roster = AttendanceRoster(responses);
    return ScheduleRow(
      match: match,
      attendingCount: roster.attendingCount,
      myState: roster.responseOf(me)?.state,
      myWaitPosition: roster.waitlistPosition(me),
    );
  }

  final TeamMatch match;

  /// 참석 인원 (게스트·대기 제외)
  final int attendingCount;

  /// 내 응답 (null 이면 미투표)
  final AttendanceState? myState;

  /// 대기 순번 (대기일 때만)
  final int? myWaitPosition;
}

/// 일정 탭 달력 보기 규칙 (5-2, S4-13): 경기는 시작한 한국 날짜에 표시한다.
abstract final class ScheduleCalendar {
  /// 한국 날짜 → 그날 시작하는 일정 (시작 순). 같은 일정이 두 번 들어와도 한 번만.
  static Map<CalendarDate, List<TeamMatch>> byDate(Iterable<TeamMatch> matches) {
    final seen = <String>{};
    final out = <CalendarDate, List<TeamMatch>>{};
    for (final m in matches) {
      if (!seen.add(m.id)) continue;
      (out[Kst.dateOf(m.startsAt)] ??= []).add(m);
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final c = a.startsAt.compareTo(b.startsAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    }
    return out;
  }

  /// 달력 칸(table_calendar 가 주는 날짜, 시간대 무관하게 연·월·일만 쓴다) → 한국 날짜.
  static CalendarDate dayOf(DateTime calendarDay) => CalendarDate(calendarDay.year, calendarDay.month, calendarDay.day);

  /// 한 칸에 그리는 점 최대 개수 (일정마다 점 하나, 취소된 일정은 회색 점)
  static const maxDots = 3;
}
