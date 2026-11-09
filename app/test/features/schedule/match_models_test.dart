import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/shared/domain/venue.dart';

void main() {
  group('일정 한 줄 읽기 (matches)', () {
    final row = <String, dynamic>{
      'id': 'm1',
      'team_id': 't1',
      'source': 'manual',
      'status': 'cancelled',
      'starts_at': '2027-01-06T01:00:00+00:00',
      'ends_at': '2027-01-06T03:00:00+00:00',
      'rsvp_deadline_at': '2027-01-05T23:00:00+00:00',
      'rsvp_reminder_at': null,
      'capacity': 12,
      'venue_name': '동네 구장',
      'venue_address': null,
      'venue_lat': 37.1,
      'venue_lng': 127.1,
      'venue_map_provider': 'kakao',
      'venue_map_place_id': '777',
      'cancelled_at': '2027-01-01T00:00:00+00:00',
      'cancel_reason': '비 와서 취소',
    };

    test('칸을 모두 읽는다', () {
      final m = TeamMatch.fromRow(row);
      expect(m.source, MatchSource.manual);
      expect(m.isCancelled, isTrue);
      expect(m.startsAt, DateTime.utc(2027, 1, 6, 1));
      expect(m.rsvpReminderAt, isNull);
      expect(m.capacity, 12);
      expect(m.venue, const Venue.kakao(name: '동네 구장', placeId: '777', lat: 37.1, lng: 127.1));
      expect(m.cancelReason, '비 와서 취소');
    });

    test('취소는 시작 전·예정 상태에서만', () {
      final scheduled = TeamMatch.fromRow({...row, 'status': 'scheduled', 'cancelled_at': null, 'cancel_reason': null});
      final start = DateTime.utc(2027, 1, 6, 1);
      expect(scheduled.canBeCancelledAt(start.subtract(const Duration(minutes: 1))), isTrue);
      expect(scheduled.canBeCancelledAt(start), isFalse);
      expect(TeamMatch.fromRow(row).canBeCancelledAt(DateTime.utc(2026)), isFalse);
    });

    test('select 칸은 서버 일정 표에 있는 칸만', () {
      final sql = File('../supabase/migrations/202611050019_matches_attendance_guests.sql').readAsStringSync();
      for (final c in TeamMatch.columns.split(',').map((e) => e.trim())) {
        expect(sql.contains(RegExp('^  $c ', multiLine: true)), isTrue, reason: c);
      }
    });
  });

  group('직접 추가 입력 (create_match 인자)', () {
    test('자정 넘김은 종료 날짜로, 마감·알림은 안 주면 팀 설정', () {
      const input = MatchInput(
        startDate: CalendarDate(2027, 1, 8),
        startTime: ClockTime(23, 0),
        endDate: CalendarDate(2027, 1, 9),
        endTime: ClockTime(1, 0),
      );
      expect(input.toServerParams('t1'), {
        'p_team_id': 't1',
        'p_start_date': '2027-01-08',
        'p_start_time': '23:00',
        'p_end_date': '2027-01-09',
        'p_end_time': '01:00',
        'p_venue': null,
        'p_rsvp_deadline_hours': null,
        'p_rsvp_reminder_hours': null,
      });
    });

    test('미투표 알림 끄기는 0', () {
      const input = MatchInput(
        startDate: CalendarDate(2027, 1, 8),
        startTime: ClockTime(19, 0),
        endDate: CalendarDate(2027, 1, 8),
        endTime: ClockTime(21, 0),
        rsvpDeadlineHours: 5,
        rsvpReminderHours: MatchInput.reminderOff,
      );
      final p = input.toServerParams('t1');
      expect(p['p_rsvp_deadline_hours'], 5);
      expect(p['p_rsvp_reminder_hours'], 0);
    });
  });

  group('경기 설정: 미투표 알림 (Q-072 1번)', () {
    const base = MatchSettings.defaults;

    test('기본 2시간 전, 끄기(null) 가능', () {
      expect(base.rsvpReminderHours, 2);
      expect(MatchSettingsValidator.validate(base.copyWith(rsvpReminderHours: () => null), regularStart: null), isEmpty);
    });

    test('선택지 1·2·3·6·12·24 만', () {
      for (final h in [1, 2, 3, 6, 12, 24]) {
        expect(MatchSettingsValidator.validate(base.copyWith(rsvpReminderHours: () => h), regularStart: null), isEmpty);
      }
      for (final h in [0, 4, 5, 48]) {
        expect(
          MatchSettingsValidator.validate(base.copyWith(rsvpReminderHours: () => h), regularStart: null),
          {MatchSettingsError.reminderRange},
        );
      }
    });

    test('서버 검사와 같은 선택지', () {
      final sql = File('../supabase/migrations/202611050020_team_settings_rsvp_reminder.sql').readAsStringSync();
      expect(sql.contains('rsvp_reminder_hours in (${MatchSettings.reminderHourOptions.join(', ')})'), isTrue);
    });
  });

  group('직접 추가 화면 검사 (서버 create_match 와 같은 규칙)', () {
    // 2027-01-06 09:00 KST = 2027-01-06 00:00 UTC
    final now = DateTime.utc(2027, 1, 6);
    MatchInput input(CalendarDate sd, ClockTime st, CalendarDate ed, ClockTime et, {int? deadline}) =>
        MatchInput(startDate: sd, startTime: st, endDate: ed, endTime: et, rsvpDeadlineHours: deadline);
    const d6 = CalendarDate(2027, 1, 6);
    const d7 = CalendarDate(2027, 1, 7);

    test('한국 시간 날짜·시각 → 절대 시각', () {
      expect(Kst.toInstant(d6, const ClockTime(10, 0)), DateTime.utc(2027, 1, 6, 1));
      expect(Kst.dateOf(DateTime.utc(2027, 1, 6, 15)), d7);
      expect(Kst.timeOf(DateTime.utc(2027, 1, 6, 15, 30)), const ClockTime(0, 30));
      expect(d6.weekday, 3);
      expect(const CalendarDate(2026, 12, 31).plusDays(1), const CalendarDate(2027, 1, 1));
    });

    test('정상 / 자정 넘김은 종료 날짜로', () {
      expect(input(d6, const ClockTime(20, 0), d6, const ClockTime(22, 0)).validate(now), isEmpty);
      expect(input(d6, const ClockTime(22, 0), d7, const ClockTime(0, 30)).validate(now), isEmpty);
    });

    test('종료가 시작과 같거나 이르면 불가 (같은 날짜 10:00~09:00)', () {
      expect(input(d6, const ClockTime(10, 0), d6, const ClockTime(10, 0)).validate(now), {MatchInputError.endNotAfterStart});
      expect(input(d6, const ClockTime(22, 0), d6, const ClockTime(0, 30)).validate(now), {MatchInputError.endNotAfterStart});
    });

    test('24시간 초과 불가, 24시간 정확히는 가능 (Q-073 9번)', () {
      expect(input(d6, const ClockTime(10, 0), d7, const ClockTime(10, 0)).validate(now), isEmpty);
      expect(input(d6, const ClockTime(10, 0), d7, const ClockTime(10, 1)).validate(now), {MatchInputError.tooLong});
    });

    test('지난 시각 불가 (지금 09:00)', () {
      expect(input(d6, const ClockTime(9, 0), d6, const ClockTime(11, 0)).validate(now), {MatchInputError.startInPast});
      expect(input(d6, const ClockTime(9, 1), d6, const ClockTime(11, 0)).validate(now), isEmpty);
    });

    test('마감 0~720시간', () {
      expect(input(d6, const ClockTime(20, 0), d6, const ClockTime(22, 0), deadline: 721).validate(now), {MatchInputError.deadlineRange});
      expect(input(d6, const ClockTime(20, 0), d6, const ClockTime(22, 0), deadline: 0).validate(now), isEmpty);
    });
  });
}
