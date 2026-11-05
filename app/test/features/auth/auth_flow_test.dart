import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/auth/data/auth_repository.dart';
import 'package:futsal_on/features/auth/domain/signup_consent.dart';
import 'package:futsal_on/features/auth/presentation/auth_gate.dart';
import 'package:futsal_on/features/auth/presentation/auth_texts.dart';
import 'package:futsal_on/features/profile/data/profile_repository.dart';
import 'package:futsal_on/features/profile/domain/profile_validation.dart';
import 'package:futsal_on/features/profile/presentation/profile_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/position.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.currentUserId});

  final _controller = StreamController<String?>.broadcast();
  final List<SignInMethod> signInCalls = [];
  SignInFailure? nextFailure;

  @override
  String? currentUserId;

  @override
  Stream<String?> get userIdChanges => _controller.stream;

  @override
  Future<void> signIn(SignInMethod method) async {
    signInCalls.add(method);
    final failure = nextFailure;
    if (failure != null) throw failure;
    currentUserId = 'user-1';
    _controller.add(currentUserId);
  }

  @override
  Future<void> signOut() async {
    currentUserId = null;
    _controller.add(null);
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.hasProfile = false});

  bool hasProfile;
  ProfileInput? createdInput;
  SignupConsent? createdConsent;
  ServerFailure? nextFailure;

  @override
  Future<bool> hasOwnProfile() async => hasProfile;

  @override
  Future<void> createProfile(ProfileInput input, SignupConsent consent) async {
    final failure = nextFailure;
    if (failure != null) throw failure;
    createdInput = input.normalized();
    createdConsent = consent;
    hasProfile = true;
  }

  @override
  Future<OwnProfile> getOwnProfile() => throw UnimplementedError();

  @override
  Future<void> updateOwnProfile(ProfileInput input) =>
      throw UnimplementedError();
}

Widget _app(AuthRepository auth, ProfileRepository profile) => MaterialApp(
  home: AuthGate(authRepository: auth, profileRepository: profile),
);

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('로그인 안 됨 → 로그인 화면 (안드로이드: 카카오·구글만, Q-050)', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      _app(FakeAuthRepository(), FakeProfileRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-kakao')), findsOneWidget);
    expect(find.byKey(const Key('login-google')), findsOneWidget);
    expect(find.byKey(const Key('login-apple')), findsNothing);
  });

  testWidgets('로그인 취소는 오류 문구를 띄우지 않는다', (tester) async {
    _tallScreen(tester);
    final auth = FakeAuthRepository()
      ..nextFailure = const SignInFailure(SignInFailureReason.cancelled);
    await tester.pumpWidget(_app(auth, FakeProfileRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-kakao')));
    await tester.pumpAndSettle();
    expect(auth.signInCalls, [SignInMethod.kakao]);
    expect(find.text(AuthTempTexts.loginFailed), findsNothing);
  });

  testWidgets('로그인 실패는 오류 문구', (tester) async {
    _tallScreen(tester);
    final auth = FakeAuthRepository()
      ..nextFailure = const SignInFailure(SignInFailureReason.failed);
    await tester.pumpWidget(_app(auth, FakeProfileRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-google')));
    await tester.pumpAndSettle();
    expect(find.text(AuthTempTexts.loginFailed), findsOneWidget);
  });

  testWidgets('프로필 있는 계정은 동의 없이 바로 홈 (Q-063)', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      _app(
        FakeAuthRepository(currentUserId: 'u'),
        FakeProfileRepository(hasProfile: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AuthTempTexts.homePlaceholder), findsOneWidget);
    expect(find.byKey(const Key('consent-all')), findsNothing);
  });

  testWidgets('첫 로그인 → 동의 → 프로필 → 홈', (tester) async {
    _tallScreen(tester);
    final profile = FakeProfileRepository();
    await tester.pumpWidget(_app(FakeAuthRepository(), profile));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login-kakao')));
    await tester.pumpAndSettle();

    // 동의 화면: 부상 정보 처음 해제, 다음 버튼 비활성
    CheckboxListTile tile(String key) =>
        tester.widget<CheckboxListTile>(find.byKey(Key(key)));
    FilledButton next() =>
        tester.widget<FilledButton>(find.byKey(const Key('consent-next')));
    expect(tile('consent-injury').value, isFalse);
    expect(next().onPressed, isNull);

    // 필수 3개 → 다음 가능, 전체 동의는 아님
    await _tapVisible(tester, find.byKey(const Key('consent-age14')));
    await _tapVisible(tester, find.byKey(const Key('consent-terms')));
    await _tapVisible(tester, find.byKey(const Key('consent-privacy')));
    expect(next().onPressed, isNotNull);
    expect(tile('consent-all').value, isFalse);

    // 전체 동의 → 부상 정보까지
    await _tapVisible(tester, find.byKey(const Key('consent-all')));
    expect(tile('consent-injury').value, isTrue);
    expect(tile('consent-all').value, isTrue);

    await _tapVisible(tester, find.byKey(const Key('consent-next')));

    // 프로필: 빈 이름 → 문서 문구
    await _tapVisible(tester, find.byKey(const Key('profile-submit')));
    expect(find.text('이름을 입력해주세요'), findsOneWidget);
    expect(profile.createdInput, isNull);

    await tester.enterText(find.byKey(const Key('profile-name')), '  철수  킴 ');
    await _tapVisible(
      tester,
      find.byKey(const Key('profile-position-forward')),
    );
    await _tapVisible(tester, find.byKey(const Key('profile-submit')));

    expect(profile.createdInput?.name, '철수 킴');
    expect(profile.createdInput?.positions, [Position.forward]);
    expect(
      profile.createdConsent,
      const SignupConsent(
        age14: true,
        terms: true,
        privacy: true,
        injuryInfo: true,
      ),
    );
    expect(find.text(AuthTempTexts.homePlaceholder), findsOneWidget);
  });

  testWidgets('전문 골키퍼: 골키퍼 자동 선택, 골키퍼 아닌 3개면 막고 안내 (Q-019, Q-035)', (
    tester,
  ) async {
    _tallScreen(tester);
    final profile = FakeProfileRepository();
    await tester.pumpWidget(
      _app(FakeAuthRepository(currentUserId: 'u'), profile),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('consent-all')));
    await _tapVisible(tester, find.byKey(const Key('consent-next')));

    bool selected(Position p) => tester
        .widget<FilterChip>(find.byKey(Key('profile-position-${p.name}')))
        .selected;
    bool dedicated() =>
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('profile-dedicated-gk')),
            )
            .value ??
        false;

    await _tapVisible(tester, find.byKey(const Key('profile-dedicated-gk')));
    expect(selected(Position.goalkeeper), isTrue);
    expect(dedicated(), isTrue);

    // 전문 골키퍼인 동안 골키퍼 칩은 잠김 (Q-067 16번)
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('profile-position-goalkeeper')))
          .onSelected,
      isNull,
    );
    // 전문 골키퍼를 풀어도 골키퍼 선택은 남는다 (Q-067 16번)
    await _tapVisible(tester, find.byKey(const Key('profile-dedicated-gk')));
    expect(dedicated(), isFalse);
    expect(selected(Position.goalkeeper), isTrue);
    // 이제 골키퍼를 직접 뺄 수 있다
    await _tapVisible(
      tester,
      find.byKey(const Key('profile-position-goalkeeper')),
    );
    expect(selected(Position.goalkeeper), isFalse);

    for (final p in [
      Position.defender,
      Position.midfielder,
      Position.forward,
    ]) {
      await _tapVisible(tester, find.byKey(Key('profile-position-${p.name}')));
    }
    await _tapVisible(tester, find.byKey(const Key('profile-dedicated-gk')));
    expect(dedicated(), isFalse);
    expect(selected(Position.goalkeeper), isFalse);
    expect(
      find.text(ProfileTexts.error(ProfileError.dedicatedGkNeedsFreeSlot)),
      findsOneWidget,
    );

    // 4번째 포지션은 선택되지 않고 안내 (Q-067 1번)
    await _tapVisible(tester, find.byKey(const Key('profile-position-winger')));
    expect(selected(Position.winger), isFalse);
    expect(find.text(ProfileTexts.maxPositionsReached), findsOneWidget);
  });

  testWidgets('서버가 이미 프로필이 있다고 하면 가입 완료로 본다', (tester) async {
    _tallScreen(tester);
    final profile = FakeProfileRepository()
      ..nextFailure = const ServerFailure(ServerErrorCode.profileExists);
    await tester.pumpWidget(
      _app(FakeAuthRepository(currentUserId: 'u'), profile),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('consent-all')));
    await _tapVisible(tester, find.byKey(const Key('consent-next')));
    await tester.enterText(find.byKey(const Key('profile-name')), '영희');
    await _tapVisible(tester, find.byKey(const Key('profile-position-winger')));
    await _tapVisible(tester, find.byKey(const Key('profile-submit')));
    expect(find.text(AuthTempTexts.homePlaceholder), findsOneWidget);
  });

  testWidgets('서버 거절은 오류 문구, 화면 유지', (tester) async {
    _tallScreen(tester);
    final profile = FakeProfileRepository()
      ..nextFailure = const ServerFailure(ServerErrorCode.invalidProfile);
    await tester.pumpWidget(
      _app(FakeAuthRepository(currentUserId: 'u'), profile),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('consent-all')));
    await _tapVisible(tester, find.byKey(const Key('consent-next')));
    await tester.enterText(find.byKey(const Key('profile-name')), '영희');
    await _tapVisible(tester, find.byKey(const Key('profile-position-winger')));
    await _tapVisible(tester, find.byKey(const Key('profile-submit')));
    expect(
      find.text(ProfileTexts.serverError(ServerErrorCode.invalidProfile)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-submit')), findsOneWidget);
  });

  testWidgets('로그아웃하면 로그인 화면', (tester) async {
    _tallScreen(tester);
    final auth = FakeAuthRepository(currentUserId: 'u');
    await tester.pumpWidget(
      _app(auth, FakeProfileRepository(hasProfile: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AuthTempTexts.signOut));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-kakao')), findsOneWidget);
  });
}
