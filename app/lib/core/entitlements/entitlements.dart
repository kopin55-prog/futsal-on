/// "이 사람이 이 정보를 볼 수 있나 / 이 행동을 할 수 있나"를 판단하는 단일 지점.
///
/// 화면·서비스는 권한을 직접 판단하지 않고 반드시 이 클래스를 거친다.
/// 서버 쪽 최종 차단은 Supabase RLS가 맡고, 이 클래스는 앱에서의 표시·버튼 노출 판단용이다.
///
/// 기준 문서: docs/permissions.md (상태: kopn 승인 전 정리본).
library;

import 'grants.dart';
import 'info.dart';
import 'team_action.dart';
import 'team_role.dart';
import 'viewer.dart';

export 'grants.dart';
export 'info.dart';
export 'team_action.dart';
export 'team_role.dart';
export 'viewer.dart';

class Entitlements {
  const Entitlements();

  /// 1차에서 투표 결과는 항목별 1위만 공개한다 (동점이면 공동 1위).
  static const int phase1VoteResultMaxRank = 1;

  // ---------------------------------------------------------------------------
  // 행동 권한
  // ---------------------------------------------------------------------------

  /// [viewer]가 자기 팀에서 [action]을 할 수 있는지.
  bool canPerform(Viewer viewer, TeamAction action) {
    final role = viewer.role;
    if (role == null) return false;

    switch (action) {
      case TeamAction.reviewJoinRequests:
      case TeamAction.editTeamInfo:
      case TeamAction.setSkillLevel:
      case TeamAction.editMatchSettings:
      case TeamAction.editAwardSettings:
      case TeamAction.editGroupRivalRules:
      case TeamAction.manageSchedule:
      case TeamAction.manageLineup:
      case TeamAction.copyShareImage:
        return role.isStaff;
      case TeamAction.editLogoText:
      case TeamAction.appointOrDismissManager:
      case TeamAction.removeMember:
      case TeamAction.transferOwnership:
      case TeamAction.disbandTeam:
        return role == TeamRole.owner;
      case TeamAction.leaveTeam:
        return role != TeamRole.owner;
      case TeamAction.voteAttendance:
      case TeamAction.voteAwards:
        return true;
    }
  }

  /// 관리 탭을 보여줄지: 팀장·운영진 (가입 승인·초대 코드가 관리 탭의 기본 기능).
  bool showAdminTab(Viewer viewer) =>
      canPerform(viewer, TeamAction.reviewJoinRequests);

  /// 홈 "처리할 일"의 가입 신청 대기, 관리 탭 아이콘의 숫자 배지 (스프린트 04 4-6, S4-05): 팀장·운영진만.
  /// 팀원 화면에는 가입 신청 수가 나오지 않는다 (서버도 팀원에게 다른 사람의 가입 신청을 주지 않는다).
  bool showJoinRequestTodo(Viewer viewer) =>
      canPerform(viewer, TeamAction.reviewJoinRequests);

  /// 홈 "처리할 일"의 팀 나누기 대기 (참석 마감 뒤·경기 종료 전·배치 미확정 일정, S4-05): 팀장·운영진만.
  /// 미확정(초안) 배치를 볼 수 있는 사람만 "미확정"을 알 수 있다.
  bool showLineupTodo(Viewer viewer) =>
      canPerform(viewer, TeamAction.manageLineup) &&
      canView(viewer, const LineupInfo(confirmed: false));

  /// [viewer]가 팀원 [target]에게 할 수 있는 관리 행동 (관리 탭의 팀원 메뉴).
  /// 서버도 같은 규칙으로 다시 거절한다 (3-3, Q-018).
  Set<TeamAction> memberActions(
    Viewer viewer, {
    required String targetUserId,
    required TeamRole targetRole,
  }) {
    if (viewer.userId == targetUserId) return const {};
    return {
      if (targetRole == TeamRole.member &&
          canPerform(viewer, TeamAction.appointOrDismissManager))
        TeamAction.appointOrDismissManager,
      if (targetRole == TeamRole.manager &&
          canPerform(viewer, TeamAction.appointOrDismissManager))
        TeamAction.appointOrDismissManager,
      if (targetRole == TeamRole.manager &&
          canPerform(viewer, TeamAction.transferOwnership))
        TeamAction.transferOwnership,
      if (targetRole != TeamRole.owner &&
          canPerform(viewer, TeamAction.removeMember))
        TeamAction.removeMember,
    };
  }

  /// 팀 배치 공유 이미지 버튼 (스프린트 03 6-1): "공유 이미지 복사" 권한(팀장·운영진)이고
  /// 확정된 배치일 때만. 취소된 일정은 공유하지 않는다.
  bool canShareLineupImage(
    Viewer viewer, {
    required bool lineupConfirmed,
    required bool matchCancelled,
  }) =>
      canPerform(viewer, TeamAction.copyShareImage) &&
      lineupConfirmed &&
      !matchCancelled &&
      canView(viewer, const LineupInfo(confirmed: true));

  /// POM·오늘의 골 결과 공유 이미지 버튼 (스프린트 03 6-2): "공유 이미지 복사" 권한(팀장·운영진)이고
  /// 투표가 마감(결과 확정)된 뒤에만. 이미지에 들어가는 것도 1위 이름뿐이다 (득표수 없음).
  bool canShareAwardResultImage(Viewer viewer, {required bool pollClosed}) =>
      canPerform(viewer, TeamAction.copyShareImage) &&
      pollClosed &&
      VoteCategory.values.any((c) => voteResultMaxRank(viewer, c) >= 1);

  /// 알림을 눌렀을 때 그 팀의 화면(일정 상세 등)으로 이동할 수 있는지: 지금 그 팀 팀원일 때만.
  /// 떠난 팀·해체된 팀의 알림은 남지만 이동하지 않는다 (Q-041). [viewer] 는 알림의 팀 기준.
  bool canOpenNotificationTarget(Viewer viewer) => viewer.isTeamMember;

  /// 팀 식별코드를 볼 수 있는지: 팀원 전체 (Q-051).
  bool canViewTeamCode(Viewer viewer) => viewer.isTeamMember;

  /// 부상 등록·연장·회복·메모 수정, 부상 동의·철회 버튼: 본인만 (서버 함수도 본인 것만 다룬다, 스프린트 04 1-3).
  bool canManageInjury(Viewer viewer, {required String subjectUserId}) =>
      viewer.userId == subjectUserId;

  /// "부상 정보 동의 철회" 메뉴: 본인이고 유효한 부상 동의가 있을 때만 (2-4).
  bool canWithdrawInjuryConsent(Viewer viewer, {required String subjectUserId, required bool hasConsent}) =>
      canManageInjury(viewer, subjectUserId: subjectUserId) && hasConsent;

  /// 프로필 항목(선호 포지션·전문 골키퍼 포함)을 수정할 수 있는지: 본인만.
  bool canEditProfile(Viewer viewer, {required String subjectUserId}) =>
      viewer.userId == subjectUserId;

  // ---------------------------------------------------------------------------
  // 정보 공개
  // ---------------------------------------------------------------------------

  /// [viewer]가 자기 팀 맥락에서 [info]를 볼 수 있는지.
  bool canView(Viewer viewer, Info info) {
    final bool isSelf = switch (info) {
      SkillLevelInfo(:final subjectUserId) ||
      PreferredPositionsInfo(:final subjectUserId) ||
      VoteCountInfo(:final subjectUserId) ||
      InjuryInfo(:final subjectUserId) ||
      PersonalRecordInfo(
        :final subjectUserId,
      ) => viewer.userId == subjectUserId,
      _ => false,
    };

    // 내 기록은 팀 소속과 무관하게 본인만.
    if (info is PersonalRecordInfo) return isSelf;

    // 내 부상은 팀 소속과 무관하게 본인이 본다. 1차 화면에는 진행 중인 것만 (S4-06 (4): 지난 기록은 저장만).
    if (info is InjuryInfo && isSelf) return info.isActive;

    final role = viewer.role;
    if (role == null) return false;

    switch (info) {
      case SkillLevelInfo():
        // 팀장·운영진만, 본인 등급 포함 (Q-016). 팀원은 본인 등급도 못 본다.
        return role.isStaff;

      case PreferredPositionsInfo():
        // 선호 포지션·전문 골키퍼: 본인, 그리고 팀장·운영진만 (Q-017).
        // 팀원 명단에는 표시하지 않는다.
        return isSelf || role.isStaff;

      case GroupRivalSettingsInfo():
      case LineupChangeHistoryInfo():
      case GuestPositionInfo():
        // 팀장·운영진만 (Q-017).
        return role.isStaff;

      case AttendanceListInfo():
        return true;

      case LineupInfo(:final confirmed):
        // 팀장·운영진은 작성 중(초안)도, 팀원은 확정된 배치만 (스프린트 03 1-1, 서버 권한 규칙과 같음).
        return confirmed || role.isStaff;

      case VoteWinnerInfo():
        return true;

      case VoteCountInfo():
        // 1차: 저장만 하고 아무도 조회 불가 (득표수 보기 버튼은 숨김).
        // TODO(2차): viewer.grants.adUnlocks 에 해당 경기·항목이 있거나
        //   viewer.grants.personalPlan 이면 본인 득표수 허용.
        return false;

      case VoterChoiceInfo():
        // 익명 투표: 누구도 조회 불가 (2차에서도 열지 않음).
        return false;

      case InjuryInfo(:final subjectConsented, :final isActive):
        // 다른 사람: 같은 팀 팀원 전체, 주인의 동의가 유효하고 진행 중인 부상만 (서버 권한 규칙과 같음, S-07).
        // 본인은 위에서 처리. TODO(2차): 팀 구독 리포트의 지난 부상 기록은 TeamReportInfo 로 따로 판단.
        return subjectConsented && isActive;

      case TeamReportInfo():
        // 1차: 리포트 메뉴 숨김.
        // TODO(2차): 팀 구독(teamPlan)이면 팀장·운영진에게 허용.
        return false;

      case PersonalRecordInfo():
        return isSelf; // 위에서 이미 처리됨. switch 완전성용.
    }
  }

  /// [viewer]에게 [category] 투표 결과를 몇 위까지 보여줄지. 0이면 비공개.
  int voteResultMaxRank(Viewer viewer, VoteCategory category) {
    if (!canView(viewer, VoteWinnerInfo(category: category))) return 0;
    // TODO(2차): viewer.grants.personalPlan 이면 상위 3위.
    return phase1VoteResultMaxRank;
  }

  /// 득표수 보기 버튼을 노출할지. 1차에서는 항상 숨김.
  bool showVoteCountButton(Viewer viewer) {
    // TODO(2차): 보상형 광고·개인 구독 도입 시 노출.
    return false;
  }

  /// 팀 리포트 메뉴를 노출할지. 1차에서는 항상 숨김.
  bool showTeamReportMenu(Viewer viewer) =>
      canView(viewer, const TeamReportInfo());
}
