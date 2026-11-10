import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/name_search.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../../shared/presentation/list_controls.dart';
import '../../schedule/domain/match_models.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../../team/domain/team_models.dart';
import '../domain/bib_color.dart';
import '../domain/lineup_board.dart';
import '../domain/lineup_models.dart';
import '../domain/team_split.dart';
import 'lineup_blocks.dart';
import 'lineup_texts.dart';

/// 팀 나누기 (운영진, 스프린트 03 3-1~3-3). 일정 상세에서 연다.
///
/// - 팀 수·팀당 인원 (처음 값: 저장된 배치 → 지난 경기에 쓴 값 → 2팀·인원÷2 올림, Q-075 7번 (4)).
/// - [자동 나누기]: 참석자·게스트를 계산 함수로 나눈다. 이미 배치가 있으면 그 배치에 있는 사람으로 다시 나눈다.
///   운영진이 직접 넣은 팀원(참석자가 아닌 사람)도 계산에 넣어 팀에 배정한다 (Q-076 6번).
///   계산 정보가 없는 사람(경기 시작 뒤 팀을 떠난 사람)만 교체 블록에 그대로 둔다.
/// - [재조합]: 다음으로 좋은 배치. 직접 옮긴 뒤면 확인 창, 후보를 다 보면 "모든 조합을 봤어요" (Q-075 7번 (1)(2)).
/// - 끌어 옮기기(길게 눌러 끌기) 또는 이름을 눌러 옮길 곳 고르기("빨강 팀으로/교체 블록으로"): 팀 ↔ 팀 ↔ 교체 블록,
///   배치에서 빼기(Q-046). 규칙이 깨져도 막지 않고 경고만 (Q-075 7번 (3)).
/// - 위쪽 이름 검색 (Q-079 3번 e): 찾은 사람을 블록 안에서 강조하고 "N명 찾음". 명단은 그대로 둔다 (옮기기는 그 자리에서).
/// - [팀원 추가]: 배치에 없는 팀원(대기·불참·미투표 등)을 교체 블록에 (Q-075 2번).
/// - 조끼 색: 자동 배정(빨강·파랑…노조끼), 팀마다 고르기, 한 배치 안 중복 불가 (Q-075 8번).
/// - 저장: [초안 저장]·[확정], 확정 뒤에는 [변경 저장] 한 번 = 알림 한 번 (Q-075 7번 (6), 서버 save_lineup).
///   다른 운영진이 먼저 저장했으면 "다른 운영진이 먼저 바꿨어요" 후 새로 불러온다 (Q-075 7번 (5)).
/// - 실력 등급·점수·포지션·GK 는 어디에도 표시하지 않는다 (Q-075 5·6번). 계산 재료는 기기 안에서만 쓴다.
class LineupEditorScreen extends StatefulWidget {
  const LineupEditorScreen({
    required this.services,
    required this.team,
    required this.viewer,
    required this.match,
    this.now = DateTime.now,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;
  final TeamMatch match;
  final DateTime Function() now;

  @override
  State<LineupEditorScreen> createState() => _LineupEditorScreenState();
}

class _LineupEditorScreenState extends State<LineupEditorScreen> {
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;

  LineupPool? _pool;
  Map<String, String> _memberNames = const {};
  Map<String, String> _guestNames = const {};

  /// 서버에 저장된 배치 (없으면 null).
  Lineup? _saved;

  /// 화면에서 고치는 중인 배치 (아직 안 나눴으면 null).
  LineupBoard? _board;
  int _teams = LineupLimits.minTeams;
  int _players = LineupLimits.minPlayers;

  /// 마지막 자동 나누기·재조합 뒤 직접 옮겼는지 (재조합 확인 창).
  bool _manualMoved = false;

  /// 이름 검색어 (정리 키). 비어 있으면 강조 없음.
  String _queryKey = '';
  TeamSplitShuffler? _shuffler;
  String? _shufflerKey;

  AppServices get _s => widget.services;
  TeamMatch get _m => widget.match;
  bool get _canManage => _s.entitlements.canPerform(widget.viewer, TeamAction.manageLineup);
  LineupWindow get _window => LineupWindow.of(_m, widget.now());
  bool get _editable => _canManage && _window == LineupWindow.open;

  bool get _dirty {
    final b = _board;
    if (b == null) return false;
    final saved = _saved;
    return saved == null || b.signature != LineupBoard.fromLineup(saved).signature;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final teamId = _m.teamId;
      final members = await _s.teams.listMembers(teamId);
      final responses = await _s.attendance.listResponses(_m.id);
      final guests = await _s.guests.listGuestDetails(_m.id);
      final skills = await _s.admin.listSkillLevels(teamId);
      final rules = await _s.admin.listPairingRules(teamId);
      final prefs = await _s.teams.listPlayPrefs([for (final m in members) m.userId]);
      final lineup = await _s.lineups.getLineup(_m.id);
      final last = lineup == null
          ? await _s.lineups.lastLineupSize(teamId, before: _m.startsAt, excludeMatchId: _m.id)
          : null;
      if (!mounted) return;
      final pool = LineupPool.build(
        members: members,
        responses: responses,
        guests: guests,
        skills: skills,
        prefs: prefs,
        rules: rules,
      );
      final size = lineup != null
          ? (teams: lineup.teamCount, players: lineup.playersPerTeam)
          : LineupLimits.defaults(last: last, poolCount: pool.autoPeople.length);
      setState(() {
        _pool = pool;
        _memberNames = {for (final m in members) m.userId: m.displayName};
        _guestNames = {for (final g in guests) g.id: _guestName(g.name, g.guestNo)};
        _saved = lineup;
        _board = lineup == null ? null : LineupBoard.fromLineup(lineup);
        _teams = size.teams;
        _players = size.players;
        _manualMoved = false;
        _shuffler = null;
        _shufflerKey = null;
      });
    } on ServerFailure {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _guestName(String? name, int no) => name ?? '${LineupTexts.guest}$no';

  String _nameOf(LineupPerson p) => p.isGuest
      ? (_guestNames[p.guestId] ?? LineupTexts.guest)
      : (_memberNames[p.userId] ?? ScheduleTexts.leftMember);

  /// 검색어에 맞는 사람인지 (빈 검색어면 아무도 강조하지 않음)
  bool _matches(LineupPerson p) => _queryKey.isNotEmpty && NameSearch.matchesKey(NameSearch.key(_nameOf(p)), _queryKey);

  void _toast(String text) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));

  // ---------------------------------------------------------------------------
  // 나누기
  // ---------------------------------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!_manualMoved || _board == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LineupTexts.discardTitle),
        content: const Text(LineupTexts.discardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(LineupTexts.keep)),
          TextButton(
            key: const Key('lineup-discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(LineupTexts.discardOk),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _split({required bool reshuffle}) async {
    final pool = _pool;
    if (pool == null || !_editable) return;
    if (!await _confirmDiscard() || !mounted) return;

    final current = _board;
    final people = current?.people ?? [...pool.autoPeople];
    // 계산하는 사람 = 배치에 있는 사람 중 계산 정보가 있는 사람 (참석자·게스트 + 운영진이 직접 넣은 팀원, Q-076 6번).
    // 계산 정보가 없는 사람(경기 시작 뒤 팀을 떠나 팀원 목록에 없는 사람)만 교체 블록에 그대로 둔다.
    final auto = [for (final p in people) if (pool.candidates.containsKey(p)) p]..sort();
    final extras = [for (final p in people) if (!auto.contains(p)) p];
    final key = '$_teams/$_players/${auto.map((p) => p.key).join(',')}';

    var wrapped = false;
    TeamSplitPlan plan;
    final shuffler = _shuffler;
    if (reshuffle && shuffler != null && _shufflerKey == key) {
      plan = shuffler.next();
      wrapped = shuffler.wrapped;
    } else {
      final fresh = TeamSplitShuffler(pool.input(auto, teams: _teams, players: _players));
      _shuffler = fresh;
      _shufflerKey = key;
      plan = fresh.current;
      // 재조합인데 지금 보이는 배치와 같으면 다음 것 (같은 배치가 연달아 나오지 않게)
      if (reshuffle && current != null && current.teamCount == _teams && current.sameTeamsAs(plan)) {
        plan = fresh.next();
        wrapped = fresh.wrapped;
      }
    }
    setState(() {
      _board = LineupBoard.fromPlan(
        plan,
        playersPerTeam: _players,
        colors: current?.teamCount == plan.squads.length ? [for (final q in current!.squads) q.color] : null,
        extraBench: extras,
      );
      _manualMoved = false;
    });
    if (wrapped) _toast(LineupTexts.allSeen);
  }

  // ---------------------------------------------------------------------------
  // 직접 고치기
  // ---------------------------------------------------------------------------

  void _move(LineupPerson p, int? toSquad) {
    final b = _board;
    if (b == null || !_editable) return;
    setState(() {
      if (b.move(p, toSquad)) _manualMoved = true;
    });
  }

  void _remove(LineupPerson p) {
    final b = _board;
    if (b == null || !_editable) return;
    setState(() {
      if (b.remove(p)) _manualMoved = true;
    });
  }

  Future<void> _openMoveSheet(LineupPerson p) async {
    final b = _board;
    if (b == null || !_editable) return;
    final from = b.squadOf(p);
    final inBench = b.bench.contains(p);
    // 결과: 팀 번호(0부터), -1 = 교체 블록, -2 = 배치에서 빼기
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(LineupTexts.moveTitle(_nameOf(p)), style: Theme.of(context).textTheme.titleMedium)),
            for (var i = 0; i < b.squads.length; i++)
              if (i != from)
                ListTile(
                  key: Key('move-to-$i'),
                  leading: BibSwatch(b.squads[i].color),
                  title: Text(LineupTexts.moveTo(b.squads[i].color)),
                  onTap: () => Navigator.pop(context, i),
                ),
            if (!inBench)
              ListTile(
                key: const Key('move-to-bench'),
                leading: const Icon(Icons.event_seat_outlined),
                title: const Text(LineupTexts.moveToBench),
                onTap: () => Navigator.pop(context, -1),
              ),
            ListTile(
              key: const Key('move-remove'),
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text(LineupTexts.removeFromLineup),
              onTap: () => Navigator.pop(context, -2),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == -2) {
      _remove(p);
    } else {
      _move(p, choice == -1 ? null : choice);
    }
  }

  Future<void> _openAddSheet() async {
    final b = _board;
    final pool = _pool;
    if (b == null || pool == null || !_editable) return;
    final memberIds = [
      for (final id in _memberNames.keys)
        if (!b.contains(LineupPerson.member(id))) id,
    ]..sort((x, y) => _memberNames[x]!.compareTo(_memberNames[y]!));
    final guestIds = [
      for (final id in _guestNames.keys)
        if (!b.contains(LineupPerson.guest(id))) id,
    ]..sort((x, y) => _guestNames[x]!.compareTo(_guestNames[y]!));
    final picked = await showModalBottomSheet<LineupPerson>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(LineupTexts.addMemberTitle, style: Theme.of(context).textTheme.titleMedium)),
              if (memberIds.isEmpty && guestIds.isEmpty)
                const ListTile(title: Text(LineupTexts.addMemberEmpty)),
              for (final id in memberIds)
                ListTile(
                  key: Key('add-member-$id'),
                  title: Text(_memberNames[id]!),
                  trailing: Text(LineupTexts.memberState(pool.states[id])),
                  onTap: () => Navigator.pop(context, LineupPerson.member(id)),
                ),
              for (final id in guestIds)
                ListTile(
                  key: Key('add-guest-$id'),
                  title: LineupNameChip(name: _guestNames[id]!, isGuest: true),
                  trailing: const Text(LineupTexts.removedGuest),
                  onTap: () => Navigator.pop(context, LineupPerson.guest(id)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (b.addToBench(picked)) _manualMoved = true;
    });
  }

  Future<void> _pickColor(int squad) async {
    final b = _board;
    if (b == null || !_editable) return;
    final used = b.colorsUsedByOthers(squad);
    final picked = await showDialog<BibColor>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text(LineupTexts.pickColor),
        children: [
          for (final c in BibColor.values)
            ListTile(
              key: Key('bib-${c.serverValue}'),
              enabled: !used.contains(c),
              leading: BibSwatch(c),
              title: Text(LineupTexts.color(c)),
              subtitle: used.contains(c) ? const Text(LineupTexts.colorInUse) : null,
              trailing: b.squads[squad].color == c ? const Icon(Icons.check) : null,
              onTap: used.contains(c) ? null : () => Navigator.pop(context, c),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => b.setColor(squad, picked));
  }

  // ---------------------------------------------------------------------------
  // 저장
  // ---------------------------------------------------------------------------

  Future<void> _save({bool confirm = false}) async {
    final b = _board;
    final pool = _pool;
    if (b == null || pool == null || !_editable || _busy) return;
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(LineupTexts.confirmTitle),
          content: const Text(LineupTexts.confirmBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(LineupTexts.cancel)),
            TextButton(
              key: const Key('lineup-confirm-ok'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(LineupTexts.confirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final wasConfirmed = _saved?.isConfirmed ?? false;
    setState(() => _busy = true);
    try {
      final stored = {for (final w in b.warnings(pool)) ?w.stored};
      await _s.lineups.saveLineup(_m.id, b.toDraft(stored), expectedUpdatedAt: _saved?.updatedAt, confirm: confirm);
      final fresh = await _s.lineups.getLineup(_m.id);
      if (!mounted) return;
      setState(() {
        _saved = fresh;
        _board = fresh == null ? null : LineupBoard.fromLineup(fresh);
        _manualMoved = false;
      });
      _toast(wasConfirmed ? LineupTexts.changesSaved : (confirm ? LineupTexts.confirmedDone : LineupTexts.savedDraft));
    } on ServerFailure catch (e) {
      if (!mounted) return;
      if (e.code == ServerErrorCode.lineupConflict || e.code == ServerErrorCode.invalidLineupSlot) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(LineupTexts.serverError(e.code)),
            actions: [
              TextButton(
                key: const Key('lineup-reload'),
                onPressed: () => Navigator.pop(context),
                child: const Text(LineupTexts.ok),
              ),
            ],
          ),
        );
        if (mounted) await _load();
      } else {
        _toast(LineupTexts.serverError(e.code));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPopBlocked() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LineupTexts.unsavedTitle),
        content: const Text(LineupTexts.unsavedBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(LineupTexts.cancel)),
          TextButton(
            key: const Key('lineup-leave'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(LineupTexts.leave),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // 화면
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_pool == null) {
      body = _failed
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              message: ScheduleTexts.loadFailed,
              actions: [TextButton(onPressed: _load, child: const Text(ScheduleTexts.retry))],
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = _content(context, _pool!);
    }
    return PopScope(
      canPop: !_dirty || !_editable,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(LineupTexts.splitTeams),
          bottom: _loading && _pool != null
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        body: SafeArea(child: body),
        bottomNavigationBar: _pool == null || !_editable || _board == null ? null : _saveBar(context),
      ),
    );
  }

  Widget _content(BuildContext context, LineupPool pool) {
    final theme = Theme.of(context);
    final window = _window;
    final b = _board;
    final saved = _saved;
    final warnings = b == null ? const <SplitWarning>{} : b.warnings(pool);
    final now = widget.now();
    return ListView(
      padding: AppSpacing.page,
      children: [
        if (!_canManage || window != LineupWindow.open) ...[
          Card(
            key: const Key('lineup-window-note'),
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(_canManage ? LineupTexts.window(window) : LineupTexts.notYet),
            ),
          ),
          AppSpacing.fieldGap,
        ],
        if (saved != null) ...[
          Row(
            children: [
              Chip(
                key: const Key('lineup-status'),
                label: Text(saved.isConfirmed ? LineupTexts.confirmedBadge : LineupTexts.draftBadge),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!saved.isConfirmed) Expanded(child: Text(LineupTexts.draftNote, style: theme.textTheme.bodySmall)),
              if (saved.isConfirmed && !now.isBefore(_m.startsAt))
                Expanded(child: Text(LineupTexts.afterStartNote, style: theme.textTheme.bodySmall)),
            ],
          ),
          AppSpacing.fieldGap,
        ],
        if (_editable) ...[
          _settings(context, pool),
          AppSpacing.sectionGap,
        ],
        if (warnings.isNotEmpty) ...[
          _warnings(context, warnings),
          AppSpacing.fieldGap,
        ],
        if (b == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              _editable ? LineupTexts.emptyBoard : LineupTexts.noLineupStaff,
              key: const Key('lineup-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else if (_editable) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(LineupTexts.dragHint, style: theme.textTheme.bodySmall),
          ),
          _search(context, b),
          for (var i = 0; i < b.squads.length; i++) _squadTarget(context, b, i),
          _benchTarget(context, b),
        ] else if (saved != null)
          LineupBlocksView(lineup: saved, nameOf: _nameOf),
      ],
    );
  }

  Widget _settings(BuildContext context, LineupPool pool) {
    final theme = Theme.of(context);
    return SectionCard(
      dividers: false,
      children: [
        _StepperRow(
          keyName: 'teams',
          label: LineupTexts.teamCount,
          value: _teams,
          display: LineupTexts.teamCountValue(_teams),
          min: LineupLimits.minTeams,
          max: LineupLimits.maxTeams,
          onChanged: (v) => setState(() => _teams = v),
        ),
        _StepperRow(
          keyName: 'players',
          label: LineupTexts.playersPerTeam,
          value: _players,
          display: LineupTexts.playersValue(_players),
          min: LineupLimits.minPlayers,
          max: LineupLimits.maxPlayers,
          onChanged: (v) => setState(() => _players = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
          child: Text(
            LineupTexts.poolInfo(pool.autoPeople.length),
            key: const Key('lineup-pool-info'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('lineup-auto'),
                  onPressed: _busy ? null : () => _split(reshuffle: false),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text(LineupTexts.autoSplit),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('lineup-reshuffle'),
                  onPressed: _busy || _board == null ? null : () => _split(reshuffle: true),
                  icon: const Icon(Icons.shuffle),
                  label: const Text(LineupTexts.reshuffle),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _warnings(BuildContext context, Set<SplitWarning> warnings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ordered = [...warnings]..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return Container(
      key: const Key('lineup-warnings'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in ordered)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      LineupTexts.warning(w),
                      key: Key('lineup-warning-${w.kind.name}'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 위쪽 이름 검색 (Q-079 3번 e). 찾은 사람 수를 보여 주고 블록 안에서 강조한다.
  Widget _search(BuildContext context, LineupBoard b) {
    final theme = Theme.of(context);
    final found = _queryKey.isEmpty ? null : b.people.where(_matches).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            key: const Key('lineup-search'),
            hintText: LineupTexts.searchName,
            clearTooltip: LineupTexts.clearSearch,
            onChanged: (v) => setState(() => _queryKey = NameSearch.key(v)),
          ),
          if (found != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.xs),
              child: Text(
                found == 0 ? LineupTexts.noNameMatch : LineupTexts.found(found),
                key: const Key('lineup-search-result'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: found == 0 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _person(LineupPerson p, Color? fg) {
    // 검색에 걸린 사람은 강조 (팀원 화면의 "내 이름" 강조와 같은 모양)
    final chip = LineupNameChip(name: _nameOf(p), isGuest: p.isGuest, foreground: fg, highlight: _matches(p));
    return LongPressDraggable<LineupPerson>(
      key: Key('lineup-person-${p.key}'),
      data: p,
      feedback: Material(color: Colors.transparent, child: LineupNameChip(name: _nameOf(p), isGuest: p.isGuest)),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () => _openMoveSheet(p),
        child: chip,
      ),
    );
  }

  Widget _squadTarget(BuildContext context, LineupBoard b, int i) {
    final q = b.squads[i];
    final fg = bibColorStyle(q.color, Theme.of(context).colorScheme).foreground;
    return DragTarget<LineupPerson>(
      key: Key('lineup-squad-${i + 1}'),
      onWillAcceptWithDetails: (d) => b.squadOf(d.data) != i,
      onAcceptWithDetails: (d) => _move(d.data, i),
      builder: (context, candidates, _) => SquadBlockFrame(
        color: q.color,
        highlighted: candidates.isNotEmpty,
        title: LineupTexts.squadTitle(q.color, q.people.length),
        trailing: IconButton(
          key: Key('lineup-color-${i + 1}'),
          tooltip: LineupTexts.pickColor,
          icon: Icon(Icons.palette_outlined, color: fg),
          onPressed: () => _pickColor(i),
        ),
        children: [for (final p in sortByName(q.people, _nameOf)) _person(p, fg)],
      ),
    );
  }

  Widget _benchTarget(BuildContext context, LineupBoard b) {
    return DragTarget<LineupPerson>(
      key: const Key('lineup-bench'),
      onWillAcceptWithDetails: (d) => !b.bench.contains(d.data),
      onAcceptWithDetails: (d) => _move(d.data, null),
      builder: (context, candidates, _) => SquadBlockFrame(
        highlighted: candidates.isNotEmpty,
        title: LineupTexts.benchTitle(b.bench.length),
        trailing: TextButton.icon(
          key: const Key('lineup-add-member'),
          onPressed: _openAddSheet,
          icon: const Icon(Icons.person_add_alt),
          label: const Text(LineupTexts.addMember),
        ),
        children: [for (final p in sortByName(b.bench, _nameOf)) _person(p, null)],
      ),
    );
  }

  Widget _saveBar(BuildContext context) {
    final confirmed = _saved?.isConfirmed ?? false;
    final dirty = _dirty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.md),
        child: confirmed
            ? FilledButton(
                key: const Key('lineup-save-changes'),
                onPressed: dirty && !_busy ? () => _save() : null,
                child: const Text(LineupTexts.saveChanges),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('lineup-save-draft'),
                      onPressed: dirty && !_busy ? () => _save() : null,
                      child: const Text(LineupTexts.saveDraft),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      key: const Key('lineup-confirm'),
                      onPressed: _busy ? null : () => _save(confirm: true),
                      child: const Text(LineupTexts.confirm),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.keyName,
    required this.label,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final int value;
  final String display;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('lineup-$keyName-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 52,
            child: Text(
              display,
              key: Key('lineup-$keyName-value'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: Key('lineup-$keyName-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
