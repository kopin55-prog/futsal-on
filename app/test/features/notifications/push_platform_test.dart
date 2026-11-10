import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/notifications/data/device_token_repository.dart';
import 'package:futsal_on/features/notifications/data/push_messaging.dart';

/// 스프린트 04 7-4: iOS 도 푸시를 켜 보고, 기기 주소는 platform=ios 로 등록.
void main() {
  test('푸시를 켜 보는 기기는 안드로이드·iOS 만', () {
    expect(FirebasePushMessaging.supportsPush(false, TargetPlatform.android), isTrue);
    expect(FirebasePushMessaging.supportsPush(false, TargetPlatform.iOS), isTrue);
    expect(FirebasePushMessaging.supportsPush(true, TargetPlatform.android), isFalse);
    expect(FirebasePushMessaging.supportsPush(false, TargetPlatform.windows), isFalse);
  });

  test('설정 파일이 없는 환경(테스트)에서는 iOS 도 푸시 없이 동작', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final push = await FirebasePushMessaging.tryCreate(platform: TargetPlatform.iOS);
    expect(push, isA<NoPushMessaging>());
  });

  test('기기 주소의 기기 종류: 안드로이드는 그대로 android, iOS 는 ios', () {
    expect(SupabaseDeviceTokenRepository.platformName(TargetPlatform.android), 'android');
    expect(SupabaseDeviceTokenRepository.platformName(TargetPlatform.iOS), 'ios');
  });
}
