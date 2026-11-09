import '../../team/domain/team_validation.dart';

/// POM·오늘의 골 투표 항목 (data-model.md 6-3~6-5).
enum AwardCategory {
  pom('pom'),
  goalOfTheDay('goal_of_the_day');

  const AwardCategory(this.code);

  /// 서버 값
  final String code;

  static AwardCategory? fromCode(String? code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// 투표 회차 상태: 진행 중 / 마감(결과 확정).
enum AwardPollStatus {
  open('open'),
  closed('closed');

  const AwardPollStatus(this.code);

  final String code;

  static AwardPollStatus fromCode(String? code) =>
      code == 'closed' ? AwardPollStatus.closed : AwardPollStatus.open;
}

/// 투표 설정 (team_settings.award_announce_time, Q-076 1번).
///
/// 발표 시각 = 투표 마감 시각. 경기 종료일 다음날의 이 시각(한국 시간). 새벽 포함 자유 선택, 분 단위.
/// 투표가 열릴 때(경기 종료) 그때 설정으로 마감이 정해지므로 바꿔도 이미 열린 투표는 그대로.
abstract final class AwardSettings {
  static const ClockTime defaultAnnounceTime = ClockTime(15, 0);
}

/// 한 경기의 투표 화면 재료 (5단계 화면이 쓴다).
///
/// - 회차·대상자·수상자는 그 팀 팀원이 읽는다 (서버 권한 규칙).
/// - [myVoted] 는 본인 참여 표시만 (누구를 찍었는지는 서버에도 기기에도 없다, 6장).
/// - 득표수는 어디에도 없다 (1차, 득표 집계는 앱에서 읽을 수 없음).
class AwardPollView {
  const AwardPollView({
    required this.matchId,
    required this.teamId,
    required this.opensAt,
    required this.closesAt,
    required this.status,
    required this.participantIds,
    required this.myVoted,
    required this.winners,
  });

  /// 서버 줄 → 화면 재료. [poll] 은 award_polls 한 줄, 나머지는 각 표의 줄들.
  factory AwardPollView.fromRows(
    Map<String, dynamic> poll, {
    required List<Map<String, dynamic>> participants,
    required List<Map<String, dynamic>> myReceipts,
    required List<Map<String, dynamic>> winners,
  }) {
    final byCategory = <AwardCategory, List<String>>{};
    for (final w in winners) {
      final c = AwardCategory.fromCode(w['category'] as String?);
      if (c == null) continue;
      (byCategory[c] ??= []).add(w['user_id'] as String);
    }
    return AwardPollView(
      matchId: poll['match_id'] as String,
      teamId: poll['team_id'] as String,
      opensAt: DateTime.parse(poll['opens_at'] as String),
      closesAt: DateTime.parse(poll['closes_at'] as String),
      status: AwardPollStatus.fromCode(poll['status'] as String?),
      participantIds: {for (final p in participants) p['user_id'] as String},
      myVoted: {
        for (final r in myReceipts)
          if (AwardCategory.fromCode(r['category'] as String?) case final c?) c,
      },
      winners: {for (final e in byCategory.entries) e.key: List.unmodifiable(e.value)},
    );
  }

  static const pollColumns = 'match_id, team_id, opens_at, closes_at, status';

  final String matchId;
  final String teamId;
  final DateTime opensAt;

  /// 마감 = 결과 발표 시각
  final DateTime closesAt;
  final AwardPollStatus status;

  /// 투표 대상자 (= 후보가 될 수 있는 사람). 열릴 때 고정, 팀을 떠난 사람도 남는다.
  final Set<String> participantIds;

  /// 내가 이미 낸 항목
  final Set<AwardCategory> myVoted;

  /// 항목별 1위 (마감 뒤에만 생김, 공동 1위는 여럿, 없으면 "결과 없음")
  final Map<AwardCategory, List<String>> winners;

  /// 서버 시각 기준 진행 중인지 (서버가 다시 확인한다).
  bool isOpenAt(DateTime now) => status == AwardPollStatus.open && now.isBefore(closesAt);

  bool isParticipant(String userId) => participantIds.contains(userId);

  /// [userId] 가 지금 [category] 에 투표할 수 있는지 (대상자, 지금 팀원, 아직 안 냄, 진행 중).
  bool canVote(String userId, AwardCategory category, {required bool isCurrentMember, required DateTime now}) =>
      isOpenAt(now) && isCurrentMember && isParticipant(userId) && !myVoted.contains(category);

  /// 후보: 대상자 중 본인이 아니고 지금 팀원인 사람 (떠난 사람 제외, Q-075 13번 (3)).
  /// 이름 순 정렬은 화면에서 (5단계).
  Set<String> candidates({required String me, required Set<String> currentMemberIds}) => {
    for (final id in participantIds)
      if (id != me && currentMemberIds.contains(id)) id,
  };

  /// 결과 화면용 1위 (마감 뒤에만). 표가 없던 항목은 빈 목록 = "결과 없음".
  List<String> winnersOf(AwardCategory category) =>
      status == AwardPollStatus.closed ? (winners[category] ?? const []) : const [];
}
