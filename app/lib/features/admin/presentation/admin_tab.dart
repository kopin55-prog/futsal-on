import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../pom_vote/presentation/award_settings_screen.dart';
import '../../pom_vote/presentation/award_texts.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/roster_tab.dart' show RoleBadge;
import '../../team/presentation/team_texts.dart';
import 'admin_texts.dart';
import 'match_settings_screen.dart';
import 'pairing_rules_screen.dart';
import 'skill_levels_screen.dart';
import 'team_info_edit_screen.dart';

/// 관리 탭 (팀장·운영진): 팀 설정(팀 정보·경기 설정·투표 설정·실력 등급·그룹·라이벌), 초대 코드 발급, 가입 신청 승인·거절,
/// 팀원 관리(운영진 지정·해제, 위임, 내보내기 — 팀장만), 팀 해체(팀장만).
/// 버튼 노출은 Entitlements 로만 판단하고, 서버가 같은 규칙으로 다시 거절한다.
///
/// 역할 변경·위임·내보내기·가입 처리·해체 알림은 서버 함수가 같은 처리 안에서 만든다 (202611050029, Q-022, Q-067 8·15번).
class AdminTab extends StatefulWidget {
  const AdminTab({
    required this.services,
    required this.team,
    required this.viewer,
    required this.onTeamChanged,
    required this.onDissolved,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;

  /// 위임처럼 내 역할이 바뀌거나 팀 정보를 고친 뒤 (팀 목록 다시 읽기)
  final Future<void> Function() onTeamChanged;
  final Future<void> Function() onDissolved;

  @override
  State<AdminTab> createState() => _AdminTabState();
}

class _AdminTabState extends State<AdminTab> {
  List<IncomingJoinRequest>? _requests;
  List<MemberEntry>? _members;
  bool _busy = false;
  String? _error;

  AppServices get _s => widget.services;
  Entitlements get _e => _s.entitlements;
  String get _teamId => widget.team.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await _s.membership.listPendingRequests(_teamId);
      final members = _e.canPerform(widget.viewer, TeamAction.removeMember)
          ? await _s.teams.listMembers(_teamId)
          : null;
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _members = members;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = TeamTexts.serverError(e.code));
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = TeamTexts.serverError(e.code));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TeamTexts.cancel),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TeamTexts.confirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _issueInvite() async {
    String? code;
    final ok = await _run(() async => code = await _s.membership.issueInvite(_teamId));
    if (!ok || !mounted || code == null) return;
    // 원본은 이번 한 번만 보인다 (Q-020). 링크 페이지는 Q-039 보류 → 코드만 복사.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(TeamTexts.inviteIssuedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(code!, key: const Key('invite-code')),
            const SizedBox(height: AppSpacing.md),
            const Text(TeamTexts.inviteIssuedNote),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(TeamTexts.copied)),
                );
              }
            },
            child: const Text(TeamTexts.copy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(TeamTexts.close),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(IncomingJoinRequest r, bool approve) async {
    if (await _run(() => _s.membership.decideJoinRequest(r.requestId, approve: approve))) {
      await _load();
    }
  }

  Future<void> _memberAction(MemberEntry m, TeamAction action) async {
    final String message;
    final Future<void> Function() call;
    var rolesChangedForMe = false;
    switch (action) {
      case TeamAction.appointOrDismissManager when m.role == TeamRole.member:
        message = TeamTexts.confirmAction(TeamTexts.appointManager, m.displayName);
        call = () => _s.membership.appointManager(_teamId, m.userId);
      case TeamAction.appointOrDismissManager:
        message = TeamTexts.confirmAction(TeamTexts.dismissManager, m.displayName);
        call = () => _s.membership.dismissManager(_teamId, m.userId);
      case TeamAction.transferOwnership:
        message = TeamTexts.confirmTransfer(m.displayName);
        call = () => _s.membership.transferOwnership(_teamId, m.userId);
        rolesChangedForMe = true;
      case TeamAction.removeMember:
        message = TeamTexts.confirmRemove(m.displayName);
        call = () => _s.membership.removeMember(_teamId, m.userId);
      default:
        return;
    }
    if (!await _confirm(message)) return;
    if (!await _run(call)) return;
    if (rolesChangedForMe) {
      await widget.onTeamChanged();
    } else {
      await _load();
    }
  }

  String _actionLabel(MemberEntry m, TeamAction a) => switch (a) {
    TeamAction.appointOrDismissManager =>
      m.role == TeamRole.member ? TeamTexts.appointManager : TeamTexts.dismissManager,
    TeamAction.transferOwnership => TeamTexts.transferOwnership,
    TeamAction.removeMember => TeamTexts.removeMember,
    _ => '',
  };

  Future<void> _openTeamInfo() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TeamInfoEditScreen(
          admin: _s.admin,
          logos: _s.logos,
          logoPicker: _s.logoPicker,
          places: _s.places,
          entitlements: _e,
          viewer: widget.viewer,
          team: widget.team,
        ),
      ),
    );
    if (saved ?? false) await widget.onTeamChanged();
  }

  Future<void> _openMatchSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MatchSettingsScreen(admin: _s.admin, team: widget.team),
      ),
    );
    if ((saved ?? false) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AdminTexts.saved)),
      );
    }
  }

  Future<void> _openAwardSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AwardSettingsScreen(awards: _s.awards, team: widget.team),
      ),
    );
    if ((saved ?? false) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AwardTexts.saved)),
      );
    }
  }

  Future<void> _openSkillLevels() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SkillLevelsScreen(
        admin: _s.admin,
        teams: _s.teams,
        entitlements: _e,
        viewer: widget.viewer,
        team: widget.team,
      ),
    ),
  );

  Future<void> _openPairingRules() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PairingRulesScreen(admin: _s.admin, teams: _s.teams, team: widget.team),
    ),
  );

  /// 2차 팀 구독 리포트 화면 자리 (1차에는 메뉴가 숨겨져 불리지 않는다).
  // TODO(2차): 팀 구독 리포트 화면 연결 (TeamReportInfo).
  Future<void> _openTeamReport() async {}

  /// 팀 설정 메뉴. 메뉴마다 Entitlements 로만 보일지 정한다.
  List<Widget> _settingsSection(ThemeData theme) {
    final v = widget.viewer;
    final items = [
      if (_e.canPerform(v, TeamAction.editTeamInfo))
        (const Key('open-team-info'), Icons.edit_outlined, AdminTexts.teamInfo, _openTeamInfo),
      if (_e.canPerform(v, TeamAction.editMatchSettings))
        (const Key('open-match-settings'), Icons.event_note_outlined, AdminTexts.matchSettings, _openMatchSettings),
      if (_e.canPerform(v, TeamAction.editAwardSettings))
        (const Key('open-award-settings'), Icons.emoji_events_outlined, AwardTexts.awardSettings, _openAwardSettings),
      if (_e.canPerform(v, TeamAction.setSkillLevel))
        (const Key('open-skill-levels'), Icons.leaderboard_outlined, AdminTexts.skillLevels, _openSkillLevels),
      if (_e.canPerform(v, TeamAction.editGroupRivalRules) &&
          _e.canView(v, const GroupRivalSettingsInfo()))
        (const Key('open-pairing-rules'), Icons.compare_arrows, AdminTexts.groupRival, _openPairingRules),
      // 2차 "출석·참여 리포트" 메뉴 자리 (팀 구독). 1차에는 Entitlements.showTeamReportMenu 가 거절해 보이지 않는다.
      if (_e.showTeamReportMenu(v))
        (const Key('open-team-report'), Icons.insights_outlined, AdminTexts.teamReport, _openTeamReport),
    ];
    if (items.isEmpty) return const [];
    return [
      const SectionHeader(AdminTexts.settingsSection),
      SectionCard(
        children: [
          for (final (key, icon, label, onTap) in items)
            ListTile(
              key: key,
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(Icons.chevron_right),
              enabled: !_busy,
              onTap: onTap,
            ),
        ],
      ),
      AppSpacing.sectionGap,
    ];
  }

  Future<void> _dissolve() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => _DissolveDialog(teamName: widget.team.name),
    );
    if (input == null) return;
    final logoPath = widget.team.logoImagePath;
    if (await _run(() => _s.teams.dissolveTeam(_teamId, input))) {
      // 서버가 로고 칸을 비웠다. 해체 당시 관리자로서 파일도 지운다 (실패하면 team-logo-cleanup).
      if (logoPath != null) await _s.logos.deleteFileQuietly(logoPath);
      await widget.onDissolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requests = _requests;
    final members = _members;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppSpacing.page,
        children: [
          if (_error != null) ...[
            Text(_error!, key: const Key('admin-error'), style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: AppSpacing.sm),
          ],
          // ---- 팀 설정 (팀 정보·경기 설정·실력 등급·그룹·라이벌)
          ..._settingsSection(theme),
          // ---- 초대 코드 (팀장·운영진)
          if (_e.canPerform(widget.viewer, TeamAction.reviewJoinRequests)) ...[
            const SectionHeader(TeamTexts.inviteSection),
            const SizedBox(height: AppSpacing.xs),
            const Text(TeamTexts.issueInviteNote),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const Key('issue-invite'),
              onPressed: _busy ? null : _issueInvite,
              child: const Text(TeamTexts.issueInvite),
            ),
            AppSpacing.sectionGap,
            // ---- 가입 신청
            const SectionHeader(TeamTexts.requestsSection),
            if (requests == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (requests.isEmpty)
              const EmptyState(
                icon: Icons.mark_email_read_outlined,
                message: TeamTexts.noRequests,
                compact: true,
              )
            else
              for (final r in requests)
                ListTile(
                  key: Key('request-${r.requestId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.displayName),
                  subtitle: (r.bio == null || r.bio!.isEmpty) ? null : Text(r.bio!),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _decide(r, false),
                        child: const Text(TeamTexts.reject),
                      ),
                      FilledButton(
                        key: Key('approve-${r.requestId}'),
                        onPressed: _busy ? null : () => _decide(r, true),
                        child: const Text(TeamTexts.approve),
                      ),
                    ],
                  ),
                ),
          ],
          // ---- 팀원 관리 (팀장만)
          if (members != null) ...[
            AppSpacing.sectionGap,
            const SectionHeader(TeamTexts.membersSection),
            for (final m in members)
              Builder(
                builder: (context) {
                  final actions = _e.memberActions(
                    widget.viewer,
                    targetUserId: m.userId,
                    targetRole: m.role,
                  );
                  return ListTile(
                    key: Key('manage-${m.userId}'),
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Flexible(child: Text(m.displayName)),
                        if (m.role != TeamRole.member) ...[
                          const SizedBox(width: 8),
                          RoleBadge(role: m.role),
                        ],
                      ],
                    ),
                    trailing: actions.isEmpty
                        ? null
                        : PopupMenuButton<TeamAction>(
                            key: Key('manage-menu-${m.userId}'),
                            enabled: !_busy,
                            onSelected: (a) => _memberAction(m, a),
                            itemBuilder: (_) => [
                              for (final a in actions)
                                PopupMenuItem(value: a, child: Text(_actionLabel(m, a))),
                            ],
                          ),
                  );
                },
              ),
          ],
          // ---- 팀 해체 (팀장만, Q-067 7·8번)
          if (_e.canPerform(widget.viewer, TeamAction.disbandTeam)) ...[
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(TeamTexts.dissolveSection),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const Key('dissolve-team'),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: _busy ? null : _dissolve,
              child: const Text(TeamTexts.dissolve),
            ),
          ],
        ],
      ),
    );
  }
}

/// 팀 해체 확인: 팀 이름을 입력해야 버튼이 켜진다 (Q-067 7번). 확인하면 입력값을 돌려준다.
class _DissolveDialog extends StatefulWidget {
  const _DissolveDialog({required this.teamName});

  final String teamName;

  @override
  State<_DissolveDialog> createState() => _DissolveDialogState();
}

class _DissolveDialogState extends State<_DissolveDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = TeamValidator.dissolveConfirmationMatches(
      teamName: widget.teamName,
      input: _controller.text,
    );
    return AlertDialog(
      title: const Text(TeamTexts.dissolve),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(TeamTexts.dissolveGuide(widget.teamName)),
          TextField(
            key: const Key('dissolve-input'),
            controller: _controller,
            decoration: const InputDecoration(labelText: TeamTexts.dissolveInputLabel),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(TeamTexts.cancel),
        ),
        FilledButton(
          key: const Key('dissolve-confirm'),
          onPressed: matches ? () => Navigator.of(context).pop(_controller.text) : null,
          child: const Text(TeamTexts.dissolve),
        ),
      ],
    );
  }
}
