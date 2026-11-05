import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 묶음 제목 (예: "팀 설정", "가입 신청"). 화면마다 같은 크기·여백.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 목록 묶음 카드. 안의 줄 사이에 얇은 선을 넣는다.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.children, this.dividers = true, super.key});

  final List<Widget> children;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (dividers && i > 0) items.add(const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg));
      items.add(children[i]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
      ),
    );
  }
}

/// 빈 화면 안내 (아이콘 + 한 줄 + 선택 버튼들).
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actions = const [],
    this.compact = false,
    super.key,
  });

  final String message;
  final IconData icon;
  final List<Widget> actions;

  /// 목록 안의 작은 안내 (아이콘 작게, 여백 적게)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? AppSpacing.lg : AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: compact ? 28 : 48, color: muted.withValues(alpha: 0.6)),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: (compact ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)?.copyWith(color: muted),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              actions[i],
            ],
          ],
        ],
      ),
    );
  }
}

/// 오류 문구 한 줄 (빨간 글자).
class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
    );
  }
}

/// 저장·만들기 버튼 (처리 중이면 작은 원).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({required this.label, required this.onPressed, this.busy = false, super.key});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}
