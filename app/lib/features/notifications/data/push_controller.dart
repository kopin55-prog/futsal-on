import 'dart:async';

import '../domain/push_message.dart';
import 'device_token_repository.dart';
import 'push_messaging.dart';

/// 푸시 기기 등록·해제 한 곳 (스프린트 02 5-1).
///
/// - [start]: 로그인해 홈에 들어올 때마다 이 기기 토큰을 서버에 등록하고, 토큰이 바뀌면 다시 등록한다.
/// - [stop]: 로그아웃(회원 탈퇴 포함) 직전에 이 기기 주소를 서버에서 지우고 기기 토큰도 없앤다.
/// - [requestPermission]: 프로필 만든 직후 한 번 (Q-071 13번). 거절해도 앱·알림함은 그대로.
/// 앱 안 알림 종류별 끄기는 없다 (Q-071 13번, 휴대폰 설정으로만).
/// 모든 실패는 조용히 넘긴다 (푸시가 안 돼도 앱 사용은 막지 않는다).
class PushController {
  PushController({
    required PushMessaging messaging,
    required DeviceTokenRepository tokens,
    this.timeout = const Duration(seconds: 5),
  }) : _messaging = messaging,
       _tokens = tokens;

  final PushMessaging _messaging;
  final DeviceTokenRepository _tokens;

  /// 서버·FCM 호출 하나의 최대 대기 (로그아웃이 오프라인에서 멈추지 않게).
  final Duration timeout;

  StreamSubscription<String>? _refresh;
  String? _token;

  Stream<PushMessage> get foregroundMessages => _messaging.onForegroundMessage;

  Stream<PushMessage> get openedMessages => _messaging.onMessageOpened;

  Future<PushMessage?> takeInitialMessage() => _quiet(_messaging.takeInitialMessage, null);

  Future<void> requestPermission() => _quiet(_messaging.requestPermission, null);

  Future<void> start() async {
    // 취소 완료를 기다리지 않는다 (기다릴 일이 없고, 테스트의 가짜 시계에서 멈출 수 있다)
    unawaited(_refresh?.cancel());
    _refresh = _messaging.onTokenRefresh.listen((t) => unawaited(_register(t)));
    final token = await _quiet(_messaging.getToken, null);
    if (token != null) await _register(token);
  }

  Future<void> stop() async {
    unawaited(_refresh?.cancel());
    _refresh = null;
    final token = _token ?? await _quiet(_messaging.getToken, null);
    _token = null;
    if (token != null) await _quiet(() => _tokens.remove(token), null);
    await _quiet(_messaging.deleteToken, null);
  }

  Future<void> _register(String token) async {
    if (token.isEmpty) return;
    _token = token;
    await _quiet(() => _tokens.register(token), null);
  }

  Future<T> _quiet<T>(Future<T> Function() run, T fallback) async {
    try {
      return await run().timeout(timeout);
    } catch (_) {
      return fallback;
    }
  }
}
