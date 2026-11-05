import 'package:flutter/material.dart';

import '../../../shared/domain/position.dart';
import '../domain/position_picker.dart';
import '../domain/profile_validation.dart';
import 'profile_texts.dart';

/// 프로필 입력 칸 (가입 단계 만들기·내 프로필 수정 공통).
///
/// [onSubmit] 은 저장을 시도하고 실패하면 화면에 보일 문구를, 성공하면 null 을 돌려준다.
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    required this.submitLabel,
    required this.onSubmit,
    this.initialName = '',
    this.initialBio,
    this.initialPositions = const [],
    this.initialDedicatedGk = false,
    super.key,
  });

  final String submitLabel;
  final Future<String?> Function(ProfileInput input) onSubmit;
  final String initialName;
  final String? initialBio;
  final List<Position> initialPositions;
  final bool initialDedicatedGk;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final _nameController = TextEditingController(text: widget.initialName);
  late final _bioController = TextEditingController(text: widget.initialBio ?? '');
  late final _picker = PositionPicker(
    positions: widget.initialPositions,
    isDedicatedGk: widget.initialDedicatedGk,
  );
  bool _submitted = false;
  bool _saving = false;
  String? _serverError;
  String? _pickHint;

  ProfileInput get _input => ProfileInput(
    name: _nameController.text,
    bio: _bioController.text,
    positions: _picker.positions,
    isDedicatedGk: _picker.isDedicatedGk,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _togglePosition(Position p) {
    setState(() {
      final hint = _picker.toggle(p);
      _pickHint = hint == null ? null : ProfileTexts.hint(hint);
    });
  }

  void _toggleDedicatedGk(bool value) {
    setState(() {
      final hint = _picker.setDedicatedGk(value);
      _pickHint = hint == null ? null : ProfileTexts.hint(hint);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (ProfileValidator.validate(_input).isNotEmpty) return;

    setState(() => _saving = true);
    final error = await widget.onSubmit(_input);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _serverError = error;
    });
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
        _pickHint ??
        firstOf(const [
          ProfileError.positionsRequired,
          ProfileError.tooManyPositions,
          ProfileError.dedicatedGkNeedsFreeSlot,
          ProfileError.duplicatePositions,
        ]);
    final errorColor = Theme.of(context).colorScheme.error;

    return ListView(
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
                selected: _picker.isSelected(p),
                // 전문 골키퍼인 동안 골키퍼는 해제할 수 없음 (Q-067 16번)
                onSelected: _picker.isLocked(p)
                    ? null
                    : (_) => _togglePosition(p),
              ),
          ],
        ),
        CheckboxListTile(
          key: const Key('profile-dedicated-gk'),
          value: _picker.isDedicatedGk,
          onChanged: (v) => _toggleDedicatedGk(v ?? false),
          title: const Text(ProfileTexts.dedicatedGkLabel),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (positionError != null)
          Text(
            positionError,
            key: const Key('profile-position-error'),
            style: TextStyle(color: errorColor),
          ),
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
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
