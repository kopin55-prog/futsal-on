import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../schedule/presentation/match_detail_screen.dart';
import '../../team/domain/team_models.dart';
import '../domain/notification_models.dart';
import 'notification_texts.dart';

/// 알림을 눌러 팀 화면으로 가야 할 때 (팀 전환 + 탭). 일정 상세는 이 화면에서 바로 연다.
class NotificationTeamTarget {
  const NotificationTeamTarget({required this.teamId, this.openAdmin = false});

  final String teamId;

  /// 가입 신청 알림: 관리 탭(가입 신청 목록)
  final bool openAdmin;
}

/// 알림함 (스프린트 02 4-3, Q-071 10번, Q-073 4번).
///
/// - 모든 팀 알림을 한 곳에, 항목마다 팀 이름(알림 제목), 최신순, 최근 30일 (Q-041).
/// - "모두 읽음"만 (개별 삭제·안 읽음 되돌리기 없음).
/// - 누르면 읽음 처리 후 관련 화면으로: 일정 알림 → 일정 상세(취소된 일정도 "취소됨 + 사유"),
///   가입 신청 → 그 팀 관리 탭, 그 밖의 팀 알림 → 그 팀.
///   지금 소속이 아닌 팀(떠난 팀·해체된 팀)이나 사라진 대상은 이동하지 않는다 (Entitlements.canOpenNotificationTarget).
/// 팀으로 가야 하면 [NotificationTeamTarget] 으로 닫힌다.
class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({
    required this.services,
    required this.userId,
    required this.myTeams,
    super.key,
  });

  final AppServices services;
  final String userId;

  /// 지금 소속된 팀 (이동 가능 여부와 그 팀에서의 역할)
  final List<TeamSummary> myTeams;

  @override
  State<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  List<AppNotification>? _items;
  bool _failed = false;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final items = await _s.notifications.listNotifications();
      if (mounted) setState(() => _items = items);
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _markAll() async {
    try {
      await _s.notifications.markAllRead();
    } on ServerFailure {
      // 다음 새로고침 때 다시 보인다
    }
    await _load();
  }

  TeamSummary? _teamOf(AppNotification n) =>
      widget.myTeams.where((t) => t.id == n.teamId).firstOrNull;

  Future<void> _open(AppNotification n) async {
    if (!n.isRead) {
      try {
        await _s.notifications.markRead(n.id);
      } on ServerFailure {
        // 읽음 표시에 실패해도 이동은 한다
      }
    }
    final team = _teamOf(n);
    final viewer = Viewer(userId: widget.userId, role: team?.myRole);
    if (team == null || !_s.entitlements.canOpenNotificationTarget(viewer)) {
      await _load();
      return;
    }
    switch (n.refType) {
      case NotificationRefType.match:
        final match = await _matchOrNull(n.refId!);
        if (!mounted) return;
        if (match != null) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => MatchDetailScreen(
                services: _s,
                team: team,
                viewer: viewer,
                matchId: match,
              ),
            ),
          );
        }
        await _load();
      case NotificationRefType.joinRequest:
        if (mounted) Navigator.of(context).pop(NotificationTeamTarget(teamId: team.id, openAdmin: true));
      case NotificationRefType.team:
      case null:
        if (mounted) Navigator.of(context).pop(NotificationTeamTarget(teamId: team.id));
    }
  }

  /// 일정이 아직 있고 볼 수 있으면 그 ID, 아니면 null (사라진 대상은 이동 안 함, Q-041).
  Future<String?> _matchOrNull(String id) async {
    try {
      return (await _s.matches.getMatch(id))?.id;
    } on ServerFailure {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = items?.any((n) => !n.isRead) ?? false;
    Widget body;
    if (items == null) {
      body = _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              message: NotificationTexts.loadFailed,
              actions: [TextButton(onPressed: _load, child: const Text(NotificationTexts.retry))],
            )
          : const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            EmptyState(icon: Icons.notifications_none, message: NotificationTexts.empty),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(indent: AppSpacing.gutter, endIndent: AppSpacing.gutter),
          itemBuilder: (context, i) => _NotificationTile(item: items[i], onTap: () => _open(items[i])),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(NotificationTexts.title),
        actions: [
          TextButton(
            key: const Key('notifications-read-all'),
            onPressed: hasUnread ? _markAll : null,
            child: const Text(NotificationTexts.readAll),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !item.isRead;
    return ListTile(
      key: Key('notification-${item.id}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      leading: Icon(
        unread ? Icons.circle : Icons.circle_outlined,
        size: 10,
        color: unread ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
      ),
      minLeadingWidth: 10,
      title: Text(
        item.title,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            item.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: unread ? FontWeight.w600 : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(NotificationTexts.when(item.createdAt, DateTime.now()), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 위쪽 종 모양 + 안 읽은 개수 (모든 팀 합계, Q-071 10번).
class NotificationBell extends StatelessWidget {
  const NotificationBell({required this.unread, required this.onPressed, super.key});

  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: NotificationTexts.title,
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread', key: const Key('notification-unread')),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
