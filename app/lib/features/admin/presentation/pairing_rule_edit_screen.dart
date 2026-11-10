import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/domain/name_search.dart';
import '../../team/domain/team_models.dart';
import '../domain/pairing_rules.dart';
import 'admin_texts.dart';

/// 그룹·라이벌 설정 하나 만들기·고치기 (스프린트 04 6-4, kopn 2026-11-10: 팀원이 많아도 찾기 쉽게).
///
/// - 위: 이름 검색 칸. 일부 글자로 바로 걸러진다 (정리 규칙은 기존 이름 검색과 같음, [NameSearch]).
/// - 그 아래: 고른 사람 이름표(칩). X 로 뺀다.
/// - 목록: 지금 팀원 이름 가나다순, 고른 사람은 체크 표시. 100명이어도 보이는 줄만 그린다(ListView.builder).
/// - 아래: 켜기 스위치, 2명 미만·모순 안내, 저장. 저장하면 설정을 돌려준다 (사람 순서는 가나다순).
class PairingRuleEditScreen extends StatefulWidget {
  const PairingRuleEditScreen({
    required this.initial,
    required this.members,
    required this.conflictMessage,
    super.key,
  });

  final PairingRule initial;
  final List<MemberEntry> members;

  /// 저장했을 때 모순이면 안내 문구, 없으면 null
  final String? Function(PairingRule) conflictMessage;

  @override
  State<PairingRuleEditScreen> createState() => _PairingRuleEditScreenState();
}

class _Person {
  _Person(this.member) : nameKey = NameSearch.key(member.displayName);

  final MemberEntry member;
  final String nameKey;
}

class _PairingRuleEditScreenState extends State<PairingRuleEditScreen> {
  final _search = TextEditingController();

  /// 지금 팀원, 이름 가나다순 (같으면 ID 순). 검색용 정리 키는 한 번만 만든다.
  late final List<_Person> _people = [
    for (final m in widget.members) _Person(m),
  ]..sort((a, b) {
      final c = a.member.displayName.compareTo(b.member.displayName);
      return c != 0 ? c : a.member.userId.compareTo(b.member.userId);
    });

  // 지금 팀원만 고를 수 있다 (떠난 사람은 서버가 이미 뺀다).
  late final Set<String> _picked = widget.initial.userIds
      .where((id) => widget.members.any((m) => m.userId == id))
      .toSet();
  late bool _enabled = widget.initial.enabled;
  String _queryKey = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PairingRule get _rule => PairingRule(
    id: widget.initial.id,
    kind: widget.initial.kind,
    enabled: _enabled,
    userIds: [
      for (final p in _people)
        if (_picked.contains(p.member.userId)) p.member.userId,
    ],
  );

  void _toggle(String userId) => setState(() {
    if (!_picked.remove(userId)) _picked.add(userId);
  });

  void _onQuery(String text) {
    // 지우기 버튼 표시도 바뀌므로 매번 다시 그린다 (보이는 줄만 그려서 100명이어도 가볍다)
    setState(() => _queryKey = NameSearch.key(text));
  }

  void _clearQuery() {
    _search.clear();
    _onQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rule = _rule;
    final membersOk = PairingRules.membersValid(rule.userIds);
    final conflict = membersOk && _enabled ? widget.conflictMessage(rule) : null;
    final shown = [
      for (final p in _people)
        if (NameSearch.matchesKey(p.nameKey, _queryKey)) p,
    ];
    final pickedPeople = [
      for (final p in _people)
        if (_picked.contains(p.member.userId)) p,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(AdminTexts.kind(rule.kind))),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.sm),
              child: TextField(
                key: const Key('pick-search'),
                controller: _search,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: AdminTexts.searchName,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('pick-search-clear'),
                          tooltip: AdminTexts.clearSearch,
                          icon: const Icon(Icons.close),
                          onPressed: _clearQuery,
                        ),
                ),
              ),
            ),
            // 고른 사람 이름표 (많아지면 이 칸 안에서 스크롤)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Text(
                AdminTexts.pickedCount(pickedPeople.length),
                key: const Key('picked-count'),
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (pickedPeople.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 112),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final p in pickedPeople)
                        InputChip(
                          key: Key('picked-${p.member.userId}'),
                          label: Text(p.member.displayName),
                          onDeleted: () => _toggle(p.member.userId),
                          deleteButtonTooltipMessage: AdminTexts.unpick,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        AdminTexts.noNameMatch,
                        key: const Key('pick-no-match'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('pick-list'),
                      itemCount: shown.length,
                      itemExtent: 52,
                      itemBuilder: (context, i) {
                        final m = shown[i].member;
                        return CheckboxListTile(
                          key: Key('pick-${m.userId}'),
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                          title: Text(m.displayName, overflow: TextOverflow.ellipsis),
                          value: _picked.contains(m.userId),
                          onChanged: (_) => _toggle(m.userId),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const Key('rule-dialog-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(AdminTexts.enabled),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  if (!membersOk)
                    Text(AdminTexts.pickMembers, style: TextStyle(color: scheme.error)),
                  if (conflict != null)
                    Text(conflict, key: const Key('rule-dialog-conflict'), style: TextStyle(color: scheme.error)),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton(
                    key: const Key('rule-dialog-save'),
                    onPressed: membersOk && conflict == null ? () => Navigator.of(context).pop(rule) : null,
                    child: const Text(AdminTexts.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
