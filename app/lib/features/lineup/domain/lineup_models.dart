import 'bib_color.dart';

/// 팀 배치 상태 (data-model.md 5-1). 확정 취소(초안으로 되돌리기)는 없다 (Q-075 1번).
enum LineupStatus {
  draft,
  confirmed;

  static LineupStatus fromServer(String value) => LineupStatus.values.byName(value);
}

/// 서버에 저장하는 경고 종류 (lineups.warnings). 필수 조건(전문 GK·그룹·라이벌)을 못 지켰을 때.
/// 사람 이름·등급은 담지 않는다. 교체 N명·N명 모자람은 명단에서 바로 셀 수 있어 저장하지 않는다.
enum LineupWarningKind {
  /// 전문 골키퍼가 팀보다 많아 한 팀에 2명 이상.
  dedicatedGkOverTeams('dedicated_gk_over_teams'),

  /// 그룹을 한 팀에 모두 넣지 못함 (그룹 인원이 팀당 인원보다 많을 때 등).
  groupSplit('group_split'),

  /// 라이벌을 모두 다른 팀으로 나누지 못함.
  rivalSameTeam('rival_same_team');

  const LineupWarningKind(this.serverValue);

  final String serverValue;

  static LineupWarningKind? fromServer(String value) {
    for (final k in LineupWarningKind.values) {
      if (k.serverValue == value) return k;
    }
    return null;
  }
}

/// 배치에 들어가는 사람: 팀원(userId) 또는 게스트(guestId) 중 하나.
class LineupPerson implements Comparable<LineupPerson> {
  const LineupPerson.member(String this.userId) : guestId = null;
  const LineupPerson.guest(String this.guestId) : userId = null;

  final String? userId;
  final String? guestId;

  bool get isGuest => guestId != null;

  /// 계산·비교용 고유 문자열.
  String get key => isGuest ? 'g:$guestId' : 'u:$userId';

  Map<String, dynamic> toServerJson(int? squadNo) => {
    'squad_no': squadNo,
    if (isGuest) 'guest_id': guestId else 'user_id': userId,
  };

  static LineupPerson fromRow(Map<String, dynamic> row) {
    final guestId = row['guest_id'] as String?;
    return guestId != null
        ? LineupPerson.guest(guestId)
        : LineupPerson.member(row['user_id'] as String);
  }

  @override
  int compareTo(LineupPerson other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is LineupPerson && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// 저장된 배치의 팀 블록 하나.
class LineupSquad {
  const LineupSquad({
    required this.id,
    required this.squadNo,
    required this.bibColor,
    required this.people,
  });

  final String id;
  final int squadNo;
  final BibColor bibColor;

  /// 화면 표시 순서(가나다순)는 저장하지 않는다. 화면이 이름으로 정렬한다.
  final List<LineupPerson> people;
}

/// 저장된 배치 (서버 읽기). 팀원은 확정된 배치만 읽을 수 있다(초안은 null 로 보인다).
class Lineup {
  const Lineup({
    required this.id,
    required this.matchId,
    required this.teamCount,
    required this.playersPerTeam,
    required this.status,
    required this.warnings,
    required this.version,
    required this.updatedAt,
    required this.squads,
    required this.bench,
    this.confirmedAt,
  });

  final String id;
  final String matchId;
  final int teamCount;
  final int playersPerTeam;
  final LineupStatus status;
  final Set<LineupWarningKind> warnings;
  final int version;

  /// 동시 수정 검사용. 서버가 준 문자열 그대로 다시 보낸다(마이크로초까지 같아야 함).
  final String updatedAt;
  final DateTime? confirmedAt;

  /// 팀 블록 (squad_no 순).
  final List<LineupSquad> squads;

  /// 교체 블록.
  final List<LineupPerson> bench;

  bool get isConfirmed => status == LineupStatus.confirmed;

  static const columns =
      'id, match_id, team_count, players_per_team, status, warnings, version, updated_at, confirmed_at';
  static const squadColumns = 'id, lineup_id, squad_no, bib_color';
  static const slotColumns = 'id, lineup_id, squad_id, user_id, guest_id';

  /// lineups 한 줄 + 그 배치의 lineup_squads·lineup_slots 줄로 만든다.
  static Lineup fromRows(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> squadRows,
    List<Map<String, dynamic>> slotRows,
  ) {
    final sortedSquads = [...squadRows]
      ..sort((a, b) => (a['squad_no'] as int).compareTo(b['squad_no'] as int));
    final squads = [
      for (final q in sortedSquads)
        LineupSquad(
          id: q['id'] as String,
          squadNo: q['squad_no'] as int,
          bibColor: BibColor.fromServer(q['bib_color'] as String),
          people: [
            for (final s in slotRows)
              if (s['squad_id'] == q['id']) LineupPerson.fromRow(s),
          ],
        ),
    ];
    return Lineup(
      id: row['id'] as String,
      matchId: row['match_id'] as String,
      teamCount: row['team_count'] as int,
      playersPerTeam: row['players_per_team'] as int,
      status: LineupStatus.fromServer(row['status'] as String),
      warnings: {
        for (final w in (row['warnings'] as List?) ?? const [])
          ?LineupWarningKind.fromServer(w as String),
      },
      version: row['version'] as int,
      updatedAt: row['updated_at'] as String,
      confirmedAt: row['confirmed_at'] == null ? null : DateTime.parse(row['confirmed_at'] as String),
      squads: squads,
      bench: [
        for (final s in slotRows)
          if (s['squad_id'] == null) LineupPerson.fromRow(s),
      ],
    );
  }

  /// 다시 저장할 때 쓰는 내용.
  LineupDraft toDraft() => LineupDraft(
    playersPerTeam: playersPerTeam,
    squads: [
      for (final q in squads) LineupSquadDraft(bibColor: q.bibColor, people: q.people),
    ],
    bench: bench,
    warnings: warnings,
  );
}

/// 저장할 팀 블록 하나 (번호는 목록 순서 + 1).
class LineupSquadDraft {
  const LineupSquadDraft({required this.bibColor, required this.people});

  final BibColor bibColor;
  final List<LineupPerson> people;
}

/// 저장할 배치 내용 (save_lineup 에 한 번에 보냄). 팀 수 = [squads] 길이.
class LineupDraft {
  const LineupDraft({
    required this.playersPerTeam,
    required this.squads,
    required this.bench,
    this.warnings = const {},
  });

  final int playersPerTeam;
  final List<LineupSquadDraft> squads;
  final List<LineupPerson> bench;
  final Set<LineupWarningKind> warnings;

  int get teamCount => squads.length;

  /// save_lineup 인자. [expectedUpdatedAt] 은 마지막으로 읽은 배치의 updated_at (처음 만들 때 null).
  Map<String, dynamic> toServerParams(
    String matchId, {
    required String? expectedUpdatedAt,
    required bool confirm,
  }) => {
    'p_match_id': matchId,
    'p_expected_updated_at': expectedUpdatedAt,
    'p_team_count': teamCount,
    'p_players_per_team': playersPerTeam,
    'p_squads': [
      for (var i = 0; i < squads.length; i++)
        {'squad_no': i + 1, 'bib_color': squads[i].bibColor.serverValue},
    ],
    'p_slots': [
      for (var i = 0; i < squads.length; i++)
        for (final p in squads[i].people) p.toServerJson(i + 1),
      for (final p in bench) p.toServerJson(null),
    ],
    'p_warnings': [for (final w in LineupWarningKind.values) if (warnings.contains(w)) w.serverValue],
    'p_confirm': confirm,
  };
}

/// save_lineup 결과 (실력·점수 없음).
class LineupSaveResult {
  const LineupSaveResult({
    required this.lineupId,
    required this.status,
    required this.version,
    required this.updatedAt,
  });

  final String lineupId;
  final LineupStatus status;
  final int version;
  final String updatedAt;

  static LineupSaveResult fromJson(Map<String, dynamic> json) => LineupSaveResult(
    lineupId: json['lineup_id'] as String,
    status: LineupStatus.fromServer(json['status'] as String),
    version: json['version'] as int,
    updatedAt: json['updated_at'] as String,
  );
}
