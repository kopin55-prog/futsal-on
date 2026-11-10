import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../injury/presentation/injury_flows.dart';
import '../../lineup/domain/lineup_board.dart';
import '../../lineup/domain/lineup_models.dart';
import '../../lineup/presentation/lineup_blocks.dart';
import '../../lineup/presentation/lineup_editor_screen.dart';
import '../../lineup/presentation/lineup_texts.dart';
import '../../pom_vote/domain/award_models.dart';
import '../../schedule/domain/attendance_models.dart';
import '../../schedule/domain/match_models.dart';
import '../../schedule/presentation/match_create_screen.dart';
import '../../schedule/presentation/match_detail_screen.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../../team/domain/team_models.dart';
import '../data/dashboard_loader.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_texts.dart';

/// 홈 = 팀 대시보드 (스프린트 04 4단계, 기획서 11장, kopn 2026-11-10).
///
/// 정보는 카드·상자로 보여주고 **카드를 누르면 바로 해당 화면으로** 간다.
/// - 헤더: 팀원 수 (4-2). 팀 로고·이름은 위쪽 바에만 (중복 정리, 6-3). 누르면 팀원 탭
/// - 처리할 일 (팀장·운영진만, S4-05): 가입 신청 대기 → 관리 탭, 팀 나누기 대기 → 그 경기 배치 화면
/// - 다음 경기 (S4-02): 누르면 일정 상세. 카드에서 바로 참석·불참 (부상 중이면 복귀 확인 창, 2-5).
///   배치가 확정되면 내 팀 블록(조끼 색 + 이름 가나다순, 게스트 상자)을 크게. 실력·포지션 없음.
/// - 지난 경기 POM·오늘의 골 (S4-03): 누르면 그 경기 결과·투표 화면(일정 상세의 투표 부분)
/// - 부상자 (S4-04): 누르면 팀원 탭. 없으면 칸 숨김
/// 권한(무엇을 보일지)은 Entitlements 에서만 판단한다. 2차 리포트·득표수는 홈에 없다.
class DashboardTab extends StatefulWidget {
  const DashboardTab({
    required this.services,
    required this.team,
    required this.viewer,
    required this.onOpenMembers,
    required this.onOpenAdmin,
    this.onLoaded,
    this.now = DateTime.now,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;

  /// 부상자 카드 → 팀원 탭
  final VoidCallback onOpenMembers;

  /// 처리할 일 "가입 신청" → 관리 탭
  final VoidCallback onOpenAdmin;

  /// 다 읽은 뒤 (관리 탭 아이콘의 가입 신청 숫자를 맞춘다)
  final void Function(DashboardData data)? onLoaded;
  final DateTime Function() now;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DashboardData? _data;
  bool _failed = false;
  bool _busy = false;

  AppServices get _s => widget.services;
  Entitlements get _e => _s.entitlements;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final data = await loadDashboard(services: _s, team: widget.team, viewer: widget.viewer, now: widget.now());
      if (!mounted) return;
      setState(() => _data = data);
      widget.onLoaded?.call(data);
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openMatch(TeamMatch m) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchDetailScreen(
          services: _s,
          team: widget.team,
          viewer: widget.viewer,
          matchId: m.id,
          initial: m,
          now: widget.now,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openLineup(TeamMatch m) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LineupEditorScreen(
          services: _s,
          team: widget.team,
          viewer: widget.viewer,
          match: m,
          now: widget.now,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _addMatch() async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => MatchCreateScreen(services: _s, team: widget.team, now: widget.now)),
    );
    if (created != null && mounted) await _load();
  }

  Future<void> _respond(TeamMatch m, bool attending) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 부상 중 참석이면 "부상에서 복귀하셨나요?" 확인 창 (취소하면 응답 그대로, 2-5)
      await respondWithReturnConfirm(context, _s.attendance, m.id, attending: attending);
    } on ServerFailure catch (e) {
      if (mounted) _toast(DashboardTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_failed) {
        return Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            message: DashboardTexts.loadFailed,
            actions: [TextButton(onPressed: _load, child: const Text(DashboardTexts.retry))],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final now = widget.now();
    final todos = data.todos;
    final last = data.lastAward;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('dashboard'),
        padding: AppSpacing.page,
        children: [
          _Header(memberCount: data.memberCount, onTap: widget.onOpenMembers),
          const SizedBox(height: AppSpacing.md),
          if (todos != null && !todos.isEmpty) ...[
            _TodoCard(todos: todos, onOpenJoin: widget.onOpenAdmin, onOpenLineup: _openLineup),
            const SizedBox(height: AppSpacing.md),
          ],
          if (data.next case final next?)
            _NextMatchCard(
              next: next,
              me: widget.viewer.userId,
              memberNames: data.memberNames,
              now: now,
              busy: _busy,
              onOpen: () => _openMatch(next.match),
              onRespond: (attending) => _respond(next.match, attending),
            )
          else
            _NoNextCard(
              canAdd: _e.canPerform(widget.viewer, TeamAction.manageSchedule),
              onAdd: _addMatch,
            ),
          if (last != null) ...[
            const SizedBox(height: AppSpacing.md),
            _LastAwardCard(
              view: last,
              me: widget.viewer.userId,
              memberNames: data.memberNames,
              entitlements: _e,
              viewer: widget.viewer,
              now: now,
              onOpen: () => _openMatch(last.match),
            ),
          ],
          if (data.injured.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _InjuredCard(injured: data.injured, onOpen: widget.onOpenMembers),
          ],
        ],
      ),
    );
  }
}

/// 누를 수 있는 카드 틀 (카드 전체가 눌림, 오른쪽 위 화살표).
class _TapCard extends StatelessWidget {
  const _TapCard({required this.child, required this.onTap, super.key});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: child),
      ),
    );
  }
}

/// 카드 제목 줄 (제목 + 오른쪽 덧붙임 + 화살표)
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ),
        ?trailing,
        Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}

/// 홈 머리: 팀원 수 (누르면 팀원 탭). 팀 로고·이름은 위쪽 바(팀 전환 버튼)에 이미 있어 여기서는 다시 보이지 않는다 (6-3).
class _Header extends StatelessWidget {
  const _Header({required this.memberCount, required this.onTap});

  final int memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: const Key('dash-header'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.groups_outlined, size: 20, color: muted),
            const SizedBox(width: AppSpacing.sm),
            Text(
              DashboardTexts.memberCount(memberCount),
              key: const Key('dash-member-count'),
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.todos, required this.onOpenJoin, required this.onOpenLineup});

  final DashboardTodos todos;
  final VoidCallback onOpenJoin;
  final void Function(TeamMatch) onOpenLineup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('dash-todos'),
      color: theme.colorScheme.secondaryContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Text(
              DashboardTexts.todoTitle,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          if (todos.pendingJoinRequests > 0)
            ListTile(
              key: const Key('dash-todo-join'),
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: Text(DashboardTexts.joinRequests(todos.pendingJoinRequests)),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenJoin,
            ),
          for (final m in todos.lineupPending)
            ListTile(
              key: Key('dash-todo-lineup-${m.id}'),
              leading: const Icon(Icons.groups_2_outlined),
              title: Text(DashboardTexts.lineupPending(ScheduleTexts.dateTime(m.startsAt))),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenLineup(m),
            ),
        ],
      ),
    );
  }
}

class _NoNextCard extends StatelessWidget {
  const _NoNextCard({required this.canAdd, required this.onAdd});

  final bool canAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('dash-next-none'),
      child: EmptyState(
        icon: Icons.event_available_outlined,
        message: DashboardTexts.noNext,
        compact: true,
        actions: [
          if (canAdd)
            FilledButton(key: const Key('dash-add-match'), onPressed: onAdd, child: const Text(DashboardTexts.addMatch)),
        ],
      ),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({
    required this.next,
    required this.me,
    required this.memberNames,
    required this.now,
    required this.busy,
    required this.onOpen,
    required this.onRespond,
  });

  final NextMatchView next;
  final String me;
  final Map<String, String> memberNames;
  final DateTime now;
  final bool busy;
  final VoidCallback onOpen;
  final void Function(bool attending) onRespond;

  String _nameOf(LineupPerson p) {
    if (p.isGuest) {
      return next.guests.where((g) => g.id == p.guestId).firstOrNull?.displayName ?? ScheduleTexts.guest;
    }
    return memberNames[p.userId] ?? ScheduleTexts.leftMember;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = next.match;
    final myResponse = next.roster.responseOf(me);
    final myState = myResponse?.state;
    final statusText = next.myInjured
        ? DashboardTexts.injured
        : ScheduleTexts.state(myState, next.roster.waitlistPosition(me));
    final lineup = next.lineup;
    return _TapCard(
      key: const Key('dash-next'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            DashboardTexts.nextTitle,
            trailing: DashboardRules.isInProgress(m, now)
                ? const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.xs),
                    child: Chip(
                      key: Key('dash-in-progress'),
                      label: Text(DashboardTexts.inProgress),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(ScheduleTexts.matchTime(m), style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            m.venue?.name ?? ScheduleTexts.venueNone,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('${DashboardTexts.myStatus}  ', style: theme.textTheme.bodyMedium),
              Text(statusText, key: const Key('dash-my-status'), style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            DashboardTexts.counts(
              attending: next.attendingCount,
              capacity: m.capacity,
              waitlist: next.waitlistCount,
              notResponded: next.notRespondedCount,
            ),
            key: const Key('dash-counts'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (m.isRsvpOpenAt(now))
            Row(
              children: [
                Expanded(child: _choice(key: 'dash-attend', label: DashboardTexts.attend, selected: myState == AttendanceState.attending || myState == AttendanceState.waitlisted, onPressed: () => onRespond(true))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _choice(key: 'dash-decline', label: DashboardTexts.decline, selected: myState == AttendanceState.declined, onPressed: () => onRespond(false))),
              ],
            )
          else
            Text(
              DashboardTexts.deadlinePassed,
              key: const Key('dash-deadline-passed'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (lineup != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _mySlot(context, lineup),
          ],
        ],
      ),
    );
  }

  Widget _choice({required String key, required String label, required bool selected, required VoidCallback onPressed}) {
    final onTap = busy ? null : onPressed;
    return selected
        ? FilledButton(key: Key(key), onPressed: onTap, child: Text(label))
        : OutlinedButton(key: Key(key), onPressed: onTap, child: Text(label));
  }

  Widget _mySlot(BuildContext context, Lineup lineup) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(LineupPerson p, Color? fg) => LineupNameChip(
      key: Key('dash-lineup-person-${p.key}'),
      name: _nameOf(p),
      isGuest: p.isGuest,
      highlight: p.userId == me,
      foreground: fg,
    );
    switch (DashboardRules.mySlot(lineup, me)) {
      case MySquadSlot(:final squad):
        final fg = bibColorStyle(squad.bibColor, scheme).foreground;
        return SquadBlockFrame(
          key: const Key('dash-my-squad'),
          color: squad.bibColor,
          title: '${DashboardTexts.myTeam} · ${LineupTexts.squadTitle(squad.bibColor, squad.people.length)}',
          children: [for (final p in sortByName(squad.people, _nameOf)) chip(p, fg)],
        );
      case MyBenchSlot(:final bench):
        return SquadBlockFrame(
          key: const Key('dash-my-bench'),
          title: LineupTexts.benchTitle(bench.length),
          children: [for (final p in sortByName(bench, _nameOf)) chip(p, null)],
        );
      case NotInLineup():
        return Row(
          key: const Key('dash-not-in-lineup'),
          children: [
            Expanded(child: Text(DashboardTexts.notInLineup, style: Theme.of(context).textTheme.bodyMedium)),
            TextButton(key: const Key('dash-view-lineup'), onPressed: onOpen, child: const Text(DashboardTexts.viewLineup)),
          ],
        );
    }
  }
}

class _LastAwardCard extends StatelessWidget {
  const _LastAwardCard({
    required this.view,
    required this.me,
    required this.memberNames,
    required this.entitlements,
    required this.viewer,
    required this.now,
    required this.onOpen,
  });

  final LastAwardView view;
  final String me;
  final Map<String, String> memberNames;
  final Entitlements entitlements;
  final Viewer viewer;
  final DateTime now;
  final VoidCallback onOpen;

  /// 1위 이름: 지금 팀원은 가나다순, 떠난 1위는 뒤에 빈칸 자리 (Q-058 5번). 회원 탈퇴한 1위는 서버에서 이미 빠져 있다 (Q-038).
  List<String> _winnerNames(AwardCategory c) {
    final all = view.poll.winnersOf(c);
    final current = [for (final id in all) if (memberNames.containsKey(id)) memberNames[id]!]..sort();
    final left = all.where((id) => !memberNames.containsKey(id)).length;
    return [...current, for (var i = 0; i < left; i++) DashboardTexts.leftMember];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poll = view.poll;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final isMember = memberNames.containsKey(me);
    final canVoteAny = AwardCategory.values.any((c) => poll.canVote(me, c, isCurrentMember: isMember, now: now));
    final List<Widget> body;
    if (poll.isOpenAt(now)) {
      body = [
        Text(DashboardTexts.voting(poll.closesAt), key: const Key('dash-award-voting'), style: theme.textTheme.bodyMedium),
        if (canVoteAny) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(key: const Key('dash-award-vote'), onPressed: onOpen, child: const Text(DashboardTexts.vote)),
          ),
        ] else if (poll.isParticipant(me)) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(DashboardTexts.voted, style: muted),
        ],
      ];
    } else if (poll.status != AwardPollStatus.closed) {
      body = [Text(DashboardTexts.closedPending, style: muted)];
    } else {
      body = [
        for (final c in AwardCategory.values)
          if (entitlements.voteResultMaxRank(viewer, c.voteCategory) >= 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      c == AwardCategory.pom ? DashboardTexts.pom : DashboardTexts.goalOfTheDay,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final names = _winnerNames(c);
                        return Text(
                          names.isEmpty ? DashboardTexts.noResult : names.join(', '),
                          key: Key('dash-award-${c.code}'),
                          style: names.isEmpty ? muted : theme.textTheme.bodyLarge,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      ];
    }
    return _TapCard(
      key: const Key('dash-award'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(DashboardTexts.lastTitle),
          const SizedBox(height: 2),
          Text(ScheduleTexts.dateTime(view.match.startsAt), style: muted),
          const SizedBox(height: AppSpacing.sm),
          ...body,
        ],
      ),
    );
  }
}

class _InjuredCard extends StatelessWidget {
  const _InjuredCard({required this.injured, required this.onOpen});

  final List<InjuredMember> injured;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return _TapCard(
      key: const Key('dash-injured'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(DashboardTexts.injuredTitle(injured.length)),
          const SizedBox(height: AppSpacing.xs),
          for (final i in injured)
            Padding(
              key: Key('dash-injured-${i.member.userId}'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Flexible(child: Text(i.member.displayName, style: theme.textTheme.bodyLarge, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(DashboardTexts.weeks(i.remainingWeeks), style: theme.textTheme.titleSmall),
                  if (i.injury.memo case final memo?) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(memo, style: muted, overflow: TextOverflow.ellipsis)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
