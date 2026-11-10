import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/roster_tab.dart' show RoleBadge;
import '../data/team_admin_repository.dart';
import '../domain/skill_level.dart';
import 'admin_texts.dart';

/// 실력 등급 설정 (팀장·운영진, data-model.md 3-4). 팀장·운영진은 본인 등급도 보고 정한다 (Q-016).
/// 일반 팀원에게는 이 화면 자체가 열리지 않고(관리 탭), 서버도 읽기를 거절한다.
/// 고르는 즉시 저장한다. "미정"으로 되돌리면 서버가 줄을 지운다.
class SkillLevelsScreen extends StatefulWidget {
  const SkillLevelsScreen({
    required this.admin,
    required this.teams,
    required this.entitlements,
    required this.viewer,
    required this.team,
    super.key,
  });

  final TeamAdminRepository admin;
  final TeamRepository teams;
  final Entitlements entitlements;
  final Viewer viewer;
  final TeamSummary team;

  @override
  State<SkillLevelsScreen> createState() => _SkillLevelsScreenState();
}

class _SkillLevelsScreenState extends State<SkillLevelsScreen> {
  List<MemberEntry>? _members;
  Map<String, SkillLevel> _levels = const {};
  final Set<String> _saving = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await widget.teams.listMembers(widget.team.id);
      final levels = await widget.admin.listSkillLevels(widget.team.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _levels = levels;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    }
  }

  Future<void> _set(MemberEntry m, SkillLevel level) async {
    final before = _levels[m.userId] ?? SkillLevel.undecided;
    if (before == level) return;
    setState(() {
      _saving.add(m.userId);
      _error = null;
      _levels = {..._levels, m.userId: level};
    });
    try {
      await widget.admin.setSkillLevel(widget.team.id, m.userId, level);
    } on ServerFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _levels = {..._levels, m.userId: before};
        _error = AdminTexts.serverError(e.code);
      });
    } finally {
      if (mounted) setState(() => _saving.remove(m.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = _members;
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.skillLevels)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(AdminTexts.skillLevelsNote, style: theme.textTheme.bodySmall),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                key: const Key('skill-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (members == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (members != null)
              for (final m in members)
                // 한 사람씩 Entitlements 로 확인 (화면에서 따로 판단하지 않음).
                if (widget.entitlements.canView(
                  widget.viewer,
                  SkillLevelInfo(subjectUserId: m.userId),
                ))
                  ListTile(
                    key: Key('skill-${m.userId}'),
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
                    trailing: DropdownButton<SkillLevel>(
                      key: Key('skill-select-${m.userId}'),
                      value: _levels[m.userId] ?? SkillLevel.undecided,
                      onChanged: _saving.contains(m.userId)
                          ? null
                          : (v) {
                              if (v != null) _set(m, v);
                            },
                      items: [
                        for (final l in SkillLevel.values)
                          DropdownMenuItem(value: l, child: Text(AdminTexts.skillLevel(l))),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
