/// 팀 안에서 하는 행동. docs/permissions.md "역할별 권한 (1차)" 표의 행과 대응.
enum TeamAction {
  /// 가입 승인·거절, 초대 링크 발급
  reviewJoinRequests,

  /// 팀 정보 수정 (사진 로고 포함, 로고 글자 제외), 인원 모집 켜기·끄기
  editTeamInfo,

  /// 로고 글자 변경 (Q-014: 팀장만)
  editLogoText,

  /// 실력 등급 설정 (조회는 SkillLevelInfo)
  setSkillLevel,

  /// 경기 설정 (정원·마감·자동 생성 시점)
  editMatchSettings,

  /// 그룹·라이벌 설정
  editGroupRivalRules,

  /// 일정 추가·취소, 게스트 추가
  manageSchedule,

  /// 팀 나누기 생성·수정·확정
  manageLineup,

  /// 공유 이미지 복사
  copyShareImage,

  /// 운영진 지정·해제
  appointOrDismissManager,

  /// 팀원 내보내기
  removeMember,

  /// 팀장 위임
  transferOwnership,

  /// 팀 해체
  disbandTeam,

  /// 참석 투표
  voteAttendance,

  /// POM·오늘의 골 투표
  voteAwards,
}
