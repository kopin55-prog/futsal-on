import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/team_texts.dart';
import '../data/award_repository.dart';
import '../domain/award_models.dart';
import 'award_texts.dart';

/// 투표 설정 (팀장·운영진, Q-076 1번): POM·오늘의 골 발표 시각 하나.
///
/// 경기 설정과 따로 둔다. 발표 시각 = 투표 마감 시각 = 경기 종료일 다음날의 이 시각(한국 시간).
/// 새벽 포함 자유롭게 고른다(분 단위). 투표가 열릴 때 그때 설정으로 마감이 정해지므로 이미 열린 투표는 그대로.
/// 메뉴 노출은 Entitlements(TeamAction.editAwardSettings)로 판단하고 서버(update_award_settings)가 다시 거절한다.
/// 저장하면 true 로 닫힌다.
class AwardSettingsScreen extends StatefulWidget {
  const AwardSettingsScreen({required this.awards, required this.team, super.key});

  final AwardRepository awards;
  final TeamSummary team;

  @override
  State<AwardSettingsScreen> createState() => _AwardSettingsScreenState();
}

class _AwardSettingsScreenState extends State<AwardSettingsScreen> {
  ClockTime _time = AwardSettings.defaultAnnounceTime;
  ClockTime? _loadedTime;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.awards.getAnnounceTime(widget.team.id);
      if (!mounted) return;
      setState(() {
        _time = t;
        _loadedTime = t;
        _error = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AwardTexts.serverError(e.code));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time.hour, minute: _time.minute),
    );
    if (picked != null) setState(() => _time = ClockTime(picked.hour, picked.minute));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.awards.updateAnnounceTime(widget.team.id, _time);
      if (mounted) Navigator.of(context).pop(true);
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = AwardTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = _loadedTime != null;
    return Scaffold(
      appBar: AppBar(title: const Text(AwardTexts.awardSettings)),
      body: SafeArea(
        child: !loaded
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(onPressed: _load, child: const Text(TeamTexts.retry)),
                        ],
                      ),
              )
            : ListView(
                padding: AppSpacing.page,
                children: [
                  const SectionHeader(AwardTexts.announceLabel),
                  OutlinedButton(
                    key: const Key('award-announce-time'),
                    onPressed: _saving ? null : _pickTime,
                    child: Text(AwardTexts.announceButton(_time.hhmm)),
                  ),
                  AppSpacing.fieldGap,
                  Text(AwardTexts.announceNote, style: theme.textTheme.bodySmall),
                  Text(AwardTexts.keepNote, style: theme.textTheme.bodySmall),
                  AppSpacing.fieldGap,
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const Key('award-settings-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  FilledButton(
                    key: const Key('award-settings-save'),
                    onPressed: _saving ? null : _save,
                    child: const Text(AwardTexts.save),
                  ),
                ],
              ),
      ),
    );
  }
}
