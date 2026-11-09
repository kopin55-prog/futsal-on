import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../schedule/presentation/guest_badge.dart';
import '../domain/bib_color.dart';
import '../domain/lineup_board.dart';
import '../domain/lineup_models.dart';
import 'lineup_texts.dart';

/// 조끼 색 → 팀 블록 배경색. 밝은·어두운 모드와 상관없이 같은 색(조끼 색 그대로)이고, 글자색은 배경 밝기로 고른다.
/// 노조끼는 색이 없으므로 테마 바탕색 + 테두리.
({Color background, Color foreground, Color? border}) bibColorStyle(BibColor c, ColorScheme scheme) {
  final Color? fixed = switch (c) {
    BibColor.red => const Color(0xFFD93A3A),
    BibColor.blue => const Color(0xFF2F6FDB),
    BibColor.yellow => const Color(0xFFF2C94C),
    BibColor.green => const Color(0xFF3E9B5B),
    BibColor.orange => const Color(0xFFF08A2C),
    BibColor.navy => const Color(0xFF233A6B),
    BibColor.purple => const Color(0xFF7D4CC2),
    BibColor.pink => const Color(0xFFF08DB5),
    BibColor.black => const Color(0xFF222222),
    BibColor.white => const Color(0xFFFAFAFA),
    BibColor.noBib => null,
  };
  if (fixed == null) {
    return (background: scheme.surfaceContainerHighest, foreground: scheme.onSurface, border: scheme.outline);
  }
  final dark = ThemeData.estimateBrightnessForColor(fixed) == Brightness.dark;
  return (
    background: fixed,
    foreground: dark ? Colors.white : const Color(0xFF1B1B1B),
    border: c == BibColor.white ? scheme.outlineVariant : null,
  );
}

/// 조끼 색 동그라미 (색 고르기 목록용).
class BibSwatch extends StatelessWidget {
  const BibSwatch(this.color, {this.size = 20, super.key});

  final BibColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = bibColorStyle(color, Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.background,
        shape: BoxShape.circle,
        border: Border.all(color: style.border ?? style.background),
      ),
    );
  }
}

/// 사람 이름 한 칸: 이름만 (게스트는 뒤에 "게스트" 상자). 실력·포지션·GK 표시 없음.
class LineupNameChip extends StatelessWidget {
  const LineupNameChip({
    required this.name,
    required this.isGuest,
    this.highlight = false,
    this.foreground,
    super.key,
  });

  final String name;
  final bool isGuest;

  /// 내 이름 강조 (팀원 화면).
  final bool highlight;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: highlight ? theme.colorScheme.onPrimary : (foreground ?? theme.colorScheme.onSurface),
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? theme.colorScheme.primary : theme.colorScheme.surface.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: (foreground ?? theme.colorScheme.outline).withValues(alpha: 0.35)),
      ),
      child: isGuest ? GuestNameLabel(name, style: style) : Text(name, style: style),
    );
  }
}

/// 팀 블록 하나의 틀 (배경 = 조끼 색). 내용은 [children].
class SquadBlockFrame extends StatelessWidget {
  const SquadBlockFrame({
    required this.title,
    required this.children,
    this.color,
    this.trailing,
    this.highlighted = false,
    super.key,
  });

  /// null 이면 교체 블록 (테마 색).
  final BibColor? color;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  /// 끌어 놓을 수 있을 때 테두리 강조.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color;
    final style = c == null
        ? (background: scheme.surfaceContainerLow, foreground: scheme.onSurface, border: scheme.outlineVariant)
        : bibColorStyle(c, scheme);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.lg),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: highlighted
            ? Border.all(color: scheme.primary, width: 3)
            : (style.border == null ? null : Border.all(color: style.border!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(color: style.foreground, fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
              if (trailing == null) const SizedBox(height: 40),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (children.isEmpty)
            Text(LineupTexts.nobody, style: theme.textTheme.bodySmall?.copyWith(color: style.foreground))
          else
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: children),
        ],
      ),
    );
  }
}

/// 배치 보기 (읽기 전용): 팀 블록(조끼 색 + 이름 가나다순, 게스트 상자) + 교체 블록.
/// 팀원 화면과 운영진의 일정 상세 요약에 쓴다.
class LineupBlocksView extends StatelessWidget {
  const LineupBlocksView({
    required this.lineup,
    required this.nameOf,
    this.highlightUserId,
    super.key,
  });

  final Lineup lineup;
  final String Function(LineupPerson) nameOf;
  final String? highlightUserId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(LineupPerson p, Color? fg) => LineupNameChip(
      key: Key('lineup-person-${p.key}'),
      name: nameOf(p),
      isGuest: p.isGuest,
      highlight: p.userId != null && p.userId == highlightUserId,
      foreground: fg,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final q in lineup.squads)
          SquadBlockFrame(
            key: Key('lineup-squad-${q.squadNo}'),
            color: q.bibColor,
            title: LineupTexts.squadTitle(q.bibColor, q.people.length),
            children: [
              for (final p in sortByName(q.people, nameOf)) chip(p, bibColorStyle(q.bibColor, scheme).foreground),
            ],
          ),
        if (lineup.bench.isNotEmpty)
          SquadBlockFrame(
            key: const Key('lineup-bench'),
            title: LineupTexts.benchTitle(lineup.bench.length),
            children: [for (final p in sortByName(lineup.bench, nameOf)) chip(p, null)],
          ),
      ],
    );
  }
}
