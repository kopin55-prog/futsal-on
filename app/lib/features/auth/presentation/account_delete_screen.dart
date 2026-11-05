import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../team/presentation/team_texts.dart';
import '../data/account_repository.dart';

/// 회원 탈퇴 확인 화면 (Q-067 12번): "모든 기록이 지워지고 되돌릴 수 없어요" 확인 후 한 번 더 누르면 진행.
/// 팀장인 팀이 있으면 서버가 거절한다 (Q-037). 성공하면 [onDeleted] (로그아웃 처리).
///
/// 주의: 서버 함수(account-delete)는 아직 배포 전이라 개발 앱에서는 실패 문구가 보인다.
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({required this.accounts, required this.onDeleted, super.key});

  final AccountRepository accounts;
  final Future<void> Function() onDeleted;

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.accounts.deleteAccount();
      if (mounted) Navigator.of(context).pop();
      await widget.onDeleted();
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = TeamTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(TeamTexts.deleteAccountTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TeamTexts.deleteAccountWarning,
                key: const Key('delete-warning'),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (_error != null) ...[
                Text(_error!, key: const Key('delete-error'), style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton(
                key: const Key('delete-confirm'),
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: _busy ? null : _delete,
                child: const Text(TeamTexts.deleteAccountConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
