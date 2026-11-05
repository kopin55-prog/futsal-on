import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../auth/presentation/account_delete_screen.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/team_texts.dart';
import '../data/profile_repository.dart';
import 'profile_edit_screen.dart';
import 'profile_texts.dart';

/// 내 정보 탭: 내 프로필 보기·수정, 팀 식별코드, 팀 탈퇴, 로그아웃, 회원 탈퇴.
class MyTab extends StatefulWidget {
  const MyTab({
    required this.services,
    required this.team,
    required this.viewer,
    required this.onLeftTeam,
    required this.onSignOut,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;
  final Future<void> Function() onLeftTeam;
  final Future<void> Function() onSignOut;

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  OwnProfile? _profile;
  String? _error;
  bool _busy = false;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _s.profiles.getOwnProfile();
      if (mounted) setState(() => _profile = p);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = TeamTexts.serverError(e.code));
    }
  }

  Future<void> _edit() async {
    final profile = _profile;
    if (profile == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(profileRepository: _s.profiles, profile: profile),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(TeamTexts.saved)),
        );
      }
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(TeamTexts.confirmLeave(widget.team.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TeamTexts.cancel),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TeamTexts.leaveTeam),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _s.teams.leaveTeam(widget.team.id);
      await widget.onLeftTeam();
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = TeamTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccountDeleteScreen(
          accounts: _s.accounts,
          onDeleted: widget.onSignOut,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _profile;
    final e = _s.entitlements;
    return ListView(
      padding: AppSpacing.page,
      children: [
        if (_error != null) ...[
          Text(_error!, key: const Key('my-error'), style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (p == null && _error == null)
          const Center(child: CircularProgressIndicator())
        else if (p != null) ...[
          Text(p.displayName, key: const Key('my-name'), style: theme.textTheme.titleLarge),
          if (p.bio != null) ...[const SizedBox(height: AppSpacing.xs), Text(p.bio!)],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            children: [
              for (final pos in p.positions) Chip(label: Text(ProfileTexts.position(pos))),
              if (p.isDedicatedGk) const Chip(label: Text(TeamTexts.dedicatedGk)),
            ],
          ),
          // 프로필 수정은 본인만 (Entitlements.canEditProfile, Q-067 2번)
          if (e.canEditProfile(widget.viewer, subjectUserId: widget.viewer.userId))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('edit-profile'),
                onPressed: _edit,
                child: const Text(TeamTexts.editProfile),
              ),
            ),
        ],
        AppSpacing.sectionGap,
        SectionCard(
          children: [
            if (e.canViewTeamCode(widget.viewer))
              ListTile(
                title: const Text(TeamTexts.teamCode),
                subtitle: Text(widget.team.teamCode, key: const Key('my-team-code')),
                trailing: IconButton(
                  tooltip: TeamTexts.copy,
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.team.teamCode));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(TeamTexts.copied)),
                      );
                    }
                  },
                ),
              ),
            if (e.canPerform(widget.viewer, TeamAction.leaveTeam))
              ListTile(
                key: const Key('leave-team'),
                enabled: !_busy,
                title: const Text(TeamTexts.leaveTeam),
                onTap: _leave,
              )
            else
              const ListTile(
                enabled: false,
                title: Text(TeamTexts.leaveTeam),
                subtitle: Text(TeamTexts.ownerCannotLeave),
              ),
            ListTile(
              key: const Key('sign-out'),
              title: const Text(TeamTexts.signOut),
              onTap: widget.onSignOut,
            ),
            ListTile(
              key: const Key('delete-account'),
              title: Text(TeamTexts.deleteAccount, style: TextStyle(color: theme.colorScheme.error)),
              onTap: _deleteAccount,
            ),
          ],
        ),
      ],
    );
  }
}
