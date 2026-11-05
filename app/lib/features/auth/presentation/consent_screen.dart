import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/signup_consent.dart';
import 'auth_texts.dart';

/// 가입 동의 화면 (로그인 직후, 프로필 만들기 전). docs/consent-texts.md.
///
/// 필수 3개를 모두 체크해야 [onNext] 가 눌린다. 부상 정보는 처음에 해제(Q-064),
/// "전체 동의"는 부상 정보까지 모두 체크(Q-060 3번).
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    required this.onNext,
    this.onSignOut,
    this.initial = const SignupConsent(),
    super.key,
  });

  final SignupConsent initial;
  final ValueChanged<SignupConsent> onNext;
  final VoidCallback? onSignOut;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  late SignupConsent _consent = widget.initial;

  void _showDocumentPending(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        // TODO(문구 미정): 이용약관·개인정보 처리방침 본문은 출시 전 작성 (docs/consent-texts.md).
        content: const Text(AuthTempTexts.documentPending),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AuthTempTexts.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AuthTempTexts.consentTitle),
        actions: [
          if (widget.onSignOut != null)
            TextButton(
              onPressed: widget.onSignOut,
              child: const Text(AuthTempTexts.signOut),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            CheckboxListTile(
              key: const Key('consent-all'),
              value: _consent.allAgreed,
              onChanged: (v) =>
                  setState(() => _consent = _consent.withAll(v ?? false)),
              title: Text(ConsentTexts.agreeAll, style: textTheme.titleMedium),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(),
            CheckboxListTile(
              key: const Key('consent-age14'),
              value: _consent.age14,
              onChanged: (v) =>
                  setState(() => _consent = _consent.copyWith(age14: v)),
              title: const Text(ConsentTexts.age14Title),
              subtitle: const Text(ConsentTexts.age14Body),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              key: const Key('consent-terms'),
              value: _consent.terms,
              onChanged: (v) =>
                  setState(() => _consent = _consent.copyWith(terms: v)),
              title: const Text(ConsentTexts.termsTitle),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showDocumentPending(ConsentTexts.termsLink),
                  child: const Text(ConsentTexts.termsLink),
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              key: const Key('consent-privacy'),
              value: _consent.privacy,
              onChanged: (v) =>
                  setState(() => _consent = _consent.copyWith(privacy: v)),
              title: const Text(ConsentTexts.privacyTitle),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      _showDocumentPending(ConsentTexts.privacyLink),
                  child: const Text(ConsentTexts.privacyLink),
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              key: const Key('consent-injury'),
              value: _consent.injuryInfo,
              onChanged: (v) =>
                  setState(() => _consent = _consent.copyWith(injuryInfo: v)),
              title: const Text(ConsentTexts.injuryTitle),
              subtitle: const Text(ConsentTexts.injuryBody),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Table(
                columnWidths: const {0: IntrinsicColumnWidth()},
                children: [
                  for (final (label, value) in ConsentTexts.injuryTable)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 6),
                          child: Text(label, style: textTheme.labelMedium),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(value, style: textTheme.bodySmall),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                ConsentTexts.injuryWithdrawNote,
                style: textTheme.bodySmall,
              ),
            ),
            FilledButton(
              key: const Key('consent-next'),
              onPressed: _consent.requiredAgreed
                  ? () => widget.onNext(_consent)
                  : null,
              child: const Text(AuthTempTexts.next),
            ),
          ],
        ),
      ),
    );
  }
}
