import 'package:futsal_on/features/lineup/data/lineup_repository.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 팀 배치 흉내. 서버 규칙 중 화면에 필요한 것만: 동시 수정 검사(updated_at), 확정 후 version +1,
/// 팀원에게 초안 숨김([hideDrafts]).
class FakeLineupRepository implements LineupRepository {
  final Map<String, Lineup> byMatch = {};
  final Map<String, ({int teams, int players})> lastSizes = {};
  final List<String> calls = [];
  final List<LineupDraft> savedDrafts = [];
  ServerFailure? nextFailure;

  /// 팀원으로 읽는 흉내: 초안은 없는 것으로 보인다.
  bool hideDrafts = false;
  int _seq = 0;

  String _stamp() => '2026-11-09T00:00:00.${(++_seq).toString().padLeft(6, '0')}+00:00';

  /// 테스트 준비용.
  void seed(String matchId, LineupDraft draft, {bool confirmed = false, int version = 1}) {
    byMatch[matchId] = _build(matchId, draft, confirmed ? LineupStatus.confirmed : LineupStatus.draft, version);
  }

  /// 다른 운영진이 먼저 저장한 흉내 (updated_at 만 바뀜).
  void touch(String matchId) {
    final l = byMatch[matchId]!;
    byMatch[matchId] = _build(matchId, l.toDraft(), l.status, l.version);
  }

  Lineup _build(String matchId, LineupDraft d, LineupStatus status, int version) {
    final id = 'L-$matchId';
    return Lineup(
      id: id,
      matchId: matchId,
      teamCount: d.teamCount,
      playersPerTeam: d.playersPerTeam,
      status: status,
      warnings: d.warnings,
      version: version,
      updatedAt: _stamp(),
      confirmedAt: status == LineupStatus.confirmed ? DateTime.utc(2026, 11, 9) : null,
      squads: [
        for (var i = 0; i < d.squads.length; i++)
          LineupSquad(id: '$id-q${i + 1}', squadNo: i + 1, bibColor: d.squads[i].bibColor, people: d.squads[i].people),
      ],
      bench: d.bench,
    );
  }

  @override
  Future<Lineup?> getLineup(String matchId) async {
    final l = byMatch[matchId];
    if (l == null || (hideDrafts && !l.isConfirmed)) return null;
    return l;
  }

  @override
  Future<({int teams, int players})?> lastLineupSize(
    String teamId, {
    required DateTime before,
    required String excludeMatchId,
  }) async => lastSizes[teamId];

  @override
  Future<LineupSaveResult> saveLineup(
    String matchId,
    LineupDraft draft, {
    required String? expectedUpdatedAt,
    bool confirm = false,
  }) async {
    calls.add('save:$matchId:${confirm ? 'confirm' : 'plain'}');
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    final current = byMatch[matchId];
    if (current?.updatedAt != expectedUpdatedAt) throw const ServerFailure(ServerErrorCode.lineupConflict);
    savedDrafts.add(draft);
    final status = current?.isConfirmed == true || confirm ? LineupStatus.confirmed : LineupStatus.draft;
    final version = current?.isConfirmed == true ? current!.version + 1 : 1;
    final next = _build(matchId, draft, status, version);
    byMatch[matchId] = next;
    return LineupSaveResult(lineupId: next.id, status: next.status, version: next.version, updatedAt: next.updatedAt);
  }
}
