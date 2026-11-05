import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/team/data/team_repository.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/team/domain/recent_teams.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

void main() {
  const t2000 = ClockTime(20, 0);
  const t2200 = ClockTime(22, 0);
  const t0030 = ClockTime(0, 30);

  group('정기 운동일 (3-1, Q-067 4번)', () {
    Set<RegularScheduleError> v({int? weekday, ClockTime? start, ClockTime? end}) =>
        TeamValidator.validateRegularSchedule(weekday: weekday, start: start, end: end);

    test('모두 비어도 된다 (선택 항목)', () => expect(v(), isEmpty));
    test('요일만', () => expect(v(weekday: 3), isEmpty));
    test('요일 + 시작 + 종료', () => expect(v(weekday: 3, start: t2000, end: t2200), isEmpty));
    test('자정 넘김 허용: 22:00~00:30', () {
      expect(v(weekday: 5, start: t2200, end: t0030), isEmpty);
      expect(TeamValidator.crossesMidnight(t2200, t0030), isTrue);
      expect(TeamValidator.crossesMidnight(t2000, t2200), isFalse);
    });
    test('시작 = 종료는 불가', () {
      expect(v(weekday: 5, start: t2200, end: t2200), {RegularScheduleError.sameStartEnd});
    });
    test('시각만 있고 요일 없음, 종료만 있고 시작 없음은 불가', () {
      expect(v(start: t2000), {RegularScheduleError.weekdayRequired});
      expect(v(weekday: 1, end: t2200), {RegularScheduleError.startRequired});
    });
    test('표시: 자정 넘김이면 "다음날"', () {
      expect(
        TeamTexts.schedule(const RegularSchedule(weekday: 5, start: t2200, end: t0030)),
        '매주 금 22:00~다음날 00:30',
      );
      expect(
        TeamTexts.schedule(const RegularSchedule(weekday: 3, start: t2000, end: t2200)),
        '매주 수 20:00~22:00',
      );
      expect(TeamTexts.schedule(const RegularSchedule()), isNull);
    });
    test('서버 시각 문자열 읽기', () {
      expect(ClockTime.parse('20:00:00'), t2000);
      expect(ClockTime.parse('00:30'), t0030);
      expect(t0030.hhmm, '00:30');
    });
  });

  group('팀 해체 확인 입력 (Q-067 7번)', () {
    bool m(String name, String input) =>
        TeamValidator.dissolveConfirmationMatches(teamName: name, input: input);

    test('같은 이름', () => expect(m('코코 FC', '코코 FC'), isTrue));
    test('앞뒤 공백 무시', () => expect(m('코코 FC', '  코코 FC  '), isTrue));
    test('가운데 연속 공백은 하나로 정리 후 비교', () => expect(m('코코 FC', '코코   FC'), isTrue));
    test('영문 대소문자 무시', () => expect(m('코코 FC', '코코 fc'), isTrue));
    test('보이지 않는 문자 무시', () => expect(m('코코 FC', '코코​ FC'), isTrue));
    test('다른 이름·빈 입력은 불일치', () {
      expect(m('코코 FC', '코코'), isFalse);
      expect(m('코코 FC', '코코FC'), isFalse);
      expect(m('코코 FC', ''), isFalse);
      expect(m('코코 FC', '   '), isFalse);
    });
  });

  group('마지막으로 본 팀 (Q-067 6번)', () {
    test('최근 본 팀이 열린다', () {
      expect(RecentTeams.pick(recent: ['b', 'a'], myTeamIds: ['a', 'b', 'c']), 'b');
    });
    test('기록에 없으면 목록 첫 팀', () {
      expect(RecentTeams.pick(recent: [], myTeamIds: ['a', 'b']), 'a');
      expect(RecentTeams.pick(recent: ['x'], myTeamIds: ['a', 'b']), 'a');
    });
    test('소속 팀이 없으면 null (만들기·찾기 홈)', () {
      expect(RecentTeams.pick(recent: ['a'], myTeamIds: []), isNull);
    });
    test('떠난 팀을 빼면 가장 최근에 본 다른 팀', () {
      final recent = RecentTeams.forget(['b', 'c', 'a'], 'b');
      expect(RecentTeams.pick(recent: recent, myTeamIds: ['a', 'c']), 'c');
    });
    test('touch 는 맨 앞으로, 중복 없음, 최대 개수', () {
      expect(RecentTeams.touch(['a', 'b', 'c'], 'c'), ['c', 'a', 'b']);
      final many = [for (var i = 0; i < 30; i++) '$i'];
      expect(RecentTeams.touch(many, 'new').length, RecentTeams.maxKept);
    });
  });

  test('팀원 명단 정렬: 팀장 → 운영진 → 팀원, 같은 역할은 이름순', () {
    final sorted = sortMembers(const [
      MemberEntry(userId: '1', role: TeamRole.member, displayName: '나'),
      MemberEntry(userId: '2', role: TeamRole.manager, displayName: '하'),
      MemberEntry(userId: '3', role: TeamRole.owner, displayName: '타'),
      MemberEntry(userId: '4', role: TeamRole.member, displayName: '가'),
      MemberEntry(userId: '5', role: TeamRole.manager, displayName: '다'),
    ]);
    expect([for (final m in sorted) m.userId], ['3', '5', '2', '4', '1']);
  });
}
