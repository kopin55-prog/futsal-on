import 'grants.dart';

/// "이 정보"를 표현한다. docs/permissions.md "정보별 공개 범위 (1차)" 표의 행과 대응.
sealed class Info {
  const Info();
}

/// 특정 사람의 실력 등급.
final class SkillLevelInfo extends Info {
  const SkillLevelInfo({required this.subjectUserId});
  final String subjectUserId;
}

/// 특정 사람의 선호 포지션·전문 골키퍼 여부.
final class PreferredPositionsInfo extends Info {
  const PreferredPositionsInfo({required this.subjectUserId});
  final String subjectUserId;
}

/// 일정의 참석·불참·미투표 명단.
final class AttendanceListInfo extends Info {
  const AttendanceListInfo();
}

/// POM·오늘의 골 결과 (1위 이름).
final class VoteWinnerInfo extends Info {
  const VoteWinnerInfo({required this.category});
  final VoteCategory category;
}

/// 특정 경기·항목에서 특정 사람의 득표수.
final class VoteCountInfo extends Info {
  const VoteCountInfo({
    required this.subjectUserId,
    required this.matchId,
    required this.category,
  });
  final String subjectUserId;
  final String matchId;
  final VoteCategory category;
}

/// 누가 누구를 찍었는지.
final class VoterChoiceInfo extends Info {
  const VoterChoiceInfo();
}

/// 특정 사람의 부상 정보 (기간·메모).
final class InjuryInfo extends Info {
  const InjuryInfo({
    required this.subjectUserId,
    required this.subjectConsented,
  });
  final String subjectUserId;

  /// 본인이 건강 정보 처리·팀원 공개에 동의했는지 (동의 문구는 Q-003 대기).
  final bool subjectConsented;
}

/// 특정 사람의 내 기록 (수상·출석 횟수).
final class PersonalRecordInfo extends Info {
  const PersonalRecordInfo({required this.subjectUserId});
  final String subjectUserId;
}

/// 2차 팀 구독: 운영진용 출석·참여 리포트.
final class TeamReportInfo extends Info {
  const TeamReportInfo();
}

/// 그룹·라이벌 설정 (누구와 누구를 같은 팀/다른 팀으로 둘지). 팀 단위.
final class GroupRivalSettingsInfo extends Info {
  const GroupRivalSettingsInfo();
}

/// 팀 나누기 배치 변경 이력. 팀 단위.
final class LineupChangeHistoryInfo extends Info {
  const LineupChangeHistoryInfo();
}

/// 게스트의 포지션. 팀 단위.
final class GuestPositionInfo extends Info {
  const GuestPositionInfo();
}
