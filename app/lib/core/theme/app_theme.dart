import 'package:flutter/material.dart';

import 'app_colors.dart';

export 'app_colors.dart';

/// 앱 전체 모양 (Q-079 1·2번 디자인 개편, decisions.md 2026-11-10: "고급스럽고 깔끔하고 편하게").
///
/// - 색은 [AppPalette] 토큰만 쓴다(짙은 숲색 초록 주 색, 따뜻한 흰 배경, 금색은 POM·1위만).
/// - 카드형 목록: 흰 카드 면 + 얇은 테두리, 그림자 없음. 모서리·간격은 [AppSpacing] 한 곳에서.
/// - 누르는 곳은 48dp 이상 ([AppSpacing.minTouch]). 주요 버튼 52dp.
/// - 글자 위계: 화면 제목 22 → 묶음 제목 17 → 줄 제목 16 → 본문 15 → 보조 13.
/// - 흔한 사용 방식(아래 탭, 위쪽 필터 칩, 큰 버튼)까지만 참고하고 다른 서비스의 색·배치·아이콘·문구는 따라 하지 않는다.
abstract final class AppTheme {
  /// 주 색. 바꾸려면 [AppPalette] 를 고친다.
  static const seed = AppPalette.lightPrimary;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = AppPalette.scheme(brightness);
    final extra = brightness == Brightness.light ? AppColors.light : AppColors.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final text = _textTheme(base.textTheme, scheme);
    const radius = BorderRadius.all(Radius.circular(AppSpacing.radius));
    const buttonShape = RoundedRectangleBorder(borderRadius: radius);
    const minTouch = Size(AppSpacing.minTouch, AppSpacing.minTouch);

    return base.copyWith(
      extensions: [extra],
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: extra.cardBorder)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        minVerticalPadding: AppSpacing.sm,
        minTileHeight: AppSpacing.minTouch + AppSpacing.sm,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: const OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: buttonShape,
          elevation: 0,
          textStyle: text.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: buttonShape,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.titleSmall,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: buttonShape,
          elevation: 0,
          textStyle: text.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: minTouch,
          shape: buttonShape,
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minTouch)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouch),
          shape: buttonShape,
          backgroundColor: scheme.surfaceContainerLowest,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        elevation: 0,
        pressElevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        highlightElevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppSpacing.lg))),
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppSpacing.xl))),
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        dividerColor: scheme.outlineVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      switchTheme: base.switchTheme,
    );
  }

  static TextTheme _textTheme(TextTheme t, ColorScheme scheme) => t
      .copyWith(
        headlineSmall: t.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3),
        titleLarge: t.titleLarge?.copyWith(fontSize: 21, fontWeight: FontWeight.w700, height: 1.3),
        titleMedium: t.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
        titleSmall: t.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
        bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.4),
        labelLarge: t.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        labelMedium: t.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
        labelSmall: t.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
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
  static const radius = 14.0;

  /// 작은 표시(배지) 모서리
  static const badgeRadius = 6.0;

  /// 주요 버튼 높이
  static const buttonHeight = 52.0;

  /// 누르는 곳 최소 크기 (48dp)
  static const minTouch = 48.0;

  /// 스크롤 화면 바깥 여백 (아래는 버튼·내비게이션과 겹치지 않게 조금 더)
  static const page = EdgeInsets.fromLTRB(gutter, lg, gutter, xxl);

  /// 입력 항목 사이
  static const fieldGap = SizedBox(height: lg);

  /// 묶음(섹션) 사이
  static const sectionGap = SizedBox(height: xl);

  /// 카드 목록의 카드 사이
  static const cardGap = SizedBox(height: md);
}
