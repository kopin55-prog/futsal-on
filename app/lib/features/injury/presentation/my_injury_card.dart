import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../schedule/domain/match_models.dart';
import '../domain/injury_models.dart';
import 'injury_flows.dart';
import 'injury_report_screen.dart';
import 'injury_texts.dart';

/// 내 부상 상태 (동의 여부 + 진행 중 부상). 내 정보 탭의 부상 카드(2-3)와 동의 철회 메뉴(2-4)가 함께 본다.
class MyInjuryController extends ChangeNotifier {
  MyInjuryController({required this.services, required this.userId});

  final AppServices services;
  final String userId;

  bool loaded = false;
  bool failed = false;
  bool busy = false;
  bool hasConsent = false;
  Injury? injury;

  Future<void> load() async {
    failed = false;
    notifyListeners();
    try {
      final consent = await services.injuries.hasActiveConsent(userId);
      final active = await services.injuries.myActiveInjury(userId);
      hasConsent = consent;
      injury = active;
      loaded = true;
    } on ServerFailure {
      failed = true;
    }
    notifyListeners();
  }

  /// 처리 중 표시를 켜고 [action] 을 한 뒤 다시 읽는다. 실패 문구(없으면 null)를 돌려준다.
  Future<String?> run(Future<void> Function() action) async {
    busy = true;
    notifyListeners();
    String? error;
    try {
      await action();
    } on ServerFailure catch (e) {
      error = InjuryTexts.serverError(e.code);
    }
    busy = false;
    await load();
    return error;
  }
}

/// 내 부상 카드 (스프린트 04 2-3, 기획서 12장).
///
/// 진행 중 부상: 남은 W(오늘 한국 날짜 기준 올림, S4-04)·예상 복귀일·메모 + [연장 +1W] [연장 +2W] [회복했어요] [메모 수정](S4-06 (2)).
/// 없으면 [부상 등록] (동의가 없으면 동의 화면부터, 2-1). 지난(회복한) 기록은 보이지 않는다(S4-06 (4)).
/// 보이기·버튼은 Entitlements(InjuryInfo, canManageInjury) 한 곳에서 판단한다 (2-7).
class MyInjuryCard extends StatelessWidget {
  const MyInjuryCard({
    required this.controller,
    required this.viewer,
    this.now = DateTime.now,
    super.key,
  });

  final MyInjuryController controller;
  final Viewer viewer;
  final DateTime Function() now;

  AppServices get _s => controller.services;

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _report(BuildContext context) async {
    await startInjuryReport(context, services: _s, userId: controller.userId, now: now);
    // 등록했거나, 동의만 하고 등록을 그만둔 경우에도(동의 철회 메뉴가 보이게) 다시 읽는다
    await controller.load();
  }

  Future<void> _extend(BuildContext context, int weeks) async {
    DateTime? next;
    final error = await controller.run(() async => next = await _s.injuries.extend(weeks));
    if (!context.mounted) return;
    _toast(context, error ?? InjuryTexts.extended(next!));
  }

  Future<void> _recover(BuildContext context) async {
    final error = await controller.run(_s.injuries.recover);
    if (context.mounted) _toast(context, error ?? InjuryTexts.recovered);
  }

  Future<void> _editMemo(BuildContext context, String? current) async {
    final memo = await showDialog<_MemoResult>(
      context: context,
      builder: (_) => _MemoDialog(initial: current ?? ''),
    );
    if (memo == null || !context.mounted) return;
    final error = await controller.run(() => _s.injuries.updateMemo(memo.value));
    if (context.mounted) _toast(context, error ?? InjuryTexts.memoSaved);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final e = _s.entitlements;
        if (!e.canManageInjury(viewer, subjectUserId: controller.userId)) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final c = controller;
        Widget body;
        if (!c.loaded) {
          body = c.failed
              ? ListTile(
                  title: const Text(InjuryTexts.loadFailed),
                  trailing: TextButton(onPressed: c.load, child: const Text(InjuryTexts.retry)),
                )
              : const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                );
        } else {
          final injury = c.injury;
          final visible = injury != null &&
              e.canView(
                viewer,
                InjuryInfo(subjectUserId: injury.userId, subjectConsented: c.hasConsent, isActive: injury.isActive),
              );
          body = visible ? _active(context, theme, injury) : _empty(context, theme);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(InjuryTexts.sectionTitle),
            Card(key: const Key('my-injury-card'), child: body),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context, ThemeData theme) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      children: [
        Expanded(
          child: Text(
            InjuryTexts.noInjury,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        OutlinedButton.icon(
          key: const Key('injury-report'),
          onPressed: controller.busy ? null : () => _report(context),
          icon: const Icon(Icons.healing_outlined),
          label: const Text(InjuryTexts.reportButton),
        ),
      ],
    ),
  );

  Widget _active(BuildContext context, ThemeData theme, Injury injury) {
    final today = Kst.dateOf(now());
    final weeks = injury.remainingWeeks(DateTime.utc(today.year, today.month, today.day));
    final busy = controller.busy;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.healing, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  InjuryTexts.remaining(weeks),
                  key: const Key('injury-remaining'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(InjuryTexts.expectedReturn(injury.expectedReturnOn), style: theme.textTheme.bodySmall),
          if (injury.memo != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(injury.memo!, key: const Key('injury-memo-text')),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('injury-edit-memo'),
              onPressed: busy ? null : () => _editMemo(context, injury.memo),
              child: const Text(InjuryTexts.editMemo),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final w in InjuryRules.extendWeeks)
                OutlinedButton(
                  key: Key('injury-extend-$w'),
                  onPressed: busy ? null : () => _extend(context, w),
                  child: Text(InjuryTexts.extendButton(w)),
                ),
              FilledButton(
                key: const Key('injury-recover'),
                onPressed: busy ? null : () => _recover(context),
                child: const Text(InjuryTexts.recoverButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoResult {
  const _MemoResult(this.value);
  final String? value;
}

/// 메모 수정 창. 저장하면 정리된 메모(비우면 null), 취소하면 창이 null.
class _MemoDialog extends StatefulWidget {
  const _MemoDialog({required this.initial});

  final String initial;

  @override
  State<_MemoDialog> createState() => _MemoDialogState();
}

class _MemoDialogState extends State<_MemoDialog> {
  late final _memo = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = InjuryRules.validateMemo(_memo.text) == null;
    return AlertDialog(
      title: const Text(InjuryTexts.editMemo),
      content: InjuryMemoField(controller: _memo, autofocus: true, onChanged: () => setState(() {})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(InjuryTexts.cancel)),
        TextButton(
          key: const Key('injury-memo-save'),
          onPressed: ok ? () => Navigator.pop(context, _MemoResult(InjuryRules.normalizeMemo(_memo.text))) : null,
          child: const Text(InjuryTexts.save),
        ),
      ],
    );
  }
}
