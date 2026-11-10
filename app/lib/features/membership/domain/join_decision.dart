/// 가입 신청 여러 개 한 번에 승인·거절한 결과 (서버 decide_join_requests, Q-079 3번 c).
///
/// 서버는 신청 순서대로 처리하고, 정원(100명)·사람당 팀 수(10개)에 걸린 승인은 그 신청만 건너뛰어
/// 대기 상태로 둔다. 이미 처리된 신청·이 팀 신청이 아닌 것도 건너뛴다. 결과는 신청마다 한 줄.
enum JoinDecisionOutcome {
  approved('approved'),
  rejected('rejected'),

  /// 이미 처리됐거나(승인·거절·취소) 이 팀의 신청이 아님
  alreadyDecided('already_decided'),

  /// 팀 인원이 가득 참 (대기로 남음)
  teamFull('team_full'),

  /// 신청자가 이미 10개 팀 소속 (대기로 남음)
  teamLimitReached('team_limit_reached');

  const JoinDecisionOutcome(this.serverValue);

  final String serverValue;

  static JoinDecisionOutcome fromServer(String value) =>
      JoinDecisionOutcome.values.firstWhere((e) => e.serverValue == value, orElse: () => alreadyDecided);

  /// 승인·거절이 실제로 된 것
  bool get done => this == approved || this == rejected;
}

class JoinDecisionResult {
  const JoinDecisionResult(this.requestId, this.outcome);

  final String requestId;
  final JoinDecisionOutcome outcome;

  static JoinDecisionResult fromRow(Map<String, dynamic> row) =>
      JoinDecisionResult(row['request_id'] as String, JoinDecisionOutcome.fromServer(row['result'] as String));
}

/// 결과를 종류별로 센다 (안내 문구 재료).
class JoinDecisionSummary {
  JoinDecisionSummary(Iterable<JoinDecisionResult> results)
    : counts = {
        for (final o in JoinDecisionOutcome.values) o: results.where((r) => r.outcome == o).length,
      };

  final Map<JoinDecisionOutcome, int> counts;

  int of(JoinDecisionOutcome o) => counts[o] ?? 0;

  /// 승인·거절된 수
  int get doneCount => of(JoinDecisionOutcome.approved) + of(JoinDecisionOutcome.rejected);

  /// 건너뛴 수 (정원·팀 수·이미 처리)
  int get skippedCount => counts.values.fold(0, (a, b) => a + b) - doneCount;

  bool get allDone => skippedCount == 0;
}
