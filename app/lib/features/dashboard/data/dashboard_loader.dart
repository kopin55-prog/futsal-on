import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../lineup/domain/lineup_models.dart';
import '../../schedule/domain/attendance_models.dart';
import '../../schedule/domain/guest_models.dart';
import '../../schedule/domain/match_models.dart';
import '../../team/domain/team_models.dart';
import '../domain/dashboard_models.dart';

/// 팀 대시보드 읽기 (스프린트 04 4-1).
///
/// 한 번에 읽는 서버 함수를 따로 두지 않고 기존 저장소(= 기존 권한 규칙)로 읽는다 (builder 판단):
/// - 팀원은 확정 배치만, 부상은 진행 중 + 동의 유효한 것만, 가입 신청은 관리자만 서버가 준다.
///   실력 등급·포지션·득표수는 읽지 않는다(대시보드에 필요 없음, 팀원에게는 서버도 주지 않음).
/// - 앱에서의 표시 판단은 Entitlements 한 곳에서 다시 한다.
/// 실패는 [ServerFailure] 그대로 (화면이 다시 시도 버튼을 보여준다).
Future<DashboardData> loadDashboard({
  required AppServices services,
  required TeamSummary team,
  required Viewer viewer,
  required DateTime now,
}) async {
  final e = services.entitlements;
  final members = await services.teams.listMembers(team.id);
  final memberIds = [for (final m in members) m.userId];

  // ---- 다음 경기
  final upcoming = await services.matches.listMatches(team.id, from: now);
  final nextMatch = DashboardRules.nextMatch(upcoming, now);
  final myInjury = await services.injuries.myActiveInjury(viewer.userId);
  NextMatchView? next;
  Lineup? nextLineupRaw;
  if (nextMatch != null) {
    final responses = await services.attendance.listResponses(nextMatch.id);
    nextLineupRaw = await services.lineups.getLineup(nextMatch.id);
    final raw = nextLineupRaw;
    // 팀원 카드에는 확정 배치만 (관리자도 홈 카드에는 확정 배치만 크게 보여준다, 기획서 11장)
    final lineup = raw != null && raw.isConfirmed && e.canView(viewer, const LineupInfo(confirmed: true)) ? raw : null;
    final guests = lineup != null ? await services.guests.listGuests(nextMatch.id) : const <MatchGuest>[];
    next = NextMatchView(
      match: nextMatch,
      roster: AttendanceRoster(responses),
      memberIds: memberIds,
      myInjured: myInjury != null && e.canView(
        viewer,
        InjuryInfo(subjectUserId: viewer.userId, subjectConsented: true, isActive: myInjury.isActive),
      ),
      lineup: lineup,
      guests: guests,
    );
  }

  // ---- 지난 경기 POM·오늘의 골 (가장 최근에 끝난 경기, 투표가 안 열렸으면 숨김)
  LastAwardView? lastAward;
  final past = await services.matches.listPastMatches(team.id, before: now, limit: 11);
  final lastMatch = DashboardRules.lastFinishedMatch(past, now);
  if (lastMatch != null) {
    final poll = await services.awards.getPoll(lastMatch.id, myUserId: viewer.userId);
    if (poll != null) lastAward = LastAwardView(match: lastMatch, poll: poll);
  }

  // ---- 부상자 라인업 (서버가 진행 중 + 동의 유효한 것만 준다. 앱 표시 판단은 InjuryInfo)
  final injuries = await services.injuries.listActiveInjuries(memberIds);
  final visibleInjuries = [
    for (final i in injuries)
      if (e.canView(viewer, InjuryInfo(subjectUserId: i.userId, subjectConsented: true, isActive: i.isActive))) i,
  ];
  final injured = DashboardRules.injuredLineup(members, visibleInjuries, DashboardRules.todayKst(now));

  // ---- 처리할 일 (팀장·운영진만)
  DashboardTodos? todos;
  final showJoin = e.showJoinRequestTodo(viewer);
  final showLineup = e.showLineupTodo(viewer);
  if (showJoin || showLineup) {
    final joinCount = showJoin ? (await services.membership.listPendingRequests(team.id)).length : 0;
    final pending = <TeamMatch>[];
    if (showLineup) {
      for (final m in upcoming) {
        // 배치 화면이 열리는 때(마감 뒤·종료 전·취소 아님)의 일정만 배치를 읽어 본다
        if (!DashboardRules.needsLineup(m, null, now)) continue;
        final lineup = m.id == nextMatch?.id ? nextLineupRaw : await services.lineups.getLineup(m.id);
        if (DashboardRules.needsLineup(m, lineup, now)) pending.add(m);
      }
      pending.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    todos = DashboardTodos(pendingJoinRequests: joinCount, lineupPending: pending);
  }

  return DashboardData(
    members: members,
    next: next,
    lastAward: lastAward,
    injured: injured,
    todos: todos,
  );
}
