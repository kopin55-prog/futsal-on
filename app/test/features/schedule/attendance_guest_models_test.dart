import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/shared/domain/position.dart';

Map<String, dynamic> _row(String id, String user, String state, {String? waitlistedAt}) => {
  'id': id,
  'match_id': 'm1',
  'user_id': user,
  'state': state,
  'waitlisted_at': waitlistedAt,
  'promoted_at': null,
  'responded_at': '2027-01-01T00:00:00+00:00',
  'updated_at': '2027-01-01T00:00:00+00:00',
};

void main() {
  final schema = File('../supabase/migrations/202611050019_matches_attendance_guests.sql').readAsStringSync();

  group('참석 응답', () {
    test('한 줄 읽기', () {
      final r = AttendanceResponse.fromRow({
        ..._row('r1', 'u1', 'attending'),
        'promoted_at': '2027-01-02T00:00:00+00:00',
        'updated_at': '2027-01-02T00:00:00+00:00',
      });
      expect(r.state, AttendanceState.attending);
      expect(r.promotedAt, DateTime.utc(2027, 1, 2));
      expect(r.waitlistedAt, isNull);
      expect(r.respondedAt.isBefore(r.updatedAt), isTrue);
    });

    test('대기 순번은 waitlisted_at 순, 같으면 id 순', () {
      final roster = AttendanceRoster([
        _row('r1', 'u1', 'attending'),
        _row('r4', 'u4', 'waitlisted', waitlistedAt: '2027-01-01T00:00:02+00:00'),
        _row('r3', 'u3', 'waitlisted', waitlistedAt: '2027-01-01T00:00:01+00:00'),
        _row('r2', 'u2', 'waitlisted', waitlistedAt: '2027-01-01T00:00:01+00:00'),
        _row('r5', 'u5', 'declined'),
      ].map(AttendanceResponse.fromRow));
      expect(roster.waitlistPosition('u2'), 1);
      expect(roster.waitlistPosition('u3'), 2);
      expect(roster.waitlistPosition('u4'), 3);
      expect(roster.waitlistPosition('u1'), isNull);
      expect(roster.attendingCount, 1);
      expect(roster.responseOf('u9'), isNull);
      expect(roster.notRespondedAmong(['u1', 'u5', 'u9']), ['u9']);
    });

    test('select 칸은 서버 응답 표에 있는 칸만', () {
      for (final c in AttendanceResponse.columns.split(',').map((e) => e.trim())) {
        expect(schema.contains(RegExp('^  $c ', multiLine: true)), isTrue, reason: c);
      }
    });
  });

  group('게스트', () {
    test('팀원용 select 칸은 권한 있는 칸만 (포지션 없음)', () {
      final grant = RegExp(r'grant select \(([^)]*)\) on table public\.match_guests').firstMatch(schema)!.group(1)!;
      final granted = grant.split(',').map((e) => e.trim()).toSet();
      for (final c in MatchGuest.columns.split(',').map((e) => e.trim())) {
        expect(granted, contains(c));
      }
      expect(MatchGuest.columns.contains('positions'), isFalse);
    });

    test('관리자용 정보 읽기', () {
      final d = MatchGuestDetail.fromRow({
        'id': 'g1',
        'name': '김 철수',
        'positions': ['goalkeeper', 'winger'],
        'skill_level': 'amateur',
        'added_by': null,
        'created_at': '2027-01-01T00:00:00+00:00',
      });
      expect(d.positions, [Position.goalkeeper, Position.winger]);
      expect(d.skillLevel, SkillLevel.amateur);
      final none = MatchGuestDetail.fromRow({
        'id': 'g2',
        'name': '박',
        'positions': null,
        'skill_level': 'undecided',
        'added_by': 'u1',
        'created_at': '2027-01-01T00:00:00+00:00',
      });
      expect(none.positions, isEmpty);
      expect(none.skillLevel, SkillLevel.undecided);
    });

    test('이름 규칙: 정리 후 1~8자, 줄바꿈 불가', () {
      expect(const GuestInput(name: '  김  철수 ').validate(), isEmpty);
      expect(const GuestInput(name: '여덟글자이름이야').validate(), isEmpty);
      expect(const GuestInput(name: '아홉글자이름입니다').validate(), {GuestInputError.nameTooLong});
      expect(const GuestInput(name: '   ').validate(), {GuestInputError.nameRequired});
      expect(const GuestInput(name: '​').validate(), {GuestInputError.nameRequired});
      expect(const GuestInput(name: '줄\n바꿈').validate(), contains(GuestInputError.nameHasLineBreak));
      expect(const GuestInput(name: '👨‍👩‍👧가족').validate(), isEmpty);
    });

    test('포지션 최대 3개, 중복 불가', () {
      expect(
        const GuestInput(name: '넷', positions: Position.values).validate(),
        {GuestInputError.tooManyPositions},
      );
      expect(
        const GuestInput(name: '중복', positions: [Position.winger, Position.winger]).validate(),
        {GuestInputError.duplicatePositions},
      );
    });

    test('서버 인자: 이름 정리, 빈 포지션·미정 실력은 null', () {
      expect(const GuestInput(name: ' 김  철수 ', skillLevel: SkillLevel.undecided).toServerParams('m1'), {
        'p_match_id': 'm1',
        'p_name': '김 철수',
        'p_positions': null,
        'p_skill_level': null,
      });
      expect(
        const GuestInput(name: '박', positions: [Position.defender], skillLevel: SkillLevel.pro).toServerParams('m1'),
        {
          'p_match_id': 'm1',
          'p_name': '박',
          'p_positions': ['defender'],
          'p_skill_level': 'pro',
        },
      );
    });
  });
}
