/// 부상 기록 (data-model.md v4.6 8-2). 화면(2단계)은 아직 없다.
///
/// 읽기 범위는 서버 권한 규칙이 정한다: 본인은 전부, 지금 같은 팀 팀원은 진행 중인 것만(주인의 부상 동의가
/// 유효할 때만). 앱에서 "이 사람이 볼 수 있나" 판단은 entitlements(`InjuryInfo`) 한 곳에서 한다.
class Injury {
  const Injury({
    required this.id,
    required this.userId,
    required this.startedOn,
    required this.expectedReturnOn,
    required this.isActive,
    this.memo,
    this.recoveredAt,
  });

  /// 표에서 읽는 칸 (return_check_sent_for 는 앱에 필요 없음).
  static const columns = 'id, user_id, started_on, expected_return_on, memo, status, recovered_at';

  final String id;
  final String userId;

  /// 등록일 (한국 날짜)
  final DateTime startedOn;

  /// 예상 복귀일 (한국 날짜)
  final DateTime expectedReturnOn;
  final String? memo;
  final bool isActive;
  final DateTime? recoveredAt;

  factory Injury.fromRow(Map<String, dynamic> row) => Injury(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    startedOn: DateTime.parse(row['started_on'] as String),
    expectedReturnOn: DateTime.parse(row['expected_return_on'] as String),
    memo: row['memo'] as String?,
    isActive: row['status'] == 'active',
    recoveredAt: row['recovered_at'] == null ? null : DateTime.parse(row['recovered_at'] as String),
  );

  /// 남은 회복 기간(주). 저장하지 않고 오늘(한국 날짜) 기준으로 계산한다 (8-2).
  /// 올림: 1~7일 남음 = 1, 8~14일 = 2, 복귀일 당일·지남 = 0 (마이너스 없음, 자동 해제 없음) (S4-04).
  int remainingWeeks(DateTime todayKst) => remainingWeeksBetween(todayKst, expectedReturnOn);

  static int remainingWeeksBetween(DateTime todayKst, DateTime expectedReturnOn) {
    final today = DateTime.utc(todayKst.year, todayKst.month, todayKst.day);
    final target = DateTime.utc(expectedReturnOn.year, expectedReturnOn.month, expectedReturnOn.day);
    final days = target.difference(today).inDays;
    if (days <= 0) return 0;
    return (days + 6) ~/ 7;
  }
}

/// 예상 회복 기간 선택지 1~12주 (S4-06 (1)). 더 길면 12주로 등록 뒤 연장.
abstract final class InjuryRules {
  static const int minWeeks = 1;
  static const int maxWeeks = 12;

  /// 연장 선택지 (+1W, +2W)
  static const List<int> extendWeeks = [1, 2];

  /// 메모 최대 글자 수 (보이는 글자, Flutter characters 로 셈)
  static const int maxMemoLength = 20;
}
