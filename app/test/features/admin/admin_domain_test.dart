import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';

void main() {
  group('경기 설정: 마감이 자동 생성보다 뒤 (3-2, 서버 team_settings_deadline_ok 와 같은 경계)', () {
    bool ok(ClockTime? start, int hours, int days, ClockTime at) =>
        MatchSettingsValidator.deadlineAfterAutoCreate(
          regularStart: start,
          rsvpDeadlineHours: hours,
          autoCreateDaysBefore: days,
          autoCreateTime: at,
        );
    const nine = ClockTime(9, 0);
    const eight = ClockTime(20, 0);

    test('기본값(6일 전 09:00, 2시간 전 마감)은 통과', () {
      expect(ok(eight, 2, 6, nine), isTrue);
    });
    test('20:00 경기, 0일 전 09:00 생성: 11시간 전 마감(=09:00)은 불가, 10시간은 허용', () {
      expect(ok(eight, 11, 0, nine), isFalse);
      expect(ok(eight, 10, 0, nine), isTrue);
    });
    test('20:00 경기, 0일 전 09:00 생성, 40시간 전 마감은 불가', () {
      expect(ok(eight, 40, 0, nine), isFalse);
    });
    test('경기보다 늦은 시각에 같은 날 생성하면 마감 0시간도 불가', () {
      expect(ok(const ClockTime(8, 0), 0, 0, nine), isFalse);
    });
    test('정기 운동 시작 시각이 없으면 검사하지 않는다', () {
      expect(ok(null, 40, 0, nine), isTrue);
    });
  });

  group('경기 설정 입력 범위', () {
    Set<MatchSettingsError> v(MatchSettings s, {ClockTime? start}) =>
        MatchSettingsValidator.validate(s, regularStart: start);
    const base = MatchSettings.defaults;

    test('기본값은 정원 없음·2시간 전 마감·6일 전 09:00 (Q-066)', () {
      expect(base.capacity, isNull);
      expect(base.rsvpDeadlineHours, 2);
      expect(base.autoCreateDaysBefore, 6);
      expect(base.autoCreateTime, const ClockTime(9, 0));
      expect(v(base, start: const ClockTime(20, 0)), isEmpty);
    });
    test('정원 1~100', () {
      expect(v(base.copyWith(capacity: () => 1)), isEmpty);
      expect(v(base.copyWith(capacity: () => 100)), isEmpty);
      expect(v(base.copyWith(capacity: () => 0)), {MatchSettingsError.capacityRange});
      expect(v(base.copyWith(capacity: () => 101)), {MatchSettingsError.capacityRange});
    });
    test('마감 0~720시간, 자동 생성 0~30일', () {
      expect(v(base.copyWith(rsvpDeadlineHours: 721)), {MatchSettingsError.deadlineRange});
      expect(v(base.copyWith(rsvpDeadlineHours: -1)), {MatchSettingsError.deadlineRange});
      expect(v(base.copyWith(autoCreateDaysBefore: 31)), {MatchSettingsError.autoCreateDaysRange});
    });
    test('마감이 자동 생성보다 앞서면 오류', () {
      expect(
        v(base.copyWith(rsvpDeadlineHours: 40, autoCreateDaysBefore: 0), start: const ClockTime(20, 0)),
        {MatchSettingsError.deadlineBeforeAutoCreate},
      );
    });
  });

  group('그룹·라이벌 모순 (3-7)', () {
    PairingRule g(String id, List<String> u, {bool on = true}) =>
        PairingRule(id: id, kind: PairingKind.group, enabled: on, userIds: u);
    PairingRule r(String id, List<String> u, {bool on = true}) =>
        PairingRule(id: id, kind: PairingKind.rival, enabled: on, userIds: u);

    test('같은 두 사람이 그룹과 라이벌에 함께 있으면 모순', () {
      expect(PairingRules.findConflicts([g('g1', ['a', 'b']), r('r1', ['a', 'b'])]), [
        const PairingConflict(rivalRuleId: 'r1', userA: 'a', userB: 'b'),
      ]);
    });
    test('그룹이 이어져 생긴 간접 모순도 찾는다 (a-b, b-c 그룹 + a-c 라이벌)', () {
      final c = PairingRules.findConflicts([
        g('g1', ['a', 'b']),
        g('g2', ['b', 'c']),
        r('r1', ['a', 'c']),
      ]);
      expect(c, [const PairingConflict(rivalRuleId: 'r1', userA: 'a', userB: 'c')]);
    });
    test('꺼진 설정은 모순 검사에서 뺀다', () {
      expect(PairingRules.findConflicts([g('g1', ['a', 'b'], on: false), r('r1', ['a', 'b'])]), isEmpty);
      expect(PairingRules.findConflicts([g('g1', ['a', 'b']), r('r1', ['a', 'b'], on: false)]), isEmpty);
      expect(
        PairingRules.findConflicts([
          g('g1', ['a', 'b']),
          g('g2', ['b', 'c'], on: false),
          r('r1', ['a', 'c']),
        ]),
        isEmpty,
      );
    });
    test('겹치지 않으면 모순 없음', () {
      expect(PairingRules.findConflicts([g('g1', ['a', 'b']), r('r1', ['a', 'c'])]), isEmpty);
      expect(PairingRules.findConflicts([r('r1', ['a', 'b']), r('r2', ['a', 'b'])]), isEmpty);
    });
    test('세 명 라이벌이면 같은 묶음인 쌍마다 알려준다', () {
      final c = PairingRules.findConflicts([g('g1', ['a', 'b', 'c']), r('r1', ['a', 'b', 'd'])]);
      expect(c, [const PairingConflict(rivalRuleId: 'r1', userA: 'a', userB: 'b')]);
    });
    test('저장 전 확인: 새 설정·고친 설정·켜기를 반영해 검사', () {
      final current = [g('g1', ['a', 'b']), r('r1', ['a', 'c'])];
      // 새 라이벌 a-b → 모순
      expect(
        PairingRules.conflictsAfterSave(
          current,
          const PairingRule(id: null, kind: PairingKind.rival, enabled: true, userIds: ['a', 'b']),
        ),
        isNotEmpty,
      );
      // 그룹 g1 을 a-c 로 고치면 기존 라이벌 r1 과 모순
      expect(PairingRules.conflictsAfterSave(current, g('g1', ['a', 'c'])), isNotEmpty);
      // 그룹 g1 을 끄면 모순 없음
      expect(PairingRules.conflictsAfterSave(current, g('g1', ['a', 'b'], on: false)), isEmpty);
    });
    test('사람 수: 2명 이상, 중복 없음', () {
      expect(PairingRules.membersValid(['a', 'b']), isTrue);
      expect(PairingRules.membersValid(['a']), isFalse);
      expect(PairingRules.membersValid([]), isFalse);
      expect(PairingRules.membersValid(['a', 'a']), isFalse);
    });
  });

  group('실력 등급', () {
    test('서버 값 → 등급, 없으면 미정', () {
      expect(SkillLevel.fromServer('semipro'), SkillLevel.semipro);
      expect(SkillLevel.fromServer(null), SkillLevel.undecided);
      expect(SkillLevel.fromServer('weird'), SkillLevel.undecided);
    });
  });
}

