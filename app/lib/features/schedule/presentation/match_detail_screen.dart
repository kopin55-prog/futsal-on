import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../admin/presentation/admin_texts.dart';
import '../../lineup/domain/lineup_models.dart';
import '../../lineup/presentation/lineup_editor_screen.dart';
import '../../lineup/presentation/lineup_section.dart';
import '../../pom_vote/domain/award_models.dart';
import '../../pom_vote/presentation/award_section.dart';
import '../../pom_vote/presentation/award_texts.dart';
import '../../profile/presentation/profile_texts.dart';
import '../../share_image/domain/share_image_content.dart';
import '../../share_image/presentation/share_image_texts.dart';
import '../../share_image/presentation/share_images.dart';
import '../../team/domain/team_models.dart';
import '../domain/attendance_models.dart';
import '../domain/guest_models.dart';
import '../domain/match_models.dart';
import 'guest_add_sheet.dart';
import 'guest_badge.dart';
import 'schedule_texts.dart';

/// 일정 상세 (임시, 스프린트 02 4-1·4-2).
///
/// - 일시·장소·정원·마감, 내 상태(참석·대기 n번·불참·미투표), 참석/불참 버튼(마감·취소 후 잠김, 서버가 다시 거절).
/// - 명단 4개(참석·대기·불참·미투표)는 팀원 전체 공개 (Entitlements: AttendanceListInfo).
///   순서 (Q-073 7번): 참석·불참은 마지막으로 바꾼 시각 순, 대기는 순번, 미투표는 이름 가나다순.
/// - 게스트: 이름 뒤 "게스트" 상자. 포지션·대략 실력은 팀장·운영진만 (GuestPositionInfo).
/// - 운영진 버튼(일정 취소·게스트 추가·삭제)은 TeamAction.manageSchedule 일 때만.
/// - 취소된 일정은 "취소됨 + 사유" (Q-073 4번).
/// - 팀 배치 (스프린트 03 3-1·3-4): [LineupSection]. 운영진은 [LineupEditorScreen] 으로 팀 나누기.
/// - POM·오늘의 골 (스프린트 03 5-2·5-3): 투표가 열린 경기(경기 종료 뒤)만 [AwardSection].
class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    required this.services,
    required this.team,
    required this.viewer,
    required this.matchId,
    this.initial,
    this.now = DateTime.now,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;
  final String matchId;

  /// 목록에서 이미 읽은 일정 (먼저 보여주고 다시 읽는다)
  final TeamMatch? initial;

  final DateTime Function() now;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  TeamMatch? _match;
  AttendanceRoster? _roster;
  Map<String, String> _members = const {};
  List<MatchGuest> _guests = const [];
  Map<String, MatchGuestDetail> _guestDetails = const {};
  Lineup? _lineup;
  AwardPollView? _poll;
  bool _loading = true;
  bool _missing = false;
  bool _failed = false;
  bool _busy = false;

  AppServices get _s => widget.services;
  Entitlements get _e => _s.entitlements;
  bool get _canManage => _e.canPerform(widget.viewer, TeamAction.manageSchedule);
  bool get _canSeeGuestDetails => _e.canView(widget.viewer, const GuestPositionInfo());

  @override
  void initState() {
    super.initState();
    _match = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final match = await _s.matches.getMatch(widget.matchId);
      if (match == null) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final responses = await _s.attendance.listResponses(match.id);
      final members = await _s.teams.listMembers(match.teamId);
      final guests = await _s.guests.listGuests(match.id);
      final details = _canSeeGuestDetails ? await _s.guests.listGuestDetails(match.id) : const <MatchGuestDetail>[];
      final lineup = await _s.lineups.getLineup(match.id);
      // 투표는 경기 종료 처리 때 열린다 (취소된 일정·끝나지 않은 일정은 없음)
      final poll = !match.isCancelled && !widget.now().isBefore(match.endsAt)
          ? await _s.awards.getPoll(match.id, myUserId: widget.viewer.userId)
          : null;
      if (!mounted) return;
      setState(() {
        _match = match;
        _roster = AttendanceRoster(responses);
        _members = {for (final m in members) m.userId: m.displayName};
        _guests = guests;
        _guestDetails = {for (final d in details) d.id: d};
        _lineup = lineup;
        _poll = poll;
        _missing = false;
      });
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _respond(bool attending) async {
    final m = _match;
    if (m == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _s.attendance.respond(m.id, attending: attending);
      await _load();
    } on ServerFailure catch (e) {
      if (mounted) _toast(ScheduleTexts.serverError(e.code));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final m = _match;
    if (m == null) return;
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelDialog());
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _s.matches.cancelMatch(m.id, reason: reason.trim().isEmpty ? null : reason);
      if (mounted) _toast(ScheduleTexts.cancelledDone);
    } on ServerFailure catch (e) {
      if (mounted) _toast(ScheduleTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _addGuest() async {
    final m = _match;
    if (m == null) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GuestAddSheet(guests: _s.guests, matchId: m.id, existing: _guests),
    );
    if (added == true) await _load();
  }

  Future<void> _openLineupEditor() async {
    final m = _match;
    if (m == null) return;
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

  /// 한 항목 투표. 누구를 찍었는지는 어디에도 남기지 않는다 (6-4).
  Future<void> _castVote(AwardCategory category, String candidateId) async {
    final m = _match;
    if (m == null) return;
    try {
      await _s.awards.castVote(m.id, category, candidateId);
      if (mounted) _toast(AwardTexts.votedDone);
    } on ServerFailure catch (e) {
      if (mounted) _toast(AwardTexts.serverError(e.code));
    }
    await _load();
  }

  /// 공유 이미지를 만들어 휴대폰 공유 창으로 (6-1·6-2). 실패하면 안내만.
  Future<void> _shareImage(Widget image, String fileName, Rect? origin) async {
    try {
      await _s.shareImages.share(
        context,
        image,
        fileName: fileName,
        logoImagePath: widget.team.logoImagePath,
        origin: origin,
      );
    } catch (_) {
      if (mounted) _toast(ShareImageTexts.failed);
    }
  }

  /// 확정된 배치 이미지 (6-1). 버튼은 확정 배치에서만 보인다 (Entitlements.canShareLineupImage).
  Future<void> _shareLineup(Rect? origin) async {
    final m = _match;
    final l = _lineup;
    if (m == null || l == null || !l.isConfirmed) return;
    await _shareImage(
      LineupShareImage(team: widget.team, match: m, lineup: l, nameOf: _lineupName),
      ShareImageTexts.lineupFileName,
      origin,
    );
  }

  /// POM·오늘의 골 결과 이미지 (6-2). 마감 뒤만. 팀을 떠난 1위는 뺀다 (S3-12).
  Future<void> _shareResult(Rect? origin) async {
    final m = _match;
    final poll = _poll;
    if (m == null || poll == null || poll.status != AwardPollStatus.closed) return;
    await _shareImage(
      AwardResultShareImage(
        team: widget.team,
        match: m,
        winners: {
          for (final c in AwardCategory.values)
            if (_e.voteResultMaxRank(widget.viewer, c.voteCategory) >= 1) c: shareableWinnerNames(poll, c, _members),
        },
      ),
      ShareImageTexts.resultFileName,
      origin,
    );
  }

  String _lineupName(LineupPerson p) {
    if (p.isGuest) {
      return _guests.where((g) => g.id == p.guestId).firstOrNull?.displayName ?? ScheduleTexts.guest;
    }
    return _members[p.userId] ?? ScheduleTexts.leftMember;
  }

  Future<void> _removeGuest(MatchGuest g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(ScheduleTexts.confirmRemoveGuest(g.displayName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(ScheduleTexts.keep)),
          TextButton(
            key: const Key('guest-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AdminTexts.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _s.guests.removeGuest(g.id);
    } on ServerFailure catch (e) {
      if (mounted) _toast(ScheduleTexts.serverError(e.code));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final m = _match;
    Widget body;
    if (_missing) {
      body = const EmptyState(icon: Icons.event_busy_outlined, message: ScheduleTexts.matchUnavailable);
    } else if (m == null || _roster == null) {
      body = _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              message: ScheduleTexts.loadFailed,
              actions: [TextButton(onPressed: _load, child: const Text(ScheduleTexts.retry))],
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(onRefresh: _load, child: _content(context, m, _roster!));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(ScheduleTexts.matchDetail),
        bottom: _loading && m != null
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _content(BuildContext context, TeamMatch m, AttendanceRoster roster) {
    final theme = Theme.of(context);
    final now = widget.now();
    final open = m.isRsvpOpenAt(now);
    final me = roster.responseOf(widget.viewer.userId);
    final showRoster = _e.canView(widget.viewer, const AttendanceListInfo());
    final canManage = _canManage;

    String nameOf(String userId) => _members[userId] ?? ScheduleTexts.leftMember;

    return ListView(
      padding: AppSpacing.page,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // ---- 취소됨 + 사유
        if (m.isCancelled) ...[
          Card(
            key: const Key('match-cancelled-banner'),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(Icons.event_busy, color: theme.colorScheme.onErrorContainer),
              title: Text(
                ScheduleTexts.cancelled,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
              subtitle: m.cancelReason == null
                  ? null
                  : Text(
                      ScheduleTexts.cancelReason(m.cancelReason!),
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
            ),
          ),
          AppSpacing.fieldGap,
        ],
        // ---- 일시·장소·정원·마감
        SectionCard(
          dividers: false,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(ScheduleTexts.matchTime(m), key: const Key('match-time')),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(m.venue?.name ?? ScheduleTexts.venueNone),
              subtitle: m.venue?.address == null ? null : Text(m.venue!.address!),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(ScheduleTexts.capacity(m.capacity)),
              subtitle: Text(ScheduleTexts.attendingCount(roster.attendingCount, m.capacity)),
            ),
            ListTile(
              leading: const Icon(Icons.how_to_vote_outlined),
              title: Text(
                open ? ScheduleTexts.deadline(m.rsvpDeadlineAt) : ScheduleTexts.deadlinePassed,
                key: const Key('match-deadline'),
              ),
            ),
          ],
        ),
        AppSpacing.sectionGap,
        // ---- 내 상태 + 버튼
        const SectionHeader(ScheduleTexts.myStatus),
        Text(
          ScheduleTexts.state(me?.state, roster.waitlistPosition(widget.viewer.userId)),
          key: const Key('my-status'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_e.canPerform(widget.viewer, TeamAction.voteAttendance) && !m.isCancelled)
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('rsvp-attend'),
                  onPressed: open && !_busy && me?.state != AttendanceState.attending &&
                          me?.state != AttendanceState.waitlisted
                      ? () => _respond(true)
                      : null,
                  child: const Text(ScheduleTexts.attendButton),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton(
                  key: const Key('rsvp-decline'),
                  onPressed: open && !_busy && me?.state != AttendanceState.declined ? () => _respond(false) : null,
                  child: const Text(ScheduleTexts.declineButton),
                ),
              ),
            ],
          ),
        if (!open && !m.isCancelled)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(ScheduleTexts.deadlinePassed, style: theme.textTheme.bodySmall),
          ),
        AppSpacing.sectionGap,
        // ---- 명단
        if (showRoster) ...[
          _RosterSection(
            keyName: 'attending',
            title: ScheduleTexts.attending,
            names: [for (final r in roster.attending) nameOf(r.userId)],
          ),
          _RosterSection(
            keyName: 'waitlisted',
            title: ScheduleTexts.waitlisted,
            names: [
              for (final (i, r) in roster.waitlist.indexed) '${i + 1}. ${nameOf(r.userId)}',
            ],
          ),
          _RosterSection(
            keyName: 'declined',
            title: ScheduleTexts.declined,
            names: [for (final r in roster.declined) nameOf(r.userId)],
          ),
          _RosterSection(
            keyName: 'not-responded',
            title: ScheduleTexts.notResponded,
            names: [for (final id in roster.notRespondedSorted(_members)) _members[id]!],
          ),
        ],
        // ---- 게스트
        SectionHeader(
          ScheduleTexts.guestsTitle(_guests.length),
          trailing: canManage && m.canEditGuestsAt(now)
              ? TextButton.icon(
                  key: const Key('guest-add'),
                  onPressed: _guests.length >= GuestInput.maxGuestsPerMatch ? null : _addGuest,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text(ScheduleTexts.addGuest),
                )
              : null,
        ),
        if (_guests.isEmpty)
          Text(ScheduleTexts.nobody, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
        else
          SectionCard(
            children: [
              for (final g in _guests)
                ListTile(
                  key: Key('guest-${g.id}'),
                  title: GuestNameLabel(g.displayName),
                  subtitle: _guestDetailText(g),
                  trailing: canManage && m.canEditGuestsAt(now)
                      ? IconButton(
                          key: Key('guest-remove-${g.id}'),
                          tooltip: ScheduleTexts.removeGuest,
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeGuest(g),
                        )
                      : null,
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(ScheduleTexts.guestNote, style: theme.textTheme.bodySmall),
        ),
        // ---- 팀 배치
        AppSpacing.sectionGap,
        LineupSection(
          match: m,
          lineup: _lineup,
          viewer: widget.viewer,
          entitlements: _e,
          nameOf: _lineupName,
          now: now,
          onOpenEditor: _openLineupEditor,
          onShareImage: _shareLineup,
        ),
        // ---- POM·오늘의 골 투표·결과
        if (_poll case final poll?) ...[
          AppSpacing.sectionGap,
          AwardSection(
            poll: poll,
            viewer: widget.viewer,
            entitlements: _e,
            memberNames: _members,
            now: now,
            onVote: _castVote,
            onShareImage: _shareResult,
          ),
        ],
        // ---- 운영진: 일정 취소
        if (canManage && m.canBeCancelledAt(now)) ...[
          AppSpacing.sectionGap,
          OutlinedButton.icon(
            key: const Key('match-cancel'),
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text(ScheduleTexts.cancelMatch),
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  /// 관리자에게만: 포지션·대략 실력
  Widget? _guestDetailText(MatchGuest g) {
    final d = _guestDetails[g.id];
    if (!_canSeeGuestDetails || d == null) return null;
    final parts = [
      if (d.positions.isNotEmpty) d.positions.map(ProfileTexts.position).join('·'),
      AdminTexts.skillLevel(d.skillLevel),
    ];
    return Text(parts.join(' · '));
  }
}

class _RosterSection extends StatelessWidget {
  const _RosterSection({required this.keyName, required this.title, required this.names});

  final String keyName;
  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(ScheduleTexts.rosterTitle(title, names.length)),
          if (names.isEmpty)
            Text(
              ScheduleTexts.nobody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              key: Key('roster-$keyName'),
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final n in names) Chip(label: Text(n))],
            ),
        ],
      ),
    );
  }
}

/// 일정 취소 확인 + 사유(선택, 20자). 취소하면 사유 문자열(빈 문자열 가능), 그대로 두면 null.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(ScheduleTexts.cancelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(ScheduleTexts.cancelNote),
          AppSpacing.fieldGap,
          TextField(
            key: const Key('cancel-reason'),
            controller: _reason,
            maxLength: 20,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
            decoration: const InputDecoration(labelText: ScheduleTexts.cancelReasonLabel),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(ScheduleTexts.keep)),
        TextButton(
          key: const Key('cancel-confirm'),
          onPressed: () => Navigator.pop(context, _reason.text),
          child: const Text(ScheduleTexts.cancelConfirm),
        ),
      ],
    );
  }
}
