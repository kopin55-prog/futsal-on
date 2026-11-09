import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/lineup_models.dart';

/// 팀 배치 (data-model.md 5-1~5-3).
///
/// 읽기: 관리자는 항상, 팀원은 확정된 배치만 (서버 권한 규칙). 초안은 팀원에게 없는 것(null)으로 보인다.
/// 쓰기: 서버 함수 save_lineup 하나로 저장·확정·확정 후 수정 (관리자만, 참석 마감 뒤~경기 종료 전).
/// 버튼 노출은 Entitlements(TeamAction.manageLineup)로 판단하고 서버가 다시 거절한다.
/// 실패는 모두 [ServerFailure]. 동시 수정이면 [ServerErrorCode.lineupConflict] → 새로 불러온다.
abstract interface class LineupRepository {
  /// 그 일정의 배치. 없거나 읽을 수 없으면 null.
  Future<Lineup?> getLineup(String matchId);

  /// 팀 수·팀당 인원 처음 값용 (Q-075 7번 (4)): 이 팀에서 [before] 전에 시작한 다른 일정 중 가장 최근 배치의 값.
  /// 없으면 null. 관리자만 읽힌다 (초안 포함).
  Future<({int teams, int players})?> lastLineupSize(String teamId, {required DateTime before, required String excludeMatchId});

  /// 통째로 저장. [expectedUpdatedAt] = 마지막으로 읽은 [Lineup.updatedAt] (처음 만들 때 null).
  /// [confirm] 이면 확정 (이미 확정이면 무시, 확정 취소는 없음).
  Future<LineupSaveResult> saveLineup(
    String matchId,
    LineupDraft draft, {
    required String? expectedUpdatedAt,
    bool confirm = false,
  });
}

class SupabaseLineupRepository implements LineupRepository {
  SupabaseLineupRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Lineup?> getLineup(String matchId) => guardServer(() async {
    final row = await _client
        .from('lineups')
        .select(Lineup.columns)
        .eq('match_id', matchId)
        .maybeSingle();
    if (row == null) return null;
    final lineupId = row['id'] as String;
    final squads = await _client
        .from('lineup_squads')
        .select(Lineup.squadColumns)
        .eq('lineup_id', lineupId);
    final slots = await _client
        .from('lineup_slots')
        .select(Lineup.slotColumns)
        .eq('lineup_id', lineupId);
    return Lineup.fromRows(row, squads, slots);
  });

  @override
  Future<({int teams, int players})?> lastLineupSize(
    String teamId, {
    required DateTime before,
    required String excludeMatchId,
  }) => guardServer(() async {
    final rows = await _client
        .from('lineups')
        .select('match_id, team_count, players_per_team, matches!inner(team_id, starts_at)')
        .eq('matches.team_id', teamId)
        .lt('matches.starts_at', before.toUtc().toIso8601String())
        .neq('match_id', excludeMatchId);
    // 일정 시작 시각 순 정렬은 앱에서 (최근 10경기 정리로 줄 수가 적다)
    DateTime startsAt(Map<String, dynamic> r) =>
        DateTime.parse((r['matches'] as Map<String, dynamic>)['starts_at'] as String);
    final sorted = [...rows]..sort((a, b) => startsAt(b).compareTo(startsAt(a)));
    if (sorted.isEmpty) return null;
    final r = sorted.first;
    return (teams: r['team_count'] as int, players: r['players_per_team'] as int);
  });

  @override
  Future<LineupSaveResult> saveLineup(
    String matchId,
    LineupDraft draft, {
    required String? expectedUpdatedAt,
    bool confirm = false,
  }) => guardServer(() async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'save_lineup',
      params: draft.toServerParams(matchId, expectedUpdatedAt: expectedUpdatedAt, confirm: confirm),
    );
    return LineupSaveResult.fromJson(result);
  });
}
