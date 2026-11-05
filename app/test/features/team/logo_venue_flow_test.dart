import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/team/data/logo_picker.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_logo.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/features/venue/data/place_search_repository.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/venue.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _home(TestServices t) => MaterialApp(
  home: TeamHomeScreen(services: t.services, userId: 'me', onSignOut: () async {}),
);

const _kakaoVenue = Venue.kakao(name: '강남 풋살파크', address: '서울', placeId: 'k9', lat: 37.5, lng: 127.0);

TeamSummary _team({String? logoPath, Venue? venue, TeamRole role = TeamRole.owner}) => TeamSummary(
  id: 'a',
  name: '코코FC',
  teamCode: 'KOKO22',
  logoText: '코코',
  logoImagePath: logoPath,
  myRole: role,
  isRecruiting: true,
  venue: venue,
);

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '일번'),
];

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<TestServices> _openTeamInfo(WidgetTester tester, TeamSummary team) async {
  _tall(tester);
  final t = TestServices(teams: [team], members: {'a': _members});
  await tester.pumpWidget(_home(t));
  await tester.pumpAndSettle();
  await tester.tap(find.text(TeamTexts.tabAdmin));
  await tester.pumpAndSettle();
  await _tapKey(tester, 'open-team-info');
  return t;
}

void main() {
  group('팀 만들기: 로고 사진·지정 풋살장', () {
    testWidgets('사진을 고르고 카카오 검색 결과를 고르면, 팀을 만든 뒤 사진을 올린다', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');

      await _tapKey(tester, 'logo-photo-pick');
      expect(t.logoPicker.calls, 1);
      expect(find.text(TeamTexts.changePhoto), findsOneWidget);
      expect(find.byKey(const Key('logo-photo-remove')), findsOneWidget);

      await _tapKey(tester, 'venue-field');
      await tester.enterText(find.byKey(const Key('venue-search-input')), '  강남   풋살 ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(t.places.queries, ['강남 풋살:1']);
      await tester.tap(find.byKey(const Key('venue-result-k1')));
      await tester.pumpAndSettle();
      expect(find.text('강남 풋살파크'), findsOneWidget);

      await _tapKey(tester, 'team-create-submit');
      final v = t.teams.lastCreatedVenue!;
      expect(v.provider, MapProvider.kakao);
      expect(v.placeId, 'k1');
      expect(v.lat, 37.5);
      expect(t.logos.calls, ['set:new-1:3:-']);
    });

    testWidgets('사진을 골랐다 지우면 올리지 않는다 (글자 로고)', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      await _tapKey(tester, 'logo-photo-pick');
      await _tapKey(tester, 'logo-photo-remove');
      expect(find.text(TeamTexts.pickPhoto), findsOneWidget);
      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.calls, ['create:번개FC']);
      expect(t.logos.calls, isEmpty);
      expect(t.teams.lastCreatedVenue, isNull);
    });

    testWidgets('10MB 넘는 사진·JPG/PNG 아닌 사진은 안내만', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      t.logoPicker.next = const LogoPickTooLarge();
      await _tapKey(tester, 'logo-photo-pick');
      expect(find.text(TeamTexts.photoTooLarge), findsOneWidget);
      expect(find.byKey(const Key('logo-photo-remove')), findsNothing);
      t.logoPicker.next = const LogoPickUnsupported();
      await _tapKey(tester, 'logo-photo-pick');
      expect(find.text(TeamTexts.photoUnsupported), findsOneWidget);
      t.logoPicker.next = const LogoPickCancelled();
      await _tapKey(tester, 'logo-photo-pick');
      expect(find.byKey(const Key('logo-photo-error')), findsNothing);
    });

    testWidgets('사진 올리기만 실패하면 팀은 만들어지고 안내', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.logos.nextFailure = const ServerFailure(ServerErrorCode.unknown);
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      await _tapKey(tester, 'logo-photo-pick');
      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.calls, ['create:번개FC']);
      expect(find.text(TeamTexts.logoPhotoSaveFailed), findsOneWidget);
      expect(find.text('번개FC'), findsWidgets);
    });

    testWidgets('장소 검색 배포 전: "준비 중" 안내, 직접 입력은 된다', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.places.failure = const PlaceSearchFailure(PlaceSearchError.unavailable);
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      await _tapKey(tester, 'venue-field');
      await tester.enterText(find.byKey(const Key('venue-search-input')), '동네 구장');
      await _tapKey(tester, 'venue-search-submit');
      expect(find.byKey(const Key('venue-search-unavailable')), findsOneWidget);
      expect(find.text(TeamTexts.venueSearchUnavailable), findsOneWidget);

      await _tapKey(tester, 'venue-manual');
      // 검색어가 이름 칸에 미리 들어간다
      expect(find.widgetWithText(TextField, '동네 구장'), findsWidgets);
      await tester.enterText(find.byKey(const Key('venue-manual-name')), '');
      await _tapKey(tester, 'venue-manual-done');
      expect(find.text(TeamTexts.venueNameRequired), findsOneWidget);
      await tester.enterText(find.byKey(const Key('venue-manual-name')), ' 동네  구장 ');
      await tester.enterText(find.byKey(const Key('venue-manual-address')), ' 성남시 ');
      await _tapKey(tester, 'venue-manual-done');
      expect(find.text(TeamTexts.venueManualBadge, findRichText: true), findsNothing);
      expect(find.textContaining(TeamTexts.venueManualBadge), findsOneWidget);

      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.lastCreatedVenue, const Venue.manual(name: '동네 구장', address: '성남시'));
    });

    testWidgets('검색 실패는 다시 시도, 결과 없음 안내', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.places.failure = const PlaceSearchFailure(PlaceSearchError.failed);
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await _tapKey(tester, 'venue-field');
      await tester.enterText(find.byKey(const Key('venue-search-input')), '풋살');
      await _tapKey(tester, 'venue-search-submit');
      expect(find.byKey(const Key('venue-search-failed')), findsOneWidget);
      t.places
        ..failure = null
        ..results = const [];
      await tester.tap(find.text(TeamTexts.retry));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('venue-no-result')), findsOneWidget);
    });
  });

  group('팀 정보 수정: 로고 사진·지정 풋살장', () {
    testWidgets('사진 바꾸기: 정보 저장 뒤 새 사진, 이전 경로 넘김. 구장은 그대로 보낸다', (tester) async {
      final t = await _openTeamInfo(tester, _team(logoPath: 'a/old.png', venue: _kakaoVenue));
      expect(find.text('강남 풋살파크'), findsOneWidget);
      expect(find.text(TeamTexts.changePhoto), findsOneWidget);
      await _tapKey(tester, 'logo-photo-pick');
      await _tapKey(tester, 'team-info-save');
      expect(t.admin.calls, ['info:a']);
      expect(t.admin.lastInfo!.venue, _kakaoVenue);
      expect(t.logos.calls, ['set:a:3:a/old.png']);
    });

    testWidgets('사진 지우기 → 글자 로고, 구장 지우기 → 없음으로 저장', (tester) async {
      final t = await _openTeamInfo(tester, _team(logoPath: 'a/old.png', venue: _kakaoVenue));
      await _tapKey(tester, 'logo-photo-remove');
      final preview = tester.widget<TeamLogo>(find.byKey(const Key('team-info-logo-preview')));
      expect(preview.imagePath, isNull);
      expect(preview.imageBytes, isNull);
      await _tapKey(tester, 'venue-clear');
      expect(
        find.descendant(of: find.byKey(const Key('venue-field')), matching: find.text(TeamTexts.venueNone)),
        findsOneWidget,
      );
      await _tapKey(tester, 'team-info-save');
      expect(t.admin.lastInfo!.venue, isNull);
      expect(t.logos.calls, ['remove:a:a/old.png']);
    });

    testWidgets('사진을 건드리지 않으면 저장소를 부르지 않는다', (tester) async {
      final t = await _openTeamInfo(tester, _team(logoPath: 'a/old.png'));
      final preview = tester.widget<TeamLogo>(find.byKey(const Key('team-info-logo-preview')));
      expect(preview.imagePath, 'a/old.png');
      await _tapKey(tester, 'team-info-save');
      expect(t.admin.calls, ['info:a']);
      expect(t.logos.calls, isEmpty);
    });

    testWidgets('팀 정보 저장이 실패하면 사진도 바꾸지 않는다', (tester) async {
      final t = await _openTeamInfo(tester, _team(logoPath: 'a/old.png'));
      await _tapKey(tester, 'logo-photo-pick');
      t.admin.nextFailure = const ServerFailure(ServerErrorCode.invalidVenue);
      await _tapKey(tester, 'team-info-save');
      expect(find.byKey(const Key('team-info-error')), findsOneWidget);
      expect(find.text('지정 풋살장 정보를 확인해 주세요'), findsOneWidget);
      expect(t.logos.calls, isEmpty);
    });
  });

  testWidgets('팀 해체 뒤 로고 사진 파일을 지운다', (tester) async {
    _tall(tester);
    final t = TestServices(
      teams: [_team(logoPath: 'a/old.png'), team('b', '비팀', TeamRole.member)],
      members: {'a': _members},
    );
    await t.recent.save('me', ['a', 'b']);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabAdmin));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'dissolve-team');
    await tester.enterText(find.byKey(const Key('dissolve-input')), '코코FC');
    await tester.pump();
    await tester.tap(find.byKey(const Key('dissolve-confirm')));
    await tester.pumpAndSettle();
    expect(t.teams.calls, ['dissolve:a:코코FC']);
    expect(t.logos.calls, ['delete:a/old.png']);
  });

  testWidgets('로고 사진 경로가 있으면 TeamLogoImages 로 불러오고, 없으면 글자 로고', (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TeamLogoImages(
          resolve: (p) {
            asked.add(p);
            return null;
          },
          child: const Column(
            children: [
              TeamLogo(text: '코코', imagePath: 'a/x.png'),
              TeamLogo(text: '번개'),
            ],
          ),
        ),
      ),
    );
    expect(asked, ['a/x.png']);
    expect(find.text('코코'), findsOneWidget);
    expect(find.text('번개'), findsOneWidget);
  });
}
