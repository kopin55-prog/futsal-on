import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/team_texts.dart';
import '../data/team_admin_repository.dart';
import '../domain/match_settings.dart';
import 'admin_texts.dart';

/// 경기 설정 (팀장·운영진, data-model.md 3-2): 정원 없음 / 정원(넘으면 대기 순번),
/// 참석 투표 마감(경기 몇 시간 전), 일정 자동 생성 시점(며칠 전·시각).
/// 마감이 자동 생성보다 앞서면 저장 버튼 대신 안내를 보여준다 (서버도 다시 거절).
/// 저장하면 true 로 닫힌다.
class MatchSettingsScreen extends StatefulWidget {
  const MatchSettingsScreen({required this.admin, required this.team, super.key});

  final TeamAdminRepository admin;
  final TeamSummary team;

  @override
  State<MatchSettingsScreen> createState() => _MatchSettingsScreenState();
}

class _MatchSettingsScreenState extends State<MatchSettingsScreen> {
  final _capacity = TextEditingController();
  final _deadline = TextEditingController();
  final _days = TextEditingController();
  bool _hasCapacity = false;
  ClockTime _autoTime = MatchSettings.defaults.autoCreateTime;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _capacity.dispose();
    _deadline.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.admin.getMatchSettings(widget.team.id);
      if (!mounted) return;
      setState(() {
        _hasCapacity = s.hasCapacity;
        _capacity.text = s.capacity?.toString() ?? '';
        _deadline.text = '${s.rsvpDeadlineHours}';
        _days.text = '${s.autoCreateDaysBefore}';
        _autoTime = s.autoCreateTime;
        _loaded = true;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    }
  }

  /// 입력값. 숫자가 아니면 -1 로 두어 범위 오류로 보인다.
  MatchSettings get _input => MatchSettings(
    capacity: _hasCapacity ? (int.tryParse(_capacity.text) ?? -1) : null,
    rsvpDeadlineHours: int.tryParse(_deadline.text) ?? -1,
    autoCreateDaysBefore: int.tryParse(_days.text) ?? -1,
    autoCreateTime: _autoTime,
  );

  Set<MatchSettingsError> get _errors =>
      MatchSettingsValidator.validate(_input, regularStart: widget.team.schedule.start);

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _autoTime.hour, minute: _autoTime.minute),
    );
    if (picked != null) setState(() => _autoTime = ClockTime(picked.hour, picked.minute));
  }

  Future<void> _save() async {
    if (_errors.isNotEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.admin.updateMatchSettings(widget.team.id, _input);
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AdminTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numberField(Key key, TextEditingController c, String label, {bool enabled = true}) =>
      TextField(
        key: key,
        controller: c,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text(AdminTexts.matchSettings)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text(TeamTexts.retry)),
                  ],
                ),
        ),
      );
    }
    final errors = _errors;
    return Scaffold(
      appBar: AppBar(title: const Text(AdminTexts.matchSettings)),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.page,
          children: [
            // ---- 정원
            const SectionHeader(AdminTexts.capacitySection),
            RadioGroup<bool>(
              groupValue: _hasCapacity,
              onChanged: (v) => setState(() => _hasCapacity = v ?? false),
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    key: Key('settings-no-capacity'),
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(AdminTexts.noCapacity),
                  ),
                  RadioListTile<bool>(
                    key: Key('settings-has-capacity'),
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text(AdminTexts.setCapacity),
                    subtitle: Text(AdminTexts.capacityNote),
                  ),
                ],
              ),
            ),
            if (_hasCapacity)
              _numberField(const Key('settings-capacity'), _capacity, AdminTexts.capacityLabel),
            AppSpacing.sectionGap,
            // ---- 참석 투표 마감
            _numberField(const Key('settings-deadline'), _deadline, AdminTexts.deadlineLabel),
            AppSpacing.sectionGap,
            // ---- 일정 자동 생성
            const SectionHeader(AdminTexts.autoCreateSection),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    const Key('settings-auto-days'),
                    _days,
                    AdminTexts.autoCreateDaysLabel,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  key: const Key('settings-auto-time'),
                  onPressed: _pickTime,
                  child: Text(AdminTexts.autoCreateTimeButton(_autoTime.hhmm)),
                ),
              ],
            ),
            AppSpacing.fieldGap,
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  AdminTexts.settingsError(e),
                  key: Key('settings-error-${e.name}'),
                  style: TextStyle(color: errorColor),
                ),
              ),
            Text(AdminTexts.settingsKeepNote, style: theme.textTheme.bodySmall),
            AppSpacing.fieldGap,
            if (_error != null) ...[
              Text(_error!, key: const Key('settings-server-error'), style: TextStyle(color: errorColor)),
              const SizedBox(height: AppSpacing.md),
            ],
            FilledButton(
              key: const Key('settings-save'),
              onPressed: _saving || errors.isNotEmpty ? null : _save,
              child: const Text(AdminTexts.save),
            ),
          ],
        ),
      ),
    );
  }
}
