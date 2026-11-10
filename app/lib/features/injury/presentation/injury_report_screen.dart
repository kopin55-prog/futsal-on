import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/text_length.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../data/injury_repository.dart';
import '../domain/injury_models.dart';
import 'injury_texts.dart';

/// 부상 등록 (스프린트 04 2-2, 기획서 12장).
///
/// 예상 회복 기간 1~12W 중 하나(S4-06 (1)) + 메모(선택, 20자, 보이는 글자로 셈, 보이지 않는 문자는 이름과 같은 규칙으로 정리).
/// 등록되면 true 로 닫힌다. 서버가 동의·진행 중 부상·메모를 다시 확인한다.
class InjuryReportScreen extends StatefulWidget {
  const InjuryReportScreen({required this.injuries, super.key});

  final InjuryRepository injuries;

  @override
  State<InjuryReportScreen> createState() => _InjuryReportScreenState();
}

class _InjuryReportScreenState extends State<InjuryReportScreen> {
  final _memo = TextEditingController();
  int _weeks = InjuryRules.defaultWeeks;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (InjuryRules.validateMemo(_memo.text) != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.injuries.report(weeks: _weeks, memo: InjuryRules.normalizeMemo(_memo.text));
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = InjuryTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memoError = InjuryRules.validateMemo(_memo.text);
    return Scaffold(
      appBar: AppBar(title: const Text(InjuryTexts.reportTitle)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(InjuryTexts.weeksLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var w = InjuryRules.minWeeks; w <= InjuryRules.maxWeeks; w++)
                  ChoiceChip(
                    key: Key('injury-weeks-$w'),
                    label: Text(InjuryTexts.weeks(w)),
                    selected: _weeks == w,
                    onSelected: _busy ? null : (_) => setState(() => _weeks = w),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(InjuryTexts.longerNote, style: theme.textTheme.bodySmall),
            AppSpacing.sectionGap,
            InjuryMemoField(controller: _memo, onChanged: () => setState(() {})),
            AppSpacing.sectionGap,
            if (_error != null) ErrorText(_error!),
            PrimaryButton(
              key: const Key('injury-report-submit'),
              label: InjuryTexts.submit,
              busy: _busy,
              onPressed: memoError == null ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 부상 메모 입력칸 (등록·메모 수정 공통). 줄바꿈은 입력 단계에서 막고, 글자 수는 보이는 글자로 센다.
class InjuryMemoField extends StatelessWidget {
  const InjuryMemoField({required this.controller, required this.onChanged, this.autofocus = false, super.key});

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final error = InjuryRules.validateMemo(controller.text);
    final count = countChars(InjuryRules.normalizeMemo(controller.text) ?? '');
    return TextField(
      key: const Key('injury-memo'),
      controller: controller,
      autofocus: autofocus,
      maxLines: 1,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
      decoration: InputDecoration(
        labelText: InjuryTexts.memoLabel,
        hintText: InjuryTexts.memoHint,
        counterText: '$count/${InjuryRules.maxMemoLength}',
        errorText: error == null ? null : InjuryTexts.memoError(error),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}
