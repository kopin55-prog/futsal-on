import 'package:flutter/material.dart';

import '../../auth/presentation/auth_texts.dart';

/// 가입 후 첫 화면 자리. 팀 화면(스프린트 01 다음 단계)으로 교체한다.
/// TODO(문구 미정): 화면 구성·문구 승인 후 교체.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({required this.onSignOut, super.key});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AuthTempTexts.appTitle),
        actions: [
          TextButton(
            onPressed: onSignOut,
            child: const Text(AuthTempTexts.signOut),
          ),
        ],
      ),
      body: const Center(child: Text(AuthTempTexts.homePlaceholder)),
    );
  }
}
