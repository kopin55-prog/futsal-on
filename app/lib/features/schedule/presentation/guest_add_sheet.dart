import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/position.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../admin/domain/skill_level.dart';
import '../../admin/presentation/admin_texts.dart';
import '../../profile/presentation/profile_texts.dart';
import '../data/guest_repository.dart';
import '../domain/guest_models.dart';
import 'schedule_texts.dart';

/// 게스트 추가 (운영진, 4-2). 이름은 선택(비우면 "게스트N"), 포지션 최대 3개(4번째는 안내), 대략 실력 선택.
/// 매번 새로 입력한다 (M-19). 추가하면 true 로 닫힌다. 서버가 같은 규칙으로 다시 거절한다.
class GuestAddSheet extends StatefulWidget {
  const GuestAddSheet({required this.guests, required this.matchId, required this.existing, super.key});

  final GuestRepository guests;
  final String matchId;

  /// 지금 이 일정의 게스트 (다음 번호·같은 이름·인원 검사용)
  final List<MatchGuest> existing;

  @override
  State<GuestAddSheet> createState() => _GuestAddSheetState();
}

class _GuestAddSheetState extends State<GuestAddSheet> {
  final _name = TextEditingController();
  final List<Position> _positions = [];
  SkillLevel _skill = SkillLevel.undecided;
  String? _hint;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  GuestInput get _input => GuestInput(name: _name.text, positions: List.of(_positions), skillLevel: _skill);

  Set<GuestInputError> get _errors => _input.validate(existing: widget.existing);

  void _toggle(Position p) {
    setState(() {
      _hint = null;
      if (_positions.contains(p)) {
        _positions.remove(p);
      } else if (_positions.length >= GuestInput.maxPositions) {
        _hint = ScheduleTexts.guestMaxPositions;
      } else {
        _positions.add(p);
      }
    });
  }

  Future<void> _save() async {
    if (_errors.isNotEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.guests.addGuest(widget.matchId, _input);
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = ScheduleTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = _errors;
    final nameError = errors
        .where((e) => e == GuestInputError.nameTooLong || e == GuestInputError.nameHasLineBreak ||
            e == GuestInputError.duplicateName)
        .map(ScheduleTexts.guestError)
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ScheduleTexts.addGuest, style: theme.textTheme.titleLarge),
            AppSpacing.fieldGap,
            TextField(
              key: const Key('guest-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: ScheduleTexts.guestName,
                hintText: ScheduleTexts.guestNameHint(GuestInput.nextGuestNo(widget.existing)),
                errorText: nameError,
              ),
              onChanged: (_) => setState(() {}),
            ),
            AppSpacing.fieldGap,
            Text(ScheduleTexts.guestPositions, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final p in Position.values)
                  FilterChip(
                    key: Key('guest-position-${p.name}'),
                    label: Text(ProfileTexts.position(p)),
                    selected: _positions.contains(p),
                    onSelected: (_) => _toggle(p),
                  ),
              ],
            ),
            if (_hint != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(_hint!, key: const Key('guest-position-hint'), style: theme.textTheme.bodySmall),
              ),
            AppSpacing.fieldGap,
            DropdownButtonFormField<SkillLevel>(
              key: const Key('guest-skill'),
              initialValue: _skill,
              decoration: const InputDecoration(labelText: ScheduleTexts.guestSkill),
              items: [
                for (final l in SkillLevel.values) DropdownMenuItem(value: l, child: Text(AdminTexts.skillLevel(l))),
              ],
              onChanged: (v) => setState(() => _skill = v ?? SkillLevel.undecided),
            ),
            AppSpacing.fieldGap,
            if (errors.contains(GuestInputError.tooManyGuests))
              ErrorText(ScheduleTexts.guestError(GuestInputError.tooManyGuests)),
            if (_error != null) ErrorText(_error!),
            PrimaryButton(
              key: const Key('guest-save'),
              label: ScheduleTexts.addGuest,
              busy: _saving,
              onPressed: errors.isEmpty ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
