import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/presentation/team_logo.dart';
import '../data/record_repository.dart';
import '../domain/my_records.dart';
import 'records_texts.dart';

/// 내 기록 (스프린트 04 3-2, 기획서 10장, S4-12).
///
/// - 위에 시즌 버튼: 누적(기본) + 기록이 있는 연도만.
/// - 전체 합산 카드: POM·오늘의 골·출석 횟수 + 참석 투표 참여율(소수점 없이 반올림, 대상 0회면 "기록 없음").
/// - 팀별 카드: 지금 팀 먼저, 떠난 팀 "(떠난 팀)", 해체된 팀 "(해체된 팀)". 모든 팀 기록을 보여준다(지금 연 팀과 무관).
/// - 득표수 없음. 본인만 (Entitlements PersonalRecordInfo).
class MyRecordsSection extends StatefulWidget {
  const MyRecordsSection({
    required this.records,
    required this.entitlements,
    required this.viewer,
    super.key,
  });

  final RecordRepository records;
  final Entitlements entitlements;
  final Viewer viewer;

  @override
  State<MyRecordsSection> createState() => _MyRecordsSectionState();
}

class _MyRecordsSectionState extends State<MyRecordsSection> {
  MyRecords? _data;
  String? _error;

  /// null = 누적
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await widget.records.getMyRecords();
      if (!mounted) return;
      setState(() {
        _data = data;
        if (_season != null && !data.seasons.contains(_season)) _season = null;
      });
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _error = RecordsTexts.serverError(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.entitlements.canView(widget.viewer, PersonalRecordInfo(subjectUserId: widget.viewer.userId))) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final data = _data;
    return Column(
      key: const Key('my-records'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(RecordsTexts.sectionTitle),
        if (_error != null)
          Row(
            children: [
              Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              TextButton(onPressed: _load, child: const Text(RecordsTexts.retry)),
            ],
          )
        else if (data == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (data.isEmpty)
          const EmptyState(
            key: Key('my-records-empty'),
            icon: Icons.insights_outlined,
            message: RecordsTexts.empty,
            compact: true,
          )
        else ...[
          _seasonPicker(data),
          const SizedBox(height: AppSpacing.sm),
          _TotalsCard(
            key: const Key('records-total'),
            title: RecordsTexts.totalTitle,
            totals: data.total(season: _season),
          ),
          for (final t in data.byTeam(season: _season))
            _TotalsCard(
              key: Key('records-team-${t.teamId}'),
              title: t.teamName,
              logoText: t.logoText,
              suffix: t.isDissolved
                  ? RecordsTexts.dissolvedTeam
                  : (t.isMember ? null : RecordsTexts.leftTeam),
              totals: t.totals,
            ),
        ],
      ],
    );
  }

  Widget _seasonPicker(MyRecords data) {
    final options = <int?>[null, ...data.seasons];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                key: Key('records-season-${s ?? 'all'}'),
                label: Text(s == null ? RecordsTexts.allSeasons : RecordsTexts.seasonLabel(s)),
                selected: _season == s,
                onSelected: (_) => setState(() => _season = s),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.title, required this.totals, this.logoText, this.suffix, super.key});

  final String title;
  final String? logoText;
  final String? suffix;
  final RecordTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (logoText != null) ...[
                  TeamLogo(text: logoText!, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(suffix!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _Stat(label: RecordsTexts.pom, value: RecordsTexts.times(totals.pom)),
                _Stat(label: RecordsTexts.goalOfTheDay, value: RecordsTexts.times(totals.goalOfTheDay)),
                _Stat(label: RecordsTexts.attendance, value: RecordsTexts.times(totals.attendance)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: Text(RecordsTexts.participation, style: theme.textTheme.bodyMedium?.copyWith(color: muted))),
                Text(
                  RecordsTexts.percent(totals.participationPercent),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
