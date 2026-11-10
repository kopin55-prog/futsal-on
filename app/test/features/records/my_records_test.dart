import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/records/domain/my_records.dart';

TeamSeasonRecord _r(
  String team,
  int season, {
  String? name,
  bool member = true,
  bool dissolved = false,
  int att = 0,
  int pom = 0,
  int goal = 0,
  int eligible = 0,
  int responded = 0,
}) => TeamSeasonRecord(
  teamId: team,
  teamName: name ?? team,
  logoText: (name ?? team).substring(0, 1),
  isMember: member,
  isDissolved: dissolved,
  season: season,
  attendance: att,
  pom: pom,
  goalOfTheDay: goal,
  voteEligible: eligible,
  voteResponded: responded,
);

void main() {
  group('참석 투표 참여율 (7-7, Q-064)', () {
    test('4번 중 3번 75%, 3번 중 2번 67%(반올림), 8번 중 1번 13%(0.5 올림), 4/4 100%', () {
      expect(RecordTotals.participationPercentOf(3, 4), 75);
      expect(RecordTotals.participationPercentOf(2, 3), 67);
      expect(RecordTotals.participationPercentOf(1, 3), 33);
      expect(RecordTotals.participationPercentOf(1, 8), 13);
      expect(RecordTotals.participationPercentOf(4, 4), 100);
      expect(RecordTotals.participationPercentOf(0, 5), 0);
    });

    test('대상 0회면 null ("기록 없음")', () {
      expect(RecordTotals.participationPercentOf(0, 0), isNull);
      expect(const RecordTotals().participationPercent, isNull);
    });
  });

  group('내 기록 묶기 (S4-12)', () {
    final records = MyRecords([
      _r('a', 2025, name: '코코FC', att: 3, pom: 1, eligible: 3, responded: 2),
      _r('a', 2026, name: '코코FC', att: 5, goal: 2, eligible: 4, responded: 3),
      _r('b', 2026, name: '가나FC', member: false, att: 1),
      _r('e', 2026, name: '다라FC', member: false, dissolved: true, att: 2, pom: 1, goal: 1),
      _r('c', 2024, name: '비FC', att: 7, eligible: 1),
    ]);

    test('시즌은 기록이 있는 연도만 최근 순', () {
      expect(records.seasons, [2026, 2025, 2024]);
    });

    test('누적 전체 합산과 시즌별 합산', () {
      final all = records.total();
      expect(all.attendance, 18);
      expect(all.pom, 2);
      expect(all.goalOfTheDay, 3);
      expect(all.voteEligible, 8);
      expect(all.voteResponded, 5);
      expect(all.participationPercent, 63); // 5/8 = 62.5 → 63

      final y2026 = records.total(season: 2026);
      expect(y2026.attendance, 8);
      expect(y2026.participationPercent, 75);
      expect(records.total(season: 2023).attendance, 0);
    });

    test('팀별: 지금 팀 먼저(이름순), 그다음 떠난 팀·해체된 팀(이름순). 시즌을 고르면 그 시즌 기록이 있는 팀만', () {
      final teams = records.byTeam();
      expect([for (final t in teams) t.teamId], ['c', 'a', 'b', 'e']);
      expect(teams[1].totals.attendance, 8);
      expect(teams[1].totals.participationPercent, 71); // 5/7 = 71.4
      expect(teams.last.isDissolved, isTrue);

      final y2026 = records.byTeam(season: 2026);
      expect([for (final t in y2026) t.teamId], ['a', 'b', 'e']);
      expect(y2026.first.totals.attendance, 5);
    });

    test('줄 변환 (get_my_records 칸 이름)', () {
      final r = TeamSeasonRecord.fromRow({
        'team_id': 't',
        'team_name': '코코FC',
        'logo_text': '코',
        'is_member': false,
        'is_dissolved': true,
        'season': 2026,
        'attendance_count': 4,
        'pom_count': 1,
        'goal_of_the_day_count': 2,
        'vote_eligible': 3,
        'vote_responded': 1,
      });
      expect(r.isDissolved, isTrue);
      expect(r.attendance + r.pom + r.goalOfTheDay, 7);
      expect(r.voteEligible, 3);
    });
  });
}
