import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../lineup/domain/lineup_models.dart';
import '../../lineup/presentation/lineup_blocks.dart';
import '../../pom_vote/domain/award_models.dart';
import '../../pom_vote/presentation/award_texts.dart';
import '../../schedule/domain/match_models.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../../team/domain/team_models.dart';
import '../../team/presentation/team_logo.dart';
import 'share_image_texts.dart';

/// 공유 이미지 너비 (논리 픽셀). 그림으로 만들 때 [ShareImageFrame.pixelRatio] 배로 키운다.
const double shareImageWidth = 360;

/// 공유 이미지 틀 (스프린트 03 6-3): 간결하고 깔끔하게, 밝은·어두운 모드와 상관없이 같은 그림.
///
/// 위: 팀 로고·팀 이름·경기 일시(·장소), 가운데: [child], 아래: 작게 "풋살ON".
/// 테마는 항상 밝은 테마로 고정하고 글자 크기 설정도 따르지 않는다(받는 사람마다 같은 그림).
class ShareImageFrame extends StatelessWidget {
  const ShareImageFrame({
    required this.team,
    required this.match,
    required this.title,
    required this.child,
    this.showVenue = false,
    super.key,
  });

  /// 1080px 너비 PNG (360 × 3).
  static const double pixelRatio = 3;

  final TeamSummary team;
  final TeamMatch match;

  /// 이미지 종류 ("팀 배치" 등)
  final String title;
  final Widget child;
  final bool showVenue;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.light();
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Theme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurface),
            child: Container(
              width: shareImageWidth,
              color: scheme.surface,
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      TeamLogo(text: team.logoText, imagePath: team.logoImagePath, size: 48),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team.name,
                              key: const Key('share-team-name'),
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(ScheduleTexts.matchTime(match), key: const Key('share-match-time'), style: muted),
                            if (showVenue)
                              Text(
                                match.venue?.name ?? ScheduleTexts.venueNone,
                                key: const Key('share-venue'),
                                style: muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  child,
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      ShareImageTexts.brand,
                      key: const Key('share-brand'),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 팀 배치 공유 이미지 (스프린트 03 6-1, S3-12).
///
/// 팀 블록(조끼 색 배경 + 이름 가나다순, 게스트 상자) + 교체 블록. 화면의 배치 보기와 같은 블록을 쓰고,
/// 내 이름 강조는 하지 않는다. 실력·포지션·GK 표시 없음 (배치에 없음, Q-075 5·6번).
class LineupShareImage extends StatelessWidget {
  const LineupShareImage({
    required this.team,
    required this.match,
    required this.lineup,
    required this.nameOf,
    super.key,
  });

  final TeamSummary team;
  final TeamMatch match;

  /// 확정된 배치 (버튼은 확정 배치에서만 보인다, Entitlements.canShareLineupImage)
  final Lineup lineup;
  final String Function(LineupPerson) nameOf;

  @override
  Widget build(BuildContext context) => ShareImageFrame(
    key: const Key('share-lineup-image'),
    team: team,
    match: match,
    title: ShareImageTexts.lineupTitle,
    showVenue: true,
    child: LineupBlocksView(lineup: lineup, nameOf: nameOf),
  );
}

/// POM·오늘의 골 결과 공유 이미지 (스프린트 03 6-2, S3-12).
///
/// 항목별 1위 이름(공동이면 모두, [winners] 는 이미 떠난 사람을 뺀 이름 가나다순). 없으면 "결과 없음".
/// 득표수·순위 없음.
class AwardResultShareImage extends StatelessWidget {
  const AwardResultShareImage({
    required this.team,
    required this.match,
    required this.winners,
    super.key,
  });

  final TeamSummary team;
  final TeamMatch match;

  /// 넣을 항목 → 1위 이름 (항목 순서대로 그린다)
  final Map<AwardCategory, List<String>> winners;

  @override
  Widget build(BuildContext context) {
    return ShareImageFrame(
      key: const Key('share-result-image'),
      team: team,
      match: match,
      title: ShareImageTexts.resultTitle,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in AwardCategory.values)
                if (winners[c] case final names?)
                  Container(
                    key: Key('share-result-${c.code}'),
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      border: Border.all(color: AppColors.of(context).cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.emoji_events_outlined, size: 20, color: AppColors.of(context).accent),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              AwardTexts.category(c),
                              style: theme.textTheme.titleSmall?.copyWith(color: AppColors.of(context).accent, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (names.isEmpty)
                          Text(AwardTexts.noResult, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant))
                        else
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final n in names)
                                Text(n, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
