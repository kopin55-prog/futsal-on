import 'package:flutter/material.dart';

import '../../../shared/data/server_error.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';
import '../domain/team_validation.dart';
import 'team_logo.dart';
import 'team_texts.dart';

/// 팀 만들기 (data-model.md 3-1): 팀 이름(필수), 정기 운동일, 로고 글자.
/// 만든 사람이 팀장이므로 로고 글자도 정할 수 있다 (Q-014). 만들면 팀 ID 를 돌려주며 닫힌다.
///
/// 자리만 있는 항목: 지정 풋살장(카카오맵 검색, 연동 작업 전), 로고 사진(저장소 승인 전).
class TeamCreateScreen extends StatefulWidget {
  const TeamCreateScreen({required this.teams, super.key});

  final TeamRepository teams;

  @override
  State<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends State<TeamCreateScreen> {
  final _name = TextEditingController();
  final _logo = TextEditingController();
  int? _weekday;
  ClockTime? _start;
  ClockTime? _end;
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
        weekday: _weekday,
        start: _start,
        end: _end,
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

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current?.hour ?? (start ? 20 : 22),
        minute: current?.minute ?? 0,
      ),
    );
    if (picked == null) return;
    setState(() {
      final t = ClockTime(picked.hour, picked.minute);
      if (start) {
        _start = t;
      } else {
        _end = t;
      }
    });
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
        schedule: RegularSchedule(weekday: _weekday, start: _start, end: _end),
        logoText: logo.isEmpty ? null : logo,
      );
      if (mounted) Navigator.of(context).pop(id);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _serverError = TeamTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeButton({required bool start}) {
    final value = start ? _start : _end;
    final label = start ? TeamTexts.startTime : TeamTexts.endTime;
    final enabled = start ? _weekday != null : _start != null;
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: Key(start ? 'team-start-time' : 'team-end-time'),
              onPressed: enabled ? () => _pickTime(start: start) : null,
              child: Text(value == null ? label : '$label ${value.hhmm}'),
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: TeamTexts.clearTime,
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                if (start) {
                  _start = null;
                  _end = null;
                } else {
                  _end = null;
                }
              }),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final preview = TeamValidator.defaultLogoText(_name.text);
    final logoShown = TeamValidator.normalizeLogoText(_logo.text).isEmpty
        ? preview
        : TeamValidator.normalizeLogoText(_logo.text);
    final scheduleErrors = _scheduleErrors;
    final crosses = _start != null && _end != null &&
        TeamValidator.crossesMidnight(_start!, _end!);

    return Scaffold(
      appBar: AppBar(title: const Text(TeamTexts.createTeam)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: TeamLogo(text: logoShown, size: 64)),
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 20),
            DropdownButtonFormField<int?>(
              key: const Key('team-weekday'),
              initialValue: _weekday,
              decoration: const InputDecoration(labelText: TeamTexts.regularDay),
              items: [
                const DropdownMenuItem(value: null, child: Text(TeamTexts.noWeekday)),
                for (var d = 1; d <= 7; d++)
                  DropdownMenuItem(value: d, child: Text(TeamTexts.weekday(d))),
              ],
              onChanged: (v) => setState(() {
                _weekday = v;
                if (v == null) {
                  _start = null;
                  _end = null;
                }
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [_timeButton(start: true), _timeButton(start: false)]),
            if (crosses)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  TeamTexts.schedule(
                        RegularSchedule(weekday: _weekday, start: _start, end: _end),
                      ) ??
                      '',
                ),
              ),
            for (final e in scheduleErrors)
              Text(TeamTexts.scheduleError(e), style: TextStyle(color: errorColor)),
            const SizedBox(height: 20),
            // 자리만: Q-067 답변으로 동작은 정해졌지만 카카오맵 연동·로고 사진 저장소는 다음 작업.
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
              Text(_serverError!, style: TextStyle(color: errorColor)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('team-create-submit'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(TeamTexts.create),
            ),
          ],
        ),
      ),
    );
  }
}
