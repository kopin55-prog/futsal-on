import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/domain/team_split.dart';
import 'package:futsal_on/shared/domain/position.dart';

// sprint-03.md "QA 완료 기준" K-01~K-14 (팀 나누기 알고리즘).

final _t0 = DateTime.utc(2026, 11, 10, 9);

SplitCandidate m(
  String id, {
  SkillLevel skill = SkillLevel.amateur,
  Set<Position> pos = const {Position.midfielder},
  bool gk = false,
  int minute = 0,
}) => SplitCandidate(
  person: LineupPerson.member(id),
  skill: skill,
  positions: gk ? {...pos, Position.goalkeeper} : pos,
  isDedicatedGk: gk,
  attendedAt: _t0.add(Duration(minutes: minute)),
);

SplitCandidate g(
  String id, {
  SkillLevel skill = SkillLevel.undecided,
  Set<Position> pos = const {},
  bool gk = false,
  int minute = 0,
}) => SplitCandidate(
  person: LineupPerson.guest(id),
  skill: skill,
  positions: pos,
  isDedicatedGk: gk,
  attendedAt: _t0.add(Duration(minutes: minute)),
);

PairingRule grp(List<String> ids, {bool enabled = true}) =>
    PairingRule(id: 'g-${ids.join()}', kind: PairingKind.group, enabled: enabled, userIds: ids);

PairingRule rival(List<String> ids, {bool enabled = true}) =>
    PairingRule(id: 'r-${ids.join()}', kind: PairingKind.rival, enabled: enabled, userIds: ids);

/// 여러 포지션이 섞인 팀원 n명 (p1..pn)
List<SplitCandidate> people(int n, {int from = 1}) => [
  for (var i = from; i < from + n; i++)
    m('p$i', pos: {Position.values[i % 4 + 1]}, minute: i),
];

int teamOf(TeamSplitPlan plan, String key) =>
    plan.squads.indexWhere((s) => s.any((p) => p.key == key));

Set<SplitWarningKind> kinds(TeamSplitPlan plan) => {for (final w in plan.warnings) w.kind};

void main() {
  group('K-01 기본', () {
    test('12명, 2팀 × 6명 → 6:6, 교체 0, 경고 없음', () {
      final plan = TeamSplitter.split(
        TeamSplitInput(candidates: people(12), teamCount: 2, playersPerTeam: 6),
      );
      expect(plan.squads.map((s) => s.length), [6, 6]);
      expect(plan.bench, isEmpty);
      expect(plan.warnings, isEmpty);
      final all = {for (final s in plan.squads) ...s};
      expect(all.length, 12);
    });
  });

  group('K-02 전문 GK 분산', () {
    test('전문 GK 2명, 2팀 → 팀마다 1명, 재조합 10번에도 지켜짐', () {
      final input = TeamSplitInput(
        candidates: [...people(10), m('gk1', gk: true), m('gk2', gk: true)],
        teamCount: 2,
        playersPerTeam: 6,
      );
      final shuffler = TeamSplitShuffler(input);
      var plan = shuffler.current;
      for (var i = 0; i <= 10; i++) {
        expect(teamOf(plan, 'u:gk1'), isNot(teamOf(plan, 'u:gk2')), reason: 'try $i');
        expect(plan.warnings, isEmpty);
        plan = shuffler.next();
      }
    });

    test('전문 GK 가 팀보다 많으면 한 팀에 2명 + 경고 (S3-06 (1))', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [...people(9), m('gk1', gk: true), m('gk2', gk: true), m('gk3', gk: true)],
        teamCount: 2,
        playersPerTeam: 6,
      ));
      final perTeam = [
        for (final s in plan.squads) s.where((p) => p.key.startsWith('u:gk')).length,
      ]..sort();
      expect(perTeam, [1, 2]);
      expect(kinds(plan), {SplitWarningKind.dedicatedGkOverTeams});
      expect(plan.storedWarnings, {LineupWarningKind.dedicatedGkOverTeams});
    });
  });

  group('K-03 그룹', () {
    test('켜진 그룹은 항상 같은 팀, 끄면 갈라질 수 있음', () {
      final on = TeamSplitShuffler(TeamSplitInput(
        candidates: people(12),
        rules: [grp(['p3', 'p4'])],
        teamCount: 2,
        playersPerTeam: 6,
      ));
      for (final plan in on.plans) {
        expect(teamOf(plan, 'u:p3'), teamOf(plan, 'u:p4'));
      }
      final off = TeamSplitShuffler(TeamSplitInput(
        candidates: people(12),
        rules: [grp(['p3', 'p4'], enabled: false)],
        teamCount: 2,
        playersPerTeam: 6,
      ));
      expect(off.plans.any((p) => teamOf(p, 'u:p3') != teamOf(p, 'u:p4')), isTrue);
    });

    test('그룹 중 온 사람끼리 같은 팀 (S3-06 (3))', () {
      final plans = TeamSplitter.plans(TeamSplitInput(
        candidates: people(8),
        rules: [grp(['p1', 'p2', 'absent'])],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      for (final plan in plans) {
        expect(teamOf(plan, 'u:p1'), teamOf(plan, 'u:p2'));
        expect(plan.warnings, isEmpty);
      }
    });

    test('그룹 인원 > 팀당 인원 → 최대한 같은 팀 + 경고 (S3-06 (4))', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: people(6),
        rules: [grp(['p1', 'p2', 'p3', 'p4'])],
        teamCount: 2,
        playersPerTeam: 3,
      ));
      final together = [
        for (final s in plan.squads) s.where((p) => ['u:p1', 'u:p2', 'u:p3', 'u:p4'].contains(p.key)).length,
      ]..sort();
      expect(together, [1, 3]);
      expect(kinds(plan), {SplitWarningKind.groupSplit});
    });

    test('한 사람이 두 그룹에 있으면 이어서 한 묶음', () {
      final plans = TeamSplitter.plans(TeamSplitInput(
        candidates: people(8),
        rules: [grp(['p1', 'p2']), grp(['p2', 'p3'])],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      for (final plan in plans) {
        expect({teamOf(plan, 'u:p1'), teamOf(plan, 'u:p2'), teamOf(plan, 'u:p3')}.length, 1);
      }
    });
  });

  group('K-04 라이벌', () {
    test('켜진 라이벌은 항상 다른 팀', () {
      final plans = TeamSplitter.plans(TeamSplitInput(
        candidates: people(12),
        rules: [rival(['p5', 'p6'])],
        teamCount: 2,
        playersPerTeam: 6,
      ));
      expect(plans, isNotEmpty);
      for (final plan in plans) {
        expect(teamOf(plan, 'u:p5'), isNot(teamOf(plan, 'u:p6')));
      }
    });
  });

  group('K-05 필수 조건을 모두 지킬 수 없을 때', () {
    test('배치는 나오고 GK·그룹·라이벌 경고', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          m('gk1', gk: true), m('gk2', gk: true), m('gk3', gk: true),
          ...people(3),
        ],
        rules: [
          grp(['p1', 'p2', 'p3', 'gk1']),
          rival(['gk2', 'gk3', 'p1']),
        ],
        teamCount: 2,
        playersPerTeam: 3,
      ));
      expect(plan.squads.map((s) => s.length), [3, 3]);
      expect(kinds(plan), {
        SplitWarningKind.dedicatedGkOverTeams,
        SplitWarningKind.groupSplit,
        SplitWarningKind.rivalSameTeam,
      });
      expect(plan.storedWarnings, LineupWarningKind.values.toSet());
    });

    test('GK 분산이 그룹보다 우선: 같은 그룹의 전문 GK 2명은 갈라짐', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [m('gk1', gk: true), m('gk2', gk: true), ...people(6)],
        rules: [grp(['gk1', 'gk2'])],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      expect(teamOf(plan, 'u:gk1'), isNot(teamOf(plan, 'u:gk2')));
      expect(kinds(plan), {SplitWarningKind.groupSplit});
    });
  });

  group('K-06 실력', () {
    test('프로 2·비기너 2, 2팀 × 2명 → 팀마다 프로 1·비기너 1', () {
      final input = TeamSplitInput(
        candidates: [
          m('pro1', skill: SkillLevel.pro), m('pro2', skill: SkillLevel.pro),
          m('beg1', skill: SkillLevel.beginner), m('beg2', skill: SkillLevel.beginner),
        ],
        teamCount: 2,
        playersPerTeam: 2,
      );
      for (final plan in TeamSplitter.plans(input).take(1)) {
        for (final s in plan.squads) {
          expect(s.where((p) => p.key.startsWith('u:pro')).length, 1);
        }
      }
    });

    test('점수 차이 반영: 세미프로+아마추어 vs 프로+비기너는 같은 합(50)', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          m('a', skill: SkillLevel.pro), m('b', skill: SkillLevel.semipro),
          m('c', skill: SkillLevel.amateur), m('d', skill: SkillLevel.beginner),
        ],
        teamCount: 2,
        playersPerTeam: 2,
      ));
      expect(teamOf(plan, 'u:a'), teamOf(plan, 'u:d'));
      expect(teamOf(plan, 'u:b'), teamOf(plan, 'u:c'));
    });
  });

  group('K-07 미정', () {
    test('미정 4 + 아마추어 4, 2팀 × 4명 → 팀마다 미정 2명', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          for (var i = 0; i < 4; i++) m('und$i', skill: SkillLevel.undecided),
          for (var i = 0; i < 4; i++) m('ama$i'),
        ],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      for (final s in plan.squads) {
        expect(s.where((p) => p.key.startsWith('u:und')).length, 2);
      }
    });
  });

  group('K-08 선호 포지션', () {
    test('공격 4명, 2팀 → 팀마다 공격 2명 (다른 조건이 같을 때)', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          for (var i = 0; i < 4; i++) m('fw$i', pos: {Position.forward}),
          for (var i = 0; i < 4; i++) m('df$i', pos: {Position.defender}),
        ],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      for (final s in plan.squads) {
        expect(s.where((p) => p.key.startsWith('u:fw')).length, 2);
      }
    });
  });

  group('K-09 일반 선호 포지션 골키퍼', () {
    test('GK 분산(1번 규칙)에 들어가지 않음', () {
      final input = TeamSplitInput(
        candidates: [
          for (var i = 0; i < 3; i++) m('kp$i', pos: {Position.goalkeeper}),
          ...people(3),
        ],
        teamCount: 2,
        playersPerTeam: 3,
      );
      final plan = TeamSplitter.split(input);
      expect(kinds(plan), isNot(contains(SplitWarningKind.dedicatedGkOverTeams)));
      // 일반 골키퍼 선호 3명을 한 팀에 몰아도 GK 경고 없음
      final manual = TeamSplitter.evaluateWarnings(
        input,
        [
          [for (var i = 0; i < 3; i++) LineupPerson.member('kp$i')],
          [for (var i = 1; i <= 3; i++) LineupPerson.member('p$i')],
        ],
        const [],
      );
      expect(manual, isEmpty);
    });

    test('전문 GK 2 + 일반 골키퍼 선호 2, 2팀 → 전문 GK 만 팀마다 1명 보장', () {
      final plans = TeamSplitter.plans(TeamSplitInput(
        candidates: [
          m('gk1', gk: true), m('gk2', gk: true),
          m('kp1', pos: {Position.goalkeeper}), m('kp2', pos: {Position.goalkeeper}),
          ...people(4),
        ],
        teamCount: 2,
        playersPerTeam: 4,
      ));
      for (final plan in plans) {
        expect(teamOf(plan, 'u:gk1'), isNot(teamOf(plan, 'u:gk2')));
      }
    });
  });

  group('K-10 인원 남음', () {
    test('15명, 2팀 × 7명 → 교체 1명(가장 늦게 참석) + 경고', () {
      final plan = TeamSplitter.split(
        TeamSplitInput(candidates: people(15), teamCount: 2, playersPerTeam: 7),
      );
      expect(plan.squads.map((s) => s.length), [7, 7]);
      expect(plan.bench, [const LineupPerson.member('p15')]);
      expect(plan.warnings, {const SplitWarning(SplitWarningKind.benchRemaining, 1)});
      expect(plan.storedWarnings, isEmpty);
    });

    test('게스트는 참석자보다 늦은 것으로 봄, 전문 GK 는 교체로 안 감 (Q-075 4번)', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          ...people(3),
          m('lateGk', gk: true, minute: 99),
          g('guest1', minute: -50),
          g('guest2', minute: -40),
        ],
        teamCount: 2,
        playersPerTeam: 2,
      ));
      // 6명 - 4자리 = 2명: 게스트 중 늦게 추가한 guest2, 그다음 guest1. 가장 늦게 누른 전문 GK 는 남음
      expect(plan.bench, [const LineupPerson.guest('guest2'), const LineupPerson.guest('guest1')]);
      expect(teamOf(plan, 'u:lateGk'), isNot(-1));
    });

    test('게스트가 없으면 참석을 가장 늦게 누른 팀원부터 (전문 GK 제외)', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [m('a', minute: 1), m('b', minute: 5), m('c', minute: 3), m('gk', gk: true, minute: 9), m('d', minute: 2)],
        teamCount: 2,
        playersPerTeam: 2,
      ));
      expect(plan.bench, [const LineupPerson.member('b')]);
    });
  });

  group('K-11 인원 모자람', () {
    test('10명, 2팀 × 6명 → 5:5 + "2명 모자라요"', () {
      final plan = TeamSplitter.split(
        TeamSplitInput(candidates: people(10), teamCount: 2, playersPerTeam: 6),
      );
      expect(plan.squads.map((s) => s.length), [5, 5]);
      expect(plan.bench, isEmpty);
      expect(plan.warnings, {const SplitWarning(SplitWarningKind.playersShort, 2)});
    });

    test('홀수 인원은 1명 차이로 고르게 (11명, 3팀 × 4명 → 4·4·3)', () {
      final plan = TeamSplitter.split(
        TeamSplitInput(candidates: people(11), teamCount: 3, playersPerTeam: 4),
      );
      expect(plan.squads.map((s) => s.length), [4, 4, 3]);
      expect(plan.warnings, {const SplitWarning(SplitWarningKind.playersShort, 1)});
    });
  });

  group('K-12 게스트', () {
    test('게스트도 실력·포지션 계산에 들어감', () {
      final plan = TeamSplitter.split(TeamSplitInput(
        candidates: [
          g('gp1', skill: SkillLevel.pro, pos: {Position.forward}),
          g('gp2', skill: SkillLevel.pro, pos: {Position.forward}),
          m('b1', skill: SkillLevel.beginner),
          m('b2', skill: SkillLevel.beginner),
        ],
        teamCount: 2,
        playersPerTeam: 2,
      ));
      expect(teamOf(plan, 'g:gp1'), isNot(teamOf(plan, 'g:gp2')));
    });

    test('게스트는 그룹·라이벌·전문 GK 대상 아님', () {
      final input = TeamSplitInput(
        candidates: [
          g('x', gk: true), g('y', gk: true), g('z', gk: true),
          ...people(3),
        ],
        // 게스트 ID 를 넣은 설정이 있어도 무시 (설정은 팀원 ID 만)
        rules: [grp(['x', 'y', 'z', 'p1']), rival(['x', 'p1'])],
        teamCount: 2,
        playersPerTeam: 3,
      );
      final plan = TeamSplitter.split(input);
      expect(plan.warnings, isEmpty);
      final manual = TeamSplitter.evaluateWarnings(
        input,
        [
          [const LineupPerson.guest('x'), const LineupPerson.guest('y'), const LineupPerson.guest('z')],
          [for (var i = 1; i <= 3; i++) LineupPerson.member('p$i')],
        ],
        const [],
      );
      expect(manual, isEmpty);
    });
  });

  group('K-13 재조합', () {
    test('같은 배치가 연달아 나오지 않음, 다 보면 처음으로 + wrapped', () {
      final shuffler = TeamSplitShuffler(TeamSplitInput(
        candidates: people(12),
        rules: [grp(['p1', 'p2']), rival(['p3', 'p4'])],
        teamCount: 2,
        playersPerTeam: 6,
      ));
      expect(shuffler.plans.length, greaterThan(1));
      final first = shuffler.current.signature;
      var prev = first;
      for (var i = 1; i < shuffler.plans.length; i++) {
        final next = shuffler.next().signature;
        expect(next, isNot(prev));
        expect(shuffler.wrapped, isFalse);
        prev = next;
      }
      expect(shuffler.next().signature, first);
      expect(shuffler.wrapped, isTrue);
      expect(shuffler.plans.map((p) => p.signature).toSet().length, shuffler.plans.length);
    });

    test('같은 입력이면 같은 첫 배치 (입력 순서와 무관)', () {
      final list = [...people(14), m('gk1', gk: true), g('guest', skill: SkillLevel.pro)];
      final a = TeamSplitter.split(TeamSplitInput(candidates: list, teamCount: 3, playersPerTeam: 5));
      final b = TeamSplitter.split(
        TeamSplitInput(candidates: list.reversed.toList(), teamCount: 3, playersPerTeam: 5),
      );
      expect(a.signature, b.signature);
      expect(a.squads.map((s) => s.map((p) => p.key).toList()), b.squads.map((s) => s.map((p) => p.key).toList()));
    });
  });

  group('K-14 실력 비노출', () {
    test('결과·저장 값 어디에도 실력 등급·점수가 없음', () {
      final input = TeamSplitInput(
        candidates: [
          m('a', skill: SkillLevel.pro), m('b', skill: SkillLevel.semipro),
          m('c', skill: SkillLevel.beginner), g('d', skill: SkillLevel.pro),
        ],
        teamCount: 2,
        playersPerTeam: 2,
      );
      final plan = TeamSplitter.split(input);
      final draft = LineupDraft(
        playersPerTeam: 2,
        squads: [
          for (var i = 0; i < plan.squads.length; i++)
            LineupSquadDraft(bibColor: BibColor.defaults(2)[i], people: plan.squads[i]),
        ],
        bench: plan.bench,
        warnings: plan.storedWarnings,
      );
      final text = jsonEncode(draft.toServerParams('m1', expectedUpdatedAt: null, confirm: true)) +
          plan.signature +
          plan.warnings.toString();
      for (final word in ['skill', 'level', 'score', 'pro', 'semipro', 'beginner', 'amateur', '40', '30']) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('성능', () {
    test('30명·6팀 (그룹·라이벌·GK 포함) 계산이 1초 안', () {
      final input = TeamSplitInput(
        candidates: [
          for (var i = 1; i <= 26; i++)
            m('p$i',
                skill: SkillLevel.values[i % 5],
                pos: {Position.values[i % 4 + 1], Position.values[(i * 3) % 5]},
                minute: i),
          for (var i = 1; i <= 4; i++) m('gk$i', gk: true, minute: 40 + i),
        ],
        rules: [grp(['p1', 'p2', 'p3']), grp(['p7', 'p8']), rival(['p4', 'p5', 'p6']), rival(['p9', 'p10'])],
        teamCount: 6,
        playersPerTeam: 5,
      );
      final watch = Stopwatch()..start();
      final shuffler = TeamSplitShuffler(input);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(1000));
      final plan = shuffler.current;
      expect(plan.squads.map((s) => s.length), everyElement(5));
      expect(plan.warnings, isEmpty);
    });
  });
}
