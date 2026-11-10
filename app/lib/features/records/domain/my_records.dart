/// 내 기록 (data-model.md v4.6 7-2·7-3·7-7, 스프린트 04 3-1·3-2, S4-12).
///
/// 서버 함수 get_my_records 가 본인 기록만 팀별·시즌별 줄로 준다 (떠난 팀·해체된 팀 포함, 득표수 없음).
/// 시즌 고르기·전체 합산·팀별 묶기·참여율 계산은 여기서 한다.
library;

/// 한 팀·한 시즌의 기록 (get_my_records 한 줄).
class TeamSeasonRecord {
  const TeamSeasonRecord({
    required this.teamId,
    required this.teamName,
    required this.logoText,
    required this.isMember,
    required this.isDissolved,
    required this.season,
    this.attendance = 0,
    this.pom = 0,
    this.goalOfTheDay = 0,
    this.voteEligible = 0,
    this.voteResponded = 0,
  });

  factory TeamSeasonRecord.fromRow(Map<String, dynamic> row) => TeamSeasonRecord(
    teamId: row['team_id'] as String,
    teamName: row['team_name'] as String,
    logoText: row['logo_text'] as String,
    isMember: row['is_member'] as bool,
    isDissolved: row['is_dissolved'] as bool,
    season: row['season'] as int,
    attendance: row['attendance_count'] as int,
    pom: row['pom_count'] as int,
    goalOfTheDay: row['goal_of_the_day_count'] as int,
    voteEligible: row['vote_eligible'] as int,
    voteResponded: row['vote_responded'] as int,
  );

  final String teamId;
  final String teamName;
  final String logoText;

  /// 지금 그 팀 소속인지
  final bool isMember;

  /// 팀이 해체됐는지
  final bool isDissolved;

  /// 시즌 (연도)
  final int season;
  final int attendance;
  final int pom;
  final int goalOfTheDay;

  /// 참석 투표 대상 횟수
  final int voteEligible;

  /// 그중 응답(또는 마감 시각 부상 중) 횟수
  final int voteResponded;
}

/// 합친 숫자 (전체 합산 또는 한 팀).
class RecordTotals {
  const RecordTotals({
    this.attendance = 0,
    this.pom = 0,
    this.goalOfTheDay = 0,
    this.voteEligible = 0,
    this.voteResponded = 0,
  });

  final int attendance;
  final int pom;
  final int goalOfTheDay;
  final int voteEligible;
  final int voteResponded;

  RecordTotals operator +(TeamSeasonRecord r) => RecordTotals(
    attendance: attendance + r.attendance,
    pom: pom + r.pom,
    goalOfTheDay: goalOfTheDay + r.goalOfTheDay,
    voteEligible: voteEligible + r.voteEligible,
    voteResponded: voteResponded + r.voteResponded,
  );

  /// 참석 투표 참여율 (%). 소수점 없이 반올림(0.5 는 올림, Q-064), 대상 0회면 null = "기록 없음" (7-7).
  int? get participationPercent => participationPercentOf(voteResponded, voteEligible);

  static int? participationPercentOf(int responded, int eligible) {
    if (eligible <= 0) return null;
    return (responded * 200 + eligible) ~/ (eligible * 2);
  }
}

/// 팀 하나의 기록 카드 재료.
class TeamRecordSummary {
  const TeamRecordSummary({
    required this.teamId,
    required this.teamName,
    required this.logoText,
    required this.isMember,
    required this.isDissolved,
    required this.totals,
  });

  final String teamId;
  final String teamName;
  final String logoText;
  final bool isMember;
  final bool isDissolved;
  final RecordTotals totals;
}

/// 내 기록 전체. [season] null = 누적.
class MyRecords {
  MyRecords(this.rows);

  final List<TeamSeasonRecord> rows;

  bool get isEmpty => rows.isEmpty;

  /// 고를 수 있는 시즌: 기록이 있는 연도만, 최근 순 (S4-12).
  List<int> get seasons => ({for (final r in rows) r.season}.toList()..sort((a, b) => b.compareTo(a)));

  Iterable<TeamSeasonRecord> _of(int? season) => season == null ? rows : rows.where((r) => r.season == season);

  /// 전체 합산 (모든 팀).
  RecordTotals total({int? season}) => _of(season).fold(const RecordTotals(), (t, r) => t + r);

  /// 팀별: 지금 팀 먼저, 그다음 떠난 팀·해체된 팀. 같은 묶음 안에서는 팀 이름 가나다순 (같으면 ID 순).
  List<TeamRecordSummary> byTeam({int? season}) {
    final groups = <String, List<TeamSeasonRecord>>{};
    for (final r in _of(season)) {
      (groups[r.teamId] ??= []).add(r);
    }
    final list = [
      for (final e in groups.entries)
        TeamRecordSummary(
          teamId: e.key,
          teamName: e.value.first.teamName,
          logoText: e.value.first.logoText,
          isMember: e.value.first.isMember,
          isDissolved: e.value.first.isDissolved,
          totals: e.value.fold(const RecordTotals(), (t, r) => t + r),
        ),
    ];
    list.sort((a, b) {
      if (a.isMember != b.isMember) return a.isMember ? -1 : 1;
      final byName = a.teamName.compareTo(b.teamName);
      return byName != 0 ? byName : a.teamId.compareTo(b.teamId);
    });
    return list;
  }
}
