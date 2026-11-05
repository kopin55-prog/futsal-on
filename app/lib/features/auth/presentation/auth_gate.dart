import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/data/server_error.dart';
import '../../dashboard/presentation/home_placeholder_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_create_screen.dart';
import '../data/auth_repository.dart';
import '../domain/signup_consent.dart';
import 'auth_texts.dart';
import 'consent_screen.dart';
import 'login_screen.dart';

/// 로그인 상태에 따라 첫 화면을 고른다.
///
/// 로그인 안 됨 → 로그인 / 로그인 + 프로필 없음 → 동의 → 프로필 만들기 / 프로필 있음 → 홈.
/// 같은 이메일 안내 화면은 없다 (Q-063). 기존 계정에 새 로그인 방법이 붙으면 프로필이 이미 있으므로
/// 동의를 다시 받지 않고 바로 홈으로 간다 (data-model.md 2-1).
class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.authRepository,
    required this.profileRepository,
    super.key,
  });

  final AuthRepository authRepository;
  final ProfileRepository profileRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Stage { loading, signedOut, consent, profile, home, error }

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<String?>? _subscription;
  String? _userId;
  _Stage _stage = _Stage.loading;
  SignupConsent _consent = const SignupConsent();
  int _checkToken = 0;

  @override
  void initState() {
    super.initState();
    _onUser(widget.authRepository.currentUserId);
    _subscription = widget.authRepository.userIdChanges.listen((id) {
      if (id != _userId) _onUser(id);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onUser(String? userId) {
    _userId = userId;
    _consent = const SignupConsent();
    if (userId == null) {
      setState(() => _stage = _Stage.signedOut);
      return;
    }
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final token = ++_checkToken;
    setState(() => _stage = _Stage.loading);
    _Stage next;
    try {
      next = await widget.profileRepository.hasOwnProfile()
          ? _Stage.home
          : _Stage.consent;
    } on ServerFailure {
      next = _Stage.error;
    }
    if (mounted && token == _checkToken) setState(() => _stage = next);
  }

  Future<void> _signOut() => widget.authRepository.signOut();

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _Stage.signedOut => LoginScreen(authRepository: widget.authRepository),
      _Stage.consent => ConsentScreen(
        initial: _consent,
        onSignOut: _signOut,
        onNext: (consent) => setState(() {
          _consent = consent;
          _stage = _Stage.profile;
        }),
      ),
      _Stage.profile => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _stage = _Stage.consent);
        },
        child: ProfileCreateScreen(
          profileRepository: widget.profileRepository,
          consent: _consent,
          onCreated: () => setState(() => _stage = _Stage.home),
        ),
      ),
      _Stage.home => HomePlaceholderScreen(onSignOut: _signOut),
      _Stage.error => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(AuthTempTexts.loadFailed),
              TextButton(
                onPressed: _checkProfile,
                child: const Text(AuthTempTexts.retry),
              ),
              TextButton(
                onPressed: _signOut,
                child: const Text(AuthTempTexts.signOut),
              ),
            ],
          ),
        ),
      ),
    };
  }
}
