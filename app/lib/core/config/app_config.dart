/// 앱 설정값. 빌드 때 `--dart-define-from-file=config/dev.json` 으로 넣는다.
///
/// 앱에 들어가는 값은 공개용 값뿐이다 (Supabase URL·anon 키, 카카오 네이티브 앱 키, 구글 클라이언트 ID).
/// DB 비밀번호·service_role 키는 절대 넣지 않는다. 파일은 app/tool/make_dev_config.dart 로 만든다.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.kakaoNativeAppKey,
    required this.googleWebClientId,
    this.googleIosClientId = '',
    this.appleSignInEnabled = false,
  });

  /// dart-define 값에서 읽는다. 없는 값은 빈 문자열(켜고 끄는 값은 꺼짐).
  const AppConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
      kakaoNativeAppKey = const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
      googleWebClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      googleIosClientId = const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
      appleSignInEnabled = const bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String kakaoNativeAppKey;

  /// 구글 로그인의 서버 클라이언트 ID (Supabase 가 ID 토큰을 확인할 때 쓰는 웹 클라이언트).
  final String googleWebClientId;

  /// iOS 구글 로그인 클라이언트 ID (iOS 전용, 비어 있어도 된다).
  /// 비어 있으면 iOS 에서 구글 로그인 버튼이 "준비 중" 안내만 띄운다. 안드로이드는 쓰지 않는다.
  final String googleIosClientId;

  /// 애플 로그인 버튼 켜기 (iOS 전용). 유료 애플 계정 전에는 꺼 둔다 (7-3, Q-005-2).
  final bool appleSignInEnabled;

  /// 비어 있는 필수 설정 이름 목록 (값은 담지 않는다). iOS 전용 값은 넣지 않는다.
  List<String> get missingKeys => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (kakaoNativeAppKey.isEmpty) 'KAKAO_NATIVE_APP_KEY',
    if (googleWebClientId.isEmpty) 'GOOGLE_WEB_CLIENT_ID',
  ];

  bool get isComplete => missingKeys.isEmpty;
}
