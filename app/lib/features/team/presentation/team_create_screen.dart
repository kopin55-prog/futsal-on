import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/region.dart';
import '../../../shared/domain/venue.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../venue/data/place_search_repository.dart';
import '../../venue/presentation/venue_field.dart';
import '../data/logo_picker.dart';
import '../data/team_logo_repository.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';
import '../domain/team_validation.dart';
import 'logo_photo_field.dart';
import 'region_field.dart';
import 'regular_schedule_fields.dart';
import 'team_logo.dart';
import 'team_texts.dart';

/// 팀 만들기 (data-model.md 3-1): 팀 이름(필수), 로고 글자·로고 사진, 정기 운동일, 지정 풋살장, 활동 지역.
/// 활동 지역은 카카오 검색으로 구장을 고르면 주소로 채우고, 바꾸거나 비울 수 있다 (Q-079 4번).
/// 만든 사람이 팀장이므로 로고 글자도 정할 수 있다 (Q-014). 만들면 팀 ID 를 돌려주며 닫힌다.
///
/// 로고 사진은 팀이 생긴 뒤에 올린다 (저장 경로에 팀 ID 가 필요). 사진만 실패하면 팀은 만들어진 채로
/// 안내하고 닫는다 (팀 정보 수정에서 다시).
class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({
    required this.teams,
    required this.logos,
    required this.logoPicker,
    required this.places,
    super.key,
  });

  final TeamRepository teams;
  final TeamLogoRepository logos;
  final LogoPicker logoPicker;
  final PlaceSearchRepository places;

  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  final _name = TextEditingController();
  final _logo = TextEditingController();
  RegularSchedule _schedule = const RegularSchedule();
  LogoPhotoDraft _photo = const LogoPhotoDraft();
  Venue? _venue;
  Region? _region;
  bool _submitted = false;
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _name.dispose();
    _logo.dispose();
    super.dispose();
  }

  Set<TeamCreateError> get _nameErrors =>
      TeamValidator.validateCreate(name: _name.text);

  Set<LogoTextError> get _logoErrors => _logo.text.trim().isEmpty
      ? const {}
      : TeamValidator.validateLogoText(_logo.text);

  Set<RegularScheduleError> get _scheduleErrors =>
      TeamValidator.validateRegularSchedule(
        weekday: _schedule.weekday,
        start: _schedule.start,
        end: _schedule.end,
      );

  String? get _nameErrorText {
    if (!_submitted) return null;
    final e = _nameErrors;
    if (e.contains(TeamCreateError.nameRequired)) return TeamTexts.nameRequired;
    if (e.contains(TeamCreateError.nameTooLong)) return TeamTexts.nameTooLong;
    if (e.contains(TeamCreateError.nameHasLineBreak)) {
      return TeamTexts.nameHasLineBreak;
    }
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
      final logo = TeamValidator.normalizeLogoText(_logo.text);
      final id = await widget.teams.createTeam(
        name: TeamValidator.normalizeName(_name.text),
        schedule: _schedule,
        logoText: logo.isEmpty ? null : logo,
        venue: _venue,
        region: _region,
      );
      final png = _photo.newPng;
      if (png != null) {
        try {
          await widget.logos.setLogo(id, png);
        } on ServerFailure {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(TeamTexts.logoPhotoSaveFailed)),
            );
          }
        }
      }
      if (mounted) Navigator.of(context).pop(id);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _serverError = TeamTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = TeamValidator.defaultLogoText(_name.text);
    final logoShown = TeamValidator.normalizeLogoText(_logo.text).isEmpty
        ? preview
        : TeamValidator.normalizeLogoText(_logo.text);

    return Scaffold(
      appBar: AppBar(title: const Text(TeamTexts.createTeam)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Center(
              child: TeamLogo(
                key: const Key('team-create-logo-preview'),
                text: logoShown,
                imageBytes: _photo.newPng,
                size: 88,
              ),
            ),
            AppSpacing.sectionGap,
            TextField(
              key: const Key('team-name'),
              controller: _name,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: TeamTexts.teamName,
                errorText: _nameErrorText,
              ),
              onChanged: (_) => setState(() {}),
            ),
            AppSpacing.fieldGap,
            TextField(
              key: const Key('team-logo-text'),
              controller: _logo,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: TeamTexts.logoText,
                helperText: TeamTexts.logoTextHint(preview),
                errorText: _logoErrorText,
              ),
              onChanged: (_) => setState(() {}),
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
            AppSpacing.sectionGap,
            if (_serverError != null) ErrorText(_serverError!),
            PrimaryButton(
              key: const Key('team-create-submit'),
              label: TeamTexts.create,
              busy: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
