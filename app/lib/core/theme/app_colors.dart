import 'package:flutter/material.dart';

/// 색 토큰 (Q-079 1·2번, decisions.md 2026-11-10 디자인 개편). 앱의 모든 색은 여기서만 정한다.
///
/// - 주 색: 짙은 숲색 초록 #1F4D3A. 어두운 모드는 같은 초록을 밝게 조정해 대비를 확보한다.
/// - 배경: 살짝 따뜻한 흰색. 카드는 그 위의 흰 면 + 얇은 테두리(그림자 최소).
/// - 강조: 차분한 금색. **POM·1위 표시에만** 쓴다([AppColors.accent]).
/// - 본문 글자는 바탕·카드 면 어디서나 대비 4.5:1 이상 (test/core/theme_contrast_test.dart 가 확인).
/// 다른 서비스의 색을 따라 하지 않는다 (CLAUDE.md 금지 사항).
abstract final class AppPalette {
  // ---- 밝은 모드 ----
  static const lightPrimary = Color(0xFF1F4D3A);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFD3E6DA);
  static const lightOnPrimaryContainer = Color(0xFF0E2A1E);
  static const lightSecondary = Color(0xFF4D5F55);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFE2EAE4);
  static const lightOnSecondaryContainer = Color(0xFF16241C);
  static const lightBackground = Color(0xFFFAF8F3); // 따뜻한 흰색
  static const lightSurfaceLowest = Color(0xFFFFFFFF); // 카드 면
  static const lightSurfaceLow = Color(0xFFF6F3EC);
  static const lightSurfaceContainer = Color(0xFFF2EFE8);
  static const lightSurfaceHigh = Color(0xFFECE8DF);
  static const lightSurfaceHighest = Color(0xFFE5E1D7);
  static const lightOnSurface = Color(0xFF1B1F1C);
  static const lightOnSurfaceVariant = Color(0xFF4A524D);
  static const lightOutline = Color(0xFF757C77);
  static const lightOutlineVariant = Color(0xFFDDD8CD);
  static const lightError = Color(0xFFB3261E);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFF9DEDC);
  static const lightOnErrorContainer = Color(0xFF410E0B);
  static const lightAccent = Color(0xFF7A5C14); // 차분한 금색 (글자·아이콘)
  static const lightAccentContainer = Color(0xFFF4E7C3);
  static const lightOnAccentContainer = Color(0xFF3A2B05);

  // ---- 어두운 모드 (초록을 밝게) ----
  static const darkPrimary = Color(0xFF8CCFAE);
  static const darkOnPrimary = Color(0xFF00382A);
  static const darkPrimaryContainer = Color(0xFF2A5E48);
  static const darkOnPrimaryContainer = Color(0xFFCDEEDC);
  static const darkSecondary = Color(0xFFB3C9BC);
  static const darkOnSecondary = Color(0xFF1F3329);
  static const darkSecondaryContainer = Color(0xFF33443B);
  static const darkOnSecondaryContainer = Color(0xFFD2E6D9);
  static const darkBackground = Color(0xFF111513);
  static const darkSurfaceLowest = Color(0xFF191D1B); // 카드 면
  static const darkSurfaceLow = Color(0xFF1B1F1D);
  static const darkSurfaceContainer = Color(0xFF1D2220);
  static const darkSurfaceHigh = Color(0xFF262B28);
  static const darkSurfaceHighest = Color(0xFF313633);
  static const darkOnSurface = Color(0xFFE3E6E2);
  static const darkOnSurfaceVariant = Color(0xFFBDC5BF);
  static const darkOutline = Color(0xFF8A938D);
  static const darkOutlineVariant = Color(0xFF353B37);
  static const darkError = Color(0xFFF2B8B5);
  static const darkOnError = Color(0xFF601410);
  static const darkErrorContainer = Color(0xFF8C1D18);
  static const darkOnErrorContainer = Color(0xFFF9DEDC);
  static const darkAccent = Color(0xFFE2C273);
  static const darkAccentContainer = Color(0xFF4A3B12);
  static const darkOnAccentContainer = Color(0xFFF6E7BC);

  static ColorScheme scheme(Brightness b) {
    final light = b == Brightness.light;
    return ColorScheme(
      brightness: b,
      primary: light ? lightPrimary : darkPrimary,
      onPrimary: light ? lightOnPrimary : darkOnPrimary,
      primaryContainer: light ? lightPrimaryContainer : darkPrimaryContainer,
      onPrimaryContainer: light ? lightOnPrimaryContainer : darkOnPrimaryContainer,
      secondary: light ? lightSecondary : darkSecondary,
      onSecondary: light ? lightOnSecondary : darkOnSecondary,
      secondaryContainer: light ? lightSecondaryContainer : darkSecondaryContainer,
      onSecondaryContainer: light ? lightOnSecondaryContainer : darkOnSecondaryContainer,
      // 3차 색은 따로 쓰지 않는다 (강조는 금색 토큰, POM·1위만)
      tertiary: light ? lightSecondary : darkSecondary,
      onTertiary: light ? lightOnSecondary : darkOnSecondary,
      tertiaryContainer: light ? lightSecondaryContainer : darkSecondaryContainer,
      onTertiaryContainer: light ? lightOnSecondaryContainer : darkOnSecondaryContainer,
      error: light ? lightError : darkError,
      onError: light ? lightOnError : darkOnError,
      errorContainer: light ? lightErrorContainer : darkErrorContainer,
      onErrorContainer: light ? lightOnErrorContainer : darkOnErrorContainer,
      surface: light ? lightBackground : darkBackground,
      onSurface: light ? lightOnSurface : darkOnSurface,
      onSurfaceVariant: light ? lightOnSurfaceVariant : darkOnSurfaceVariant,
      surfaceContainerLowest: light ? lightSurfaceLowest : darkSurfaceLowest,
      surfaceContainerLow: light ? lightSurfaceLow : darkSurfaceLow,
      surfaceContainer: light ? lightSurfaceContainer : darkSurfaceContainer,
      surfaceContainerHigh: light ? lightSurfaceHigh : darkSurfaceHigh,
      surfaceContainerHighest: light ? lightSurfaceHighest : darkSurfaceHighest,
      outline: light ? lightOutline : darkOutline,
      outlineVariant: light ? lightOutlineVariant : darkOutlineVariant,
      inverseSurface: light ? darkSurfaceHigh : lightSurfaceContainer,
      onInverseSurface: light ? darkOnSurface : lightOnSurface,
      inversePrimary: light ? darkPrimary : lightPrimary,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
    );
  }
}

/// 테마에 붙는 추가 색 (ColorScheme 에 없는 것). 화면은 `AppColors.of(context)` 로 읽는다.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.cardBorder,
  });

  static const light = AppColors(
    accent: AppPalette.lightAccent,
    accentContainer: AppPalette.lightAccentContainer,
    onAccentContainer: AppPalette.lightOnAccentContainer,
    cardBorder: AppPalette.lightOutlineVariant,
  );

  static const dark = AppColors(
    accent: AppPalette.darkAccent,
    accentContainer: AppPalette.darkAccentContainer,
    onAccentContainer: AppPalette.darkOnAccentContainer,
    cardBorder: AppPalette.darkOutlineVariant,
  );

  /// 금색 강조 (POM·1위 아이콘·글자에만)
  final Color accent;

  /// 금색 바탕 (1위 이름 상자)
  final Color accentContainer;
  final Color onAccentContainer;

  /// 카드 테두리
  final Color cardBorder;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppColors copyWith({Color? accent, Color? accentContainer, Color? onAccentContainer, Color? cardBorder}) =>
      AppColors(
        accent: accent ?? this.accent,
        accentContainer: accentContainer ?? this.accentContainer,
        onAccentContainer: onAccentContainer ?? this.onAccentContainer,
        cardBorder: cardBorder ?? this.cardBorder,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(onAccentContainer, other.onAccentContainer, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }
}

/// 조끼 색 (팀 배치 블록). 실제 조끼 색을 나타내므로 밝은·어두운 모드와 상관없이 같다.
abstract final class BibPalette {
  static const red = Color(0xFFD93A3A);
  static const blue = Color(0xFF2F6FDB);
  static const yellow = Color(0xFFF2C94C);
  static const green = Color(0xFF3E9B5B);
  static const orange = Color(0xFFF08A2C);
  static const navy = Color(0xFF233A6B);
  static const purple = Color(0xFF7D4CC2);
  static const pink = Color(0xFFF08DB5);
  static const black = Color(0xFF222222);
  static const white = Color(0xFFFAFAFA);

  /// 조끼 위 글자 (어두운 조끼 / 밝은 조끼)
  static const onDark = Color(0xFFFFFFFF);
  static const onLight = Color(0xFF1B1B1B);
}
