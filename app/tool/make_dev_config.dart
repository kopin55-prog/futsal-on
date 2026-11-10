// 저장소 루트의 .env.local 에서 앱 설정 파일을 만든다.
//
// 사용: (app 폴더에서) dart run tool/make_dev_config.dart
//       클라우드 빌드(Codemagic)처럼 .env.local 이 없고 환경 변수로 값을 받을 때:
//       dart run tool/make_dev_config.dart --from-env
// 실행: flutter run --dart-define-from-file=config/dev.json
//
// 만드는 파일 (둘 다 .gitignore 대상, 값을 화면에 출력하지 않는다)
// - config/dev.json : 앱 설정값 (--dart-define-from-file)
// - ios/Flutter/DevConfig.xcconfig : iOS Info.plist 의 로그인 URL 스킴 값 (카카오·구글)
//   안드로이드는 같은 값을 build.gradle.kts 가 dart-define 에서 직접 읽는다.
//
// 앱에 넣는 값은 공개용 값뿐이다 (Supabase URL·anon 키, 카카오 네이티브 앱 키, 구글 클라이언트 ID).
// DB 비밀번호 등 다른 값은 절대 옮기지 않는다.
import 'dart:convert';
import 'dart:io';

/// 앱 설정 이름 → .env.local 이름. 비어 있으면 앱이 설정 누락 화면을 띄운다.
const _required = {
  'SUPABASE_URL': 'SUPABASE_DEV_URL',
  'SUPABASE_ANON_KEY': 'SUPABASE_DEV_ANON_KEY',
  'KAKAO_NATIVE_APP_KEY': 'KAKAO_NATIVE_APP_KEY',
  'GOOGLE_WEB_CLIENT_ID': 'GOOGLE_WEB_CLIENT_ID',
};

/// 비어 있어도 되는 값 (iOS 전용). 비면 iOS 구글 로그인만 "준비 중" 안내.
const _optional = {
  'GOOGLE_IOS_CLIENT_ID': 'GOOGLE_IOS_CLIENT_ID',
};

/// 켜고 끄는 설정 (비밀 아님). true 일 때만 켠다. 기본 꺼짐.
const _flags = {
  // 애플 로그인 버튼 (iOS 전용). 유료 애플 계정 후 켠다 (7-6, Q-005-2).
  'APPLE_SIGN_IN_ENABLED': 'APPLE_SIGN_IN_ENABLED',
};

const _googleClientSuffix = '.apps.googleusercontent.com';

void main(List<String> args) {
  final fromEnv = args.contains('--from-env');
  final Map<String, String> env;
  if (fromEnv) {
    env = Platform.environment;
  } else {
    final envFile = File('../.env.local');
    if (!envFile.existsSync()) {
      stderr.writeln('../.env.local 이 없습니다 (app 폴더에서 실행하세요).');
      exitCode = 1;
      return;
    }
    env = parseEnv(envFile.readAsLinesSync());
  }

  final config = <String, String>{};
  final missing = <String>[];
  final missingOptional = <String>[];
  _required.forEach((appKey, envKey) {
    final value = (env[envKey] ?? '').trim();
    if (value.isEmpty) missing.add(envKey);
    config[appKey] = value;
  });
  _optional.forEach((appKey, envKey) {
    final value = (env[envKey] ?? '').trim();
    if (value.isEmpty) missingOptional.add(envKey);
    config[appKey] = value;
  });
  _flags.forEach((appKey, envKey) {
    config[appKey] = (env[envKey] ?? '').trim().toLowerCase() == 'true' ? 'true' : 'false';
  });

  Directory('config').createSync(recursive: true);
  File('config/dev.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
  stdout.writeln('config/dev.json 을 만들었습니다 (값은 출력하지 않음).');

  final iosProblems = writeIosConfig(
    kakaoNativeAppKey: config['KAKAO_NATIVE_APP_KEY']!,
    googleIosClientId: config['GOOGLE_IOS_CLIENT_ID']!,
  );
  stdout.writeln('ios/Flutter/DevConfig.xcconfig 를 만들었습니다 (값은 출력하지 않음).');

  if (missing.isNotEmpty) {
    stdout.writeln('비어 있는 항목: ${missing.join(', ')}');
  }
  if (missingOptional.isNotEmpty) {
    stdout.writeln(
      '비어 있는 iOS 항목 (안드로이드는 영향 없음): ${missingOptional.join(', ')}',
    );
  }
  for (final p in iosProblems) {
    stdout.writeln(p);
  }
}

/// .env 형식(KEY=VALUE, # 주석) 읽기.
Map<String, String> parseEnv(List<String> lines) {
  final env = <String, String>{};
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final i = trimmed.indexOf('=');
    if (i <= 0) continue;
    env[trimmed.substring(0, i).trim()] = trimmed.substring(i + 1).trim();
  }
  return env;
}

/// iOS 구글 클라이언트 ID(`123-abc.apps.googleusercontent.com`)를 URL 스킴
/// (`com.googleusercontent.apps.123-abc`)으로 뒤집는다. 형식이 다르면 null.
String? reversedGoogleClientId(String clientId) {
  if (!clientId.endsWith(_googleClientSuffix)) return null;
  final prefix = clientId.substring(0, clientId.length - _googleClientSuffix.length);
  if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(prefix)) return null;
  return 'com.googleusercontent.apps.$prefix';
}

/// xcconfig 값으로 넣어도 안전한 글자인지 (`//` 는 주석, 줄바꿈·공백은 값을 깨뜨림).
bool _xcconfigSafe(String v) => RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(v);

/// ios/Flutter/DevConfig.xcconfig 를 쓴다. 문제(값 형식 오류)를 문구 목록으로 돌려준다 (값은 담지 않음).
/// 쓸 수 없는 값은 줄을 빼서 Debug/Release.xcconfig 의 자리표시 값이 쓰이게 한다.
List<String> writeIosConfig({
  required String kakaoNativeAppKey,
  required String googleIosClientId,
}) {
  final problems = <String>[];
  final lines = <String>[
    '// make_dev_config.dart 가 만든 파일입니다. 저장소에 넣지 않습니다 (.gitignore).',
  ];
  if (kakaoNativeAppKey.isNotEmpty) {
    if (_xcconfigSafe(kakaoNativeAppKey)) {
      lines.add('KAKAO_NATIVE_APP_KEY = $kakaoNativeAppKey');
    } else {
      problems.add('KAKAO_NATIVE_APP_KEY 형식이 이상해 iOS 설정에 넣지 않았습니다.');
    }
  }
  if (googleIosClientId.isNotEmpty) {
    final reversed = reversedGoogleClientId(googleIosClientId);
    if (reversed != null) {
      lines.add('GOOGLE_IOS_REVERSED_CLIENT_ID = $reversed');
    } else {
      problems.add(
        'GOOGLE_IOS_CLIENT_ID 는 "…$_googleClientSuffix" 형식이어야 합니다. iOS 설정에 넣지 않았습니다.',
      );
    }
  }
  File('ios/Flutter/DevConfig.xcconfig').writeAsStringSync('${lines.join('\n')}\n');
  return problems;
}
