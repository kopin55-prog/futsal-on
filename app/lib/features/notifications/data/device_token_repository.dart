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
  SupabaseDeviceTokenRepository(this._client);

  final SupabaseClient _client;

  /// 1차는 안드로이드만 (5-4 iOS 는 04).
  static const platform = 'android';

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
