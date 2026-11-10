import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/push_message.dart';

/// 휴대폰 푸시 기능 (FCM). 화면·컨트롤러는 이 인터페이스만 쓴다. 테스트에서는 가짜로 바꾼다.
abstract interface class PushMessaging {
  /// 이 기기의 FCM 토큰 (없거나 실패하면 null).
  Future<String?> getToken();

  /// 토큰이 바뀔 때마다 새 토큰.
  Stream<String> get onTokenRefresh;

  /// 이 기기의 토큰을 없앤다 (로그아웃). 다음 getToken 은 새 토큰.
  Future<void> deleteToken();

  /// 알림 권한 요청 (안드로이드 13 이상은 시스템 창). 거절해도 앱은 그대로 (I-05).
  Future<void> requestPermission();

  /// 앱 사용 중 도착한 푸시 (안드로이드는 이때 휴대폰 알림을 띄우지 않는다).
  Stream<PushMessage> get onForegroundMessage;

  /// 백그라운드에서 휴대폰 알림을 눌러 앱으로 돌아왔을 때.
  Stream<PushMessage> get onMessageOpened;

  /// 앱이 꺼져 있을 때 휴대폰 알림을 눌러 앱이 켜졌으면 그 푸시 (한 번만).
  Future<PushMessage?> takeInitialMessage();
}

/// 푸시 없음 (설정 파일이 없는 환경·안드로이드/iOS 가 아닌 기기·테스트).
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<void> deleteToken() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushMessage> get onMessageOpened => const Stream.empty();

  @override
  Future<PushMessage?> takeInitialMessage() async => null;
}

/// firebase_messaging 연결 (안드로이드·iOS, 7-4). iOS 실제 푸시 수신은 APNs 키 등록 후 (7-6).
/// 그 전에는 iOS getToken 이 실패해 null 이 되고, 기기 주소 등록만 건너뛴다.
///
/// 토큰은 FCM 등록 토큰(getToken·onTokenRefresh·deleteToken)을 쓴다. firebase_messaging 17 은 이 함수들을
/// 새 방식(register·onRegistered: Firebase 설치 ID 로 직접 보내기)으로 바꾸라고 표시하지만, 서버 notifier 는
/// FCM HTTP v1 의 등록 토큰(message.token) 방식으로 보내므로 등록 토큰을 그대로 쓴다.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._(this._messaging);

  final FirebaseMessaging _messaging;

  /// Firebase 를 켜 본다. 설정 파일(안드로이드 google-services.json, iOS GoogleService-Info.plist)이
  /// 없어 실패하거나(테스트·CI·클라우드 빌드) 안드로이드·iOS 가 아니면 [NoPushMessaging].
  /// iOS 설정 파일은 있을 때만 빌드가 앱에 넣는다 (Xcode "Copy GoogleService-Info.plist" 단계).
  static Future<PushMessaging> tryCreate({TargetPlatform? platform}) async {
    if (!supportsPush(kIsWeb, platform ?? defaultTargetPlatform)) {
      return const NoPushMessaging();
    }
    try {
      await Firebase.initializeApp();
      return FirebasePushMessaging._(FirebaseMessaging.instance);
    } catch (_) {
      return const NoPushMessaging();
    }
  }

  /// 푸시를 켜 보는 기기 (안드로이드·iOS).
  static bool supportsPush(bool isWeb, TargetPlatform platform) =>
      !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

  static PushMessage? _convert(RemoteMessage m) => PushMessage.fromData(
    m.data,
    title: m.notification?.title,
    body: m.notification?.body,
  );

  @override
  Future<String?> getToken() async {
    try {
      // ignore: deprecated_member_use
      return await _messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() async {
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } catch (_) {
      // 오프라인 등. 서버 쪽 기기 주소는 따로 지우고, 남아도 발송 때 등록 안 된 토큰으로 지워진다.
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission();
    } catch (_) {
      // 권한 창을 못 띄워도 앱은 그대로
    }
  }

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(_convert).where((m) => m != null).cast<PushMessage>();

  @override
  Stream<PushMessage> get onMessageOpened =>
      FirebaseMessaging.onMessageOpenedApp.map(_convert).where((m) => m != null).cast<PushMessage>();

  @override
  Future<PushMessage?> takeInitialMessage() async {
    try {
      final m = await _messaging.getInitialMessage();
      return m == null ? null : _convert(m);
    } catch (_) {
      return null;
    }
  }
}
