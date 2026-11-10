import '../../../shared/data/server_error.dart';
import '../../pom_vote/presentation/award_texts.dart';
import '../../team/presentation/team_texts.dart';

/// 내 기록 화면 문구.
///
/// 문서 용어(그대로 씀): "POM", "오늘의 골", "기록 없음"(data-model 7-7), "누적".
/// 나머지는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class RecordsTexts {
  // ---- 문서 용어 ----
  static const pom = AwardTexts.pom;
  static const goalOfTheDay = AwardTexts.goalOfTheDay;
  static const noRecordPercent = '기록 없음';
  static const allSeasons = '누적';

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const sectionTitle = '나의 기록';
  static String seasonLabel(int season) => '$season';
  static const totalTitle = '전체 합산';
  static const attendance = '출석';
  static const participation = '참석 투표 참여율';
  static String times(int n) => '$n회';
  static String percent(int? p) => p == null ? noRecordPercent : '$p%';
  static const leftTeam = '(떠난 팀)';
  static const dissolvedTeam = '(해체된 팀)';
  static const empty = '아직 기록이 없어요';
  static const loadFailed = TeamTexts.loadFailed;
  static const retry = TeamTexts.retry;

  static String serverError(ServerErrorCode code) => TeamTexts.serverError(code);
}
