# 아이폰 준비 안내 (kopn용)

작성 2026-11-10 builder (스프린트 04 7단계). 맥이 없어서 아이폰 빌드는 클라우드(Codemagic)에서 한다.

## 한눈에 보기
| 순서 | 할 일 | 비용 | 끝나면 |
| --- | --- | --- | --- |
| 1 | 카카오 디벨로퍼스에 iOS 번들 ID 등록 | 무료 | 아이폰 카카오 로그인 준비 |
| 2 | 구글 클라우드에 iOS OAuth 클라이언트 만들기 | 무료 | 아이폰 구글 로그인 준비 |
| 3 | Firebase에 iOS 앱 추가 | 무료 (Spark) | 아이폰 푸시 준비 (실제 수신은 유료 계정 후) |
| 4 | Codemagic 가입·저장소 연결·비밀 값 넣기 | 무료 (맥 빌드 월 500분) | 클라우드 빌드 준비 |
| 5 | 첫 빌드 실행 | 무료 (한 번에 약 15~25분) | "아이폰용으로 빌드가 된다" 확인 |

- 아래 1~5는 **애플 유료 계정(연 99달러) 없이** 모두 무료로 할 수 있다.
- 이번 단계 결과는 "빌드 성공"까지다. 실제 아이폰에 설치해 보는 것은 유료 계정 후(맨 아래 "유료 계정 후 할 일").

## 등록할 때 쓰는 값 (비밀 아님)
| 항목 | 값 |
| --- | --- |
| iOS 번들 ID | `kr.futsalon.app` |
| 안드로이드 패키지 이름 | 지금은 `com.example.futsal_on` 그대로 (묶음 테스트 뒤 `kr.futsalon.app`으로 바꿀 때 카카오·구글·Firebase 안드로이드 등록도 다시 함) |

비밀 값은 지금처럼 `C:\Users\sdt\SDT_project\futsal-app\.env.local`에만 적는다. 채팅·저장소에 넣지 않는다.

---

## 1. 카카오 디벨로퍼스: iOS 플랫폼 등록
1. https://developers.kakao.com → 내 애플리케이션 → `풋살ON`
2. 앱 설정 → **플랫폼** → **iOS 플랫폼 등록**
3. 번들 ID에 `kr.futsalon.app` 입력 → 저장
   - 앱스토어 ID 등 다른 칸은 비워 둔다
- 새로 받을 키는 없다. 지금 쓰는 네이티브 앱 키(`KAKAO_NATIVE_APP_KEY`)를 아이폰도 같이 쓴다.

## 2. 구글 클라우드: iOS OAuth 클라이언트
1. https://console.cloud.google.com → 프로젝트 `futsal-on-dev`
2. API 및 서비스 → 사용자 인증 정보 → **사용자 인증 정보 만들기** → **OAuth 클라이언트 ID**
3. 애플리케이션 유형 **iOS**, 이름 `풋살ON iOS`, 번들 ID `kr.futsalon.app` → 만들기
   - 앱스토어 ID·팀 ID는 비워 둔다
4. 화면에 나온 **클라이언트 ID**(`숫자-글자.apps.googleusercontent.com` 모양)를 `.env.local`에 한 줄 추가
   ```
   GOOGLE_IOS_CLIENT_ID=여기에_클라이언트_ID
   ```
5. Supabase 대시보드 → Authentication → Sign In / Providers → **Google** → Client IDs 칸에 지금 있는 웹 클라이언트 ID 뒤에 쉼표(`,`)를 붙이고 iOS 클라이언트 ID를 추가 → 저장
   - 웹 클라이언트 ID·보안 비밀은 그대로 둔다
- 이 값이 비어 있으면 아이폰에서 구글 로그인 버튼을 눌렀을 때 "아직 준비 중인 로그인 방법이에요."가 뜬다 (안드로이드는 영향 없음).

## 3. Firebase: iOS 앱 추가
1. https://console.firebase.google.com → 프로젝트 `futsal-on-dev`
2. 프로젝트 설정(톱니바퀴) → 내 앱 → **앱 추가** → **iOS** (사과 모양)
3. Apple 번들 ID `kr.futsalon.app`, 앱 닉네임 `풋살ON iOS` → 앱 등록 (App Store ID는 비움)
4. **`GoogleService-Info.plist` 다운로드** → 아래 위치에 저장 (Git에 안 올라가게 이미 설정됨)
   - `C:\Users\sdt\SDT_project\futsal-app\app\ios\Runner\GoogleService-Info.plist`
5. 그다음 화면(SDK 추가, 초기화 코드)은 코드에 이미 반영되어 있으니 **다음**만 눌러 끝낸다
- APNs 키 등록(아이폰으로 실제 푸시 보내기)은 유료 애플 계정이 있어야 해서 지금은 하지 않는다.

## 4. Codemagic 가입과 연결
먼저 lead가 최신 코드를 GitHub 저장소(`futsal-on`)에 올려 두어야 한다 (lead에게 "Codemagic 연결 준비됐다"고 알려 주기).

1. https://codemagic.io → **Sign up** → **GitHub로 가입** (요금제는 무료 그대로, 카드 등록 안 함)
2. GitHub 권한 창에서 `futsal-on` 저장소 접근 허용
3. Codemagic 화면 → **Add application** → GitHub → `futsal-on` 선택 → 프로젝트 유형 **Flutter App** → 설정 방식은 **codemagic.yaml** (저장소에 이미 있음)
4. 앱 화면 → **Environment variables**에서 아래 이름으로 변수를 하나씩 추가
   - 모두 **Group 이름 `futsalon_dev`**, **Secure(비밀) 체크**
   - 값은 kopn이 `.env.local`에서 직접 복사해 넣는다 (lead·에이전트에게 보내지 않음)

| 변수 이름 | 값 | 꼭 필요? |
| --- | --- | --- |
| `SUPABASE_DEV_URL` | `.env.local`의 같은 이름 값 | 필수 |
| `SUPABASE_DEV_ANON_KEY` | `.env.local`의 같은 이름 값 | 필수 |
| `KAKAO_NATIVE_APP_KEY` | `.env.local`의 같은 이름 값 | 필수 |
| `GOOGLE_WEB_CLIENT_ID` | `.env.local`의 같은 이름 값 | 필수 |
| `GOOGLE_IOS_CLIENT_ID` | 2번에서 만든 값 | 비어도 빌드는 됨 |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | 3번 파일을 글자로 바꾼 값 (아래) | 비어도 빌드는 됨 (푸시만 꺼짐) |

- `SUPABASE_DEV_DB_PASSWORD`는 **넣지 않는다** (앱 빌드에 필요 없음).
- `GOOGLE_SERVICE_INFO_PLIST_BASE64` 값 만들기: PowerShell을 열고 아래 한 줄을 실행하면 값이 클립보드에 복사된다. Codemagic 값 칸에 붙여넣기.
  ```
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\sdt\SDT_project\futsal-app\app\ios\Runner\GoogleService-Info.plist")) | Set-Clipboard
  ```

## 5. 첫 빌드 실행
1. Codemagic 앱 화면 → **Start new build**
2. 브랜치 `main`, 워크플로 **iOS 서명 없는 빌드** 선택 → Start
3. 15~25분쯤 기다린다. 끝에 초록색 체크가 나오면 성공
   - 빨간색이면 실패한 단계 이름과 화면 아래쪽 오류 몇 줄을 lead에게 알려 주기 (비밀 값은 화면에 나오지 않게 되어 있음)
- 자동으로 돌지 않는다. 버튼을 누를 때만 빌드되어 무료 시간(월 500분)을 아낀다.
- 이 빌드는 설치 파일을 만들지 않는다 (서명은 유료 계정이 있어야 함).

---

## 유료 애플 계정 후 할 일 (7-6, 지금은 하지 않음)
애플 개발자 계정(연 99달러)이 생기면 lead가 순서를 다시 안내한다. 대략:
1. 애플 개발자 사이트에서 App ID `kr.futsalon.app` 등록 (Push Notifications, Sign in with Apple 켜기)
2. APNs 키 만들기 → Firebase iOS 앱에 올리기 → 아이폰 푸시 확인
3. 애플 로그인 서비스 설정 → Supabase에서 Apple 로그인 켜기 → `.env.local`에 `APPLE_SIGN_IN_ENABLED=true` (Codemagic 변수 그룹에도) → 로그인 화면에 애플 버튼이 보임
4. Codemagic에 서명 설정 추가 → TestFlight 업로드 → 아이폰에 설치해 묶음 테스트
