import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/membership/presentation/team_find_screen.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/features/venue/data/place_search_repository.dart';
import 'package:futsal_on/shared/domain/region.dart';
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

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 드롭다운 [key] 를 열고 [item] 을 고른다.
Future<void> _pick(WidgetTester tester, String key, String item) async {
  await _tapKey(tester, key);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

String? _shown(WidgetTester tester, String key) =>
    tester.widget<DropdownButtonFormField<String?>>(find.byKey(Key(key))).initialValue;

Future<void> _pickKakao(WidgetTester tester, TestServices t, PlaceResult place) async {
  t.places.results = [place];
  await _tapKey(tester, 'venue-field');
  await tester.enterText(find.byKey(const Key('venue-search-input')), '구장');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('venue-result-${place.placeId}')));
  await tester.pumpAndSettle();
}

const _seongsu = PlaceResult(
  placeId: 's1',
  name: '성수 풋살장',
  address: '서울특별시 성동구 성수이로 1',
  lat: 37.5,
  lng: 127.05,
);

void main() {
  group('주소 → 활동 지역 (regionFromAddress)', () {
    test('짧은·긴 시·도 표기를 목록 값으로 맞춘다', () {
      expect(regionFromAddress('서울 성동구 성수이로 1'), const Region('서울', '성동구'));
      expect(regionFromAddress('서울특별시 성동구 성수동1가 1'), const Region('서울', '성동구'));
      expect(regionFromAddress('강원특별자치도 춘천시 중앙로 1'), const Region('강원', '춘천시'));
      expect(regionFromAddress('전라북도 전주시 완산구 1'), const Region('전북', '전주시 완산구'));
      expect(regionFromAddress('전북특별자치도 군산시 1'), const Region('전북', '군산시'));
      expect(regionFromAddress('제주특별자치도 서귀포시 1'), const Region('제주', '서귀포시'));
    });

    test('일반구가 있는 시는 "시 구" 두 단어, 구가 없으면 시·군·구는 비운다', () {
      expect(regionFromAddress('경기 성남시 분당구 정자일로 1'), const Region('경기', '성남시 분당구'));
      expect(regionFromAddress('경기 성남시 1'), const Region('경기'));
      expect(regionFromAddress('경기 광주시 1'), const Region('경기', '광주시'));
    });

    test('세종은 시·도만, 모르는 주소는 null', () {
      expect(regionFromAddress('세종특별자치시 한누리대로 1'), const Region('세종'));
      expect(regionFromAddress('Seoul 1'), isNull);
      expect(regionFromAddress(''), isNull);
      expect(regionFromAddress(null), isNull);
      // "광주시"만으로는 광주광역시인지 경기 광주시인지 알 수 없어 채우지 않는다
      expect(regionFromAddress('광주시 1'), isNull);
    });

    test('목록: 시·도 17개, 값은 앞뒤 공백 없음', () {
      expect(KoreaRegions.sidoList, hasLength(17));
      for (final entry in KoreaRegions.sigunguBySido.entries) {
        expect(entry.value.toSet(), hasLength(entry.value.length), reason: '${entry.key} 중복');
        for (final s in entry.value) {
          expect(s, s.trim());
          expect(s.length, lessThanOrEqualTo(20));
        }
      }
    });

    test('직접 입력 구장·구장 지우기는 지금 값 유지, 카카오 구장은 주소로 채움', () {
      const now = Region('부산', '해운대구');
      expect(regionAfterVenueChange(const Venue.manual(name: '동네', address: '서울 성동구 1'), now), now);
      expect(regionAfterVenueChange(null, now), now);
      expect(regionAfterVenueChange(_seongsu.toVenue(), now), const Region('서울', '성동구'));
      expect(
        regionAfterVenueChange(const Venue.kakao(name: 'x', placeId: 'p', lat: 1, lng: 1, address: '알 수 없음'), now),
        now,
      );
    });
  });

  group('팀 만들기: 활동 지역 자동 채움', () {
    testWidgets('카카오 구장을 고르면 시·도·시·군·구가 채워지고, 바꾸거나 비울 수 있다', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      expect(find.text(TeamTexts.region), findsOneWidget);
      expect(_shown(tester, 'team-region-sido'), isNull);

      await _pickKakao(tester, t, _seongsu);
      expect(_shown(tester, 'team-region-sido'), '서울');
      expect(_shown(tester, 'team-region-sigungu'), '성동구');

      // 시·군·구 바꾸기
      await _pick(tester, 'team-region-sigungu', '광진구');
      expect(_shown(tester, 'team-region-sigungu'), '광진구');
      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.lastCreatedRegion, const Region('서울', '광진구'));
    });

    testWidgets('시·도를 비우면 지역 없이 만든다, 시·도를 바꾸면 시·군·구는 비운다', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      await _pickKakao(tester, t, _seongsu);

      await _pick(tester, 'team-region-sido', '부산');
      expect(_shown(tester, 'team-region-sido'), '부산');
      expect(_shown(tester, 'team-region-sigungu'), isNull);

      await _pick(tester, 'team-region-sido', TeamTexts.regionNone);
      expect(_shown(tester, 'team-region-sido'), isNull);
      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.calls, ['create:번개FC']);
      expect(t.teams.lastCreatedRegion, isNull);
    });

    testWidgets('직접 입력한 구장은 자동 채움 없음', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'home-create-team');
      await tester.enterText(find.byKey(const Key('team-name')), '번개FC');
      await _tapKey(tester, 'venue-field');
      await _tapKey(tester, 'venue-manual');
      await tester.enterText(find.byKey(const Key('venue-manual-name')), '동네 구장');
      await tester.enterText(find.byKey(const Key('venue-manual-address')), '서울 성동구 1');
      await _tapKey(tester, 'venue-manual-done');
      expect(find.text('동네 구장'), findsOneWidget);
      expect(_shown(tester, 'team-region-sido'), isNull);
      await _tapKey(tester, 'team-create-submit');
      expect(t.teams.lastCreatedRegion, isNull);
    });
  });

  group('팀 정보 수정: 활동 지역', () {
    testWidgets('지금 지역을 보여주고, 바꾼 값을 보낸다', (tester) async {
      _tall(tester);
      final t = TestServices(
        teams: [
          const TeamSummary(
            id: 'a',
            name: '코코FC',
            teamCode: 'KOKO22',
            logoText: '코코',
            myRole: TeamRole.owner,
            isRecruiting: true,
            region: Region('서울', '성동구'),
          ),
        ],
        members: {
          'a': const [MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나')],
        },
      );
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.tabAdmin));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'open-team-info');
      expect(_shown(tester, 'team-region-sido'), '서울');
      expect(_shown(tester, 'team-region-sigungu'), '성동구');

      await _pick(tester, 'team-region-sigungu', TeamTexts.regionNone);
      await _tapKey(tester, 'team-info-save');
      expect(t.admin.lastInfo!.region, const Region('서울'));
    });
  });

  group('팀 찾기: 지역 필터', () {
    Widget find0(TestServices t) => MaterialApp(home: TeamFindScreen(membership: t.membership));

    testWidgets('팀 이름 검색 위에 지역 선택, 결과 카드에 "서울 성동구"', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.searchResults = const [
        TeamSearchResult(
          teamCode: 'K7FC3M',
          name: '코코FC',
          logoText: '코코',
          memberCount: 8,
          isRecruiting: true,
          region: Region('서울', '성동구'),
        ),
      ];
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      // 식별코드 모드에는 지역 선택이 없다
      expect(find.byKey(const Key('find-region-sido')), findsNothing);
      await tester.tap(find.text('팀 이름'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('find-region-sido')), findsOneWidget);
      // 처음은 전체
      expect(find.text(TeamTexts.regionAll), findsNWidgets(2));

      await _pick(tester, 'find-region-sido', '서울');
      await _pick(tester, 'find-region-sigungu', '성동구');
      await tester.enterText(find.byKey(const Key('find-input')), '코코');
      await _tapKey(tester, 'find-submit');
      expect(t.membership.lastSearchRegion, const Region('서울', '성동구'));
      expect(find.textContaining('서울 성동구'), findsOneWidget);

      // 시·군·구 전체 → 시·도만
      await _pick(tester, 'find-region-sigungu', TeamTexts.regionAll);
      await _tapKey(tester, 'find-submit');
      expect(t.membership.lastSearchRegion, const Region('서울'));

      // 시·도 전체 → 필터 없음
      await _pick(tester, 'find-region-sido', TeamTexts.regionAll);
      await _tapKey(tester, 'find-submit');
      expect(t.membership.lastSearchRegion, isNull);
    });

    testWidgets('시·도를 고르기 전에는 시·군·구를 고를 수 없다', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.tap(find.text('팀 이름'));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButtonFormField<String?>>(find.byKey(const Key('find-region-sigungu')));
      expect(field.onChanged, isNull);
      await _pick(tester, 'find-region-sido', '세종');
      // 세종은 시·군·구가 없다
      expect(
        tester.widget<DropdownButtonFormField<String?>>(find.byKey(const Key('find-region-sigungu'))).onChanged,
        isNull,
      );
    });

    testWidgets('식별코드 찾기 결과에도 지역 표시', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.byCode = {
        'K7FC3M': const TeamSearchResult(
          teamCode: 'K7FC3M',
          name: '코코FC',
          logoText: '코코',
          memberCount: 8,
          isRecruiting: true,
          region: Region('경기', '성남시 분당구'),
        ),
      };
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), 'K7FC3M');
      await _tapKey(tester, 'find-submit');
      expect(find.textContaining('경기 성남시 분당구'), findsOneWidget);
    });
  });
}
