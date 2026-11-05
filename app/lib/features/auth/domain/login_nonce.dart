import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 로그인 재사용 방지값 (OpenID Connect nonce).
///
/// 로그인 서비스(카카오·구글)에는 [hashed](원본의 SHA-256, 16진수)를 넘기고,
/// Supabase `signInWithIdToken` 에는 [raw](원본)를 넘긴다. Supabase 가 원본을 해시해
/// ID 토큰 안의 nonce 와 비교하므로, 가로챈 ID 토큰을 다른 로그인 시도에 다시 쓸 수 없다.
/// 로그인 한 번마다 새로 만든다. 값은 로그·화면에 남기지 않는다.
class LoginNonce {
  LoginNonce._(this.raw) : hashed = hashOf(raw);

  /// 암호학적 난수 32바이트 → URL 안전 base64 (패딩 없음).
  factory LoginNonce.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return LoginNonce._(base64UrlEncode(bytes).replaceAll('=', ''));
  }

  /// 테스트용.
  factory LoginNonce.fromRaw(String raw) => LoginNonce._(raw);

  final String raw;
  final String hashed;

  static String hashOf(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();
}
