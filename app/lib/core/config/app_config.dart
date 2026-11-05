/// 앱 설정값. 빌드 때 `--dart-define-from-file=config/dev.json` 으로 넣는다.
///
/// 앱에 들어가는 값은 공개용 값뿐이다 (Supabase URL·anon 키, 카카오 네이티브 앱 키, 구글 웹 클라이언트 ID).
/// DB 비밀번호·service_role 키는 절대 넣지 않는다. 파일은 app/tool/make_dev_config.dart 로 만든다.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.kakaoNativeAppKey,
    required this.googleWebClientId,
  });

  /// dart-define 값에서 읽는다. 없는 값은 빈 문자열.
  const AppConfig.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
      kakaoNativeAppKey = const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
      googleWebClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String kakaoNativeAppKey;

  /// 구글 로그인의 서버 클라이언트 ID (Supabase 가 ID 토큰을 확인할 때 쓰는 웹 클라이언트).
  final String googleWebClientId;

  /// 비어 있는 설정 이름 목록 (값은 담지 않는다).
  List<String> get missingKeys => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (kakaoNativeAppKey.isEmpty) 'KAKAO_NATIVE_APP_KEY',
    if (googleWebClientId.isEmpty) 'GOOGLE_WEB_CLIENT_ID',
  ];

  bool get isComplete => missingKeys.isEmpty;
}
