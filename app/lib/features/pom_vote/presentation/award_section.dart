import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../domain/award_models.dart';
import 'award_texts.dart';

/// 일정 상세 안의 "POM·오늘의 골" 부분 (스프린트 03 5-2·5-3, 기능 확인용 기본 화면).
///
/// 진행 중 (마감 전):
/// - 마감 시각을 보여준다. 투표 수·득표는 보여주지 않는다 (Q-075 13번 (5)).
/// - 대상자이면서 지금 팀원이면 항목마다 따로: 후보(대상자 중 본인·떠난 사람 제외, 게스트는 대상자가 아님, 이름 가나다순)를
///   고르고 [투표하기] → 확인 창 → 낸 뒤엔 "투표 완료"(누구를 찍었는지는 보여주지도, 기기에 남기지도 않음. 바꾸기 없음).
/// - 대상자가 아니면 투표 버튼 없이 "이번 경기 투표 대상이 아니에요".
/// - 마감 시각이 지났는데 아직 마감 처리 전이면 잠그고 안내.
/// 마감 뒤: 팀원 전체에게 항목별 1위(공동이면 모두). 1위가 없으면 "결과 없음". 팀을 떠난 1위는 빼고 보여준다
///   (S3-12 결과 이미지와 같게, lead 지시). 회원 탈퇴자는 서버에서 줄이 지워져 없다. 득표수·순위 없음.
///   득표수 보기 버튼 자리는 Entitlements.showVoteCountButton 으로만 판단 (1차 숨김).
class AwardSection extends StatefulWidget {
  const AwardSection({
    required this.poll,
    required this.viewer,
    required this.entitlements,
    required this.memberNames,
    required this.now,
    required this.onVote,
    super.key,
  });

  final AwardPollView poll;
  final Viewer viewer;
  final Entitlements entitlements;

  /// 지금 팀원 ID → 이름 (떠난 사람은 없다)
  final Map<String, String> memberNames;
  final DateTime now;

  /// 투표를 서버에 보낸다 (부른 쪽이 안내·다시 읽기).
  final Future<void> Function(AwardCategory category, String candidateId) onVote;

  @override
  State<AwardSection> createState() => _AwardSectionState();
}

class _AwardSectionState extends State<AwardSection> {
  /// 고르는 중인 후보 (화면에만, 낸 뒤 바로 비운다)
  final Map<AwardCategory, String> _selected = {};
  bool _busy = false;

  String _name(String id) => widget.memberNames[id] ?? '';

  List<String> _sortedByName(Iterable<String> ids) => [...ids]..sort((a, b) {
    final c = _name(a).compareTo(_name(b));
    return c != 0 ? c : a.compareTo(b);
  });

  Future<void> _vote(AwardCategory category) async {
    final candidate = _selected[category];
    if (candidate == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AwardTexts.category(category)),
        content: Text(AwardTexts.confirmVote(_name(candidate))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(AwardTexts.cancel)),
          TextButton(
            key: Key('award-confirm-${category.code}'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AwardTexts.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onVote(category, candidate);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected.remove(category);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poll = widget.poll;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final children = <Widget>[];

    if (poll.status == AwardPollStatus.closed) {
      for (final c in AwardCategory.values) {
        if (widget.entitlements.voteResultMaxRank(widget.viewer, c.voteCategory) < 1) continue;
        children.add(_resultCard(context, c));
      }
    } else if (!poll.isOpenAt(widget.now)) {
      children.add(Text(AwardTexts.closedPending, key: const Key('award-closed-pending'), style: muted));
    } else {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            AwardTexts.deadline(poll.closesAt),
            key: const Key('award-deadline'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
      final me = widget.viewer.userId;
      final isCurrentMember = widget.viewer.isTeamMember && widget.memberNames.containsKey(me);
      final mayVote = widget.entitlements.canPerform(widget.viewer, TeamAction.voteAwards) &&
          isCurrentMember &&
          poll.isParticipant(me);
      if (!mayVote) {
        children.add(Text(AwardTexts.notParticipant, key: const Key('award-not-participant'), style: muted));
      } else {
        final candidates = _sortedByName(poll.candidates(me: me, currentMemberIds: widget.memberNames.keys.toSet()));
        for (final c in AwardCategory.values) {
          children.add(_voteCard(context, c, candidates));
        }
      }
    }

    return Column(
      key: const Key('award-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const SectionHeader(AwardTexts.sectionTitle), ...children],
    );
  }

  Widget _voteCard(BuildContext context, AwardCategory c, List<String> candidates) {
    final theme = Theme.of(context);
    final voted = widget.poll.myVoted.contains(c);
    final canVote = widget.poll.canVote(widget.viewer.userId, c, isCurrentMember: true, now: widget.now);
    final selected = _selected[c];
    return Card(
      key: Key('award-vote-${c.code}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(AwardTexts.category(c), style: theme.textTheme.titleMedium),
              trailing: voted ? Chip(key: Key('award-voted-${c.code}'), label: const Text(AwardTexts.voted)) : null,
            ),
            if (!voted && candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Text(
                  AwardTexts.noCandidates,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (!voted && candidates.isNotEmpty) ...[
              for (final id in candidates)
                ListTile(
                  key: Key('award-candidate-${c.code}-$id'),
                  dense: true,
                  enabled: canVote && !_busy,
                  selected: selected == id,
                  leading: Icon(selected == id ? Icons.check_circle : Icons.radio_button_unchecked),
                  title: Text(_name(id)),
                  onTap: () => setState(() => _selected[c] = id),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: FilledButton(
                  key: Key('award-submit-${c.code}'),
                  onPressed: canVote && selected != null && !_busy ? () => _vote(c) : null,
                  child: const Text(AwardTexts.voteButton),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, AwardCategory c) {
    final theme = Theme.of(context);
    // 떠난 1위는 빼고 (이름을 알 수 있는 지금 팀원만)
    final winners = _sortedByName(widget.poll.winnersOf(c).where(widget.memberNames.containsKey));
    final showCountButton = widget.entitlements.showVoteCountButton(widget.viewer);
    return Card(
      key: Key('award-result-${c.code}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AwardTexts.category(c), style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (winners.isEmpty)
              Text(
                AwardTexts.noResult,
                key: Key('award-no-result-${c.code}'),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Wrap(
                key: Key('award-winners-${c.code}'),
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final id in winners)
                    Chip(avatar: const Icon(Icons.emoji_events_outlined, size: 18), label: Text(_name(id))),
                ],
              ),
            // 득표수 보기 버튼 자리 (1차 숨김, 2차 보상형 광고·개인 구독)
            if (showCountButton)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('award-count-${c.code}'),
                  // TODO(2차): 보상형 광고·개인 구독 연결 (Entitlements VoteCountInfo)
                  onPressed: null,
                  child: const Text(AwardTexts.voteCountButton),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
