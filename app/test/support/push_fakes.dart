import 'dart:async';

import 'package:futsal_on/features/notifications/data/device_token_repository.dart';
import 'package:futsal_on/features/notifications/data/push_messaging.dart';
import 'package:futsal_on/features/notifications/domain/push_message.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 가짜 FCM. 토큰·받은 푸시를 테스트가 직접 넣는다.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.token = 'tok-1', this.initial});

  String? token;
  PushMessage? initial;
  int permissionRequests = 0;
  int deleted = 0;
  bool throwOnGetToken = false;

  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<String?> getToken() async {
    if (throwOnGetToken) throw StateError('no token');
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async {
    deleted++;
    token = null;
  }

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushMessage> get onMessageOpened => opened.stream;

  @override
  Future<PushMessage?> takeInitialMessage() async {
    final m = initial;
    initial = null;
    return m;
  }
}

/// 가짜 기기 주소 저장소 (호출 순서 기록).
class FakeDeviceTokenRepository implements DeviceTokenRepository {
  final List<String> log = [];
  final Set<String> tokens = {};
  bool fail = false;

  @override
  Future<void> register(String token) async {
    log.add('register:$token');
    if (fail) throw const ServerFailure(ServerErrorCode.unknown);
    tokens.add(token);
  }

  @override
  Future<void> remove(String token) async {
    log.add('remove:$token');
    if (fail) throw const ServerFailure(ServerErrorCode.unknown);
    tokens.remove(token);
  }
}
