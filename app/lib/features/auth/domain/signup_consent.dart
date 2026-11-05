/// 가입 단계 동의 선택 상태 (data-model.md 2-2, 8-1, docs/consent-texts.md).
///
/// - 필수: 만 14세 이상 확인(Q-023), 이용약관·개인정보 수집·이용(Q-053)
/// - 선택: 부상 정보 수집·이용(Q-049). 처음에는 해제 상태(Q-064 4번).
/// - "전체 동의"는 선택 항목(부상 정보)까지 모두 체크·해제한다(Q-060 3번, Q-064 4번).
class SignupConsent {
  const SignupConsent({
    this.age14 = false,
    this.terms = false,
    this.privacy = false,
    this.injuryInfo = false,
  });

  /// 만 14세 이상입니다 [필수]
  final bool age14;

  /// 이용약관 동의 [필수]
  final bool terms;

  /// 개인정보 수집·이용 동의 [필수]
  final bool privacy;

  /// 부상 정보 수집·이용 동의 [선택]
  final bool injuryInfo;

  /// 네 항목이 모두 체크되어 있으면 "전체 동의"가 체크된 것으로 보인다.
  bool get allAgreed => age14 && terms && privacy && injuryInfo;

  /// 필수 항목이 모두 체크되어 다음 단계로 갈 수 있는지.
  bool get requiredAgreed => age14 && terms && privacy;

  /// "전체 동의"를 누름: 부상 정보까지 모두 [value]로.
  SignupConsent withAll(bool value) => SignupConsent(
    age14: value,
    terms: value,
    privacy: value,
    injuryInfo: value,
  );

  SignupConsent copyWith({
    bool? age14,
    bool? terms,
    bool? privacy,
    bool? injuryInfo,
  }) => SignupConsent(
    age14: age14 ?? this.age14,
    terms: terms ?? this.terms,
    privacy: privacy ?? this.privacy,
    injuryInfo: injuryInfo ?? this.injuryInfo,
  );

  @override
  bool operator ==(Object other) =>
      other is SignupConsent &&
      other.age14 == age14 &&
      other.terms == terms &&
      other.privacy == privacy &&
      other.injuryInfo == injuryInfo;

  @override
  int get hashCode => Object.hash(age14, terms, privacy, injuryInfo);
}
