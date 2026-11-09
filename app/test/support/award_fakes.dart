import 'package:futsal_on/features/pom_vote/data/award_repository.dart';
import 'package:futsal_on/features/pom_vote/domain/award_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 가짜 투표 저장소 (투표 설정 화면 테스트용). 투표 내용은 기억하지 않는다 (누구를 찍었는지 남기지 않음).
class FakeAwardRepository implements AwardRepository {
  final Map<String, ClockTime> announceTimes = {};
  final Map<String, AwardPollView> polls = {};
  final List<(String, AwardCategory)> votes = [];
  final List<String> calls = [];

  /// 다음 호출을 이 오류로 실패시킨다.
  ServerErrorCode? failNext;

  void _maybeFail() {
    final code = failNext;
    if (code != null) {
      failNext = null;
      throw ServerFailure(code);
    }
  }

  @override
  Future<ClockTime> getAnnounceTime(String teamId) async {
    _maybeFail();
    return announceTimes[teamId] ?? AwardSettings.defaultAnnounceTime;
  }

  @override
  Future<ClockTime> updateAnnounceTime(String teamId, ClockTime time) async {
    _maybeFail();
    return announceTimes[teamId] = time;
  }

  @override
  Future<AwardPollView?> getPoll(String matchId, {required String myUserId}) async {
    calls.add('get:$matchId');
    _maybeFail();
    return polls[matchId];
  }

  @override
  Future<void> castVote(String matchId, AwardCategory category, String candidateId) async {
    calls.add('cast:$matchId');
    _maybeFail();
    votes.add((matchId, category));
    // 서버처럼 본인 참여 표시만 남긴다 (누구를 찍었는지는 기억하지 않음)
    final p = polls[matchId];
    if (p != null) {
      polls[matchId] = AwardPollView(
        matchId: p.matchId,
        teamId: p.teamId,
        opensAt: p.opensAt,
        closesAt: p.closesAt,
        status: p.status,
        participantIds: p.participantIds,
        myVoted: {...p.myVoted, category},
        winners: p.winners,
      );
    }
  }
}
