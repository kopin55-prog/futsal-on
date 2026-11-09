import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/admin/presentation/admin_texts.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_board.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/domain/team_split.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_blocks.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_texts.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/guest_badge.dart';
import 'package:futsal_on/features/schedule/presentation/match_detail_screen.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/position.dart';

import '../../support/fakes.dart';

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다현'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '나래'),
  MemberEntry(userId: 'u4', role: TeamRole.member, displayName: '라온'),
  MemberEntry(userId: 'u5', role: TeamRole.member, displayName: '바다'),
  MemberEntry(userId: 'u6', role: TeamRole.member, displayName: '사랑'),
];

const _p = LineupPerson.member;

/// 참석 마감이 지났고 경기 시작 전인 일정 (팀 나누기 가능).
TeamMatch _match({
  Duration startIn = const Duration(hours: 1),
  Duration deadlineBefore = const Duration(hours: 2),
  bool cancelled = false,
}) {
  final start = DateTime.now().toUtc().add(startIn);
  return TeamMatch(
    id: 'm1',
    teamId: 'a',
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(deadlineBefore),
  );
}

/// 참석 6명(u1~u6) + 게스트 1명, 운영진 m1 은 불참, 팀장 me 는 미투표.
void _seedPeople(TestServices t) {
  final base = DateTime.utc(2026, 11, 1);
  for (final (i, u) in ['u1', 'u2', 'u3', 'u4', 'u5', 'u6'].indexed) {
    t.attendance.seed('m1', u, AttendanceState.attending, at: base.add(Duration(minutes: i)));
  }
  t.attendance.seed('m1', 'm1', AttendanceState.declined, at: base.add(const Duration(minutes: 30)));
  t.guests.byMatch['m1'] = [
    MatchGuestDetail(
      id: 'g1',
      guestNo: 1,
      positions: const [Position.forward],
      skillLevel: SkillLevel.pro,
      createdAt: base.add(const Duration(hours: 1)),
    ),
  ];
  t.admin.levels = {'u1': SkillLevel.pro, 'u2': SkillLevel.beginner, 'u3': SkillLevel.semipro};
  t.teams.playPrefs['u4'] = const PlayPrefs(positions: [Position.goalkeeper], isDedicatedGk: true);
}

Future<TestServices> _open(
  WidgetTester tester, {
  TeamRole role = TeamRole.manager,
  String userId = 'm1',
  TeamMatch? match,
  void Function(TestServices t)? setup,
}) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(members: {'a': _members})..currentUserId = userId;
  final m = match ?? _match();
  t.matches.items.add(m);
  _seedPeople(t);
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(
      home: MatchDetailScreen(
        services: t.services,
        team: TeamSummary(id: 'a', name: '코코FC', teamCode: 'KOKO22', logoText: '코코', myRole: role, isRecruiting: true),
        viewer: Viewer(userId: userId, role: role),
        matchId: m.id,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('lineup-open')));
  await tester.tap(find.byKey(const Key('lineup-open')));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 그 블록 안의 이름 순서
List<String> _namesIn(WidgetTester tester, String blockKey) => [
  for (final c in tester.widgetList<LineupNameChip>(
    find.descendant(of: find.byKey(Key(blockKey)), matching: find.byType(LineupNameChip)),
  ))
    c.name,
];

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

/// 등급 이름·GK 같은 실력 표시가 화면 어디에도 없음 (Q-075 5·6번)
/// [scope] 가 있으면 그 안에서만 본다 (일정 상세의 다른 부분 — 장소 미정, 운영진용 게스트 대략 실력 — 은 제외).
void _expectNoSkillShown([Finder? scope]) {
  Finder f(String text) =>
      scope == null ? find.textContaining(text) : find.descendant(of: scope, matching: find.textContaining(text));
  for (final l in SkillLevel.values) {
    expect(f(AdminTexts.skillLevel(l)), findsNothing, reason: l.name);
  }
  expect(f('GK'), findsNothing);
  expect(f('골키퍼'), findsNothing);
}

final _section = find.byKey(const Key('lineup-section'));

const _confirmedDraft = LineupDraft(
  playersPerTeam: 3,
  squads: [
    LineupSquadDraft(bibColor: BibColor.red, people: [LineupPerson.member('u1'), LineupPerson.member('u2'), LineupPerson.guest('g1')]),
    LineupSquadDraft(bibColor: BibColor.noBib, people: [LineupPerson.member('u3'), LineupPerson.member('u4'), LineupPerson.member('u5')]),
  ],
  bench: [LineupPerson.member('u6')],
);

void main() {
  group('팀원 화면 (3-4)', () {
    testWidgets('확정 전: "아직 팀 배치 전이에요", 팀 나누기 버튼 없음 (초안은 서버도 안 줌)', (tester) async {
      await _open(
        tester,
        role: TeamRole.member,
        userId: 'u1',
        setup: (t) {
          t.lineups
            ..hideDrafts = true
            ..seed('m1', _confirmedDraft);
        },
      );
      expect(find.byKey(const Key('lineup-open')), findsNothing);
      expect(find.text(LineupTexts.notYet), findsOneWidget);
      expect(find.byKey(const Key('lineup-squad-1')), findsNothing);
    });

    testWidgets('확정 후: 조끼 색 블록 + 이름 가나다순, 게스트 상자, 교체 블록, 내 이름 강조, 실력 표시 없음', (tester) async {
      await _open(
        tester,
        role: TeamRole.member,
        userId: 'u1',
        setup: (t) => t.lineups
          ..hideDrafts = true
          ..seed('m1', _confirmedDraft, confirmed: true),
      );
      expect(find.text(LineupTexts.squadTitle(BibColor.red, 3)), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.noBib, 3)), findsOneWidget);
      // 다현(u1)·가람(u2)·게스트1 → 가나다순
      expect(_namesIn(tester, 'lineup-squad-1'), ['가람', '게스트1', '다현']);
      expect(_namesIn(tester, 'lineup-squad-2'), ['나래', '라온', '바다']);
      expect(_namesIn(tester, 'lineup-bench'), ['사랑']);
      expect(find.descendant(of: find.byKey(const Key('lineup-squad-1')), matching: find.byType(GuestBadge)), findsOneWidget);
      expect(tester.widget<LineupNameChip>(find.byKey(const Key('lineup-person-u:u1'))).highlight, isTrue);
      expect(tester.widget<LineupNameChip>(find.byKey(const Key('lineup-person-u:u2'))).highlight, isFalse);
      expect(find.byKey(const Key('lineup-open')), findsNothing);
      expect(find.byKey(const Key('lineup-status')), findsNothing);
      _expectNoSkillShown(_section);
    });
  });

  group('운영진: 만들 수 없는 시점 (3-1, Q-075 1번)', () {
    testWidgets('참석 마감 전 → 버튼 잠김 + 안내', (tester) async {
      await _open(tester, match: _match(startIn: const Duration(days: 1)));
      expect(tester.widget<TextButton>(find.byKey(const Key('lineup-open'))).onPressed, isNull);
      expect(find.text(LineupTexts.window(LineupWindow.beforeDeadline)), findsOneWidget);
    });

    testWidgets('경기 종료 뒤 → 잠김 + 안내, 확정 배치는 보임', (tester) async {
      await _open(
        tester,
        match: _match(startIn: const Duration(hours: -3)),
        setup: (t) => t.lineups.seed('m1', _confirmedDraft, confirmed: true),
      );
      expect(tester.widget<TextButton>(find.byKey(const Key('lineup-open'))).onPressed, isNull);
      expect(find.text(LineupTexts.window(LineupWindow.ended)), findsOneWidget);
      expect(find.byKey(const Key('lineup-squad-1')), findsOneWidget);
    });

    testWidgets('취소된 일정 → 잠김 + 안내', (tester) async {
      await _open(tester, match: _match(cancelled: true));
      expect(tester.widget<TextButton>(find.byKey(const Key('lineup-open'))).onPressed, isNull);
      expect(find.text(LineupTexts.window(LineupWindow.cancelled)), findsOneWidget);
    });
  });

  group('운영진: 팀 나누기 (3-1~3-3)', () {
    testWidgets('처음 값 2팀·인원÷2 올림 → 자동 나누기 → 초안 저장 → 확정 → 변경 저장 버튼', (tester) async {
      final t = await _open(tester);
      expect(find.text(LineupTexts.noLineupStaff), findsOneWidget);
      await _openEditor(tester);
      // 참석 6 + 게스트 1 = 7명 → 2팀 · 4명
      expect(_text(tester, 'lineup-teams-value'), LineupTexts.teamCountValue(2));
      expect(_text(tester, 'lineup-players-value'), LineupTexts.playersValue(4));
      expect(find.text(LineupTexts.emptyBoard), findsOneWidget);
      expect(find.byKey(const Key('lineup-save-draft')), findsNothing);

      await _tapKey(tester, 'lineup-auto');
      expect(find.text(LineupTexts.squadTitle(BibColor.red, 4)), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.blue, 3)), findsOneWidget);
      expect(find.text(LineupTexts.benchTitle(0)), findsOneWidget);
      expect(find.text(LineupTexts.warning(const SplitWarning(SplitWarningKind.playersShort, 1))), findsOneWidget);
      _expectNoSkillShown();

      await _tapKey(tester, 'lineup-save-draft');
      expect(t.lineups.calls, ['save:m1:plain']);
      final draft = t.lineups.savedDrafts.single;
      expect(draft.teamCount, 2);
      expect(draft.playersPerTeam, 4);
      expect({for (final q in draft.squads) ...q.people}.length, 7);
      expect(find.text(LineupTexts.savedDraft), findsOneWidget);
      expect(tester.widget<Chip>(find.byKey(const Key('lineup-status'))).label, isA<Text>());
      expect(find.text(LineupTexts.draftBadge), findsOneWidget);
      // 저장 직후에는 바뀐 것이 없어 초안 저장 잠김
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('lineup-save-draft'))).onPressed, isNull);

      await _tapKey(tester, 'lineup-confirm');
      expect(find.text(LineupTexts.confirmTitle), findsOneWidget);
      await _tapKey(tester, 'lineup-confirm-ok');
      expect(t.lineups.calls.last, 'save:m1:confirm');
      expect(t.lineups.byMatch['m1']!.isConfirmed, isTrue);
      expect(find.byKey(const Key('lineup-confirm')), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('lineup-save-changes'))).onPressed, isNull);

      // 확정 뒤 옮기면 [변경 저장] → 한 번 저장 (알림은 서버가 저장 때 1회)
      await _tapKey(tester, 'lineup-person-g:g1');
      await _tapKey(tester, 'move-to-bench');
      await _tapKey(tester, 'lineup-save-changes');
      expect(t.lineups.calls.last, 'save:m1:plain');
      expect(t.lineups.byMatch['m1']!.version, 2);
      expect(find.text(LineupTexts.changesSaved), findsOneWidget);

      // 일정 상세로 돌아가면 확정 배치 요약
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(LineupTexts.confirmedBadge), findsOneWidget);
      expect(_namesIn(tester, 'lineup-bench'), ['게스트1']);
    });

    testWidgets('지난 경기에 쓴 값이 처음 값', (tester) async {
      await _open(tester, setup: (t) => t.lineups.lastSizes['a'] = (teams: 3, players: 5));
      await _openEditor(tester);
      expect(_text(tester, 'lineup-teams-value'), LineupTexts.teamCountValue(3));
      expect(_text(tester, 'lineup-players-value'), LineupTexts.playersValue(5));
    });

    testWidgets('팀당 인원을 줄이면 교체 N명 경고, 교체 블록에 사람', (tester) async {
      await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-players-minus'); // 3명
      await _tapKey(tester, 'lineup-auto');
      expect(find.text(LineupTexts.benchTitle(1)), findsOneWidget);
      expect(find.text(LineupTexts.warning(const SplitWarning(SplitWarningKind.benchRemaining, 1))), findsOneWidget);
    });

    testWidgets('직접 옮긴 뒤 재조합 → 확인 창, 그대로 두기면 유지', (tester) async {
      await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      final first = _namesIn(tester, 'lineup-squad-1').first;
      final person = tester
          .widget<LongPressDraggable<LineupPerson>>(
            find.descendant(of: find.byKey(const Key('lineup-squad-1')), matching: find.byType(LongPressDraggable<LineupPerson>)).first,
          )
          .data!;
      await _tapKey(tester, 'lineup-person-${person.key}');
      expect(find.text(LineupTexts.moveTitle(first)), findsOneWidget);
      await _tapKey(tester, 'move-to-bench');
      expect(_namesIn(tester, 'lineup-bench'), [first]);

      await _tapKey(tester, 'lineup-reshuffle');
      expect(find.text(LineupTexts.discardTitle), findsOneWidget);
      await tester.tap(find.text(LineupTexts.keep));
      await tester.pumpAndSettle();
      expect(_namesIn(tester, 'lineup-bench'), [first]);

      await _tapKey(tester, 'lineup-reshuffle');
      await _tapKey(tester, 'lineup-discard-confirm');
      expect(find.text(LineupTexts.benchTitle(0)), findsOneWidget);
    });

    testWidgets('재조합: 후보를 다 보면 "모든 조합을 봤어요"', (tester) async {
      await _open(
        tester,
        setup: (t) {
          // 참석 2명뿐, 게스트 없음 → 2팀 × 1명은 배치가 하나뿐
          t.attendance.byMatch['m1'] = [
            for (final r in t.attendance.byMatch['m1']!)
              if (r.userId == 'u1' || r.userId == 'u2') r,
          ];
          t.guests.byMatch['m1'] = [];
        },
      );
      await _openEditor(tester);
      expect(_text(tester, 'lineup-players-value'), LineupTexts.playersValue(1));
      await _tapKey(tester, 'lineup-auto');
      await _tapKey(tester, 'lineup-reshuffle');
      expect(find.text(LineupTexts.allSeen), findsOneWidget);
    });

    testWidgets('끌어 옮기기: 팀 블록 → 교체 블록 → 다른 팀 블록', (tester) async {
      await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      final person = tester
          .widget<LongPressDraggable<LineupPerson>>(
            find.descendant(of: find.byKey(const Key('lineup-squad-1')), matching: find.byType(LongPressDraggable<LineupPerson>)).first,
          )
          .data!;

      Future<void> dragTo(String target) async {
        final from = tester.getCenter(find.byKey(Key('lineup-person-${person.key}')));
        final gesture = await tester.startGesture(from);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
        await gesture.moveTo(tester.getCenter(find.byKey(Key(target))));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await dragTo('lineup-bench');
      expect(find.text(LineupTexts.benchTitle(1)), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.red, 3)), findsOneWidget);
      await dragTo('lineup-squad-2');
      expect(find.text(LineupTexts.benchTitle(0)), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.blue, 4)), findsOneWidget);
    });

    testWidgets('조끼 색 고르기: 다른 팀이 쓰는 색은 못 고름, 노조끼 가능', (tester) async {
      final t = await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      await _tapKey(tester, 'lineup-color-1');
      expect(tester.widget<ListTile>(find.byKey(const Key('bib-blue'))).enabled, isFalse);
      expect(find.text(LineupTexts.colorInUse), findsOneWidget);
      await _tapKey(tester, 'bib-no_bib');
      expect(find.text(LineupTexts.squadTitle(BibColor.noBib, 4)), findsOneWidget);
      await _tapKey(tester, 'lineup-save-draft');
      expect(t.lineups.savedDrafts.single.squads.map((q) => q.bibColor), [BibColor.noBib, BibColor.blue]);
    });

    testWidgets('팀원 추가: 배치에 없는 팀원(불참·미투표)을 상태와 함께 보여 주고 교체 블록에 넣음', (tester) async {
      final t = await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      await _tapKey(tester, 'lineup-add-member');
      expect(find.byKey(const Key('add-member-m1')), findsOneWidget);
      expect(find.byKey(const Key('add-member-me')), findsOneWidget);
      expect(find.byKey(const Key('add-member-u1')), findsNothing, reason: '이미 배치에 있음');
      expect(
        find.descendant(of: find.byKey(const Key('add-member-m1')), matching: find.text(LineupTexts.memberState(AttendanceState.declined))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('add-member-me')), matching: find.text(LineupTexts.memberState(null))),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('add-member-m1')));
      await tester.pumpAndSettle();
      expect(_namesIn(tester, 'lineup-bench'), ['운영']);
      // 다시 나눠도 직접 추가한 사람은 교체 블록에 남음
      await _tapKey(tester, 'lineup-reshuffle');
      await _tapKey(tester, 'lineup-discard-confirm');
      expect(_namesIn(tester, 'lineup-bench'), ['운영']);
      await _tapKey(tester, 'lineup-save-draft');
      expect(t.lineups.savedDrafts.single.bench, [_p('m1')]);
    });

    testWidgets('다른 운영진이 먼저 저장 → "다른 운영진이 먼저 바꿨어요" 후 새로 불러옴', (tester) async {
      final t = await _open(tester, setup: (t) => t.lineups.seed('m1', _confirmedDraft));
      await _openEditor(tester);
      expect(find.text(LineupTexts.draftBadge), findsOneWidget);
      expect(_text(tester, 'lineup-players-value'), LineupTexts.playersValue(3));
      await _tapKey(tester, 'lineup-person-u:u6');
      await _tapKey(tester, 'move-to-0');
      expect(_namesIn(tester, 'lineup-bench'), isEmpty);
      t.lineups.touch('m1');
      await _tapKey(tester, 'lineup-save-draft');
      expect(find.text(LineupTexts.conflict), findsOneWidget);
      await _tapKey(tester, 'lineup-reload');
      expect(_namesIn(tester, 'lineup-bench'), ['사랑']);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('lineup-save-draft'))).onPressed, isNull);
    });

    testWidgets('서버가 거절(경기 종료 등)하면 안내만', (tester) async {
      final t = await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      t.lineups.nextFailure = const ServerFailure(ServerErrorCode.matchAlreadyEnded);
      await _tapKey(tester, 'lineup-save-draft');
      expect(find.text(LineupTexts.window(LineupWindow.ended)), findsOneWidget);
    });

    testWidgets('저장하지 않고 나가면 확인 창', (tester) async {
      await _open(tester);
      await _openEditor(tester);
      await _tapKey(tester, 'lineup-auto');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(LineupTexts.unsavedTitle), findsOneWidget);
      await _tapKey(tester, 'lineup-leave');
      expect(find.byKey(const Key('lineup-section')), findsOneWidget);
      expect(find.text(LineupTexts.noLineupStaff), findsOneWidget);
    });

    testWidgets('작성 중 배치는 운영진의 일정 상세에 "초안"으로 보임', (tester) async {
      await _open(tester, setup: (t) => t.lineups.seed('m1', _confirmedDraft));
      expect(find.text(LineupTexts.draftBadge), findsOneWidget);
      expect(find.text(LineupTexts.draftNote), findsOneWidget);
      expect(find.text(LineupTexts.editLineup), findsOneWidget);
      _expectNoSkillShown(_section);
    });
  });
}
