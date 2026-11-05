import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/data/server_error.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/team_logo.dart';
import '../../team/presentation/team_texts.dart';
import '../data/membership_repository.dart';

/// 팀 찾기·가입 신청 (data-model.md 3-1, 3-5, 3-6, Q-067 10·11·14번).
///
/// - 팀 식별코드: 소문자도 인식, 정확히 일치. 모집 중일 때만 신청 (Q-029, Q-051).
/// - 팀 이름 일부 검색: 2자 이상 (Q-067 11번).
/// - 초대 코드 붙여넣기 칸도 이 화면에 둔다 (Q-067 14번). 모집 여부와 무관.
/// - 보낸 대기 신청 목록과 신청 취소 (Q-067 10번).
class TeamFindScreen extends StatefulWidget {
  const TeamFindScreen({required this.membership, super.key});

  final MembershipRepository membership;

  @override
  State<TeamFindScreen> createState() => _TeamFindScreenState();
}

enum _Mode { code, name, invite }

class _TeamFindScreenState extends State<TeamFindScreen> {
  final _input = TextEditingController();
  _Mode _mode = _Mode.code;
  bool _busy = false;
  String? _message;
  List<TeamSearchResult>? _results;
  InviteTeam? _inviteTeam;
  List<MyJoinRequest> _myRequests = const [];

  MembershipRepository get _m => widget.membership;

  @override
  void initState() {
    super.initState();
    _loadMyRequests();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadMyRequests() async {
    try {
      final list = await _m.listMyPendingRequests();
      if (mounted) setState(() => _myRequests = list);
    } on ServerFailure {
      // 목록을 못 읽어도 찾기는 쓸 수 있다.
    }
  }

  void _setMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _input.clear();
      _message = null;
      _results = null;
      _inviteTeam = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on ServerFailure catch (e) {
      if (mounted) setState(() => _message = TeamTexts.serverError(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    final text = _input.text.trim();
    switch (_mode) {
      case _Mode.code:
        await _run(() async {
          final team = await _m.findTeamByCode(text);
          setState(() {
            _results = team == null ? const [] : [team];
            if (team == null) _message = TeamTexts.codeNotFound;
          });
        });
      case _Mode.name:
        if (text.characters.length < 2) {
          setState(() => _message = TeamTexts.searchTooShort);
          return;
        }
        await _run(() async {
          final list = await _m.searchTeams(text);
          setState(() {
            _results = list;
            if (list.isEmpty) _message = TeamTexts.noSearchResult;
          });
        });
      case _Mode.invite:
        await _run(() async {
          final team = await _m.getInviteTeam(text);
          setState(() => _inviteTeam = team);
        });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _input.text = data!.text!.trim());
  }

  Future<void> _requestJoin(TeamSearchResult team) => _run(() async {
    await _m.requestJoin(team.teamCode, viaSearch: _mode == _Mode.name);
    _onRequested();
  });

  Future<void> _requestByInvite() => _run(() async {
    await _m.requestJoinByInvite(_input.text);
    _onRequested();
  });

  void _onRequested() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(TeamTexts.requestSent)),
    );
    setState(() {
      _results = null;
      _inviteTeam = null;
      _input.clear();
    });
    _loadMyRequests();
  }

  Future<void> _cancel(MyJoinRequest r) => _run(() async {
    await _m.cancelJoinRequest(r.requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(TeamTexts.requestCancelled)),
      );
    }
    await _loadMyRequests();
  });

  String get _label => switch (_mode) {
    _Mode.code => TeamTexts.teamCodeLabel,
    _Mode.name => TeamTexts.nameSearchLabel,
    _Mode.invite => TeamTexts.inviteCodeLabel,
  };

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text(TeamTexts.findTeam)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.code, label: Text('식별코드')), // TODO(문구 미정)
                ButtonSegment(value: _Mode.name, label: Text('팀 이름')), // TODO(문구 미정)
                ButtonSegment(value: _Mode.invite, label: Text('초대 코드')), // TODO(문구 미정)
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('find-input'),
              controller: _input,
              maxLines: 1,
              textCapitalization: _mode == _Mode.code
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              decoration: InputDecoration(
                labelText: _label,
                suffixIcon: _mode == _Mode.invite
                    ? IconButton(
                        tooltip: TeamTexts.paste,
                        icon: const Icon(Icons.content_paste),
                        onPressed: _paste,
                      )
                    : null,
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('find-submit'),
              onPressed: _busy ? null : _search,
              child: const Text(TeamTexts.search),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, key: const Key('find-message'), style: TextStyle(color: errorColor)),
            ],
            const SizedBox(height: 12),
            for (final t in _results ?? const <TeamSearchResult>[])
              _ResultCard(team: t, busy: _busy, onRequest: () => _requestJoin(t)),
            if (_inviteTeam != null)
              Card(
                child: ListTile(
                  leading: TeamLogo(text: _inviteTeam!.logoText, imagePath: _inviteTeam!.logoImagePath),
                  title: Text(_inviteTeam!.name),
                  subtitle: Text(_inviteTeam!.teamCode),
                  trailing: FilledButton(
                    key: const Key('invite-request'),
                    onPressed: _busy ? null : _requestByInvite,
                    child: const Text(TeamTexts.requestJoin),
                  ),
                ),
              ),
            if (_myRequests.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(TeamTexts.myRequests, style: Theme.of(context).textTheme.titleSmall),
              for (final r in _myRequests)
                ListTile(
                  key: Key('my-request-${r.requestId}'),
                  leading: TeamLogo(text: r.logoText, imagePath: r.logoImagePath, size: 36),
                  title: Text(r.teamName),
                  subtitle: Text(r.teamCode),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _cancel(r),
                    child: const Text(TeamTexts.cancelRequest),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.team, required this.busy, required this.onRequest});

  final TeamSearchResult team;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final details = [
      team.teamCode,
      ?TeamTexts.schedule(team.schedule),
      ?team.venueName,
      TeamTexts.membersCount(team.memberCount),
    ];
    return Card(
      child: ListTile(
        key: Key('result-${team.teamCode}'),
        leading: TeamLogo(text: team.logoText, imagePath: team.logoImagePath),
        title: Text(team.name),
        subtitle: Text(details.join(' · ')),
        isThreeLine: true,
        trailing: team.isRecruiting
            ? FilledButton(
                onPressed: busy ? null : onRequest,
                child: const Text(TeamTexts.requestJoin),
              )
            // 모집 꺼진 팀도 보이되 신청 불가 (Q-021)
            : const Text(TeamTexts.recruitingClosed),
      ),
    );
  }
}
