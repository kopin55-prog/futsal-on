import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../auth/presentation/auth_texts.dart';
import '../data/injury_repository.dart';
import 'injury_texts.dart';

/// 부상 정보 동의 (나중에 동의, 스프린트 04 2-1).
///
/// 문구는 docs/consent-texts.md 부상 항목(표·철회 안내) 그대로 (가입 동의 화면과 같은 [ConsentTexts]).
/// [동의] → 서버 agree_injury_consent → true 로 닫힘. 뒤로 가면 null (등록 화면으로 가지 않음).
/// 그 사이 다른 기기에서 이미 동의했으면(injury_consent_exists) 동의된 것으로 본다.
class InjuryConsentScreen extends StatefulWidget {
  const InjuryConsentScreen({required this.injuries, super.key});

  final InjuryRepository injuries;

  @override
  State<InjuryConsentScreen> createState() => _InjuryConsentScreenState();
}

class _InjuryConsentScreenState extends State<InjuryConsentScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.injuries.agreeConsent();
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (e.code == ServerErrorCode.injuryConsentExists) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (mounted) setState(() => _error = InjuryTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(InjuryTexts.consentTitle)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(ConsentTexts.injuryTitle, style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            const Text(ConsentTexts.injuryBody),
            AppSpacing.fieldGap,
            Table(
              key: const Key('injury-consent-table'),
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                for (final (label, value) in ConsentTexts.injuryTable)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.md, bottom: AppSpacing.sm),
                        child: Text(label, style: textTheme.labelMedium),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(value, style: textTheme.bodySmall),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(ConsentTexts.injuryWithdrawNote, style: textTheme.bodySmall),
            AppSpacing.sectionGap,
            if (_error != null) ...[
              ErrorText(_error!),
              const SizedBox(height: AppSpacing.sm),
            ],
            FilledButton(
              key: const Key('injury-consent-agree'),
              onPressed: _busy ? null : _agree,
              child: const Text(InjuryTexts.consentAgree),
            ),
          ],
        ),
      ),
    );
  }
}
