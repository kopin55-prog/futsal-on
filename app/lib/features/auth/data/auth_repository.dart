import 'dart:async';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/login_nonce.dart';

/// 로그인 방법 (Q-030, Q-050: 안드로이드 카카오·구글, iOS 카카오·구글·애플).
enum SignInMethod { kakao, google, apple }

enum SignInFailureReason {
  /// 사용자가 로그인 창을 닫음. 화면에 오류를 띄우지 않는다.
  cancelled,

  /// 카카오가 ID 토큰을 주지 않음 → 카카오 디벨로퍼스에서 OpenID Connect 를 켜야 한다.
  kakaoIdTokenMissing,

  /// 구글이 ID 토큰을 주지 않음.
  googleIdTokenMissing,

  /// 아직 지원하지 않는 방법 (애플: 유료 개발자 계정 이후, Q-005-2).
  notSupported,

  /// 그 밖의 실패 (네트워크, Supabase 거절 등).
  failed,
}

class SignInFailure implements Exception {
  const SignInFailure(this.reason, [this.cause]);

  final SignInFailureReason reason;

  /// 원인 (디버그용). 화면·로그에 토큰을 남기지 않는다.
  final Object? cause;

  @override
  String toString() => 'SignInFailure($reason)';
}

/// 로그인 상태와 로그인·로그아웃. 화면은 이 인터페이스만 쓴다.
abstract interface class AuthRepository {
  /// 지금 로그인된 계정 ID (없으면 null).
  String? get currentUserId;

  /// 로그인 상태가 바뀔 때마다 계정 ID (로그아웃이면 null).
  Stream<String?> get userIdChanges;

  Future<void> signIn(SignInMethod method);

  Future<void> signOut();
}

/// 카카오·구글(·애플) 로그인 → Supabase 세션.
///
/// 각 로그인 서비스의 SDK 로 ID 토큰을 받고 Supabase `signInWithIdToken` 으로 세션을 만든다.
/// 인증된 같은 이메일이면 Supabase 가 기존 계정에 자동으로 붙인다 (Q-063 A). 앱은 계정 연결 기능을 쓰지 않는다.
/// 로그인 서비스가 넘긴 이름·사진을 프로필에 복사하지 않는다 (11장 10번).
/// 로그인마다 새 nonce 를 만들어 ID 토큰 재사용을 막는다 ([LoginNonce]).
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({
    required SupabaseClient client,
    required String googleServerClientId,
  }) : _client = client,
       _googleServerClientId = googleServerClientId;

  final SupabaseClient _client;
  final String _googleServerClientId;
  bool _googleInitialized = false;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<void> signIn(SignInMethod method) => switch (method) {
    SignInMethod.kakao => _signInWithKakao(),
    SignInMethod.google => _signInWithGoogle(),
    SignInMethod.apple => _signInWithApple(),
  };

  Future<void> _signInWithKakao() async {
    final nonce = LoginNonce.generate();
    final kakao.OAuthToken token;
    try {
      token = await _kakaoLogin(nonce.hashed);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') {
        throw SignInFailure(SignInFailureReason.cancelled, e);
      }
      throw SignInFailure(SignInFailureReason.failed, e);
    } on SignInFailure {
      rethrow;
    } catch (e) {
      throw SignInFailure(SignInFailureReason.failed, e);
    }

    final idToken = token.idToken;
    if (idToken == null) {
      throw const SignInFailure(SignInFailureReason.kakaoIdTokenMissing);
    }
    await _signInSupabase(
      OAuthProvider.kakao,
      idToken: idToken,
      accessToken: token.accessToken,
      nonce: nonce.raw,
    );
  }

  /// 카카오톡이 있으면 카카오톡으로, 없거나 실패하면 카카오계정으로.
  Future<kakao.OAuthToken> _kakaoLogin(String hashedNonce) async {
    if (await kakao.isKakaoTalkInstalled()) {
      try {
        return await kakao.UserApi.instance.loginWithKakaoTalk(
          nonce: hashedNonce,
        );
      } on PlatformException catch (e) {
        // 카카오톡 로그인 화면에서 사용자가 취소한 경우는 그대로 취소로 본다.
        if (e.code == 'CANCELED') rethrow;
      }
    }
    return kakao.UserApi.instance.loginWithKakaoAccount(nonce: hashedNonce);
  }

  /// google_sign_in 은 앱에서 initialize 를 한 번만 부르게 되어 있어, 두 번째 로그인부터는
  /// 플랫폼 초기화만 다시 해 새 nonce 를 넘긴다 (안드로이드·iOS 플랫폼 init 은 값만 바꾼다).
  Future<void> _prepareGoogle(String hashedNonce) async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
        nonce: hashedNonce,
      );
      _googleInitialized = true;
    } else {
      await GoogleSignInPlatform.instance.init(
        InitParameters(
          serverClientId: _googleServerClientId,
          nonce: hashedNonce,
        ),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    final nonce = LoginNonce.generate();
    final GoogleSignInAccount account;
    try {
      await _prepareGoogle(nonce.hashed);
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw SignInFailure(SignInFailureReason.cancelled, e);
      }
      throw SignInFailure(SignInFailureReason.failed, e);
    } catch (e) {
      throw SignInFailure(SignInFailureReason.failed, e);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const SignInFailure(SignInFailureReason.googleIdTokenMissing);
    }
    await _signInSupabase(
      OAuthProvider.google,
      idToken: idToken,
      nonce: nonce.raw,
    );
  }

  /// TODO(Q-005-2): 애플 로그인은 유료 애플 개발자 계정 준비 후 구현·테스트한다 (iOS 전용, Q-050).
  /// 구현 방향: sign_in_with_apple 로 ID 토큰(원본 nonce 의 SHA-256 전달) → signInWithIdToken(apple, nonce: 원본).
  Future<void> _signInWithApple() async {
    throw const SignInFailure(SignInFailureReason.notSupported);
  }

  Future<void> _signInSupabase(
    OAuthProvider provider, {
    required String idToken,
    required String nonce,
    String? accessToken,
  }) async {
    try {
      await _client.auth.signInWithIdToken(
        provider: provider,
        idToken: idToken,
        accessToken: accessToken,
        nonce: nonce,
      );
    } catch (e) {
      throw SignInFailure(SignInFailureReason.failed, e);
    }
  }

  @override
  Future<void> signOut() async {
    // 로그인 서비스 쪽 세션도 정리 (실패해도 Supabase 로그아웃은 진행).
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {
      // 카카오로 로그인하지 않았으면 실패한다. 무시.
    }
    try {
      if (_googleInitialized) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // 구글로 로그인하지 않았으면 무시.
    }
    await _client.auth.signOut();
  }
}
