/// 2차 수익화 등급(보상형 광고, 개인 구독, 팀 구독)이 끼워질 자리.
///
/// 1차에서는 [Grants.none]만 쓰이고, Entitlements는 이 값을 판단에 쓰지 않는다.
/// 2차에서 결제·광고 연동이 승인되면 이 값을 채우고 Entitlements의
/// `TODO(2차)` 지점에서 반영한다. (docs/permissions.md "2차 등급")
library;

/// 투표 항목. 득표수·결과 공개를 항목별로 판단하기 위해 core에 둔다.
enum VoteCategory { pom, goalOfTheDay }

/// 보상형 광고 1회로 열리는 범위: 그 경기 1건의 본인 득표수 (항목별).
class AdUnlock {
  const AdUnlock({required this.matchId, required this.category});

  final String matchId;
  final VoteCategory category;

  @override
  bool operator ==(Object other) =>
      other is AdUnlock &&
      other.matchId == matchId &&
      other.category == category;

  @override
  int get hashCode => Object.hash(matchId, category);
}

/// 한 사용자가 가진 2차 등급 묶음.
class Grants {
  const Grants({
    this.personalPlan = false,
    this.teamPlan = false,
    this.adUnlocks = const {},
  });

  /// 1차 기본값: 아무 등급도 없음.
  const Grants.none() : this();

  /// 개인 구독: 광고 제거, 항목별 상위 3위 + 본인 득표수.
  final bool personalPlan;

  /// 팀 구독 (팀 단위): 팀장·운영진용 출석·참여 리포트.
  final bool teamPlan;

  /// 보상형 광고로 열린 경기·항목 목록.
  final Set<AdUnlock> adUnlocks;
}
