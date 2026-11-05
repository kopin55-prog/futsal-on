import 'package:flutter/material.dart';

import '../../../shared/data/server_error.dart';
import '../../auth/domain/signup_consent.dart';
import '../data/profile_repository.dart';
import 'profile_form.dart';
import 'profile_texts.dart';

/// 가입 단계 마지막: 프로필 만들기 (data-model.md 2-2, 2-3).
/// 동의 화면에서 받은 [consent] 와 함께 서버 함수 하나로 저장한다.
class ProfileCreateScreen extends StatelessWidget {
  const ProfileCreateScreen({
    required this.profileRepository,
    required this.consent,
    required this.onCreated,
    super.key,
  });

  final ProfileRepository profileRepository;
  final SignupConsent consent;
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ProfileTexts.title)),
      body: SafeArea(
        child: ProfileForm(
          submitLabel: ProfileTexts.submit,
          onSubmit: (input) async {
            try {
              await profileRepository.createProfile(input, consent);
              onCreated();
              return null;
            } on ServerFailure catch (e) {
              // 다른 기기에서 이미 가입을 마쳤으면 가입 완료로 본다.
              if (e.code == ServerErrorCode.profileExists) {
                onCreated();
                return null;
              }
              return ProfileTexts.serverError(e.code);
            }
          },
        ),
      ),
    );
  }
}
