import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../admin/presentation/admin_tab.dart';
import '../../dashboard/presentation/dashboard_tab.dart';
import '../../dashboard/presentation/dashboard_texts.dart';
import '../../membership/presentation/team_find_screen.dart';
import '../../notifications/domain/notification_models.dart';
import '../../notifications/domain/push_message.dart';
import '../../notifications/presentation/notification_inbox_screen.dart';
import '../../notifications/presentation/notification_navigation.dart';
import '../../profile/presentation/my_tab.dart';
import '../../schedule/presentation/schedule_tab.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../domain/recent_teams.dart';
import '../domain/team_models.dart';
import 'roster_tab.dart';
import 'team_create_screen.dart';
import 'team_logo.dart';
import 'team_texts.dart';

/// 로그인·가입 후 첫 화면.
///
/// - 소속 팀이 없으면 "팀 만들기 / 팀 찾기" 홈.
/// - 있으면 가장 최근에 본 팀을 연다. 팀 이름을 누르면 팀 전환.
/// - 팀을 떠나거나 해체하면 가장 최근에 본 다른 팀, 없으면 홈 (Q-067 6번).
/// - 위쪽 종 모양: 모든 팀 알림의 안 읽은 개수. 화면을 열 때·알림함에서 돌아올 때·팀 목록을 다시 읽을 때 갱신 (4-3).
/// - 휴대폰 푸시 (5-1·5-3): 이 화면이 열릴 때(= 로그인할 때마다) 기기를 등록하고, 로그아웃·회원 탈퇴 직전에 해제한다.
///   앱 사용 중 도착한 푸시는 앱 안 짧은 안내 + 안 읽은 개수 갱신 (Q-071 13번).
///   휴대폰 알림을 눌러 들어오면 알림함과 같은 이동 + 읽음 처리 ([openNotification]).
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({
    required this.services,
    required this.userId,
    required this.onSignOut,
    super.key,
  });

  final AppServices services;
  final String userId;
  final Future<void> Function() onSignOut;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  List<TeamSummary>? _teams;
  List<String> _recent = const [];
  String? _currentId;
  bool _failed = false;
  int _unread = 0;

  /// 알림에서 팀으로 이동할 때 열 탭 (관리 탭 등). 팀 화면을 새로 만들 때 한 번 쓴다.
  String? _openTab;
  int _shellNonce = 0;

  /// 팀 목록을 읽기 전에 누른 푸시 (읽은 뒤 처리)
  PushMessage? _pendingPush;
  final List<StreamSubscription<PushMessage>> _pushSubs = [];

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _load();
    _startPush();
  }

  @override
  void dispose() {
    for (final sub in _pushSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _startPush() {
    final push = _s.push;
    if (push == null) return;
    unawaited(push.start());
    _pushSubs
      ..add(push.foregroundMessages.listen(_onForegroundPush))
      ..add(push.openedMessages.listen((m) => unawaited(_openPush(m))));
    unawaited(
      push.takeInitialMessage().then((m) {
        if (m != null) return _openPush(m);
      }),
    );
  }

  /// 로그아웃·회원 탈퇴: 이 기기 주소를 먼저 지운다 (로그인 상태여야 본인 줄을 지울 수 있다).
  Future<void> _signOut() async {
    await _s.push?.stop();
    await widget.onSignOut();
  }

  /// 앱 사용 중 도착: 휴대폰 알림 대신 앱 안 짧은 안내 + 안 읽은 개수 갱신 (Q-071 13번).
  void _onForegroundPush(PushMessage m) {
    if (!mounted) return;
    final text = m.inAppText;
    if (text.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(key: const Key('push-in-app'), content: Text(text)));
    }
    unawaited(_refreshUnread());
  }

  /// 휴대폰 알림을 눌러 들어옴: 알림함 줄을 다시 읽어 알림함과 같은 이동 + 읽음 처리.
  Future<void> _openPush(PushMessage m) async {
    if (!mounted) return;
    final teams = _teams;
    if (teams == null) {
      _pendingPush = m;
      return;
    }
    AppNotification? n;
    try {
      n = await _s.notifications.getNotification(m.notificationId);
    } on ServerFailure {
      n = null;
    }
    if (!mounted) return;
    if (n != null) {
      // 다른 화면 위에 있었으면 팀 화면으로 돌아와서 연다 (알림함에서 누른 것과 같게)
      Navigator.of(context).popUntil((route) => route.isFirst);
      final target = await openNotification(
        context,
        services: _s,
        userId: widget.userId,
        myTeams: teams,
        notification: n,
      );
      if (target != null && mounted) {
        _openTab = target.openAdmin ? _TeamShell.adminTab : null;
        _shellNonce++;
        await _switchTo(target.teamId);
      }
    }
    await _refreshUnread();
  }

  /// 팀 목록을 다시 읽는다. [open] 이 있으면 그 팀을, [forget] 이 있으면 그 팀을 기록에서 빼고 고른다.
  Future<void> _load({String? open, String? forget}) async {
    setState(() => _failed = false);
    try {
      var recent = await _s.recentTeams.load(widget.userId);
      if (forget != null) recent = RecentTeams.forget(recent, forget);
      if (open != null) recent = RecentTeams.touch(recent, open);
      final teams = await _s.teams.listMyTeams();
      final picked = RecentTeams.pick(
        recent: recent,
        myTeamIds: [for (final t in teams) t.id],
      );
      if (picked != null) recent = RecentTeams.touch(recent, picked);
      await _s.recentTeams.save(widget.userId, recent);
      if (!mounted) return;
      unawaited(_refreshUnread());
      setState(() {
        _teams = teams;
        _recent = recent;
        _currentId = picked;
      });
      final pending = _pendingPush;
      _pendingPush = null;
      if (pending != null) unawaited(_openPush(pending));
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 안 읽은 알림 수 (모든 팀 합계). 실패하면 이전 값을 둔다.
  Future<void> _refreshUnread() async {
    try {
      final n = await _s.notifications.unreadCount();
      if (mounted) setState(() => _unread = n);
    } on ServerFailure {
      // 다음 갱신 때 다시 읽는다
    }
  }

  Future<void> _openInbox() async {
    final target = await Navigator.of(context).push<NotificationTeamTarget>(
      MaterialPageRoute(
        builder: (_) => NotificationInboxScreen(
          services: _s,
          userId: widget.userId,
          myTeams: _teams ?? const [],
        ),
      ),
    );
    if (target != null) {
      _openTab = target.openAdmin ? _TeamShell.adminTab : null;
      _shellNonce++;
      await _switchTo(target.teamId);
    }
    await _refreshUnread();
  }

  Future<void> _switchTo(String teamId) async {
    final recent = RecentTeams.touch(_recent, teamId);
    await _s.recentTeams.save(widget.userId, recent);
    if (mounted) {
      setState(() {
        _recent = recent;
        _currentId = teamId;
      });
    }
  }

  Future<void> _openCreate() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TeamCreateScreen(
          teams: _s.teams,
          logos: _s.logos,
          logoPicker: _s.logoPicker,
          places: _s.places,
        ),
      ),
    );
    if (id != null) await _load(open: id);
  }

  Future<void> _openFind() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TeamFindScreen(membership: _s.membership)),
    );
    // 신청이 승인됐을 수 있으니 다시 읽는다.
    await _load();
  }

  Future<void> _showSwitcher() async {
    final teams = _teams ?? const <TeamSummary>[];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text(TeamTexts.switchTeam)),
            for (final t in teams)
              ListTile(
                key: Key('switch-team-${t.id}'),
                leading: TeamLogo(text: t.logoText, imagePath: t.logoImagePath, size: 36),
                title: Text(t.name),
                subtitle: Text(TeamTexts.role(t.myRole)),
                selected: t.id == _currentId,
                onTap: () => Navigator.of(context).pop('team:${t.id}'),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text(TeamTexts.createTeam),
              onTap: () => Navigator.of(context).pop('create'),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text(TeamTexts.findTeam),
              onTap: () => Navigator.of(context).pop('find'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'create') return _openCreate();
    if (action == 'find') return _openFind();
    await _switchTo(action.substring('team:'.length));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            message: TeamTexts.loadFailed,
            actions: [TextButton(onPressed: _load, child: const Text(TeamTexts.retry))],
          ),
        ),
      );
    }
    final teams = _teams;
    if (teams == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final current = teams.where((t) => t.id == _currentId).firstOrNull;
    if (current == null) {
      return _NoTeamView(
        onCreate: _openCreate,
        onFind: _openFind,
        onSignOut: _signOut,
        bell: NotificationBell(unread: _unread, onPressed: _openInbox),
      );
    }
    final openTab = _openTab;
    _openTab = null;
    return _TeamShell(
      key: ValueKey('${current.id}-$_shellNonce'),
      initialTab: openTab,
      bell: NotificationBell(unread: _unread, onPressed: _openInbox),
      services: _s,
      userId: widget.userId,
      team: current,
      onTapTitle: _showSwitcher,
      onLeftTeam: () => _load(forget: current.id),
      onTeamChanged: _load,
      onSignOut: _signOut,
    );
  }
}

class _NoTeamView extends StatelessWidget {
  const _NoTeamView({
    required this.onCreate,
    required this.onFind,
    required this.onSignOut,
    required this.bell,
  });

  final VoidCallback onCreate;
  final VoidCallback onFind;
  final Future<void> Function() onSignOut;
  final Widget bell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          bell,
          TextButton(onPressed: onSignOut, child: const Text(TeamTexts.signOut)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: EmptyState(
              icon: Icons.groups_outlined,
              message: TeamTexts.noTeamTitle,
              actions: [
                FilledButton(
                  key: const Key('home-create-team'),
                  onPressed: onCreate,
                  child: const Text(TeamTexts.createTeam),
                ),
                OutlinedButton(
                  key: const Key('home-find-team'),
                  onPressed: onFind,
                  child: const Text(TeamTexts.findTeam),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamShell extends StatefulWidget {
  const _TeamShell({
    required this.services,
    required this.userId,
    required this.team,
    required this.onTapTitle,
    required this.onLeftTeam,
    required this.onTeamChanged,
    required this.onSignOut,
    required this.bell,
    this.initialTab,
    super.key,
  });

  /// 탭 이름 ([initialTab] 에 쓴다)
  static const homeTab = 'home';
  static const scheduleTab = 'schedule';
  static const membersTab = 'members';
  static const adminTab = 'admin';
  static const myTab = 'my';

  final AppServices services;
  final String userId;
  final TeamSummary team;
  final VoidCallback onTapTitle;

  /// 위쪽 종 모양 (안 읽은 알림 수)
  final Widget bell;

  /// 처음 열 탭 이름. 없으면 첫 탭(홈, S4-01).
  final String? initialTab;

  /// 팀 탈퇴·해체 후
  final Future<void> Function() onLeftTeam;

  /// 위임 등으로 내 역할이 바뀐 뒤
  final Future<void> Function() onTeamChanged;
  final Future<void> Function() onSignOut;

  @override
  State<_TeamShell> createState() => _TeamShellState();
}

class _TeamShellState extends State<_TeamShell> {
  int? _tab;

  /// 지금 보이는 탭 이름 순서 (build 때 정함)
  List<String> _names = const [];

  /// 관리 탭 아이콘의 가입 신청 숫자 (팀장·운영진만, S4-05). 팀원은 읽지 않는다.
  int _pendingJoin = 0;

  Viewer get _viewer => Viewer(userId: widget.userId, role: widget.team.myRole);

  @override
  void initState() {
    super.initState();
    _refreshPendingJoin();
  }

  Future<void> _refreshPendingJoin() async {
    if (!widget.services.entitlements.showJoinRequestTodo(_viewer)) return;
    try {
      final n = (await widget.services.membership.listPendingRequests(widget.team.id)).length;
      if (mounted && n != _pendingJoin) setState(() => _pendingJoin = n);
    } on ServerFailure {
      // 다음에 다시 읽는다
    }
  }

  /// 대시보드 카드에서 다른 탭으로
  void _goTo(String name) {
    final i = _names.indexOf(name);
    if (i >= 0) setState(() => _tab = i);
  }

  void _select(int i) {
    setState(() => _tab = i);
    _refreshPendingJoin();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    final e = widget.services.entitlements;
    final showAdmin = e.showAdminTab(viewer);
    final tabs = <(String, IconData, Widget, String)>[
      (
        DashboardTexts.tabHome,
        Icons.home_outlined,
        DashboardTab(
          services: widget.services,
          team: widget.team,
          viewer: viewer,
          onOpenMembers: () => _goTo(_TeamShell.membersTab),
          onOpenAdmin: () => _goTo(_TeamShell.adminTab),
          onLoaded: (data) {
            final n = data.todos?.pendingJoinRequests ?? 0;
            if (e.showJoinRequestTodo(viewer) && n != _pendingJoin) setState(() => _pendingJoin = n);
          },
        ),
        _TeamShell.homeTab,
      ),
      (
        ScheduleTexts.tabSchedule,
        Icons.event,
        ScheduleTab(services: widget.services, team: widget.team, viewer: viewer),
        _TeamShell.scheduleTab,
      ),
      (
        TeamTexts.tabMembers,
        Icons.groups,
        RosterTab(services: widget.services, team: widget.team, viewer: viewer),
        _TeamShell.membersTab,
      ),
      if (showAdmin)
        (
          TeamTexts.tabAdmin,
          Icons.admin_panel_settings,
          AdminTab(
            services: widget.services,
            team: widget.team,
            viewer: viewer,
            onTeamChanged: widget.onTeamChanged,
            onDissolved: widget.onLeftTeam,
          ),
          _TeamShell.adminTab,
        ),
      (
        TeamTexts.tabMy,
        Icons.person,
        MyTab(
          services: widget.services,
          team: widget.team,
          viewer: viewer,
          onLeftTeam: widget.onLeftTeam,
          onSignOut: widget.onSignOut,
        ),
        _TeamShell.myTab,
      ),
    ];
    _names = [for (final t in tabs) t.$4];
    final initial = tabs.indexWhere((t) => t.$4 == widget.initialTab);
    final index = (_tab ??= initial < 0 ? 0 : initial).clamp(0, tabs.length - 1);
    final joinBadge = showAdmin && e.showJoinRequestTodo(viewer) ? _pendingJoin : 0;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const Key('team-title'),
          onTap: widget.onTapTitle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TeamLogo(text: widget.team.logoText, imagePath: widget.team.logoImagePath, size: 32),
              const SizedBox(width: 8),
              Flexible(child: Text(widget.team.name, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [widget.bell],
      ),
      body: tabs[index].$3,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: t.$4 == _TeamShell.adminTab
                  ? Badge(
                      key: const Key('admin-tab-badge'),
                      isLabelVisible: joinBadge > 0,
                      label: Text('$joinBadge'),
                      child: Icon(t.$2),
                    )
                  : Icon(t.$2),
              label: t.$1,
            ),
        ],
      ),
    );
  }
}
