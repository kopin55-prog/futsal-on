import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/domain/region.dart';
import '../../../shared/presentation/region_picker.dart';
import 'team_texts.dart';

/// 팀 만들기·팀 정보 수정의 활동 지역 칸 (Q-079 4번). 제목 + 시·도/시·군·구 고르기 + 안내 한 줄.
class TeamRegionField extends StatelessWidget {
  const TeamRegionField({required this.value, required this.onChanged, this.enabled = true, super.key});

  final Region? value;
  final ValueChanged<Region?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TeamTexts.region, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        RegionPicker(
          keyPrefix: 'team-region',
          value: value,
          onChanged: onChanged,
          enabled: enabled,
          emptyLabel: TeamTexts.regionNone,
          sidoLabel: TeamTexts.regionSido,
          sigunguLabel: TeamTexts.regionSigungu,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          TeamTexts.regionAutoNote,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
