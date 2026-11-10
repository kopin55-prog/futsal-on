import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/name_search.dart';
import '../../../shared/presentation/list_controls.dart';
import '../../../shared/presentation/selection_bar.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/roster_tab.dart' show RoleBadge;
import '../../team/presentation/team_texts.dart';
import '../data/team_admin_repository.dart';
import '../domain/skill_level.dart';
import 'admin_texts.dart';

/// 실력 등급 설정 (팀장·운영진, data-model.md 3-4). 팀장·운영진은 본인 등급도 보고 정한다 (Q-016).
/// 일반 팀원에게는 이 화면 자체가 열리지 않고(관리 탭), 서버도 읽기를 거절한다.
///
/// - 한 명씩: 줄 오른쪽에서 고르는 즉시 저장. "미정"으로 되돌리면 서버가 줄을 지운다.
/// - 큰 팀 (Q-079 3번 b): 이름 검색, "미정만 보기", 여러 명 골라(체크) [등급 한 번에 지정] → 서버가 한 번의 처리로 저장.
///   "모두 고르기"는 지금 보이는 사람만 고른다. 100명이어도 보이는 줄만 그린다 (ListView.builder).
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
  final Set<String> _selected = {};
  String? _error;
  String _queryKey = '';
  bool _undecidedOnly = false;
  bool _busy = false;

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
        // 떠난 사람은 선택에서 뺀다
        _selected.removeWhere((id) => !members.any((m) => m.userId == id));
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    }
  }

  SkillLevel _levelOf(String userId) => _levels[userId] ?? SkillLevel.undecided;

  Future<void> _set(MemberEntry m, SkillLevel level) async {
    final before = _levelOf(m.userId);
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

  /// 고른 사람 전부를 같은 등급으로 (서버 set_skill_levels, 한 번의 처리).
  Future<void> _setMany() async {
    final ids = [
      for (final m in _members ?? const <MemberEntry>[])
        if (_selected.contains(m.userId)) m.userId,
    ];
    if (ids.isEmpty || _busy) return;
    final level = await showModalBottomSheet<SkillLevel>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(AdminTexts.pickLevelTitle(ids.length), style: Theme.of(context).textTheme.titleMedium)),
            for (final l in SkillLevel.values)
              ListTile(
                key: Key('skill-many-${l.name}'),
                title: Text(AdminTexts.skillLevel(l)),
                onTap: () => Navigator.pop(context, l),
              ),
          ],
        ),
      ),
    );
    if (level == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.setSkillLevels(widget.team.id, ids, level);
      if (!mounted) return;
      final next = {..._levels};
      for (final id in ids) {
        if (level == SkillLevel.undecided) {
          next.remove(id);
        } else {
          next[id] = level;
        }
      }
      setState(() {
        _levels = next;
        _selected.clear();
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AdminTexts.levelsSaved(ids.length))));
    } on ServerFailure catch (e) {
      // 하나라도 어긋나면 서버는 아무것도 쓰지 않는다 → 명단을 새로 읽어 맞춘 뒤 안내
      await _load();
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String userId) => setState(() {
    if (!_selected.remove(userId)) _selected.add(userId);
  });

  /// 지금 보이는 사람 (Entitlements 로 볼 수 있는 사람 중 검색·"미정만 보기"에 맞는 사람)
  List<MemberEntry> _shown(List<MemberEntry> members) => [
    for (final m in members)
      // 한 사람씩 Entitlements 로 확인 (화면에서 따로 판단하지 않음).
      if (widget.entitlements.canView(widget.viewer, SkillLevelInfo(subjectUserId: m.userId)) &&
          NameSearch.matchesKey(NameSearch.key(m.displayName), _queryKey) &&
          (!_undecidedOnly || _levelOf(m.userId) == SkillLevel.undecided))
        m,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = _members;
    final shown = members == null ? const <MemberEntry>[] : _shown(members);
    final undecidedCount = members == null
        ? 0
        : members.where((m) => _levelOf(m.userId) == SkillLevel.undecided).length;
    final allShownSelected = shown.isNotEmpty && shown.every((m) => _selected.contains(m.userId));
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.skillLevels)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AdminTexts.skillLevelsNote, style: theme.textTheme.bodySmall),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, key: const Key('skill-error'), style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  AppSearchField(
                    key: const Key('skill-search'),
                    hintText: AdminTexts.searchName,
                    clearTooltip: AdminTexts.clearSearch,
                    onChanged: (v) => setState(() => _queryKey = NameSearch.key(v)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilterChipBar<bool>(
                    keyPrefix: 'skill-filter',
                    options: [
                      const FilterOption(false, TeamTexts.filterAll),
                      FilterOption(true, AdminTexts.undecidedOnly, count: undecidedCount),
                    ],
                    selected: _undecidedOnly,
                    onSelected: (v) => setState(() => _undecidedOnly = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: members == null && _error == null
                    ? const Center(child: CircularProgressIndicator())
                    : shown.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Text(
                              TeamTexts.noMemberMatch,
                              key: const Key('skill-no-match'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        key: const Key('skill-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.gutter, AppSpacing.xl),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _row(shown[i]),
                      ),
              ),
            ),
            SelectionBar(
              keyPrefix: 'skill-selection',
              countLabel: TeamTexts.selectedCount(_selected.length),
              selectAllLabel: TeamTexts.selectAll,
              clearLabel: TeamTexts.clearSelection,
              onSelectAll: allShownSelected || shown.isEmpty
                  ? null
                  : () => setState(() => _selected.addAll(shown.map((m) => m.userId))),
              onClear: _selected.isEmpty ? null : () => setState(_selected.clear),
              actions: [
                FilledButton(
                  key: const Key('skill-set-many'),
                  onPressed: _selected.isEmpty || _busy ? null : _setMany,
                  child: const Text(AdminTexts.setLevelForSelected),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(MemberEntry m) {
    final selected = _selected.contains(m.userId);
    return ListTile(
      key: Key('skill-${m.userId}'),
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        key: Key('skill-pick-${m.userId}'),
        value: selected,
        onChanged: _busy ? null : (_) => _toggle(m.userId),
      ),
      onTap: _busy ? null : () => _toggle(m.userId),
      selected: selected,
      title: Row(
        children: [
          Flexible(child: Text(m.displayName, overflow: TextOverflow.ellipsis)),
          if (m.role != TeamRole.member) ...[
            const SizedBox(width: AppSpacing.sm),
            RoleBadge(role: m.role),
          ],
        ],
      ),
      trailing: DropdownButton<SkillLevel>(
        key: Key('skill-select-${m.userId}'),
        value: _levelOf(m.userId),
        onChanged: _saving.contains(m.userId) || _busy
            ? null
            : (v) {
                if (v != null) _set(m, v);
              },
        items: [
          for (final l in SkillLevel.values) DropdownMenuItem(value: l, child: Text(AdminTexts.skillLevel(l))),
        ],
      ),
    );
  }
}
