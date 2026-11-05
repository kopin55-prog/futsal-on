import 'package:flutter/material.dart';

/// 앱 전체 모양 (kopn 지시 "간결하고 깔끔하게", decisions.md 2026-11-05).
///
/// - Material 3, 색은 주색 하나(짙은 초록)와 그 톤만 쓴다. 강조는 주색, 나머지는 무채색 표면.
/// - 글자는 본문 16 기준으로 조금 크게, 줄 간격 넉넉하게.
/// - 카드·목록·입력칸·버튼의 모서리와 여백을 한 곳에서 정한다. 화면은 [AppSpacing] 값만 쓴다.
/// 다른 서비스의 디자인을 따라 하지 않는다 (CLAUDE.md 금지 사항).
abstract final class AppTheme {
  /// 주색 (씨앗 색). 바꾸려면 여기만 고친다.
  static const seed = Color(0xFF2E6B4F);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = _textTheme(base.textTheme);
    const radius = BorderRadius.all(Radius.circular(AppSpacing.radius));
    const buttonShape = RoundedRectangleBorder(borderRadius: radius);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: AppSpacing.sm,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: buttonShape,
          textStyle: text.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: buttonShape),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm))),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppSpacing.xl))),
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        height: 68,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      switchTheme: base.switchTheme,
    );
  }

  static TextTheme _textTheme(TextTheme t) => t.copyWith(
    titleLarge: t.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
    titleMedium: t.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
    bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.4),
  );
}

/// 간격·모서리 상수. 화면은 숫자 대신 이 값을 쓴다.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// 화면 좌우 여백
  static const gutter = 20.0;

  /// 카드·입력칸·버튼 모서리
  static const radius = 12.0;

  /// 주요 버튼 높이
  static const buttonHeight = 52.0;

  /// 스크롤 화면 바깥 여백 (아래는 버튼·내비게이션과 겹치지 않게 조금 더)
  static const page = EdgeInsets.fromLTRB(gutter, lg, gutter, xxl);

  /// 입력 항목 사이
  static const fieldGap = SizedBox(height: lg);

  /// 묶음(섹션) 사이
  static const sectionGap = SizedBox(height: xl);
}
