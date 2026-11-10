import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/domain/team_models.dart';
import '../domain/attendance_models.dart';
import '../domain/match_models.dart';
import '../domain/past_matches.dart';
import '../domain/schedule_list.dart';
import 'match_create_screen.dart';
import 'match_detail_screen.dart';
import 'schedule_texts.dart';

/// 일정 탭 (스프린트 04 5단계, 기획서 11장, S4-13).
///
/// - 기본은 목록. "다가오는 경기 / 지난 경기" 두 칸을 바꿔 본다.
///   - 다가오는 경기: 아직 끝나지 않은 일정, 시작 순. 취소된 일정은 "취소됨".
///   - 지난 경기: 최근 10경기 + 그 사이 취소된 일정, 최근 순 ([PastMatches], decisions 2026-11-09).
///   - 한 줄: "11/18(수) 10:00~12:00 · 성수 풋살장 · 참석 9/12 · 나: 참석" (취소된 일정은 숫자 대신 "취소됨").
/// - 달력 보기: 한 달에 경기 있는 날 점(취소된 일정은 회색 점), 날짜를 누르면 아래에 그날 경기.
///   최근 10경기보다 이전 달은 지워졌으므로 비어 보인다.
/// - 누르면 일정 상세(참석 투표·배치·POM 투표·결과). 일정 추가 버튼은 팀장·운영진에게만 (Entitlements: TeamAction.manageSchedule).
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

enum _View { list, calendar }

enum _Range { upcoming, past }

class _ScheduleTabState extends State<ScheduleTab> {
  List<TeamMatch>? _upcoming;
  List<TeamMatch> _past = const [];
  Map<String, List<AttendanceResponse>> _responses = const {};
  bool _failed = false;

  _View _view = _View.list;
  _Range _range = _Range.upcoming;

  /// 달력에서 고른 날·보고 있는 달 (table_calendar 날짜, UTC 자정, 한국 날짜 값)
  late DateTime _selectedDay = _today;
  late DateTime _focusedDay = _today;

  DateTime get _today {
    final d = Kst.dateOf(widget.now());
    return DateTime.utc(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final now = widget.now();
      final upcoming = await widget.services.matches.listMatches(widget.team.id, from: now);
      final past = PastMatches.recent(await widget.services.matches.listPastMatches(widget.team.id, before: now));
      final responses = await widget.services.attendance.listResponsesFor([
        for (final m in [...upcoming, ...past])
          if (!m.isCancelled) m.id,
      ]);
      if (mounted) {
        setState(() {
          _upcoming = upcoming;
          _past = past;
          _responses = responses;
        });
      }
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  ScheduleRow _row(TeamMatch m) => ScheduleRow.of(m, _responses[m.id] ?? const [], widget.viewer.userId);

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

  List<Widget> _rows(List<TeamMatch> matches, String keyPrefix) => [
    for (final m in matches) ...[
      ScheduleRowCard(row: _row(m), keyPrefix: keyPrefix, onTap: () => _openDetail(m)),
      const SizedBox(height: AppSpacing.sm),
    ],
  ];

  List<Widget> _listBody(List<TeamMatch> upcoming) {
    final past = _range == _Range.past;
    final matches = past ? _past : upcoming;
    return [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<_Range>(
          key: const Key('schedule-range'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _Range.upcoming,
              label: Text(ScheduleTexts.upcoming, key: Key('schedule-range-upcoming')),
            ),
            ButtonSegment(
              value: _Range.past,
              label: Text(ScheduleTexts.pastMatches, key: Key('schedule-range-past')),
            ),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (matches.isEmpty)
        EmptyState(
          icon: past ? Icons.history : Icons.event_outlined,
          message: past ? ScheduleTexts.noPastMatches : ScheduleTexts.noUpcoming,
          compact: true,
        )
      else
        ..._rows(matches, past ? 'past-match' : 'match'),
    ];
  }

  List<Widget> _calendarBody(List<TeamMatch> upcoming) {
    final byDate = ScheduleCalendar.byDate([...upcoming, ..._past]);
    List<TeamMatch> on(DateTime day) => byDate[ScheduleCalendar.dayOf(day)] ?? const [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = _today;
    final selected = on(_selectedDay);
    return [
      Card(
        key: const Key('schedule-calendar'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TableCalendar<TeamMatch>(
            firstDay: DateTime.utc(today.year - 1, 1, 1),
            lastDay: DateTime.utc(today.year + 2, 12, 31),
            focusedDay: _focusedDay,
            currentDay: today,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            eventLoader: on,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            availableCalendarFormats: const {CalendarFormat.month: ''},
            availableGestures: AvailableGestures.horizontalSwipe,
            rowHeight: 44,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: theme.textTheme.titleMedium ?? const TextStyle(),
              titleTextFormatter: (d, _) => ScheduleTexts.monthTitle(d.year, d.month),
              leftChevronIcon: Icon(Icons.chevron_left, color: scheme.onSurface),
              rightChevronIcon: Icon(Icons.chevron_right, color: scheme.onSurface),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (d, _) => ScheduleTexts.calendarWeekday(d.weekday),
              weekdayStyle: theme.textTheme.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
              weekendStyle: theme.textTheme.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              markersMaxCount: ScheduleCalendar.maxDots,
              defaultTextStyle: TextStyle(color: scheme.onSurface),
              weekendTextStyle: TextStyle(color: scheme.onSurface),
              todayDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.primary),
              ),
              todayTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
              selectedDecoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600),
            ),
            calendarBuilders: CalendarBuilders<TeamMatch>(
              singleMarkerBuilder: (context, day, m) => Container(
                key: Key('calendar-dot-${m.id}'),
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 취소된 일정은 회색 점 (S4-13 (3))
                  color: m.isCancelled ? scheme.outline : scheme.primary,
                ),
              ),
            ),
            onDaySelected: (selectedDay, focusedDay) => setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            }),
            onPageChanged: (focusedDay) => _focusedDay = focusedDay,
          ),
        ),
      ),
      AppSpacing.sectionGap,
      SectionHeader(ScheduleTexts.date(ScheduleCalendar.dayOf(_selectedDay))),
      if (selected.isEmpty)
        const EmptyState(icon: Icons.event_outlined, message: ScheduleTexts.noMatchOnDay, compact: true)
      else
        ..._rows(selected, 'day-match'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.services.entitlements.canPerform(widget.viewer, TeamAction.manageSchedule);
    final upcoming = _upcoming;
    if (_failed && upcoming == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: ScheduleTexts.loadFailed,
        actions: [TextButton(onPressed: _load, child: const Text(ScheduleTexts.retry))],
      );
    }
    if (upcoming == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppSpacing.page,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              SegmentedButton<_View>(
                key: const Key('schedule-view'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _View.list,
                    icon: Icon(Icons.view_list_outlined),
                    label: Text(ScheduleTexts.listView, key: Key('schedule-view-list')),
                  ),
                  ButtonSegment(
                    value: _View.calendar,
                    icon: Icon(Icons.calendar_month_outlined),
                    label: Text(ScheduleTexts.calendarView, key: Key('schedule-view-calendar')),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              const Spacer(),
              if (canManage)
                TextButton.icon(
                  key: const Key('schedule-add'),
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add),
                  label: const Text(ScheduleTexts.addMatch),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...switch (_view) {
            _View.list => _listBody(upcoming),
            _View.calendar => _calendarBody(upcoming),
          },
        ],
      ),
    );
  }
}

/// 일정 한 줄 카드 (목록·달력 아래 공통).
/// 위: "11/18(수) 10:00~12:00", 아래: "성수 풋살장 · 참석 9/12 · 나: 참석" (취소된 일정은 장소만 + 오른쪽 "취소됨").
class ScheduleRowCard extends StatelessWidget {
  const ScheduleRowCard({required this.row, required this.onTap, this.keyPrefix = 'match', super.key});

  final ScheduleRow row;
  final String keyPrefix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = row.match;
    final cancelled = m.isCancelled;
    final muted = scheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        key: Key('$keyPrefix-${m.id}'),
        onTap: onTap,
        leading: Icon(
          cancelled ? Icons.event_busy_outlined : Icons.event_outlined,
          color: cancelled ? muted : scheme.primary,
        ),
        title: Text(
          ScheduleTexts.rowTime(m),
          style: cancelled ? TextStyle(color: muted, decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text(
          [
            m.venue?.name ?? ScheduleTexts.venueNone,
            // 취소된 일정은 오른쪽 "취소됨" 표시만 (숫자 없음)
            if (!cancelled) ...[
              ScheduleTexts.rowAttending(row.attendingCount, m.capacity),
              ScheduleTexts.rowMine(row.myState, row.myWaitPosition),
            ],
          ].join(' · '),
          key: Key('$keyPrefix-line-${m.id}'),
        ),
        trailing: cancelled
            ? _Tag(ScheduleTexts.cancelled, color: scheme.error)
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
