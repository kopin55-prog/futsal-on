import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'schedule_texts.dart';

/// 게스트 이름 뒤에 붙는 작은 색 상자 "게스트" (Q-073 2번: 모든 화면에서 같은 모양).
class GuestBadge extends StatelessWidget {
  const GuestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: Text(
        ScheduleTexts.guest,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}

/// 게스트 이름 + [GuestBadge]. 게스트를 이름으로 보여주는 곳은 모두 이것을 쓴다.
class GuestNameLabel extends StatelessWidget {
  const GuestNameLabel(this.name, {this.style, super.key});

  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        const GuestBadge(),
      ],
    );
  }
}
