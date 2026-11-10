import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/core/theme/app_theme.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/admin/presentation/admin_texts.dart';
import 'package:futsal_on/features/lineup/domain/bib_color.dart';
import 'package:futsal_on/features/lineup/domain/lineup_models.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_blocks.dart';
import 'package:futsal_on/features/lineup/presentation/lineup_texts.dart';
import 'package:futsal_on/features/pom_vote/domain/award_models.dart';
import 'package:futsal_on/features/pom_vote/presentation/award_texts.dart';
import 'package:futsal_on/features/profile/presentation/profile_texts.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/features/schedule/presentation/guest_badge.dart';
import 'package:futsal_on/features/schedule/presentation/match_detail_screen.dart';
import 'package:futsal_on/features/schedule/presentation/schedule_texts.dart';
import 'package:futsal_on/features/share_image/domain/share_image_content.dart';
import 'package:futsal_on/features/share_image/presentation/share_image_texts.dart';
import 'package:futsal_on/features/share_image/presentation/share_images.dart';
import 'package:futsal_on/features/share_image/presentation/widget_image_renderer.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/shared/domain/position.dart';
import 'package:futsal_on/shared/domain/venue.dart';

import '../../support/fakes.dart';

// 'left' 는 경기 뒤 팀을 떠난 사람 (팀원 목록에 없음)
const _members = [
  MemberEntry(userId: 'o1', role: TeamRole.owner, displayName: '팀장'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '다현'),
  MemberEntry(userId: 'u2', role: TeamRole.member, displayName: '가람'),
  MemberEntry(userId: 'u3', role: TeamRole.member, displayName: '나래'),
  MemberEntry(userId: 'u4', role: TeamRole.member, displayName: '라온'),
];

const _confirmedDraft = LineupDraft(
  playersPerTeam: 2,
  squads: [
    LineupSquadDraft(bibColor: BibColor.red, people: [LineupPerson.member('u1'), LineupPerson.member('u2'), LineupPerson.guest('g1')]),
    LineupSquadDraft(bibColor: BibColor.noBib, people: [LineupPerson.member('u3'), LineupPerson.member('o1')]),
  ],
  bench: [LineupPerson.member('u4')],
);

TeamSummary _team(TeamRole role) =>
    TeamSummary(id: 'a', name: '코코FC', teamCode: 'KOKO22', logoText: '코코', myRole: role, isRecruiting: true);

/// [startIn] 뒤 시작하는 경기 (음수면 이미 시작). 2시간 경기, 마감은 시작 2시간 전.
TeamMatch _match({Duration startIn = const Duration(hours: 1), bool cancelled = false}) {
  final start = DateTime.now().toUtc().add(startIn);
  return TeamMatch(
    id: 'x1',
    teamId: 'a',
    source: MatchSource.manual,
    status: cancelled ? MatchStatus.cancelled : MatchStatus.scheduled,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    rsvpDeadlineAt: start.subtract(const Duration(hours: 2)),
    venue: const Venue.manual(name: '한강풋살장'),
  );
}

AwardPollView _poll({
  AwardPollStatus status = AwardPollStatus.closed,
  Map<AwardCategory, List<String>> winners = const {},
}) {
  final now = DateTime.now().toUtc();
  return AwardPollView(
    matchId: 'x1',
    teamId: 'a',
    opensAt: now.subtract(const Duration(hours: 3)),
    closesAt: status == AwardPollStatus.closed ? now.subtract(const Duration(minutes: 1)) : now.add(const Duration(hours: 10)),
    status: status,
    participantIds: const {'o1', 'm1', 'u1', 'u2', 'u3', 'u4', 'left'},
    myVoted: const {},
    winners: winners,
  );
}

void _seed(TestServices t) {
  final base = DateTime.utc(2026, 11, 1);
  for (final (i, u) in ['u1', 'u2', 'u3', 'u4', 'o1'].indexed) {
    t.attendance.seed('x1', u, AttendanceState.attending, at: base.add(Duration(minutes: i)));
  }
  t.guests.byMatch['x1'] = [
    MatchGuestDetail(
      id: 'g1',
      guestNo: 1,
      positions: const [Position.goalkeeper],
      skillLevel: SkillLevel.pro,
      createdAt: base.add(const Duration(hours: 1)),
    ),
  ];
}

Future<TestServices> _open(
  WidgetTester tester, {
  TeamRole role = TeamRole.manager,
  String userId = 'm1',
  TeamMatch? match,
  void Function(TestServices t)? setup,
}) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = TestServices(members: {'a': _members})..currentUserId = userId;
  final m = match ?? _match();
  t.matches.items.add(m);
  _seed(t);
  setup?.call(t);
  await tester.pumpWidget(
    MaterialApp(
      home: MatchDetailScreen(
        services: t.services,
        team: _team(role),
        viewer: Viewer(userId: userId, role: role),
        matchId: m.id,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return t;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 공유 창으로 넘긴 이미지를 혼자 다시 그린다 (이미지 내용 검사).
Future<void> _pumpShared(WidgetTester tester, TestServices t, {ThemeData? theme}) async {
  expect(t.shareImages.shared, hasLength(1));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: Center(child: t.shareImages.shared.single.image))),
    ),
  );
  await tester.pumpAndSettle();
}

/// 실력·포지션·GK·득표수 표시가 이미지 어디에도 없음 (S3-12, Q-075 5·6번)
void _expectNothingForbidden() {
  for (final l in SkillLevel.values) {
    expect(find.textContaining(AdminTexts.skillLevel(l)), findsNothing, reason: l.name);
  }
  for (final p in Position.values) {
    expect(find.textContaining(ProfileTexts.position(p)), findsNothing, reason: p.name);
  }
  expect(find.textContaining('GK'), findsNothing);
  expect(find.textContaining('골키퍼'), findsNothing);
  expect(find.textContaining('표'), findsNothing); // "n표" 같은 득표수
  expect(find.textContaining(AwardTexts.voteCountButton), findsNothing);
}

List<String> _namesIn(WidgetTester tester, String blockKey) => [
  for (final c in tester.widgetList<LineupNameChip>(
    find.descendant(of: find.byKey(Key(blockKey)), matching: find.byType(LineupNameChip)),
  ))
    c.name,
];

List<String> _resultNames(WidgetTester tester, AwardCategory c) => [
  for (final w in tester.widgetList<Text>(
    find.descendant(of: find.byKey(Key('share-result-${c.code}')), matching: find.byType(Text)),
  ))
    if (w.data != AwardTexts.category(c)) w.data!,
];

void main() {
  group('Entitlements: 공유 이미지 버튼 (권한표 "공유 이미지 복사")', () {
    const e = Entitlements();
    const owner = Viewer(userId: 'o', role: TeamRole.owner);
    const manager = Viewer(userId: 'm', role: TeamRole.manager);
    const member = Viewer(userId: 'u', role: TeamRole.member);
    const outsider = Viewer(userId: 'x', role: null);

    test('배치: 팀장·운영진 + 확정된 배치 + 취소 안 된 일정만', () {
      for (final v in [owner, manager]) {
        expect(e.canShareLineupImage(v, lineupConfirmed: true, matchCancelled: false), isTrue);
        expect(e.canShareLineupImage(v, lineupConfirmed: false, matchCancelled: false), isFalse);
        expect(e.canShareLineupImage(v, lineupConfirmed: true, matchCancelled: true), isFalse);
      }
      for (final v in [member, outsider]) {
        expect(e.canShareLineupImage(v, lineupConfirmed: true, matchCancelled: false), isFalse);
      }
    });

    test('결과: 팀장·운영진 + 마감 뒤만', () {
      for (final v in [owner, manager]) {
        expect(e.canShareAwardResultImage(v, pollClosed: true), isTrue);
        expect(e.canShareAwardResultImage(v, pollClosed: false), isFalse);
      }
      for (final v in [member, outsider]) {
        expect(e.canShareAwardResultImage(v, pollClosed: true), isFalse);
      }
    });
  });

  group('결과 이미지 1위 이름 (6-2)', () {
    test('떠난 1위는 빼고, 공동 1위는 모두 이름 가나다순, 마감 전엔 없음', () {
      final names = {'u1': '다현', 'u2': '가람'};
      final closed = _poll(winners: {AwardCategory.pom: ['u1', 'left', 'u2'], AwardCategory.goalOfTheDay: ['left']});
      expect(shareableWinnerNames(closed, AwardCategory.pom, names), ['가람', '다현']);
      expect(shareableWinnerNames(closed, AwardCategory.goalOfTheDay, names), isEmpty);
      final open = _poll(status: AwardPollStatus.open, winners: {AwardCategory.pom: ['u1']});
      expect(shareableWinnerNames(open, AwardCategory.pom, names), isEmpty);
    });
  });

  group('팀 배치 이미지 (6-1)', () {
    testWidgets('운영진 + 확정 배치 → 버튼 → 공유 창. 이미지: 팀 이름·일시·장소, 조끼 색 블록 이름 가나다순, 게스트 상자, 교체, 풋살ON', (
      tester,
    ) async {
      final t = await _open(tester, setup: (t) => t.lineups.seed('x1', _confirmedDraft, confirmed: true));
      await _tap(tester, 'lineup-share');
      expect(t.shareImages.shared.single.fileName, ShareImageTexts.lineupFileName);

      await _pumpShared(tester, t);
      expect(find.byKey(const Key('share-lineup-image')), findsOneWidget);
      expect(find.text('코코FC'), findsOneWidget);
      expect(find.text(ScheduleTexts.matchTime(_match())), findsOneWidget);
      expect(find.text('한강풋살장'), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.red, 3)), findsOneWidget);
      expect(find.text(LineupTexts.squadTitle(BibColor.noBib, 2)), findsOneWidget);
      expect(_namesIn(tester, 'lineup-squad-1'), ['가람', '게스트1', '다현']);
      expect(_namesIn(tester, 'lineup-squad-2'), ['나래', '팀장']);
      expect(_namesIn(tester, 'lineup-bench'), ['라온']);
      expect(find.descendant(of: find.byKey(const Key('lineup-squad-1')), matching: find.byType(GuestBadge)), findsOneWidget);
      expect(find.text(ShareImageTexts.brand), findsOneWidget);
      // 내 이름 강조 없음, 버튼 없음
      for (final c in tester.widgetList<LineupNameChip>(find.byType(LineupNameChip))) {
        expect(c.highlight, isFalse);
      }
      expect(find.byType(OutlinedButton), findsNothing);
      _expectNothingForbidden();
    });

    testWidgets('팀장도 버튼, 팀원은 확정 배치여도 버튼 없음', (tester) async {
      await _open(tester, role: TeamRole.owner, userId: 'o1', setup: (t) => t.lineups.seed('x1', _confirmedDraft, confirmed: true));
      expect(find.byKey(const Key('lineup-share')), findsOneWidget);
      await _open(
        tester,
        role: TeamRole.member,
        userId: 'u1',
        setup: (t) => t.lineups
          ..hideDrafts = true
          ..seed('x1', _confirmedDraft, confirmed: true),
      );
      expect(find.byKey(const Key('lineup-squad-1')), findsOneWidget);
      expect(find.byKey(const Key('lineup-share')), findsNothing);
    });

    testWidgets('초안(확정 전) 배치는 버튼 없음', (tester) async {
      await _open(tester, setup: (t) => t.lineups.seed('x1', _confirmedDraft));
      expect(find.byKey(const Key('lineup-status')), findsOneWidget);
      expect(find.byKey(const Key('lineup-share')), findsNothing);
    });

    testWidgets('공유가 실패하면 안내만', (tester) async {
      final t = await _open(tester, setup: (t) {
        t.lineups.seed('x1', _confirmedDraft, confirmed: true);
        t.shareImages.failNext = true;
      });
      await _tap(tester, 'lineup-share');
      expect(find.text(ShareImageTexts.failed), findsOneWidget);
      expect(t.shareImages.shared, isEmpty);
    });
  });

  group('POM·오늘의 골 결과 이미지 (6-2)', () {
    final ended = _match(startIn: const Duration(hours: -5));

    testWidgets('마감 뒤 운영진 → 버튼 → 이미지: 공동 1위 모두(떠난 1위는 뺌), 1위 없으면 "결과 없음", 득표수 없음', (tester) async {
      final t = await _open(
        tester,
        match: ended,
        setup: (t) => t.awards.polls['x1'] = _poll(
          winners: {AwardCategory.pom: ['u1', 'left', 'u2']},
        ),
      );
      // 결과 화면은 떠난 1위를 빈칸 자리로 그대로 보여준다 (Q-058 5번)
      expect(find.text(AwardTexts.leftMember), findsOneWidget);
      await _tap(tester, 'award-share');
      expect(t.shareImages.shared.single.fileName, ShareImageTexts.resultFileName);

      await _pumpShared(tester, t);
      expect(find.byKey(const Key('share-result-image')), findsOneWidget);
      expect(find.text('코코FC'), findsOneWidget);
      expect(find.text(ScheduleTexts.matchTime(ended)), findsOneWidget);
      expect(find.byKey(const Key('share-venue')), findsNothing);
      expect(_resultNames(tester, AwardCategory.pom), ['가람', '다현']);
      expect(_resultNames(tester, AwardCategory.goalOfTheDay), [AwardTexts.noResult]);
      expect(find.text(AwardTexts.leftMember), findsNothing);
      expect(find.text(ShareImageTexts.brand), findsOneWidget);
      _expectNothingForbidden();
    });

    testWidgets('진행 중(마감 전)이면 버튼 없음', (tester) async {
      await _open(tester, match: ended, setup: (t) => t.awards.polls['x1'] = _poll(status: AwardPollStatus.open));
      expect(find.byKey(const Key('award-section')), findsOneWidget);
      expect(find.byKey(const Key('award-share')), findsNothing);
    });

    testWidgets('팀원은 마감 뒤에도 버튼 없음', (tester) async {
      await _open(
        tester,
        role: TeamRole.member,
        userId: 'u1',
        match: ended,
        setup: (t) => t.awards.polls['x1'] = _poll(winners: {AwardCategory.pom: ['u2']}),
      );
      expect(find.byKey(const Key('award-result-pom')), findsOneWidget);
      expect(find.byKey(const Key('award-share')), findsNothing);
    });
  });

  group('이미지 모양 (6-3)', () {
    final image = AwardResultShareImage(
      team: _team(TeamRole.owner),
      match: _match(),
      winners: const {AwardCategory.pom: ['가람'], AwardCategory.goalOfTheDay: []},
    );

    Color background(WidgetTester tester) => tester
        .widget<Container>(
          find.descendant(of: find.byKey(const Key('share-result-image')), matching: find.byType(Container)).first,
        )
        .color!;

    testWidgets('어두운 모드에서도 밝은 모드와 같은 색', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: Center(child: image))));
      final dark = background(tester);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: image))));
      expect(background(tester), dark);
      expect(dark, AppTheme.light().colorScheme.surface);
    });

    testWidgets('화면에 띄우지 않고 PNG 그림으로 만든다 (너비 1080px)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      final Uint8List? png = await tester.runAsync(
        () => WidgetImageRenderer.toPng(context, image, width: shareImageWidth, pixelRatio: ShareImageFrame.pixelRatio),
      );
      expect(png, isNotNull);
      // PNG 머리 + IHDR 너비
      expect(png!.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final data = ByteData.sublistView(png);
      expect(data.getUint32(16), (shareImageWidth * ShareImageFrame.pixelRatio).round());
      expect(data.getUint32(20), greaterThan(300));
    });
  });
}
