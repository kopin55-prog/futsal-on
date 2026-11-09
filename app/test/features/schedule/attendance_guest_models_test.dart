import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/shared/domain/position.dart';

Map<String, dynamic> _row(String id, String user, String state, {String? waitlistedAt, String? updatedAt}) => {
  'id': id,
  'match_id': 'm1',
  'user_id': user,
  'state': state,
  'waitlisted_at': waitlistedAt,
  'promoted_at': null,
  'responded_at': '2027-01-01T00:00:00+00:00',
  'updated_at': updatedAt ?? '2027-01-01T00:00:00+00:00',
};

MatchGuest _guest(int no, [String? name]) =>
    MatchGuest(id: 'g$no', matchId: 'm1', guestNo: no, name: name, createdAt: DateTime.utc(2027));

void main() {
  final schema = File('../supabase/migrations/202611050019_matches_attendance_guests.sql').readAsStringSync();
  final allMigrations = Directory('../supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');

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

    test('명단 순서 (Q-073 7번): 참석·불참은 마지막으로 바꾼 시각 순, 미투표는 가나다순', () {
      final roster = AttendanceRoster([
        _row('r1', 'u1', 'attending', updatedAt: '2027-01-01T00:00:03+00:00'),
        _row('r2', 'u2', 'attending', updatedAt: '2027-01-01T00:00:01+00:00'),
        // 대기에서 자동 참석: 참석이 된 시각(updated_at)이 가장 늦다
        _row('r3', 'u3', 'attending', updatedAt: '2027-01-01T00:00:09+00:00'),
        _row('r4', 'u4', 'declined', updatedAt: '2027-01-01T00:00:05+00:00'),
        _row('r5', 'u5', 'declined', updatedAt: '2027-01-01T00:00:02+00:00'),
      ].map(AttendanceResponse.fromRow));
      expect([for (final r in roster.attending) r.userId], ['u2', 'u1', 'u3']);
      expect([for (final r in roster.declined) r.userId], ['u5', 'u4']);
      expect(
        roster.notRespondedSorted({'u1': '가', 'u9': '하늘', 'u7': '나무', 'u8': '다리', 'u6': '나무'}),
        ['u6', 'u7', 'u8', 'u9'],
      );
    });

    test('select 칸은 서버 응답 표에 있는 칸만', () {
      for (final c in AttendanceResponse.columns.split(',').map((e) => e.trim())) {
        expect(schema.contains(RegExp('^  $c ', multiLine: true)), isTrue, reason: c);
      }
    });
  });

  group('게스트', () {
    test('팀원용 select 칸은 권한 있는 칸만 (포지션 없음)', () {
      final granted = {
        for (final m in RegExp(r'grant select \(([^)]*)\) on table public\.match_guests').allMatches(allMigrations))
          ...m.group(1)!.split(',').map((e) => e.trim()),
      };
      expect(granted.contains('positions'), isFalse);
      for (final c in MatchGuest.columns.split(',').map((e) => e.trim())) {
        expect(granted, contains(c));
      }
      expect(MatchGuest.columns.contains('positions'), isFalse);
    });

    test('관리자용 정보 읽기', () {
      final d = MatchGuestDetail.fromRow({
        'id': 'g1',
        'guest_no': 1,
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
        'guest_no': 2,
        'name': null,
        'positions': null,
        'skill_level': 'undecided',
        'added_by': 'u1',
        'created_at': '2027-01-01T00:00:00+00:00',
      });
      expect(none.positions, isEmpty);
      expect(none.skillLevel, SkillLevel.undecided);
      expect(none.displayName, '게스트2');
    });

    test('표시 이름: 이름이 없으면 "게스트N" (Q-073 2번)', () {
      final g = MatchGuest.fromRow({
        'id': 'g3',
        'match_id': 'm1',
        'guest_no': 3,
        'name': null,
        'added_by': null,
        'created_at': '2027-01-01T00:00:00+00:00',
      });
      expect(g.displayName, '게스트3');
      expect(_guest(4, '용병').displayName, '용병');
    });

    test('다음 번호는 가장 큰 번호 + 1 (지워도 다른 번호는 그대로)', () {
      expect(GuestInput.nextGuestNo(const []), 1);
      expect(GuestInput.nextGuestNo([_guest(2), _guest(5, '용병')]), 6);
    });

    test('같은 일정 안 같은 표시 이름 불가, 최대 12명 (Q-073 3번)', () {
      final existing = [_guest(1), _guest(2, '김 철수')];
      expect(const GuestInput(name: ' 김  철수').validate(existing: existing), {GuestInputError.duplicateName});
      expect(const GuestInput(name: '게스트1').validate(existing: existing), {GuestInputError.duplicateName});
      expect(const GuestInput().validate(existing: existing), isEmpty);
      // 다음 번호(3) 의 기본 이름 "게스트3" 을 누가 이미 쓰고 있으면 이름을 적어야 한다
      expect(const GuestInput().validate(existing: [_guest(1), _guest(2, '게스트3')]), {GuestInputError.duplicateName});
      final full = [for (var i = 1; i <= 12; i++) _guest(i, '이름$i')];
      expect(const GuestInput(name: '열셋').validate(existing: full), {GuestInputError.tooManyGuests});
    });

    test('이름 규칙: 선택, 적으면 정리 후 1~8자, 줄바꿈 불가', () {
      expect(const GuestInput(name: '  김  철수 ').validate(), isEmpty);
      expect(const GuestInput(name: '여덟글자이름이야').validate(), isEmpty);
      expect(const GuestInput(name: '아홉글자이름입니다').validate(), {GuestInputError.nameTooLong});
      // 비우면(공백만·보이지 않는 문자만) 이름 없음 → "게스트N"
      expect(const GuestInput(name: '   ').validate(), isEmpty);
      expect(const GuestInput(name: '   ').normalizedName, isNull);
      expect(const GuestInput(name: '\u200B').normalizedName, isNull);
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

    test('서버 인자: 이름 정리(비우면 null), 빈 포지션·미정 실력은 null', () {
      expect(const GuestInput(name: '  ').toServerParams('m1')['p_name'], isNull);
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
