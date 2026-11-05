import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/core/theme/app_theme.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

import '../support/fakes.dart';

void main() {
  test('공통 테마: Material 3, 같은 주색에서 밝은·어두운 모드', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.useMaterial3, isTrue);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(light.textTheme.bodyLarge?.fontSize, 16);
    expect(light.filledButtonTheme.style?.minimumSize?.resolve({}), const Size(64, AppSpacing.buttonHeight));
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('테마를 입힌 주요 화면이 오류 없이 그려진다 (${mode.name})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> pump(TestServices t) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: TeamHomeScreen(
              key: ObjectKey(t),
              services: t.services,
              userId: 'me',
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 빈 화면 안내
      await pump(TestServices());
      expect(find.text(TeamTexts.noTeamTitle), findsOneWidget);

      // 팀 화면 세 탭
      final t = TestServices(
        teams: [team('a', '코코FC', TeamRole.owner)],
        members: {
          'a': const [MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나')],
        },
      );
      await pump(t);
      for (final tab in [TeamTexts.tabAdmin, TeamTexts.tabMy, TeamTexts.tabMembers]) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
