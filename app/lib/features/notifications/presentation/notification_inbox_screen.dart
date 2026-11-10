import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/domain/team_models.dart';
import '../domain/notification_models.dart';
import 'notification_navigation.dart';
import 'notification_texts.dart';

export 'notification_navigation.dart' show NotificationTeamTarget;

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

  Future<void> _open(AppNotification n) async {
    final target = await openNotification(
      context,
      services: _s,
      userId: widget.userId,
      myTeams: widget.myTeams,
      notification: n,
    );
    if (!mounted) return;
    if (target != null) {
      Navigator.of(context).pop(target);
    } else {
      await _load();
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
          padding: AppSpacing.page,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          // 카드형 목록 (Q-079 1·2번)
          itemBuilder: (context, i) => Card(child: _NotificationTile(item: items[i], onTap: () => _open(items[i]))),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
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
