import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/config/app_config.dart';
import 'package:futsal_on/features/auth/data/auth_repository.dart';
import 'package:futsal_on/features/auth/presentation/auth_texts.dart';
import 'package:futsal_on/features/auth/presentation/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_flow_test.dart' show FakeAuthRepository;

/// 스프린트 04 7-2·7-3: 애플 버튼은 iOS + 설정 켬일 때만, 안드로이드 화면은 그대로.
void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    required TargetPlatform platform,
    bool appleSignInEnabled = false,
    AuthRepository? auth,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authRepository: auth ?? FakeAuthRepository(),
          appleSignInEnabled: appleSignInEnabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('애플 로그인 버튼 (7-3)', () {
    testWidgets('iOS 라도 설정이 꺼져 있으면(기본) 안 보인다', (tester) async {
      await pumpLogin(tester, platform: TargetPlatform.iOS);
      expect(find.byKey(const Key('login-kakao')), findsOneWidget);
      expect(find.byKey(const Key('login-google')), findsOneWidget);
      expect(find.byKey(const Key('login-apple')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS 이고 설정을 켜면 보인다', (tester) async {
      await pumpLogin(
        tester,
        platform: TargetPlatform.iOS,
        appleSignInEnabled: true,
      );
      expect(find.byKey(const Key('login-apple')), findsOneWidget);
      expect(find.text(AuthTempTexts.loginWithApple), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('안드로이드는 설정을 켜도 카카오·구글만 (Q-050)', (tester) async {
      await pumpLogin(
        tester,
        platform: TargetPlatform.android,
        appleSignInEnabled: true,
      );
      expect(find.byKey(const Key('login-kakao')), findsOneWidget);
      expect(find.byKey(const Key('login-google')), findsOneWidget);
      expect(find.byKey(const Key('login-apple')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS 구글 로그인 준비 전(notSupported)이면 준비 중 안내', (tester) async {
      final auth = FakeAuthRepository()
        ..nextFailure = const SignInFailure(SignInFailureReason.notSupported);
      await pumpLogin(tester, platform: TargetPlatform.iOS, auth: auth);
      await tester.tap(find.byKey(const Key('login-google')));
      await tester.pumpAndSettle();
      expect(find.text(AuthTempTexts.loginNotSupported), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('설정 값 (7-2·7-3)', () {
    test('iOS 전용 값은 비어도 필수 누락이 아니고, 애플 로그인은 기본 꺼짐', () {
      const config = AppConfig(
        supabaseUrl: 'u',
        supabaseAnonKey: 'a',
        kakaoNativeAppKey: 'k',
        googleWebClientId: 'g',
      );
      expect(config.isComplete, isTrue);
      expect(config.googleIosClientId, isEmpty);
      expect(config.appleSignInEnabled, isFalse);
      expect(const AppConfig.fromEnvironment().appleSignInEnabled, isFalse);
    });
  });

  group('SupabaseAuthRepository 기기별 동작', () {
    SupabaseAuthRepository repo(TargetPlatform platform, {String iosId = ''}) =>
        SupabaseAuthRepository(
          client: SupabaseClient('http://localhost:54321', 'test-anon-key'),
          googleServerClientId: 'web-client',
          googleIosClientId: iosId,
          platform: platform,
        );

    test('iOS 구글 클라이언트 ID 가 비면 구글 SDK 를 부르지 않고 notSupported', () async {
      await expectLater(
        repo(TargetPlatform.iOS).signIn(SignInMethod.google),
        throwsA(
          isA<SignInFailure>().having(
            (e) => e.reason,
            'reason',
            SignInFailureReason.notSupported,
          ),
        ),
      );
    });

    test('안드로이드에서 애플 로그인은 notSupported', () async {
      await expectLater(
        repo(TargetPlatform.android).signIn(SignInMethod.apple),
        throwsA(
          isA<SignInFailure>().having(
            (e) => e.reason,
            'reason',
            SignInFailureReason.notSupported,
          ),
        ),
      );
    });
  });
}
