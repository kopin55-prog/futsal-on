import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/regular_schedule_fields.dart';
import '../../team/presentation/team_logo.dart';
import '../../team/presentation/team_texts.dart';
import '../data/team_admin_repository.dart';
import 'admin_texts.dart';

/// 팀 정보 수정 (팀장·운영진, data-model.md 3-1): 팀 이름, 정기 운동일, 인원 모집 켜기·끄기,
/// 로고 글자(팀장만, Q-014). 저장하면 true 로 닫힌다.
///
/// - 로고 글자를 손대지 않으면 서버로 보내지 않는다 → 이름을 바꾸면 서버 트리거가 Q-047 규칙으로 갱신.
///   화면에는 같은 규칙의 미리보기를 보여준다.
/// - 팀장이 로고 글자 칸을 비우면 새 이름의 기본값(앞 두 글자)으로 저장 (팀 만들기와 같은 동작).
/// - 지정 풋살장(카카오맵)·로고 사진은 BLOCKED (Q-068) → 자리만.
class TeamInfoEditScreen extends StatefulWidget {
  const TeamInfoEditScreen({
    required this.admin,
    required this.entitlements,
    required this.viewer,
    required this.team,
    super.key,
  });

  final TeamAdminRepository admin;
  final Entitlements entitlements;
  final Viewer viewer;
  final TeamSummary team;

  @override
  State<TeamInfoEditScreen> createState() => _TeamInfoEditScreenState();
}

class _TeamInfoEditScreenState extends State<TeamInfoEditScreen> {
  late final _name = TextEditingController(text: widget.team.name);
  late final _logo = TextEditingController(text: widget.team.logoText);
  late RegularSchedule _schedule = widget.team.schedule;
  late bool _recruiting = widget.team.isRecruiting;
  bool _submitted = false;
  bool _saving = false;
  String? _serverError;

  bool get _canEditLogo =>
      widget.entitlements.canPerform(widget.viewer, TeamAction.editLogoText);

  /// 팀장이 로고 글자 칸을 처음 값에서 바꿨는지 (정리 후 비교).
  bool get _logoTouched =>
      _canEditLogo &&
      TeamValidator.normalizeLogoText(_logo.text) != widget.team.logoText;

  @override
  void dispose() {
    _name.dispose();
    _logo.dispose();
    super.dispose();
  }

  Set<TeamCreateError> get _nameErrors => TeamValidator.validateCreate(name: _name.text);

  Set<LogoTextError> get _logoErrors => !_logoTouched || _logo.text.trim().isEmpty
      ? const {}
      : TeamValidator.validateLogoText(_logo.text);

  Set<RegularScheduleError> get _scheduleErrors => TeamValidator.validateRegularSchedule(
    weekday: _schedule.weekday,
    start: _schedule.start,
    end: _schedule.end,
  );

  /// 저장 뒤 보일 로고 글자.
  String get _logoPreview {
    if (_logoTouched) {
      final typed = TeamValidator.normalizeLogoText(_logo.text);
      return typed.isEmpty ? TeamValidator.defaultLogoText(_name.text) : typed;
    }
    return TeamValidator.previewLogoTextAfterRename(
      oldTeamName: widget.team.name,
      newTeamName: _name.text,
      currentLogoText: widget.team.logoText,
    );
  }

  String? get _nameErrorText {
    if (!_submitted) return null;
    final e = _nameErrors;
    if (e.contains(TeamCreateError.nameRequired)) return TeamTexts.nameRequired;
    if (e.contains(TeamCreateError.nameTooLong)) return TeamTexts.nameTooLong;
    if (e.contains(TeamCreateError.nameHasLineBreak)) return TeamTexts.nameHasLineBreak;
    return null;
  }

  String? get _logoErrorText {
    final e = _logoErrors;
    if (e.contains(LogoTextError.tooLong)) return TeamTexts.logoTooLong;
    if (e.contains(LogoTextError.empty)) return TeamTexts.logoEmpty;
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (_nameErrors.isNotEmpty || _logoErrors.isNotEmpty || _scheduleErrors.isNotEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.admin.updateTeamInfo(
        widget.team.id,
        TeamInfoInput(
          name: TeamValidator.normalizeName(_name.text),
          schedule: _schedule,
          isRecruiting: _recruiting,
          logoText: _logoTouched ? _logoPreview : null,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _serverError = AdminTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.teamInfo)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: TeamLogo(
                key: const Key('team-info-logo-preview'),
                text: _logoPreview,
                size: 64,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('team-info-name'),
              controller: _name,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: TeamTexts.teamName,
                errorText: _nameErrorText,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_canEditLogo)
              TextField(
                key: const Key('team-info-logo-text'),
                controller: _logo,
                maxLines: 1,
                decoration: InputDecoration(
                  labelText: TeamTexts.logoText,
                  helperText: _logoTouched
                      ? AdminTexts.logoTextEditHint(TeamValidator.defaultLogoText(_name.text))
                      : AdminTexts.logoAutoNote,
                  helperMaxLines: 2,
                  errorText: _logoErrorText,
                ),
                onChanged: (_) => setState(() {}),
              )
            else
              Text(
                AdminTexts.logoTextOwnerOnly,
                key: const Key('team-info-logo-owner-only'),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 20),
            RegularScheduleFields(
              value: _schedule,
              onChanged: (v) => setState(() => _schedule = v),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('team-info-recruiting'),
              contentPadding: EdgeInsets.zero,
              title: const Text(AdminTexts.recruiting),
              subtitle: Text(
                _recruiting ? AdminTexts.recruitingOnNote : AdminTexts.recruitingOffNote,
              ),
              value: _recruiting,
              onChanged: (v) => setState(() => _recruiting = v),
            ),
            const SizedBox(height: 8),
            // BLOCKED(Q-068): 카카오맵 구장 선택·로고 사진 업로드
            const ListTile(
              enabled: false,
              leading: Icon(Icons.place_outlined),
              title: Text(TeamTexts.venuePlaceholder),
              contentPadding: EdgeInsets.zero,
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.image_outlined),
              title: Text(TeamTexts.logoPhotoPlaceholder),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            if (_serverError != null) ...[
              Text(_serverError!, key: const Key('team-info-error'), style: TextStyle(color: errorColor)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('team-info-save'),
              onPressed: _saving ? null : _submit,
              child: const Text(AdminTexts.save),
            ),
          ],
        ),
      ),
    );
  }
}
