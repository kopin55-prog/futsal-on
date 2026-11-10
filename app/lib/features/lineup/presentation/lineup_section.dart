import 'package:flutter/material.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../schedule/domain/match_models.dart';
import '../../share_image/presentation/share_image_button.dart';
import '../../share_image/presentation/share_image_texts.dart';
import '../domain/lineup_board.dart';
import '../domain/lineup_models.dart';
import 'lineup_blocks.dart';
import 'lineup_texts.dart';

/// 일정 상세 안의 "팀 배치" 부분 (스프린트 03 3-1·3-4).
///
/// - 팀원: 확정된 배치만 (팀 블록 조끼 색 + 이름 가나다순, 게스트 상자, 교체 블록, 내 이름 강조).
///   확정 전에는 "아직 팀 배치 전이에요". 서버도 초안을 팀원에게 주지 않는다.
/// - 운영진: [팀 나누기]/[배치 고치기] 버튼 (TeamAction.manageLineup). 참석 마감 전·경기 종료 뒤·취소된 일정은
///   버튼이 잠기고 이유를 보여준다. 작성 중(초안) 배치도 요약해서 보여준다.
/// 볼 수 있는지·버튼을 보일지는 Entitlements 에서만 판단한다.
class LineupSection extends StatelessWidget {
  const LineupSection({
    required this.match,
    required this.lineup,
    required this.viewer,
    required this.entitlements,
    required this.nameOf,
    required this.now,
    required this.onOpenEditor,
    this.onShareImage,
    super.key,
  });

  final TeamMatch match;
  final Lineup? lineup;
  final Viewer viewer;
  final Entitlements entitlements;
  final String Function(LineupPerson) nameOf;
  final DateTime now;
  final VoidCallback onOpenEditor;

  /// 배치 공유 이미지 (6-1). 버튼은 Entitlements.canShareLineupImage 일 때만 보인다.
  final Future<void> Function(Rect? origin)? onShareImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = entitlements.canPerform(viewer, TeamAction.manageLineup);
    final l = lineup;
    final visible = l != null && entitlements.canView(viewer, LineupInfo(confirmed: l.isConfirmed)) ? l : null;
    final window = LineupWindow.of(match, now);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (!canManage && visible == null && match.isCancelled) return const SizedBox.shrink();

    return Column(
      key: const Key('lineup-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          LineupTexts.sectionTitle,
          trailing: canManage
              ? TextButton.icon(
                  key: const Key('lineup-open'),
                  onPressed: window == LineupWindow.open ? onOpenEditor : null,
                  icon: const Icon(Icons.groups_2_outlined),
                  label: Text(l == null ? LineupTexts.openEditor : LineupTexts.editLineup),
                )
              : null,
        ),
        if (canManage && window != LineupWindow.open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(LineupTexts.window(window), key: const Key('lineup-window-note'), style: theme.textTheme.bodySmall),
          ),
        if (visible == null)
          Text(canManage ? LineupTexts.noLineupStaff : LineupTexts.notYet, key: const Key('lineup-none'), style: muted)
        else ...[
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Chip(
                    key: const Key('lineup-status'),
                    label: Text(visible.isConfirmed ? LineupTexts.confirmedBadge : LineupTexts.draftBadge),
                  ),
                  if (!visible.isConfirmed) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(LineupTexts.draftNote, style: theme.textTheme.bodySmall)),
                  ],
                ],
              ),
            ),
          LineupBlocksView(lineup: visible, nameOf: nameOf, highlightUserId: viewer.userId),
          if (onShareImage case final share?
              when entitlements.canShareLineupImage(
                viewer,
                lineupConfirmed: visible.isConfirmed,
                matchCancelled: match.isCancelled,
              ))
            Align(
              alignment: Alignment.centerRight,
              child: ShareImageButton(
                key: const Key('lineup-share'),
                label: ShareImageTexts.shareLineup,
                onShare: share,
              ),
            ),
        ],
      ],
    );
  }
}
