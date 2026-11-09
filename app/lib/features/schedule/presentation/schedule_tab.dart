import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/domain/team_models.dart';
import '../domain/match_models.dart';
import 'match_create_screen.dart';
import 'match_detail_screen.dart';
import 'schedule_texts.dart';

/// 일정 탭 (임시, 스프린트 02 4-1). 다가오는 일정(아직 끝나지 않은 일정)을 시작 순으로, 취소된 일정도 "취소됨"으로 보여준다.
/// 일정 추가 버튼은 팀장·운영진에게만 (Entitlements: TeamAction.manageSchedule). 정식 화면은 스프린트 04.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({
    required this.services,
    required this.team,
    required this.viewer,
    this.now = DateTime.now,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;

  /// 현재 시각 (테스트에서 바꿔 끼운다). 최종 판단은 서버 시각.
  final DateTime Function() now;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  List<TeamMatch>? _matches;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final list = await widget.services.matches.listMatches(widget.team.id, from: widget.now());
      if (mounted) setState(() => _matches = list);
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _openDetail(TeamMatch m) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(
          services: widget.services,
          team: widget.team,
          viewer: widget.viewer,
          matchId: m.id,
          initial: m,
          now: widget.now,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MatchCreateScreen(services: widget.services, team: widget.team, now: widget.now),
      ),
    );
    if (created == null) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(ScheduleTexts.created)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.services.entitlements.canPerform(widget.viewer, TeamAction.manageSchedule);
    final matches = _matches;
    if (_failed && matches == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: ScheduleTexts.loadFailed,
        actions: [TextButton(onPressed: _load, child: const Text(ScheduleTexts.retry))],
      );
    }
    if (matches == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppSpacing.page,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SectionHeader(
            ScheduleTexts.upcoming,
            trailing: canManage
                ? TextButton.icon(
                    key: const Key('schedule-add'),
                    onPressed: _openCreate,
                    icon: const Icon(Icons.add),
                    label: const Text(ScheduleTexts.addMatch),
                  )
                : null,
          ),
          if (matches.isEmpty)
            const EmptyState(icon: Icons.event_outlined, message: ScheduleTexts.noUpcoming, compact: true)
          else
            for (final m in matches) ...[
              _MatchCard(match: m, onTap: () => _openDetail(m)),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onTap});

  final TeamMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final cancelled = match.isCancelled;
    return Card(
      child: ListTile(
        key: Key('match-${match.id}'),
        onTap: onTap,
        leading: Icon(cancelled ? Icons.event_busy_outlined : Icons.event_outlined),
        title: Text(
          ScheduleTexts.matchTime(match),
          style: cancelled ? TextStyle(color: muted, decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text(
          [
            match.venue?.name ?? ScheduleTexts.venueNone,
            if (cancelled) ScheduleTexts.cancelled else ScheduleTexts.capacity(match.capacity),
          ].join(' · '),
        ),
        trailing: cancelled
            ? _Tag(ScheduleTexts.cancelled, color: theme.colorScheme.error)
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(AppSpacing.xs),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
  );
}
