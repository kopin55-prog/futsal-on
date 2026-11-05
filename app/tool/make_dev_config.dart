// 저장소 루트의 .env.local 에서 앱 설정 파일 app/config/dev.json 을 만든다.
//
// 사용: (app 폴더에서) dart run tool/make_dev_config.dart
// 실행: flutter run --dart-define-from-file=config/dev.json
//
// - 앱에 넣는 값은 공개용 값 4개뿐이다 (Supabase URL, anon 키, 카카오 네이티브 앱 키, 구글 웹 클라이언트 ID).
//   DB 비밀번호 등 다른 값은 절대 옮기지 않는다.
// - dev.json 은 .gitignore 대상이다. 값을 화면에 출력하지 않는다.
import 'dart:convert';
import 'dart:io';

const _mapping = {
  'SUPABASE_URL': 'SUPABASE_DEV_URL',
  'SUPABASE_ANON_KEY': 'SUPABASE_DEV_ANON_KEY',
  'KAKAO_NATIVE_APP_KEY': 'KAKAO_NATIVE_APP_KEY',
  'GOOGLE_WEB_CLIENT_ID': 'GOOGLE_WEB_CLIENT_ID',
};

void main() {
  final envFile = File('../.env.local');
  if (!envFile.existsSync()) {
    stderr.writeln('../.env.local 이 없습니다 (app 폴더에서 실행하세요).');
    exitCode = 1;
    return;
  }
  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final i = trimmed.indexOf('=');
    if (i <= 0) continue;
    env[trimmed.substring(0, i).trim()] = trimmed.substring(i + 1).trim();
  }

  final config = <String, String>{};
  final missing = <String>[];
  _mapping.forEach((appKey, envKey) {
    final value = env[envKey] ?? '';
    if (value.isEmpty) missing.add(envKey);
    config[appKey] = value;
  });

  Directory('config').createSync(recursive: true);
  File('config/dev.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
  stdout.writeln('config/dev.json 을 만들었습니다 (값은 출력하지 않음).');
  if (missing.isNotEmpty) {
    stdout.writeln('비어 있는 항목: ${missing.join(', ')}');
  }
}
