import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../../team/domain/team_validation.dart';
import '../domain/award_models.dart';

/// POM·오늘의 골 투표와 투표 설정 (data-model.md 3-2 award_announce_time, 6장).
///
/// - 투표 설정 읽기: 그 팀 팀원 / 바꾸기: 서버 함수 update_award_settings (관리자만).
/// - 회차·대상자·수상자 읽기: 그 팀 팀원. 참여 표시: 본인 것만. 득표 집계는 읽을 수 없다 (서버 권한 규칙).
/// - 투표: 서버 함수 cast_award_vote 하나. 성공/실패만 돌아오고 득표수는 없다.
///   앱은 누구를 찍었는지 기기·로그·오류 보고에 남기지 않는다 (6-4 security 반영).
/// 실패는 모두 [ServerFailure].
abstract interface class AwardRepository {
  /// 팀의 발표 시각 (없으면 기본 15:00).
  Future<ClockTime> getAnnounceTime(String teamId);

  /// 발표 시각 바꾸기. 서버가 저장한 시각(분 단위)을 돌려준다.
  Future<ClockTime> updateAnnounceTime(String teamId, ClockTime time);

  /// 그 경기의 투표. 열리지 않았거나(배치 미확정이어도 참석자 2명 이상이면 열림) 읽을 수 없으면 null.
  Future<AwardPollView?> getPoll(String matchId, {required String myUserId});

  /// 한 항목에 한 표. 바꾸기·취소 없음.
  Future<void> castVote(String matchId, AwardCategory category, String candidateId);
}

class SupabaseAwardRepository implements AwardRepository {
  SupabaseAwardRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ClockTime> getAnnounceTime(String teamId) => guardServer(() async {
    final row = await _client
        .from('team_settings')
        .select('award_announce_time')
        .eq('team_id', teamId)
        .maybeSingle();
    final value = row?['award_announce_time'] as String?;
    return value == null ? AwardSettings.defaultAnnounceTime : ClockTime.parse(value);
  });

  @override
  Future<ClockTime> updateAnnounceTime(String teamId, ClockTime time) => guardServer(() async {
    final saved = await _client.rpc<dynamic>(
      'update_award_settings',
      params: {'p_team_id': teamId, 'p_award_announce_time': time.hhmm},
    );
    return saved is String ? ClockTime.parse(saved) : time;
  });

  @override
  Future<AwardPollView?> getPoll(String matchId, {required String myUserId}) => guardServer(() async {
    final poll = await _client
        .from('award_polls')
        .select(AwardPollView.pollColumns)
        .eq('match_id', matchId)
        .maybeSingle();
    if (poll == null) return null;
    final participants = await _client.from('award_participants').select('user_id').eq('match_id', matchId);
    final receipts = await _client
        .from('award_ballot_receipts')
        .select('category')
        .eq('match_id', matchId)
        .eq('voter_id', myUserId);
    final winners = await _client.from('award_winners').select('category, user_id').eq('match_id', matchId);
    return AwardPollView.fromRows(poll, participants: participants, myReceipts: receipts, winners: winners);
  });

  @override
  Future<void> castVote(String matchId, AwardCategory category, String candidateId) => guardServer(
    () => _client.rpc<dynamic>(
      'cast_award_vote',
      params: {'p_match_id': matchId, 'p_category': category.code, 'p_candidate_id': candidateId},
    ),
  );
}
