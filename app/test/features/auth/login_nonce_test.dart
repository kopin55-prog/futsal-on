import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/auth/domain/login_nonce.dart';

void main() {
  test('해시는 원본의 SHA-256 16진수 (Supabase 가 같은 방식으로 비교)', () {
    // echo -n abc | sha256sum
    expect(
      LoginNonce.fromRaw('abc').hashed,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('매번 다른 값, 충분한 길이, URL 안전 문자', () {
    final a = LoginNonce.generate();
    final b = LoginNonce.generate();
    expect(a.raw, isNot(b.raw));
    expect(a.raw.length, 43); // 32바이트 base64url, 패딩 없음
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(a.raw), isTrue);
    expect(a.hashed, LoginNonce.hashOf(a.raw));
    expect(a.hashed, isNot(a.raw));
  });
}
