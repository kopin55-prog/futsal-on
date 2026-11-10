import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/region.dart';
import '../../../shared/domain/venue.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/data/logo_picker.dart';
import '../../team/data/team_logo_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/logo_photo_field.dart';
import '../../team/presentation/region_field.dart';
import '../../team/presentation/regular_schedule_fields.dart';
import '../../team/presentation/team_logo.dart';
import '../../team/presentation/team_texts.dart';
import '../../venue/data/place_search_repository.dart';
import '../../venue/presentation/venue_field.dart';
import '../data/team_admin_repository.dart';
import 'admin_texts.dart';

/// 팀 정보 수정 (팀장·운영진, data-model.md 3-1): 팀 이름, 정기 운동일, 인원 모집 켜기·끄기,
/// 로고 글자(팀장만, Q-014). 저장하면 true 로 닫힌다.
///
/// - 로고 글자를 손대지 않으면 서버로 보내지 않는다 → 이름을 바꾸면 서버 트리거가 Q-047 규칙으로 갱신.
///   화면에는 같은 규칙의 미리보기를 보여준다.
/// - 팀장이 로고 글자 칸을 비우면 새 이름의 기본값(앞 두 글자)으로 저장 (팀 만들기와 같은 동작).
/// - 지정 풋살장: 카카오맵 검색 또는 직접 입력 (Q-032, Q-068 2번). 팀 정보와 한 번에 저장.
/// - 활동 지역: 카카오 검색 구장을 고르면 주소로 채움, 바꾸거나 비울 수 있음 (Q-079 4번). 항상 현재 값을 보낸다.
/// - 로고 사진: 팀 정보 저장 뒤 바꾸거나 지운다 (Q-068 1번). 사진만 실패하면 안내하고 닫는다.
class TeamInfoEditScreen extends StatefulWidget {
  const TeamInfoEditScreen({
    required this.admin,
    required this.logos,
    required this.logoPicker,
    required this.places,
    required this.entitlements,
    required this.viewer,
    required this.team,
    super.key,
  });

  final TeamAdminRepository admin;
  final TeamLogoRepository logos;
  final LogoPicker logoPicker;
  final PlaceSearchRepository places;
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
  late Venue? _venue = widget.team.venue;
  late Region? _region = widget.team.region;
  late LogoPhotoDraft _photo = LogoPhotoDraft(currentPath: widget.team.logoImagePath);
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
          venue: _venue,
          region: _region,
          logoText: _logoTouched ? _logoPreview : null,
        ),
      );
      await _saveLogoPhoto();
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _serverError = AdminTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 로고 사진 바꾸기·지우기. 실패해도 팀 정보는 이미 저장됐으므로 안내만 한다.
  Future<void> _saveLogoPhoto() async {
    if (!_photo.changed) return;
    final teamId = widget.team.id;
    try {
      final png = _photo.newPng;
      if (png != null) {
        await widget.logos.setLogo(teamId, png, previousPath: _photo.currentPath);
      } else if (_photo.currentPath != null) {
        await widget.logos.removeLogo(teamId, _photo.currentPath!);
      }
    } on ServerFailure {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(TeamTexts.logoPhotoSaveFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.teamInfo)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Center(
              child: TeamLogo(
                key: const Key('team-info-logo-preview'),
                text: _logoPreview,
                imagePath: _photo.shownPath,
                imageBytes: _photo.newPng,
                size: 88,
              ),
            ),
            AppSpacing.sectionGap,
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
            AppSpacing.fieldGap,
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
            AppSpacing.sectionGap,
            LogoPhotoField(
              value: _photo,
              picker: widget.logoPicker,
              enabled: !_saving,
              onChanged: (v) => setState(() => _photo = v),
            ),
            AppSpacing.sectionGap,
            RegularScheduleFields(
              value: _schedule,
              onChanged: (v) => setState(() => _schedule = v),
            ),
            AppSpacing.sectionGap,
            VenueField(
              value: _venue,
              places: widget.places,
              enabled: !_saving,
              onChanged: (v) => setState(() {
                _venue = v;
                _region = regionAfterVenueChange(v, _region);
              }),
            ),
            AppSpacing.sectionGap,
            TeamRegionField(
              value: _region,
              enabled: !_saving,
              onChanged: (v) => setState(() => _region = v),
            ),
            AppSpacing.fieldGap,
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
            AppSpacing.sectionGap,
            if (_serverError != null) ErrorText(_serverError!, key: const Key('team-info-error')),
            PrimaryButton(
              key: const Key('team-info-save'),
              label: AdminTexts.save,
              busy: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
