import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';
import 'auth_texts.dart';

/// 로그인 화면. 안드로이드는 카카오·구글, iOS 는 애플까지 (Q-030, Q-050).
/// 디자인은 기본 위젯만 쓴 임시 화면이다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.authRepository, super.key});

  final AuthRepository authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  bool get _showApple => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _signIn(SignInMethod method) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authRepository.signIn(method);
    } on SignInFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.reason) {
          SignInFailureReason.cancelled => null,
          SignInFailureReason.kakaoIdTokenMissing =>
            AuthTempTexts.loginKakaoIdTokenMissing,
          SignInFailureReason.notSupported => AuthTempTexts.loginNotSupported,
          SignInFailureReason.googleIdTokenMissing ||
          SignInFailureReason.failed => AuthTempTexts.loginFailed,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AuthTempTexts.appTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 48),
              FilledButton(
                key: const Key('login-kakao'),
                onPressed: _busy ? null : () => _signIn(SignInMethod.kakao),
                child: const Text(AuthTempTexts.loginWithKakao),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                key: const Key('login-google'),
                onPressed: _busy ? null : () => _signIn(SignInMethod.google),
                child: const Text(AuthTempTexts.loginWithGoogle),
              ),
              if (_showApple) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  key: const Key('login-apple'),
                  onPressed: _busy ? null : () => _signIn(SignInMethod.apple),
                  child: const Text(AuthTempTexts.loginWithApple),
                ),
              ],
              if (_busy) ...[
                AppSpacing.sectionGap,
                const Center(child: CircularProgressIndicator()),
              ],
              if (_error != null) ...[
                AppSpacing.sectionGap,
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
