import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/domain/skill_score.dart';
import 'package:futsal_on/shared/data/server_error.dart';

void main() {
  test('실력 점수 10점 단위, 미정 = 아마추어 (Q-075 5번)', () {
    expect(SkillScore.of(SkillLevel.beginner), 10);
    expect(SkillScore.of(SkillLevel.amateur), 20);
    expect(SkillScore.of(SkillLevel.semipro), 30);
    expect(SkillScore.of(SkillLevel.pro), 40);
    expect(SkillScore.of(SkillLevel.undecided), 20);
  });

  test('조끼 색 자동 배정 순서 (Q-075 8번)', () {
    expect(BibColor.defaults(2), [BibColor.red, BibColor.blue]);
    expect(BibColor.defaults(11), BibColor.values);
    expect(BibColor.defaults(11).last, BibColor.noBib);
    expect(BibColor.noBib.serverValue, 'no_bib');
    expect(BibColor.fromServer('navy'), BibColor.navy);
    expect(() => BibColor.defaults(12), throwsRangeError);
  });

  test('저장 인자: 팀 블록 번호·조끼 색·명단(교체 = squad_no null)·경고', () {
    const draft = LineupDraft(
      playersPerTeam: 2,
      squads: [
        LineupSquadDraft(bibColor: BibColor.noBib, people: [LineupPerson.member('u1'), LineupPerson.guest('g1')]),
        LineupSquadDraft(bibColor: BibColor.blue, people: [LineupPerson.member('u2')]),
      ],
      bench: [LineupPerson.member('u3')],
      warnings: {LineupWarningKind.rivalSameTeam, LineupWarningKind.dedicatedGkOverTeams},
    );
    final params = draft.toServerParams('m1', expectedUpdatedAt: '2026-11-10T00:00:00.123456+00:00', confirm: true);
    expect(params, {
      'p_match_id': 'm1',
      'p_expected_updated_at': '2026-11-10T00:00:00.123456+00:00',
      'p_team_count': 2,
      'p_players_per_team': 2,
      'p_squads': [
        {'squad_no': 1, 'bib_color': 'no_bib'},
        {'squad_no': 2, 'bib_color': 'blue'},
      ],
      'p_slots': [
        {'squad_no': 1, 'user_id': 'u1'},
        {'squad_no': 1, 'guest_id': 'g1'},
        {'squad_no': 2, 'user_id': 'u2'},
        {'squad_no': null, 'user_id': 'u3'},
      ],
      'p_warnings': ['dedicated_gk_over_teams', 'rival_same_team'],
      'p_confirm': true,
    });
  });

  test('서버 줄 → 배치 (팀 블록 번호 순, 교체 블록, 모르는 경고는 무시)', () {
    final lineup = Lineup.fromRows(
      {
        'id': 'L',
        'match_id': 'm1',
        'team_count': 2,
        'players_per_team': 3,
        'status': 'confirmed',
        'warnings': ['group_split', 'future_kind'],
        'version': 2,
        'updated_at': '2026-11-10T00:00:00.123456+00:00',
        'confirmed_at': '2026-11-09T23:00:00+00:00',
      },
      [
        {'id': 'q2', 'lineup_id': 'L', 'squad_no': 2, 'bib_color': 'blue'},
        {'id': 'q1', 'lineup_id': 'L', 'squad_no': 1, 'bib_color': 'red'},
      ],
      [
        {'id': 's1', 'lineup_id': 'L', 'squad_id': 'q1', 'user_id': 'u1', 'guest_id': null},
        {'id': 's2', 'lineup_id': 'L', 'squad_id': 'q2', 'user_id': null, 'guest_id': 'g1'},
        {'id': 's3', 'lineup_id': 'L', 'squad_id': null, 'user_id': 'u2', 'guest_id': null},
      ],
    );
    expect(lineup.isConfirmed, isTrue);
    expect(lineup.version, 2);
    expect(lineup.updatedAt, '2026-11-10T00:00:00.123456+00:00');
    expect(lineup.warnings, {LineupWarningKind.groupSplit});
    expect(lineup.squads.map((q) => q.bibColor), [BibColor.red, BibColor.blue]);
    expect(lineup.squads[0].people, [const LineupPerson.member('u1')]);
    expect(lineup.squads[1].people.single.isGuest, isTrue);
    expect(lineup.bench, [const LineupPerson.member('u2')]);
    final draft = lineup.toDraft();
    expect(draft.teamCount, 2);
    expect(draft.warnings, {LineupWarningKind.groupSplit});
  });

  test('저장 결과·오류 코드', () {
    final r = LineupSaveResult.fromJson({
      'lineup_id': 'L',
      'status': 'draft',
      'version': 1,
      'updated_at': '2026-11-10T00:00:00+00:00',
    });
    expect(r.status, LineupStatus.draft);
    expect(ServerErrorCode.fromCode('lineup_conflict'), ServerErrorCode.lineupConflict);
    expect(ServerErrorCode.fromCode('lineup_not_open'), ServerErrorCode.lineupNotOpen);
    expect(ServerErrorCode.fromCode('match_already_ended'), ServerErrorCode.matchAlreadyEnded);
    expect(ServerErrorCode.fromCode('invalid_lineup'), ServerErrorCode.invalidLineup);
    expect(ServerErrorCode.fromCode('invalid_lineup_slot'), ServerErrorCode.invalidLineupSlot);
  });
}
