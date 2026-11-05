/// 로그인·가입 동의 화면 문구.
///
/// - [ConsentTexts]: docs/consent-texts.md 확정 문구 (부상 정보 동의 kopn 확인 2026-11-05, Q-057).
/// - [AuthTempTexts]: 문서에 없는 임시 문구. 모두 TODO(문구 미정) — lead 확인 후 교체.
library;

abstract final class ConsentTexts {
  static const age14Title = '[필수] 만 14세 이상입니다';
  static const age14Body = '만 14세 미만은 풋살ON에 가입할 수 없어요.';
  static const termsTitle = '[필수] 이용약관 동의';
  static const termsLink = '이용약관 보기';
  static const privacyTitle = '[필수] 개인정보 수집·이용 동의';
  static const privacyLink = '개인정보 처리방침 보기';
  static const injuryTitle = '[선택] 부상 정보 수집·이용 동의';
  static const injuryBody =
      '부상을 기록하려면 동의가 필요해요. 동의하지 않아도 풋살ON을 이용할 수 있고, '
      '부상 기록 기능만 쓸 수 없어요.';

  /// (항목, 내용) 표
  static const injuryTable = <(String, String)>[
    ('수집 항목', '부상 여부, 예상 회복 기간, 부상 메모(20자 이내)'),
    ('이용 목적', '소속 팀의 부상 인원 표시, 팀 운영 기록과 운영진용 팀 리포트 제공'),
    ('공개 범위', '내가 소속된 팀의 팀원 (팀 리포트는 팀장·운영진)'),
    ('보유 기간', '동의 철회 또는 회원 탈퇴 시까지 (철회·탈퇴 즉시 삭제)'),
    ('거부 권리', '동의하지 않을 수 있으며, 이 경우 부상 기록 기능만 이용할 수 없어요'),
  ];
  static const injuryWithdrawNote =
      '동의는 프로필 설정에서 언제든 철회할 수 있어요. 철회하면 부상 기록이 바로 삭제돼요.';

  /// "전체 동의" (Q-060 3번): 부상 정보까지 모두 체크
  static const agreeAll = '전체 동의';
}

// TODO(문구 미정): 아래는 모두 임시 문구. 화면 문구 확정 시 교체.
abstract final class AuthTempTexts {
  static const appTitle = '풋살ON';
  static const loginWithKakao = '카카오로 로그인';
  static const loginWithGoogle = '구글로 로그인';
  static const loginWithApple = 'Apple로 로그인';
  static const loginFailed = '로그인하지 못했어요. 다시 시도해 주세요.'; // U-06
  static const loginKakaoIdTokenMissing = '카카오 로그인 설정을 확인해 주세요. (개발용 안내)';
  static const loginNotSupported = '아직 준비 중인 로그인 방법이에요.';
  static const consentTitle = '서비스 이용 동의';
  static const next = '다음';
  static const documentPending = '본문은 출시 전에 공개돼요.'; // 약관·처리방침 본문 미작성
  static const close = '닫기';
  static const signOut = '로그아웃';
  static const configMissing =
      '앱 설정값이 없어요 (개발용 안내). config/dev.json 으로 실행해 주세요.';
  static const loadFailed = '정보를 불러오지 못했어요.';
  static const retry = '다시 시도';
  static const homePlaceholder = '가입이 완료됐어요. (다음 화면 준비 중)';
}
