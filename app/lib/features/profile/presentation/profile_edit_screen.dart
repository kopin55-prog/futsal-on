import 'package:flutter/material.dart';

import '../../../shared/data/server_error.dart';
import '../data/profile_repository.dart';
import 'profile_form.dart';
import 'profile_texts.dart';

/// 내 프로필 수정 (본인만, Q-067 2번). 저장하면 true 로 닫힌다.
class ProfileEditScreen extends StatelessWidget {
  const ProfileEditScreen({
    required this.profileRepository,
    required this.profile,
    super.key,
  });

  final ProfileRepository profileRepository;
  final OwnProfile profile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ProfileTexts.editTitle)),
      body: SafeArea(
        child: ProfileForm(
          submitLabel: ProfileTexts.save,
          initialName: profile.displayName,
          initialBio: profile.bio,
          initialPositions: profile.positions,
          initialDedicatedGk: profile.isDedicatedGk,
          onSubmit: (input) async {
            try {
              await profileRepository.updateOwnProfile(input);
              if (context.mounted) Navigator.of(context).pop(true);
              return null;
            } on ServerFailure catch (e) {
              return ProfileTexts.serverError(e.code);
            }
          },
        ),
      ),
    );
  }
}
