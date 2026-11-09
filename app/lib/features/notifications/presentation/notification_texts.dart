import '../../schedule/presentation/schedule_texts.dart';
import '../../team/presentation/team_texts.dart';

/// 알림함 화면 문구 (스프린트 02 4-3). 알림 본문은 서버가 만든 그대로 보여준다.
/// TODO(문구 미정): 모두 임시 — 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class NotificationTexts {
  static const title = '알림';
  static const readAll = '모두 읽음';
  static const empty = '최근 30일 동안 받은 알림이 없어요';
  static const loadFailed = TeamTexts.loadFailed;
  static const retry = TeamTexts.retry;

  /// 받은 시각: 1분 안 "방금", 1시간 안 "n분 전", 24시간 안 "n시간 전", 그 밖은 "11월 12일(수) 10:00"
  static String when(DateTime at, DateTime now) {
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    return ScheduleTexts.dateTime(at);
  }
}
