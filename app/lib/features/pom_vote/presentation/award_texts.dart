import '../../../shared/data/server_error.dart';
import '../../team/presentation/team_texts.dart';

/// 투표 설정·POM·오늘의 골 화면 문구.
///
/// 문서 용어(그대로 씀): "POM", "오늘의 골", "투표 설정"(Q-076 1번).
/// 나머지 안내·오류 문구는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class AwardTexts {
  // ---- 문서 용어 ----
  static const awardSettings = '투표 설정';
  static const pom = 'POM';
  static const goalOfTheDay = '오늘의 골';

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const announceLabel = 'POM·오늘의 골 발표 시각';
  static String announceButton(String hhmm) => '경기 다음날 $hhmm';
  static const announceNote = '경기가 끝난 다음날 이 시각에 투표가 마감되고 결과가 나와요.';
  static const keepNote = '바꾼 시각은 앞으로 열리는 투표부터 적용돼요.';
  static const save = '저장';
  static const saved = '저장했어요';

  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.invalidAwardSettings => '발표 시각을 다시 골라 주세요.',
    ServerErrorCode.awardPollNotFound => '투표를 찾을 수 없어요.',
    ServerErrorCode.awardNotParticipant => '이번 경기 투표 대상이 아니에요.',
    ServerErrorCode.awardPollClosed => '투표가 마감됐어요.',
    ServerErrorCode.awardAlreadyVoted => '이미 투표했어요.',
    ServerErrorCode.awardSelfVote => '본인에게는 투표할 수 없어요.',
    ServerErrorCode.awardInvalidCandidate || ServerErrorCode.awardInvalidCategory => '다시 불러온 뒤 골라 주세요.',
    _ => TeamTexts.serverError(code),
  };
}
