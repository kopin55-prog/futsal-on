import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/auth/presentation/account_delete_screen.dart';
import 'package:futsal_on/features/membership/presentation/team_find_screen.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/presentation/team_home_screen.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';
import 'package:futsal_on/shared/data/server_error.dart';

import '../../support/fakes.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _home(TestServices t, {String userId = 'me', VoidCallback? onSignOut}) =>
    MaterialApp(
      home: TeamHomeScreen(
        services: t.services,
        userId: userId,
        onSignOut: () async => onSignOut?.call(),
      ),
    );

const _members = [
  MemberEntry(userId: 'me', role: TeamRole.owner, displayName: '나'),
  MemberEntry(userId: 'm1', role: TeamRole.manager, displayName: '운영', bio: '반가워요'),
  MemberEntry(userId: 'u1', role: TeamRole.member, displayName: '팀원1'),
];

void main() {
  testWidgets('소속 팀이 없으면 만들기·찾기 홈, 팀을 만들면 그 팀이 열린다', (tester) async {
    _tall(tester);
    final t = TestServices();
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    expect(find.text(TeamTexts.noTeamTitle), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-create-team')));
    await tester.pumpAndSettle();
    // 이름 없이 만들기 → 오류
    await tester.tap(find.byKey(const Key('team-create-submit')));
    await tester.pumpAndSettle();
    expect(find.text(TeamTexts.nameRequired), findsOneWidget);
    expect(t.teams.calls, isEmpty);

    await tester.enterText(find.byKey(const Key('team-name')), '  코코   FC ');
    await tester.tap(find.byKey(const Key('team-create-submit')));
    await tester.pumpAndSettle();
    expect(t.teams.calls, ['create:코코 FC']);
    expect(find.text('코코 FC'), findsOneWidget);
    // 만든 사람은 팀장 → 관리 탭이 보인다
    expect(find.text(TeamTexts.tabAdmin), findsOneWidget);
  });

  testWidgets('로고 글자 3자는 막는다', (tester) async {
    _tall(tester);
    final t = TestServices();
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-create-team')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-name')), '코코');
    await tester.enterText(find.byKey(const Key('team-logo-text')), 'ABC');
    await tester.pump();
    expect(find.text(TeamTexts.logoTooLong), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-create-submit')));
    await tester.pumpAndSettle();
    expect(t.teams.calls, isEmpty);
  });

  testWidgets('마지막으로 본 팀이 열리고, 팀 전환으로 바꿀 수 있다', (tester) async {
    _tall(tester);
    final t = TestServices(
      teams: [team('a', '에이팀', TeamRole.member), team('b', '비팀', TeamRole.member)],
    );
    await t.recent.save('me', ['b']);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    expect(find.text('비팀'), findsOneWidget);

    await tester.tap(find.byKey(const Key('team-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-team-a')));
    await tester.pumpAndSettle();
    expect(find.text('에이팀'), findsOneWidget);
    expect(await t.recent.load('me'), ['a', 'b']);
  });

  testWidgets('팀원에게는 관리 탭이 없다', (tester) async {
    _tall(tester);
    final t = TestServices(teams: [team('a', '에이팀', TeamRole.member)]);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    expect(find.text(TeamTexts.tabAdmin), findsNothing);
    expect(find.text(TeamTexts.tabMembers), findsWidgets);
  });

  testWidgets('팀원 목록: 이름·역할 배지·자기소개, 누르면 프로필', (tester) async {
    _tall(tester);
    final t = TestServices(
      teams: [team('a', '에이팀', TeamRole.member)],
      members: {'a': _members},
    );
    await tester.pumpWidget(_home(t, userId: 'u1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabMembers));
    await tester.pumpAndSettle();
    expect(find.text('운영'), findsOneWidget);
    expect(find.text('반가워요'), findsOneWidget);
    expect(find.text(TeamTexts.owner), findsOneWidget);
    expect(find.text(TeamTexts.manager), findsOneWidget);

    // 일반 팀원은 남의 선호 포지션을 못 본다 (Q-017)
    await tester.tap(find.byKey(const Key('member-m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-prefs')), findsNothing);
  });

  testWidgets('팀장은 남의 선호 포지션을 본다 (Q-017)', (tester) async {
    _tall(tester);
    final t = TestServices(
      teams: [team('a', '에이팀', TeamRole.owner)],
      members: {'a': _members},
    );
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabMembers));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('member-u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-prefs')), findsOneWidget);
  });

  testWidgets('팀 탈퇴하면 가장 최근에 본 다른 팀이 열린다 (Q-067 6번)', (tester) async {
    _tall(tester);
    final t = TestServices(
      teams: [
        team('a', '에이팀', TeamRole.member),
        team('b', '비팀', TeamRole.member),
        team('c', '씨팀', TeamRole.member),
      ],
    );
    await t.recent.save('me', ['b', 'c', 'a']);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    expect(find.text('비팀'), findsOneWidget);

    await tester.tap(find.text(TeamTexts.tabMy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leave-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(t.teams.calls, ['leave:b']);
    expect(find.text('씨팀'), findsOneWidget);
  });

  testWidgets('마지막 팀을 떠나면 만들기·찾기 홈', (tester) async {
    _tall(tester);
    final t = TestServices(teams: [team('a', '에이팀', TeamRole.member)]);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabMy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('leave-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-ok')));
    await tester.pumpAndSettle();
    expect(find.text(TeamTexts.noTeamTitle), findsOneWidget);
  });

  testWidgets('팀장은 팀 탈퇴 버튼 대신 안내 (Q-037)', (tester) async {
    _tall(tester);
    final t = TestServices(teams: [team('a', '에이팀', TeamRole.owner)]);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabMy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leave-team')), findsNothing);
    expect(find.text(TeamTexts.ownerCannotLeave), findsOneWidget);
    expect(find.text('CODEA'), findsOneWidget); // 팀 식별코드
  });

  testWidgets('내 프로필 수정', (tester) async {
    _tall(tester);
    final t = TestServices(teams: [team('a', '에이팀', TeamRole.member)]);
    await tester.pumpWidget(_home(t));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TeamTexts.tabMy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-name')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-name')), ' 새이름 ');
    await tester.tap(find.byKey(const Key('profile-submit')));
    await tester.pumpAndSettle();
    expect(t.profiles.updated?.name, '새이름');
    expect(find.text('새이름'), findsOneWidget);
  });

  group('관리 탭', () {
    testWidgets('가입 신청 승인, 초대 코드 발급', (tester) async {
      _tall(tester);
      final t = TestServices(
        teams: [team('a', '에이팀', TeamRole.manager)],
        members: {'a': _members},
      );
      t.membership.incoming = [
        IncomingJoinRequest(
          requestId: 'r1',
          userId: 'x',
          displayName: '신청자',
          createdAt: DateTime(2026, 11, 5),
        ),
      ];
      await tester.pumpWidget(_home(t, userId: 'm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.tabAdmin));
      await tester.pumpAndSettle();
      expect(find.text('신청자'), findsOneWidget);
      // 운영진에게는 팀원 관리·해체가 없다
      expect(find.text(TeamTexts.membersSection), findsNothing);
      expect(find.byKey(const Key('dissolve-team')), findsNothing);

      await tester.tap(find.byKey(const Key('approve-r1')));
      await tester.pumpAndSettle();
      expect(t.membership.calls, ['decide:r1:true']);
      expect(find.text(TeamTexts.noRequests), findsOneWidget);

      await tester.tap(find.byKey(const Key('issue-invite')));
      await tester.pumpAndSettle();
      expect(find.text('INVITE-CODE-123'), findsOneWidget);
    });

    testWidgets('팀장: 운영진 지정', (tester) async {
      _tall(tester);
      final t = TestServices(
        teams: [team('a', '에이팀', TeamRole.owner)],
        members: {'a': _members},
      );
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.tabAdmin));
      await tester.pumpAndSettle();
      // 자기 자신에게는 메뉴 없음
      expect(find.byKey(const Key('manage-menu-me')), findsNothing);
      await tester.tap(find.byKey(const Key('manage-menu-u1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.appointManager).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await tester.pumpAndSettle();
      expect(t.membership.calls, ['appoint:u1']);
    });

    testWidgets('팀 해체: 이름이 맞아야 버튼이 켜지고, 해체 후 다른 팀', (tester) async {
      _tall(tester);
      final t = TestServices(
        teams: [team('a', '코코 FC', TeamRole.owner), team('b', '비팀', TeamRole.member)],
        members: {'a': _members},
      );
      await t.recent.save('me', ['a', 'b']);
      await tester.pumpWidget(_home(t));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TeamTexts.tabAdmin));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('dissolve-team')));
      await tester.tap(find.byKey(const Key('dissolve-team')));
      await tester.pumpAndSettle();

      FilledButton button() =>
          tester.widget<FilledButton>(find.byKey(const Key('dissolve-confirm')));
      expect(button().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('dissolve-input')), '코코');
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('dissolve-input')), '  코코 fc ');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('dissolve-confirm')));
      await tester.pumpAndSettle();
      expect(t.teams.calls, ['dissolve:a:  코코 fc ']);
      expect(find.text('비팀'), findsOneWidget);
    });
  });

  group('팀 찾기', () {
    Widget find0(TestServices t) =>
        MaterialApp(home: TeamFindScreen(membership: t.membership));

    testWidgets('식별코드: 소문자 입력도 찾고, 모집 마감이면 신청 버튼 없음', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.byCode['K7FC3M'] = const TeamSearchResult(
        teamCode: 'K7FC3M',
        name: '마감팀',
        logoText: '마감',
        memberCount: 7,
        isRecruiting: false,
      );
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), 'k7fc3m');
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      expect(find.text('마감팀'), findsOneWidget);
      expect(find.text(TeamTexts.recruitingClosed), findsOneWidget);
      expect(find.text(TeamTexts.requestJoin), findsNothing);
    });

    testWidgets('없는 코드', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), 'ZZZZZZ');
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.codeNotFound), findsOneWidget);
    });

    testWidgets('해체된 팀 코드는 "가입할 수 없는 팀이에요" (Q-067 8번)', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.findFailure = const ServerFailure(ServerErrorCode.teamDissolved);
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), 'ABCDEF');
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.cannotJoinTeam), findsOneWidget);
    });

    testWidgets('신청: 이미 소속·이미 신청 안내 (Q-067 10번)', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.byCode['K7FC3M'] = const TeamSearchResult(
        teamCode: 'K7FC3M',
        name: '모집팀',
        logoText: '모집',
        memberCount: 7,
        isRecruiting: true,
      );
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), 'K7FC3M');
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();

      t.membership.nextFailure = const ServerFailure(ServerErrorCode.alreadyMember);
      await tester.tap(find.text(TeamTexts.requestJoin));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.alreadyMember), findsOneWidget);

      t.membership.nextFailure =
          const ServerFailure(ServerErrorCode.requestAlreadyPending);
      await tester.tap(find.text(TeamTexts.requestJoin));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.alreadyRequested), findsOneWidget);

      await tester.tap(find.text(TeamTexts.requestJoin));
      await tester.pumpAndSettle();
      expect(t.membership.calls, ['request:K7FC3M:code']);
      expect(find.text(TeamTexts.requestSent), findsOneWidget);
    });

    testWidgets('보낸 신청 취소', (tester) async {
      _tall(tester);
      final t = TestServices();
      t.membership.myRequests = [
        MyJoinRequest(
          requestId: 'r9',
          teamName: '대기팀',
          teamCode: 'WAIT22',
          logoText: '대기',
          createdAt: DateTime(2026, 11, 5),
        ),
      ];
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      expect(find.text('대기팀'), findsOneWidget);
      await tester.tap(find.text(TeamTexts.cancelRequest));
      await tester.pumpAndSettle();
      expect(t.membership.calls, ['cancel:r9']);
      expect(find.text('대기팀'), findsNothing);
    });

    testWidgets('이름 검색은 2자 이상 (Q-067 11번)', (tester) async {
      _tall(tester);
      final t = TestServices();
      await tester.pumpWidget(find0(t));
      await tester.pumpAndSettle();
      await tester.tap(find.text('팀 이름'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('find-input')), '코');
      await tester.tap(find.byKey(const Key('find-submit')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.searchTooShort), findsOneWidget);
    });
  });

  group('회원 탈퇴 (Q-067 12번)', () {
    testWidgets('확인 화면에서 한 번 더 눌러야 진행, 팀장이면 안내', (tester) async {
      _tall(tester);
      final t = TestServices();
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountDeleteScreen(
            accounts: t.accounts,
            onDeleted: () async => signedOut = true,
          ),
        ),
      );
      expect(find.text(TeamTexts.deleteAccountWarning), findsOneWidget);
      expect(t.accounts.deleteCalls, 0);

      t.accounts.nextFailure =
          const ServerFailure(ServerErrorCode.ownerMustTransferOrDissolve);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(TeamTexts.ownerCannotLeave), findsOneWidget);
      expect(signedOut, isFalse);

      t.accounts.nextFailure = null;
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });
  });
}
