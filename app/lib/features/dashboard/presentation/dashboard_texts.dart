import '../../../shared/data/server_error.dart';
import '../../injury/presentation/injury_texts.dart';
import '../../pom_vote/presentation/award_texts.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../../team/presentation/team_texts.dart';

/// 홈(팀 대시보드) 문구.
///
/// 문서 용어(그대로 씀): "홈", "POM", "오늘의 골", "결과 없음", "부상자", "처리할 일", "게스트".
/// 나머지는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class DashboardTexts {
  // ---- 문서 용어 ----
  static const tabHome = '홈';
  static const noResult = AwardTexts.noResult;
  static const pom = AwardTexts.pom;
  static const goalOfTheDay = AwardTexts.goalOfTheDay;

  // ---- TODO(문구 미정): 아래는 임시 ----
  static String memberCount(int n) => '팀원 $n명';

  // 처리할 일
  static const todoTitle = '처리할 일';
  static String joinRequests(int n) => '가입 신청 $n건';
  static String lineupPending(String when) => '팀 나누기 대기 · $when';

  // 다음 경기
  static const nextTitle = '다음 경기';
  static const inProgress = '진행 중';
  static const noNext = '다가오는 경기가 없어요';
  static const addMatch = ScheduleTexts.addMatch;
  static const myStatus = ScheduleTexts.myStatus;
  static const injured = '부상 중';
  static String counts({required int attending, int? capacity, required int waitlist, required int notResponded}) {
    final a = capacity == null ? '참석 $attending' : '참석 $attending / $capacity';
    return '$a · 대기 $waitlist · 미투표 $notResponded';
  }

  static const attend = ScheduleTexts.attendButton;
  static const decline = ScheduleTexts.declineButton;
  static const deadlinePassed = ScheduleTexts.deadlinePassed;
  static const myTeam = '내 팀';
  static const notInLineup = '이번 경기 배치에 없어요';
  static const viewLineup = '전체 배치 보기';

  // 지난 경기
  static const lastTitle = '지난 경기 POM·오늘의 골';
  static String voting(DateTime closesAt) => '투표 중 · 발표 ${ScheduleTexts.dateTime(closesAt)}';
  static const vote = AwardTexts.voteButton;
  static const voted = AwardTexts.voted;
  static const closedPending = AwardTexts.closedPending;
  static const leftMember = AwardTexts.leftMember;

  // 부상자
  static String injuredTitle(int n) => '부상자 $n명';
  static String weeks(int w) => InjuryTexts.weeks(w);

  static const loadFailed = TeamTexts.loadFailed;
  static const retry = TeamTexts.retry;
  static String serverError(ServerErrorCode code) => ScheduleTexts.serverError(code);
}
