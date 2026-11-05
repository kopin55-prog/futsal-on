import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/team_texts.dart';
import '../data/team_admin_repository.dart';
import '../domain/pairing_rules.dart';
import 'admin_texts.dart';

/// 그룹·라이벌 설정 (팀장·운영진, data-model.md 3-7, Q-017).
///
/// - 설정 목록: 종류·묶인 사람·켜기 스위치·고치기·삭제.
/// - 켜진 설정끼리 모순이면(켜진 그룹으로 이어진 두 사람이 켜진 라이벌에 함께 있음) 저장·켜기를 막고
///   누구와 누구 때문인지 알려준다. 서버(save_pairing_rule, set_pairing_rule_enabled)도 같은 규칙으로 다시 거절한다.
class PairingRulesScreen extends StatefulWidget {
  const PairingRulesScreen({
    required this.admin,
    required this.teams,
    required this.team,
    super.key,
  });

  final TeamAdminRepository admin;
  final TeamRepository teams;
  final TeamSummary team;

  @override
  State<PairingRulesScreen> createState() => _PairingRulesScreenState();
}

class _PairingRulesScreenState extends State<PairingRulesScreen> {
  List<PairingRule>? _rules;
  List<MemberEntry> _members = const [];
  bool _busy = false;
  String? _error;

  Map<String, String> get _names => {for (final m in _members) m.userId: m.displayName};

  String _name(String userId) => _names[userId] ?? AdminTexts.unknownMember;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await widget.teams.listMembers(widget.team.id);
      final rules = await widget.admin.listPairingRules(widget.team.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _rules = rules;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    }
  }

  /// [changed] 를 저장했을 때 모순이 있으면 안내 문구, 없으면 null.
  String? _conflictMessage(PairingRule changed) {
    final conflicts = PairingRules.conflictsAfterSave(_rules ?? const [], changed);
    if (conflicts.isEmpty) return null;
    final c = conflicts.first;
    return AdminTexts.conflict(_name(c.userA), _name(c.userB));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(PairingRule rule, bool enabled) async {
    if (enabled) {
      final conflict = _conflictMessage(rule.copyWith(enabled: true));
      if (conflict != null) {
        setState(() => _error = conflict);
        return;
      }
    }
    await _run(() => widget.admin.setPairingRuleEnabled(rule.id!, enabled: enabled));
  }

  Future<void> _edit(PairingRule rule) async {
    final result = await showDialog<PairingRule>(
      context: context,
      builder: (_) => _PairingRuleDialog(
        initial: rule,
        members: _members,
        conflictMessage: _conflictMessage,
      ),
    );
    if (result == null) return;
    await _run(() async {
      await widget.admin.savePairingRule(widget.team.id, result);
    });
  }

  Future<void> _delete(PairingRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(AdminTexts.confirmDelete(AdminTexts.kind(rule.kind))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(TeamTexts.cancel),
          ),
          FilledButton(
            key: const Key('confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AdminTexts.delete),
          ),
        ],
      ),
    );
    if (ok ?? false) await _run(() => widget.admin.deletePairingRule(rule.id!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = _rules;
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.groupRival)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            const Text('${AdminTexts.group}: ${AdminTexts.groupNote}'),
            const Text('${AdminTexts.rival}: ${AdminTexts.rivalNote}'),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('add-group'),
                  icon: const Icon(Icons.add),
                  label: const Text(AdminTexts.addGroup),
                  onPressed: _busy || rules == null
                      ? null
                      : () => _edit(
                          const PairingRule(id: null, kind: PairingKind.group, enabled: true, userIds: []),
                        ),
                ),
                OutlinedButton.icon(
                  key: const Key('add-rival'),
                  icon: const Icon(Icons.add),
                  label: const Text(AdminTexts.addRival),
                  onPressed: _busy || rules == null
                      ? null
                      : () => _edit(
                          const PairingRule(id: null, kind: PairingKind.rival, enabled: true, userIds: []),
                        ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                key: const Key('pairing-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (rules == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rules != null && rules.isEmpty)
              const EmptyState(
                icon: Icons.compare_arrows,
                message: AdminTexts.noRules,
                compact: true,
              )
            else if (rules != null)
              for (final r in rules)
                Card(
                  key: Key('rule-${r.id}'),
                  child: ListTile(
                    title: Text(AdminTexts.kind(r.kind)),
                    subtitle: Text(r.userIds.map(_name).join(', ')),
                    onTap: _busy ? null : () => _edit(r),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          key: Key('rule-enabled-${r.id}'),
                          value: r.enabled,
                          onChanged: _busy ? null : (v) => _toggle(r, v),
                        ),
                        IconButton(
                          key: Key('rule-delete-${r.id}'),
                          tooltip: AdminTexts.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _delete(r),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 설정 하나 만들기·고치기: 사람 고르기(2명 이상) + 켜기. 저장할 설정을 돌려준다.
class _PairingRuleDialog extends StatefulWidget {
  const _PairingRuleDialog({
    required this.initial,
    required this.members,
    required this.conflictMessage,
  });

  final PairingRule initial;
  final List<MemberEntry> members;
  final String? Function(PairingRule) conflictMessage;

  @override
  State<_PairingRuleDialog> createState() => _PairingRuleDialogState();
}

class _PairingRuleDialogState extends State<_PairingRuleDialog> {
  // 지금 팀원만 고를 수 있다 (떠난 사람은 서버가 이미 뺀다).
  late final Set<String> _picked = widget.initial.userIds
      .where((id) => widget.members.any((m) => m.userId == id))
      .toSet();
  late bool _enabled = widget.initial.enabled;

  PairingRule get _rule => PairingRule(
    id: widget.initial.id,
    kind: widget.initial.kind,
    enabled: _enabled,
    // 명단 순서대로 보낸다
    userIds: [
      for (final m in widget.members)
        if (_picked.contains(m.userId)) m.userId,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final rule = _rule;
    final membersOk = PairingRules.membersValid(rule.userIds);
    final conflict = membersOk && _enabled ? widget.conflictMessage(rule) : null;
    final errorColor = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(AdminTexts.kind(rule.kind)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in widget.members)
              CheckboxListTile(
                key: Key('pick-${m.userId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(m.displayName),
                value: _picked.contains(m.userId),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _picked.add(m.userId);
                  } else {
                    _picked.remove(m.userId);
                  }
                }),
              ),
            SwitchListTile(
              key: const Key('rule-dialog-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text(AdminTexts.enabled),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (!membersOk)
              Text(AdminTexts.pickMembers, style: TextStyle(color: errorColor)),
            if (conflict != null)
              Text(conflict, key: const Key('rule-dialog-conflict'), style: TextStyle(color: errorColor)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(TeamTexts.cancel),
        ),
        FilledButton(
          key: const Key('rule-dialog-save'),
          onPressed: membersOk && conflict == null ? () => Navigator.of(context).pop(rule) : null,
          child: const Text(AdminTexts.save),
        ),
      ],
    );
  }
}
