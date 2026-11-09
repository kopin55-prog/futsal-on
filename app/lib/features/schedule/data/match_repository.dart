import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/match_models.dart';

/// 일정 (data-model.md 4-1). 읽기는 표(그 팀 팀원), 추가·취소는 서버 함수(관리자, 서버가 다시 확인).
/// 일정 수정 기능은 1차에 없다 (Q-071 4번). 실패는 모두 [ServerFailure].
abstract interface class MatchRepository {
  /// 팀의 일정 (취소 포함), 시작 시각 순. [from] 이 있으면 그 시각 이후에 끝나는 일정만.
  Future<List<TeamMatch>> listMatches(String teamId, {DateTime? from});

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
