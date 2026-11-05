import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/auth/domain/signup_consent.dart';

void main() {
  group('SignupConsent', () {
    test('처음에는 모두 해제 (부상 정보 포함, Q-064)', () {
      const c = SignupConsent();
      expect(c.age14 || c.terms || c.privacy || c.injuryInfo, isFalse);
      expect(c.allAgreed, isFalse);
      expect(c.requiredAgreed, isFalse);
    });

    test('전체 동의는 부상 정보까지 체크 (Q-060 3번)', () {
      final c = const SignupConsent().withAll(true);
      expect(
        c,
        const SignupConsent(
          age14: true,
          terms: true,
          privacy: true,
          injuryInfo: true,
        ),
      );
      expect(c.allAgreed, isTrue);
    });

    test('전체 동의 해제는 모두 해제', () {
      final c = const SignupConsent().withAll(true).withAll(false);
      expect(c, const SignupConsent());
    });

    test('필수 3개만 체크하면 다음 단계 가능, 전체 동의는 아님', () {
      const c = SignupConsent(age14: true, terms: true, privacy: true);
      expect(c.requiredAgreed, isTrue);
      expect(c.allAgreed, isFalse);
    });

    test('필수 하나라도 빠지면 다음 단계 불가', () {
      const base = SignupConsent(
        age14: true,
        terms: true,
        privacy: true,
        injuryInfo: true,
      );
      expect(base.copyWith(age14: false).requiredAgreed, isFalse);
      expect(base.copyWith(terms: false).requiredAgreed, isFalse);
      expect(base.copyWith(privacy: false).requiredAgreed, isFalse);
    });

    test('부상 정보는 선택: 해제해도 다음 단계 가능', () {
      final c = const SignupConsent().withAll(true).copyWith(injuryInfo: false);
      expect(c.requiredAgreed, isTrue);
      expect(c.allAgreed, isFalse);
    });
  });
}
