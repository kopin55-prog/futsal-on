import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';

/// 기기 알림 주소 (data-model.md 2-4 device_tokens).
///
/// 등록은 서버 함수 register_device_token 으로만 (같은 토큰이 다른 사람 것이면 지금 사람에게 옮겨진다, S-08).
/// 삭제는 본인 줄만 (로그아웃). 실패는 [ServerFailure].
abstract interface class DeviceTokenRepository {
  Future<void> register(String token);

  Future<void> remove(String token);
}

class SupabaseDeviceTokenRepository implements DeviceTokenRepository {
  SupabaseDeviceTokenRepository(this._client, {TargetPlatform? platform})
    : platform = platformName(platform ?? defaultTargetPlatform);

  final SupabaseClient _client;

  /// 서버 device_platform 값 ('android' / 'ios', 7-4).
  final String platform;

  /// 기기 종류 → 서버 값. 푸시는 안드로이드·iOS 에서만 켜지므로 그 밖은 안드로이드로 둔다.
  static String platformName(TargetPlatform p) =>
      p == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<void> register(String token) => guardServer(() async {
    await _client.rpc<void>(
      'register_device_token',
      params: {'p_token': token, 'p_platform': platform},
    );
  });

  @override
  Future<void> remove(String token) => guardServer(() async {
    await _client.from('device_tokens').delete().eq('token', token);
  });
}
