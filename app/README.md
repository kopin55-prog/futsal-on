# futsal_on (풋살ON 앱)

## 개발 실행

1. 저장소 루트의 `.env.local` 에서 앱 설정 파일을 만든다 (공개용 값 4개만 옮긴다. git 제외 파일).

   ```
   dart run tool/make_dev_config.dart
   ```

   예시 형식은 `config/dev.example.json`.

2. 설정 파일로 실행·빌드한다.

   ```
   flutter run --dart-define-from-file=config/dev.json
   flutter build apk --debug --dart-define-from-file=config/dev.json
   ```

설정 파일 없이 실행하면 "앱 설정값이 없어요" 화면만 보인다.
DB 비밀번호·service_role 키는 앱에 넣지 않는다.
