import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 여러 명 골라 한 번에 처리하는 화면의 공용 조작 줄 (Q-079 3번 b·c: 실력 등급 한 번에 지정, 가입 신청 한 번에 승인·거절).
///
/// - 왼쪽: "N명 선택" (문구는 부르는 쪽이 넘긴다).
/// - 가운데: 모두 고르기 / 선택 해제.
/// - 아래: 처리 버튼들 ([actions]). 고른 사람이 없으면 버튼은 부르는 쪽이 끈다.
/// 색은 테마 토큰만 쓴다 (이 파일에 화면 문구 없음).
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    required this.countLabel,
    required this.selectAllLabel,
    required this.clearLabel,
    required this.onSelectAll,
    required this.onClear,
    required this.actions,
    this.keyPrefix = 'selection',
    super.key,
  });

  /// 예: "3명 선택"
  final String countLabel;
  final String selectAllLabel;
  final String clearLabel;

  /// null 이면 "모두 고르기" 버튼이 꺼진다 (이미 다 골랐을 때).
  final VoidCallback? onSelectAll;

  /// null 이면 "선택 해제" 버튼이 꺼진다 (고른 사람이 없을 때).
  final VoidCallback? onClear;
  final List<Widget> actions;

  /// 키: `<prefix>-count`, `<prefix>-all`, `<prefix>-clear`
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      countLabel,
                      key: Key('$keyPrefix-count'),
                      style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  TextButton(
                    key: Key('$keyPrefix-all'),
                    onPressed: onSelectAll,
                    child: Text(selectAllLabel),
                  ),
                  TextButton(
                    key: Key('$keyPrefix-clear'),
                    onPressed: onClear,
                    child: Text(clearLabel),
                  ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
