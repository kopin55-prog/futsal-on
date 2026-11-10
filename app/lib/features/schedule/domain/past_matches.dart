import 'match_models.dart';

/// 일정 탭 "지난 경기" 목록 (스프린트 03 5-1·S3-16, 정식 화면 스프린트 04 5-1).
///
/// 보관 규칙(data-model 7-5, Q-061 1번)과 같은 범위만 보여준다:
/// - 종료 시각이 지났고 취소되지 않은 일정을 최근 순(종료 시각)으로 [keep]개.
/// - 취소된 일정은 세지 않지만, 남은 [keep]경기 중 가장 오래된 경기보다 뒤의 것이면 "취소됨"으로 함께 보여준다.
///   (그보다 이전 취소 일정은 보관 정리 때 지워지는 대상)
/// [ended] 는 종료 시각이 지난 일정들(순서 상관없음). 결과는 최근 순.
abstract final class PastMatches {
  static const keep = 10;

  /// 서버에서 한 번에 읽어 올 최대 줄 수 (취소 일정이 섞여 있어도 10경기를 채우도록 넉넉히).
  static const fetchLimit = 50;

  static List<TeamMatch> recent(Iterable<TeamMatch> ended, {int keep = PastMatches.keep}) {
    final sorted = [...ended]..sort((a, b) {
      final c = b.endsAt.compareTo(a.endsAt);
      return c != 0 ? c : b.startsAt.compareTo(a.startsAt);
    });
    final kept = sorted.where((m) => !m.isCancelled).take(keep).toList();
    if (kept.length < keep) return sorted;
    final oldest = kept.last;
    return [
      for (final m in sorted)
        if (!m.isCancelled ? kept.contains(m) : !m.endsAt.isBefore(oldest.endsAt)) m,
    ];
  }
}
