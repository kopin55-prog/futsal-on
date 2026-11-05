# 개발 계정 준비 안내 (kopn용)

작성 2026-11-05 lead. 지금은 **개발용**만 준비한다. 운영용 Supabase·Firebase·유료 계정은 나중에.

## 상태 (2026-11-05): Supabase·카카오·구글·GitHub 준비 완료. Supabase Email 로그인 방식 꺼짐 확인

## 왜 필요한가 (모두 무료)
| 계정 | 하는 일 | 지금 필요? |
| --- | --- | --- |
| Supabase | 앱의 서버. 회원·팀·일정·투표 데이터 저장, 권한 규칙, 로그인 처리 | **예.** 없으면 테이블·로그인을 만들 곳이 없음. 같은 이메일 별개 가입이 되는지(Q-056) 확인도 여기서 |
| 카카오 디벨로퍼스 | 카카오 로그인·카카오맵을 쓰려면 카카오가 발급하는 앱 키가 있어야 함 | **예.** 스프린트 01 로그인 작업. 카카오맵(팀 만들기 구장 선택)에도 같은 키 |
| 구글 클라우드 | 구글 로그인용 OAuth 키 발급 | **예.** 스프린트 01 로그인 작업. 같은 이메일 확인도 카카오+구글 두 방법이 있어야 가능 |
| GitHub | 코드 백업·변경 이력 보관 | 급하지 않음. 지금은 이 PC에만 있음(PC 고장 시 유실). 나중에 아이폰 클라우드 빌드가 GitHub에서 코드를 가져감 |

## 비밀 값 전달 방법
비밀 값은 채팅이나 저장소에 넣지 않는다. 아래 파일을 직접 만들어 값을 채운다.
- 위치: `C:\Users\sdt\SDT_project\futsal-app\.env.local` (Git에 올라가지 않게 이미 설정됨)

```
SUPABASE_DEV_URL=
SUPABASE_DEV_ANON_KEY=
SUPABASE_DEV_DB_PASSWORD=
KAKAO_NATIVE_APP_KEY=
GOOGLE_WEB_CLIENT_ID=
```

## 앱 정보 (등록할 때 입력할 값, 비밀 아님)
| 항목 | 값 |
| --- | --- |
| 안드로이드 패키지 이름 (임시, Q-025) | `com.example.futsal_on` |
| 개발용 SHA-1 | `25:99:C8:C1:69:85:E8:5C:7F:CC:8E:AA:C5:23:20:84:54:69:95:79` |
| 카카오 키 해시 | `JZnIwWmF6Fx/zI6qxSMghFRplXk=` |
| Supabase 콜백 주소 | `https://<프로젝트ID>.supabase.co/auth/v1/callback` (1번을 마치면 확정) |

---

## 1. Supabase (먼저)
1. https://supabase.com 가입 → New project
   - 이름 `futsal-on-dev`, 지역 **Northeast Asia (Seoul)**, 요금제 Free
   - Database Password는 직접 정하고 `.env.local`의 `SUPABASE_DEV_DB_PASSWORD`에 적기
2. Project Settings → API (또는 Data API)
   - Project URL → `SUPABASE_DEV_URL`
   - anon / publishable 키 → `SUPABASE_DEV_ANON_KEY`
   - **service_role / secret 키는 적지 않는다** (필요 없음)
3. 콜백 주소 = Project URL 뒤에 `/auth/v1/callback`. 2·3번에서 씀

## 2. 카카오 디벨로퍼스
1. https://developers.kakao.com → 내 애플리케이션 → 애플리케이션 추가 (앱 이름 `풋살ON`)
2. 앱 키 → **네이티브 앱 키** → `KAKAO_NATIVE_APP_KEY` (로그인·카카오맵에 같이 씀)
3. 플랫폼 → Android 등록: 패키지 이름·키 해시는 위 표 값
4. 카카오 로그인 → 활성화 ON, **OpenID Connect 활성화 ON**, Redirect URI에 Supabase 콜백 주소 등록
5. 카카오 로그인 → 보안 → Client Secret 생성, 활성화
6. 동의항목: 닉네임(필수), **카카오계정(이메일)** (같은 이메일 안내 Q-059에 필요. 이메일 항목을 켜려면 "개인 개발자 비즈 앱" 전환이 필요할 수 있음, 무료)
7. Supabase 대시보드 → Authentication → Sign In / Providers → **Kakao** 켜기
   - Client ID = 카카오 **REST API 키**, Client Secret = 5번 값

## 3. 구글 클라우드
1. https://console.cloud.google.com → 새 프로젝트 `futsal-on-dev`
2. OAuth 동의 화면: 외부, 앱 이름 `풋살ON`, 테스트 사용자에 본인 구글 이메일 추가
3. 사용자 인증 정보 → OAuth 클라이언트 ID 2개 만들기
   - **웹 애플리케이션**: 승인된 리디렉션 URI에 Supabase 콜백 주소 → 클라이언트 ID를 `GOOGLE_WEB_CLIENT_ID`에
   - **Android**: 패키지 이름·SHA-1은 위 표 값
4. Supabase 대시보드 → Authentication → Providers → **Google** 켜기
   - Client ID = 웹 클라이언트 ID, Client Secret = 웹 클라이언트 보안 비밀

## 4. GitHub
1. https://github.com 가입(또는 기존 계정) → New repository
   - 이름 `futsal-on`, **Private**, README 등은 체크하지 않음
2. 저장소 주소(`https://github.com/계정/futsal-on`)를 lead에게 알려주기
3. 처음 올릴 때 브라우저 로그인 창이 한 번 뜨면 로그인


## 5. Firebase (푸시 알림, 스프린트 02)
푸시 알림을 보내려면 Firebase가 필요하다. 무료(Spark 요금제)로 충분하다.
1. https://console.firebase.google.com → **프로젝트 추가** → "기존 Google Cloud 프로젝트에 Firebase 추가"에서 **`futsal-on-dev`** 선택 (구글 로그인용으로 만든 프로젝트와 같은 것) → 요금제 Spark, Google 애널리틱스는 **사용 안 함**
2. 프로젝트 설정 → 내 앱 → **Android 앱 추가**
   - 패키지 이름 `com.example.futsal_on`, 디버그 SHA-1은 위 표 값
   - 내려받은 **`google-services.json`**을 `C:\Users\sdt\SDT_project\futsal-app\app\android\app\google-services.json`에 저장 (Git에 안 올라가게 설정됨)
3. 프로젝트 설정 → **서비스 계정** → "새 비공개 키 생성" → 내려받은 JSON 파일을 `C:\Users\sdt\SDT_project\futsal-app\.secrets\firebase-service-account.json`에 저장 (Git에 안 올라가게 설정됨, 서버가 푸시를 보낼 때만 사용)
4. Cloud Messaging API(V1)가 켜져 있는지 확인 (프로젝트 설정 → 클라우드 메시징). 예전 방식(서버 키)은 쓰지 않음
- iOS 앱 추가와 APNs 키는 애플 유료 계정이 생긴 뒤에 한다
## 나중에 (지금 안 해도 됨)
| 항목 | 시점 |
| --- | --- |
| Firebase iOS 설정·APNs 키 | 애플 유료 계정 후 |
| Supabase 운영용 프로젝트 | 출시 준비 때 |
| 애플 개발자 계정 (연 99달러) | 테스트 배포 직전 |
| 구글 플레이 개발자 (25달러) | 테스트 배포 직전 |
| 정식 앱 식별자 (Q-025) | 출시 전. 정해지면 카카오·구글의 패키지 이름·키를 다시 등록 |
