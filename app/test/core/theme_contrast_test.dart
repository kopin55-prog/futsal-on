import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/core/theme/app_theme.dart';
import 'package:futsal_on/features/membership/presentation/team_find_screen.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/domain/region.dart';
import 'package:futsal_on/shared/presentation/list_controls.dart';

import '../support/fakes.dart';

/// WCAG 상대 휘도 대비.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = lum(a);
  final y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('색 토큰 (Q-079 1번)', () {
    test('주 색은 짙은 숲색 초록, 배경은 따뜻한 흰색', () {
      final light = AppTheme.light().colorScheme;
      expect(light.primary, const Color(0xFF1F4D3A));
      expect(light.surface, AppPalette.lightBackground);
      // 따뜻한 흰색: 빨강 ≥ 초록 ≥ 파랑, 거의 흰색
      final bg = light.surface;
      expect(bg.r >= bg.g && bg.g >= bg.b, isTrue);
      expect(bg.computeLuminance(), greaterThan(0.9));
      // 어두운 모드는 같은 초록을 밝게
      final dark = AppTheme.dark().colorScheme;
      expect(HSLColor.fromColor(dark.primary).lightness, greaterThan(HSLColor.fromColor(light.primary).lightness));
      expect((HSLColor.fromColor(dark.primary).hue - HSLColor.fromColor(light.primary).hue).abs(), lessThan(15));
    });

    for (final b in Brightness.values) {
      test('본문 글자 대비 4.5:1 이상 (${b.name})', () {
        final theme = b == Brightness.light ? AppTheme.light() : AppTheme.dark();
        final s = theme.colorScheme;
        final extra = theme.extension<AppColors>()!;
        final surfaces = {
          'surface': s.surface,
          'card': s.surfaceContainerLowest,
          'low': s.surfaceContainerLow,
          'container': s.surfaceContainer,
          'high': s.surfaceContainerHigh,
        };
        for (final e in surfaces.entries) {
          for (final fg in {
            'onSurface': s.onSurface,
            'onSurfaceVariant': s.onSurfaceVariant,
            'primary': s.primary,
            'error': s.error,
            'accent': extra.accent,
          }.entries) {
            expect(_contrast(fg.value, e.value), greaterThanOrEqualTo(4.5), reason: '${fg.key} on ${e.key}');
          }
        }
        for (final pair in [
          (s.onPrimary, s.primary, 'onPrimary'),
          (s.onPrimaryContainer, s.primaryContainer, 'onPrimaryContainer'),
          (s.onSecondaryContainer, s.secondaryContainer, 'onSecondaryContainer'),
          (s.onErrorContainer, s.errorContainer, 'onErrorContainer'),
          (s.onInverseSurface, s.inverseSurface, 'snackbar'),
          (extra.onAccentContainer, extra.accentContainer, 'onAccentContainer'),
        ]) {
          expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5), reason: pair.$3);
        }
      });
    }

    test('카드는 그림자 없이 얇은 테두리, 누르는 곳 48dp 이상', () {
      final t = AppTheme.light();
      expect(t.cardTheme.elevation, 0);
      expect((t.cardTheme.shape! as RoundedRectangleBorder).side.width, greaterThan(0));
      expect(t.textButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(t.iconButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(t.filledButtonTheme.style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(t.materialTapTargetSize, MaterialTapTargetSize.padded);
    });
  });

  group('화면 지침 검사 (글자 대비·누르기 영역)', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('팀 찾기 (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final t = TestServices();
        t.membership.searchResults = const [
          TeamSearchResult(
            teamCode: 'K7FC3M',
            name: '코코FC',
            logoText: '코코',
            memberCount: 8,
            isRecruiting: true,
            region: Region('서울', '성동구'),
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: TeamFindScreen(membership: t.membership),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('팀 이름'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('find-input')), '코코');
        await tester.tap(find.byKey(const Key('find-submit')));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('팀 홈 탭 (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final t = TestServices(
          teams: [team('a', '코코FC', TeamRole.owner)],
          members: {
            'a': const [
              MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
              MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '일번', bio: '반가워요'),
            ],
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(TeamTexts.tabMembers));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('공용 목록 위젯', () {
    testWidgets('검색 칸: 지우기 버튼은 글자가 있을 때만, 누르면 비운다', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: AppSearchField(hintText: '이름', onChanged: seen.add)),
        ),
      );
      expect(find.byKey(const Key('search-clear')), findsNothing);
      await tester.enterText(find.byType(TextField), '일번');
      await tester.pump();
      expect(find.byKey(const Key('search-clear')), findsOneWidget);
      await tester.tap(find.byKey(const Key('search-clear')));
      await tester.pump();
      expect(seen, ['일번', '']);
      expect(find.byKey(const Key('search-clear')), findsNothing);
    });

    testWidgets('필터 칩: 하나만 고르고 숫자를 붙인다', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => FilterChipBar<int>(
                options: const [FilterOption(0, '전체'), FilterOption(1, '부상', count: 2)],
                selected: selected,
                onSelected: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      );
      expect(find.text('부상 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filter-1')));
      await tester.pump();
      expect(selected, 1);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('filter-1'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('filter-0'))).selected, isFalse);
      expect(tester.getSize(find.byKey(const Key('filter-1'))).height, greaterThanOrEqualTo(48));
    });
  });
}
