import 'package:flutter_test/flutter_test.dart';

import '../../tool/make_dev_config.dart';

/// 스프린트 04 7-2: .env.local → iOS URL 스킴 값 만들기.
void main() {
  test('구글 iOS 클라이언트 ID 를 URL 스킴으로 뒤집는다', () {
    expect(
      reversedGoogleClientId('1234-abcDEF.apps.googleusercontent.com'),
      'com.googleusercontent.apps.1234-abcDEF',
    );
  });

  test('형식이 다른 값은 뒤집지 않는다 (xcconfig 를 깨뜨리지 않게)', () {
    expect(reversedGoogleClientId(''), isNull);
    expect(reversedGoogleClientId('1234-abc'), isNull);
    expect(reversedGoogleClientId('a//b.apps.googleusercontent.com'), isNull);
    expect(reversedGoogleClientId('.apps.googleusercontent.com'), isNull);
  });

  test('.env 읽기: 주석·빈 줄 무시, 첫 = 기준, 앞뒤 공백 제거', () {
    final env = parseEnv([
      '# 주석',
      '',
      'GOOGLE_IOS_CLIENT_ID = x.apps.googleusercontent.com ',
      'APPLE_SIGN_IN_ENABLED=false',
      'A=b=c',
      'nokey',
    ]);
    expect(env['GOOGLE_IOS_CLIENT_ID'], 'x.apps.googleusercontent.com');
    expect(env['APPLE_SIGN_IN_ENABLED'], 'false');
    expect(env['A'], 'b=c');
    expect(env.containsKey('nokey'), isFalse);
  });
}
