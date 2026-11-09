import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/venue.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../admin/domain/match_settings.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../venue/presentation/venue_field.dart';
import '../domain/match_models.dart';
import 'schedule_texts.dart';

/// 일정 직접 추가 (운영진, 4-2 / 1-4·1-5).
///
/// - 시작 날짜·시각, 종료 날짜·시각 필수 (자정을 넘기면 종료 날짜를 다음날로). 장소는 선택.
/// - 시작을 고르면 종료를 시작 2시간 뒤로 미리 채운다(자정을 넘기면 종료 날짜도 다음날). 종료를 직접 고르기
///   전까지는 시작을 바꿀 때마다 따라간다. 장소는 팀 지정 풋살장으로 미리 채운다. 둘 다 바꾸거나 비울 수 있다 (Q-074 4번).
/// - 마감(경기 몇 시간 전)·미투표 알림(마감 몇 시간 전·끄기)은 이 일정만 고른다. 팀 경기 설정 값이 먼저 채워진다 (Q-072 1번).
/// - 정원은 팀 경기 설정을 따른다 (입력 없음).
/// - 화면 검사는 서버와 같다 (지난 시각 불가, 종료는 시작보다 늦고 24시간 이하). 마감이 이미 지났으면 서버가 마감 = 시작으로 저장.
/// 추가하면 새 일정 ID 로 닫힌다.
class MatchCreateScreen extends StatefulWidget {
  const MatchCreateScreen({required this.services, required this.team, this.now = DateTime.now, super.key});

  final AppServices services;
  final TeamSummary team;
  final DateTime Function() now;

  @override
  State<MatchCreateScreen> createState() => _MatchCreateScreenState();
}

class _MatchCreateScreenState extends State<MatchCreateScreen> {
  final _deadline = TextEditingController();
  CalendarDate? _startDate;
  ClockTime? _startTime;
  CalendarDate? _endDate;
  ClockTime? _endTime;
  late Venue? _venue = widget.team.venue;
  int? _reminderHours;

  /// 종료가 아직 미리 채운 값인지 (종료 날짜·시각을 직접 고르면 false).
  bool _endAuto = true;
  bool _loaded = false;
  bool _submitted = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _deadline.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final s = await widget.services.admin.getMatchSettings(widget.team.id);
      if (!mounted) return;
      setState(() {
        _deadline.text = '${s.rsvpDeadlineHours}';
        _reminderHours = s.rsvpReminderHours;
        _loaded = true;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = ScheduleTexts.serverError(e.code));
    }
  }

  MatchInput? get _input {
    final sd = _startDate, st = _startTime, ed = _endDate, et = _endTime;
    if (sd == null || st == null || ed == null || et == null) return null;
    return MatchInput(
      startDate: sd,
      startTime: st,
      endDate: ed,
      endTime: et,
      venue: _venue,
      rsvpDeadlineHours: int.tryParse(_deadline.text) ?? -1,
      rsvpReminderHours: _reminderHours ?? MatchInput.reminderOff,
    );
  }

  Set<MatchInputError> get _errors {
    final input = _input;
    if (input == null) return {MatchInputError.timeRequired};
    return input.validate(widget.now());
  }

  Future<void> _pickDate({required bool start}) async {
    final today = Kst.dateOf(widget.now());
    final current = (start ? _startDate : _endDate) ?? _startDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked == null) return;
    final d = CalendarDate(picked.year, picked.month, picked.day);
    setState(() {
      if (start) {
        // 종료 날짜가 비었거나 시작보다 앞서면 같은 날로 맞춘다
        final oldStart = _startDate;
        _startDate = d;
        if (_endDate == null || _endDate == oldStart) _endDate = d;
        _fillDefaultEnd();
      } else {
        _endDate = d;
        _endAuto = false;
      }
    });
  }

  /// 종료가 미리 채운 값이면 시작 2시간 뒤로 다시 맞춘다 (Q-074 4번).
  void _fillDefaultEnd() {
    final st = _startTime;
    if (!_endAuto || st == null) return;
    _endTime = MatchInput.defaultEndTime(st);
    final sd = _startDate;
    if (sd != null) _endDate = MatchInput.defaultEndDate(sd, st);
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current?.hour ?? 20, minute: current?.minute ?? 0),
    );
    if (picked == null) return;
    final t = ClockTime(picked.hour, picked.minute);
    setState(() {
      if (start) {
        _startTime = t;
        _fillDefaultEnd();
      } else {
        _endTime = t;
        _endAuto = false;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final input = _input;
    if (input == null || _errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final id = await widget.services.matches.createMatch(widget.team.id, input);
      if (mounted) Navigator.of(context).pop(id);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = ScheduleTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pickerButton(Key key, String label, String? value, VoidCallback onPressed) => OutlinedButton(
    key: key,
    onPressed: onPressed,
    child: Text(value == null ? label : '$label  $value'),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text(ScheduleTexts.addMatch)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : EmptyState(
                  message: _error!,
                  actions: [TextButton(onPressed: _loadDefaults, child: const Text(ScheduleTexts.retry))],
                ),
        ),
      );
    }
    final errors = _errors;
    final visibleErrors = _submitted ? errors : errors.difference({MatchInputError.timeRequired});
    return Scaffold(
      appBar: AppBar(title: const Text(ScheduleTexts.addMatch)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Row(
              children: [
                Expanded(
                  child: _pickerButton(
                    const Key('match-start-date'),
                    ScheduleTexts.startDate,
                    _startDate == null ? null : ScheduleTexts.date(_startDate!),
                    () => _pickDate(start: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _pickerButton(
                    const Key('match-start-time'),
                    ScheduleTexts.startTime,
                    _startTime?.hhmm,
                    () => _pickTime(start: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _pickerButton(
                    const Key('match-end-date'),
                    ScheduleTexts.endDate,
                    _endDate == null ? null : ScheduleTexts.date(_endDate!),
                    () => _pickDate(start: false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _pickerButton(
                    const Key('match-end-time'),
                    ScheduleTexts.endTime,
                    _endTime?.hhmm,
                    () => _pickTime(start: false),
                  ),
                ),
              ],
            ),
            for (final e in visibleErrors.where((e) => e != MatchInputError.deadlineRange))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  ScheduleTexts.inputError(e),
                  key: Key('match-error-${e.name}'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            AppSpacing.sectionGap,
            VenueField(
              value: _venue,
              places: widget.services.places,
              label: ScheduleTexts.venueLabel,
              onChanged: (v) => setState(() => _venue = v),
            ),
            AppSpacing.sectionGap,
            TextField(
              key: const Key('match-deadline'),
              controller: _deadline,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              decoration: InputDecoration(
                labelText: ScheduleTexts.deadlineLabel,
                errorText: errors.contains(MatchInputError.deadlineRange)
                    ? ScheduleTexts.inputError(MatchInputError.deadlineRange)
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            AppSpacing.fieldGap,
            DropdownButtonFormField<int?>(
              key: const Key('match-reminder'),
              initialValue: _reminderHours,
              decoration: const InputDecoration(labelText: ScheduleTexts.reminderLabel),
              items: [
                for (final h in [...MatchSettings.reminderHourOptions, null])
                  DropdownMenuItem<int?>(value: h, child: Text(ScheduleTexts.reminderOption(h))),
              ],
              onChanged: (v) => setState(() => _reminderHours = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(ScheduleTexts.settingsDefaultNote, style: theme.textTheme.bodySmall),
            Text(ScheduleTexts.pastDeadlineNote, style: theme.textTheme.bodySmall),
            Text(ScheduleTexts.capacityNote, style: theme.textTheme.bodySmall),
            AppSpacing.sectionGap,
            if (_error != null) ErrorText(_error!),
            PrimaryButton(
              key: const Key('match-save'),
              label: ScheduleTexts.create,
              busy: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
