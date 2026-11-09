import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../../schedule/presentation/match_detail_screen.dart';
import '../../team/domain/team_models.dart';
import '../domain/notification_models.dart';

/// 알림을 눌러 팀 화면으로 가야 할 때 (팀 전환 + 탭). 일정 상세는 [openNotification] 이 바로 연다.
class NotificationTeamTarget {
  const NotificationTeamTarget({required this.teamId, this.openAdmin = false});

  final String teamId;

  /// 가입 신청 알림: 관리 탭(가입 신청 목록)
  final bool openAdmin;
}

/// 알림 하나를 눌렀을 때의 처리 한 곳 (알림함·휴대폰 푸시 공통, 4-3·5-3).
///
/// 읽음 처리 후 관련 화면으로: 일정 알림 → 일정 상세(취소된 일정도 "취소됨 + 사유", Q-073 4번)를 열고 닫힐 때까지 기다린다.
/// 가입 신청 → 그 팀 관리 탭, 그 밖의 팀 알림 → 그 팀: [NotificationTeamTarget] 을 돌려준다(부른 쪽이 팀 전환).
/// 지금 소속이 아닌 팀(떠난 팀·해체된 팀)이나 사라진 대상은 이동하지 않는다 (Q-041, Entitlements.canOpenNotificationTarget).
Future<NotificationTeamTarget?> openNotification(
  BuildContext context, {
  required AppServices services,
  required String userId,
  required List<TeamSummary> myTeams,
  required AppNotification notification,
}) async {
  final n = notification;
  if (!n.isRead) {
    try {
      await services.notifications.markRead(n.id);
    } on ServerFailure {
      // 읽음 표시에 실패해도 이동은 한다
    }
  }
  final team = myTeams.where((t) => t.id == n.teamId).firstOrNull;
  final viewer = Viewer(userId: userId, role: team?.myRole);
  if (team == null || !services.entitlements.canOpenNotificationTarget(viewer)) {
    return null;
  }
  switch (n.refType) {
    case NotificationRefType.match:
      final matchId = await _matchOrNull(services, n.refId!);
      if (matchId != null && context.mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MatchDetailScreen(
              services: services,
              team: team,
              viewer: viewer,
              matchId: matchId,
            ),
          ),
        );
      }
      return null;
    case NotificationRefType.joinRequest:
      return NotificationTeamTarget(teamId: team.id, openAdmin: true);
    case NotificationRefType.team:
    case null:
      return NotificationTeamTarget(teamId: team.id);
  }
}

/// 일정이 아직 있고 볼 수 있으면 그 ID, 아니면 null (사라진 대상은 이동 안 함, Q-041).
Future<String?> _matchOrNull(AppServices services, String id) async {
  try {
    return (await services.matches.getMatch(id))?.id;
  } on ServerFailure {
    return null;
  }
}
