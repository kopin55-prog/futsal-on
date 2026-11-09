import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/match_models.dart';
import '../domain/past_matches.dart';

/// 일정 (data-model.md 4-1). 읽기는 표(그 팀 팀원), 추가·취소는 서버 함수(관리자, 서버가 다시 확인).
/// 일정 수정 기능은 1차에 없다 (Q-071 4번). 실패는 모두 [ServerFailure].
abstract interface class MatchRepository {
  /// 팀의 일정 (취소 포함), 시작 시각 순. [from] 이 있으면 그 시각 이후에 끝나는 일정만.
  Future<List<TeamMatch>> listMatches(String teamId, {DateTime? from});

  /// 종료 시각이 [before] 이전(같은 시각 포함)인 지난 일정 (취소 포함), 최근 순(종료 시각)으로 최대 [limit]개.
  /// 화면에 보일 범위(최근 10경기)는 [PastMatches.recent] 가 정한다.
  Future<List<TeamMatch>> listPastMatches(String teamId, {required DateTime before, int limit = PastMatches.fetchLimit});

  /// 일정 한 건. 볼 수 없거나(떠난 팀) 없어진 일정이면 null.
  Future<TeamMatch?> getMatch(String matchId);

  /// 직접 추가. 새 일정 ID.
  Future<String> createMatch(String teamId, MatchInput input);

  /// 취소 (시작 전까지, 되돌리기 없음). [reason] 은 선택 (1~20자, 비우면 없음).
  Future<void> cancelMatch(String matchId, {String? reason});
}

class SupabaseMatchRepository implements MatchRepository {
  SupabaseMatchRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<TeamMatch>> listMatches(String teamId, {DateTime? from}) => guardServer(() async {
    var query = _client.from('matches').select(TeamMatch.columns).eq('team_id', teamId);
    if (from != null) query = query.gt('ends_at', from.toUtc().toIso8601String());
    final rows = await query.order('starts_at');
    return [for (final r in rows) TeamMatch.fromRow(r)];
  });

  @override
  Future<List<TeamMatch>> listPastMatches(String teamId, {required DateTime before, int limit = PastMatches.fetchLimit}) =>
      guardServer(() async {
        final rows = await _client
            .from('matches')
            .select(TeamMatch.columns)
            .eq('team_id', teamId)
            .lte('ends_at', before.toUtc().toIso8601String())
            .order('ends_at', ascending: false)
            .order('starts_at', ascending: false)
            .limit(limit);
        return [for (final r in rows) TeamMatch.fromRow(r)];
      });

  @override
  Future<TeamMatch?> getMatch(String matchId) => guardServer(() async {
    final row = await _client.from('matches').select(TeamMatch.columns).eq('id', matchId).maybeSingle();
    return row == null ? null : TeamMatch.fromRow(row);
  });

  @override
  Future<String> createMatch(String teamId, MatchInput input) => guardServer(
    () async => await _client.rpc<String>('create_match', params: input.toServerParams(teamId)),
  );

  @override
  Future<void> cancelMatch(String matchId, {String? reason}) => guardServer(
    () => _client.rpc<void>(
      'cancel_match',
      params: {'p_match_id': matchId, 'p_reason': reason},
    ),
  );
}
