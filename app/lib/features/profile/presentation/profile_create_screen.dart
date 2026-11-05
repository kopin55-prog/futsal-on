import 'package:flutter/material.dart';

import '../../../shared/data/server_error.dart';
import '../../../shared/domain/position.dart';
import '../../auth/domain/signup_consent.dart';
import '../data/profile_repository.dart';
import '../domain/profile_validation.dart';
import 'profile_texts.dart';

/// 가입 단계 마지막: 프로필 만들기 (data-model.md 2-2, 2-3).
/// 동의 화면에서 받은 [consent] 와 함께 서버 함수 하나로 저장한다.
class ProfileCreateScreen extends StatefulWidget {
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
  State<ProfileCreateScreen> createState() => _ProfileCreateScreenState();
}

class _ProfileCreateScreenState extends State<ProfileCreateScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final List<Position> _positions = [];
  bool _isDedicatedGk = false;
  bool _submitted = false;
  bool _saving = false;
  String? _serverError;
  String? _gkHint;

  ProfileInput get _input => ProfileInput(
    name: _nameController.text,
    bio: _bioController.text,
    positions: List.unmodifiable(_positions),
    isDedicatedGk: _isDedicatedGk,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // TODO(U-09): 4번째 포지션을 고를 때의 화면 동작 미정. 지금은 고를 수 있게 두고 저장 전 검사로 막는다.
  void _togglePosition(Position p, bool selected) {
    setState(() {
      if (selected) {
        _positions.add(p);
      } else {
        _positions.remove(p);
        // 전문 골키퍼는 골키퍼 포함이 조건 (Q-019) → 골키퍼를 빼면 전문 골키퍼도 해제.
        if (p == Position.goalkeeper) _isDedicatedGk = false;
      }
      _gkHint = null;
    });
  }

  void _toggleDedicatedGk(bool value) {
    setState(() {
      _gkHint = null;
      if (!value) {
        _isDedicatedGk = false;
        return;
      }
      // 골키퍼가 아닌 포지션 3개면 막고 하나 빼도록 안내 (Q-035).
      if (!ProfileValidator.canCheckDedicatedGk(_positions)) {
        _gkHint = ProfileTexts.error(ProfileError.dedicatedGkNeedsFreeSlot);
        return;
      }
      // 골키퍼 자동 선택 (Q-019).
      if (!_positions.contains(Position.goalkeeper)) {
        _positions.add(Position.goalkeeper);
      }
      _isDedicatedGk = true;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (ProfileValidator.validate(_input).isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.profileRepository.createProfile(_input, widget.consent);
      if (mounted) widget.onCreated();
    } on ServerFailure catch (e) {
      // 다른 기기에서 이미 가입을 마쳤으면 가입 완료로 본다.
      if (e.code == ServerErrorCode.profileExists) {
        if (mounted) widget.onCreated();
        return;
      }
      if (mounted) {
        setState(() => _serverError = ProfileTexts.serverError(e.code));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = _submitted
        ? ProfileValidator.validate(_input)
        : const <ProfileError>{};
    String? firstOf(Iterable<ProfileError> candidates) {
      for (final e in candidates) {
        if (errors.contains(e)) return ProfileTexts.error(e);
      }
      return null;
    }

    final nameError = firstOf(const [
      ProfileError.nameRequired,
      ProfileError.nameTooLong,
      ProfileError.nameHasLineBreak,
    ]);
    final bioError = firstOf(const [
      ProfileError.bioTooLong,
      ProfileError.bioHasLineBreak,
    ]);
    final positionError =
        _gkHint ??
        firstOf(const [
          ProfileError.positionsRequired,
          ProfileError.tooManyPositions,
          ProfileError.dedicatedGkNeedsFreeSlot,
          ProfileError.duplicatePositions,
        ]);
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text(ProfileTexts.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('profile-name'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: ProfileTexts.nameLabel,
                errorText: nameError,
              ),
              maxLines: 1,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('profile-bio'),
              controller: _bioController,
              decoration: InputDecoration(
                labelText: ProfileTexts.bioLabel,
                errorText: bioError,
              ),
              maxLines: 1,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text(
              ProfileTexts.positionsLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final p in Position.values)
                  FilterChip(
                    key: Key('profile-position-${p.name}'),
                    label: Text(ProfileTexts.position(p)),
                    selected: _positions.contains(p),
                    onSelected: (selected) => _togglePosition(p, selected),
                  ),
              ],
            ),
            CheckboxListTile(
              key: const Key('profile-dedicated-gk'),
              value: _isDedicatedGk,
              onChanged: (v) => _toggleDedicatedGk(v ?? false),
              title: const Text(ProfileTexts.dedicatedGkLabel),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (positionError != null)
              Text(positionError, style: TextStyle(color: errorColor)),
            const SizedBox(height: 24),
            if (_serverError != null) ...[
              Text(_serverError!, style: TextStyle(color: errorColor)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('profile-submit'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(ProfileTexts.submit),
            ),
          ],
        ),
      ),
    );
  }
}
