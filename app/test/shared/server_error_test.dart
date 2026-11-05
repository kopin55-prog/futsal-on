import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/config/app_config.dart';
import 'package:futsal_on/shared/data/server_error.dart';

void main() {
  test('알 수 없는 코드는 unknown', () {
    expect(
      ServerErrorCode.fromCode('profile_required'),
      ServerErrorCode.profileRequired,
    );
    expect(ServerErrorCode.fromCode('nope'), ServerErrorCode.unknown);
    expect(ServerErrorCode.fromCode(null), ServerErrorCode.unknown);
  });

  test('앱의 오류 코드는 모두 서버 마이그레이션에 있다', () {
    final sql = Directory('../supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final code in ServerErrorCode.values) {
      if (code == ServerErrorCode.unknown) continue;
      expect(
        sql.contains("raise exception '${code.code}'"),
        isTrue,
        reason: code.code,
      );
    }
  });

  test('설정값이 비면 빠진 이름만 알려준다', () {
    const config = AppConfig(
      supabaseUrl: 'x',
      supabaseAnonKey: '',
      kakaoNativeAppKey: 'k',
      googleWebClientId: '',
    );
    expect(config.isComplete, isFalse);
    expect(config.missingKeys, ['SUPABASE_ANON_KEY', 'GOOGLE_WEB_CLIENT_ID']);
  });
}
