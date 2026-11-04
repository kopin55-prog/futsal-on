import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/team/domain/team_roster.dart';

TeamRoster ok(RoleChangeResult r) {
  expect(r, isA<RoleChangeOk>());
  return (r as RoleChangeOk).roster;
}

RoleChangeError failed(RoleChangeResult r) {
  expect(r, isA<RoleChangeFailed>());
  return (r as RoleChangeFailed).error;
}

void main() {
  // o: 팀장, m1·m2: 운영진, a·b: 팀원
  TeamRoster base({bool twoManagers = false}) => TeamRoster({
        'o': TeamRole.owner,
        'm1': TeamRole.manager,
        if (twoManagers) 'm2': TeamRole.manager,
        'a': TeamRole.member,
        'b': TeamRole.member,
      });

  group('명단 불변식', () {
    test('팀을 만든 사람이 팀장', () {
      final r = TeamRoster.created(ownerUserId: 'o');
      expect(r.ownerUserId, 'o');
      expect(r.managerCount, 0);
    });
    test('팀장이 0명이거나 2명이면 만들 수 없다', () {
      expect(() => TeamRoster({'a': TeamRole.member}), throwsArgumentError);
      expect(() => TeamRoster({'a': TeamRole.owner, 'b': TeamRole.owner}),
          throwsArgumentError);
    });
    test('운영진 3명은 만들 수 없다', () {
      expect(
        () => TeamRoster({
          'o': TeamRole.owner,
          'm1': TeamRole.manager,
          'm2': TeamRole.manager,
          'm3': TeamRole.manager,
        }),
        throwsArgumentError,
      );
    });
    test('명단은 밖에서 바꿀 수 없다', () {
      expect(() => base().roles['x'] = TeamRole.member, throwsUnsupportedError);
    });
  });

  group('운영진 지정', () {
    test('팀장이 팀원을 운영진으로', () {
      final r = ok(base().appointManager(actorUserId: 'o', targetUserId: 'a'));
      expect(r.roleOf('a'), TeamRole.manager);
      expect(r.managerCount, 2);
    });
    test('최대 2명: 세 번째는 불가', () {
      expect(
        failed(base(twoManagers: true)
            .appointManager(actorUserId: 'o', targetUserId: 'a')),
        RoleChangeError.managerLimitReached,
      );
    });
    test('운영진·팀원은 지정할 수 없다', () {
      expect(
          failed(base().appointManager(actorUserId: 'm1', targetUserId: 'a')),
          RoleChangeError.notPermitted);
      expect(failed(base().appointManager(actorUserId: 'a', targetUserId: 'b')),
          RoleChangeError.notPermitted);
    });
    test('이미 운영진, 팀 밖 사람, 자기 자신은 불가', () {
      expect(
          failed(base().appointManager(actorUserId: 'o', targetUserId: 'm1')),
          RoleChangeError.alreadyManager);
      expect(failed(base().appointManager(actorUserId: 'o', targetUserId: 'z')),
          RoleChangeError.targetNotInTeam);
      expect(failed(base().appointManager(actorUserId: 'o', targetUserId: 'o')),
          RoleChangeError.cannotTargetSelf);
    });
    test('해제 후에는 다시 지정 가능', () {
      final r1 = ok(base(twoManagers: true)
          .dismissManager(actorUserId: 'o', targetUserId: 'm2'));
      expect(r1.roleOf('m2'), TeamRole.member);
      final r2 = ok(r1.appointManager(actorUserId: 'o', targetUserId: 'a'));
      expect(r2.managerCount, 2);
    });
  });

  group('운영진 해제', () {
    test('팀장만, 운영진만 대상', () {
      expect(
          failed(base().dismissManager(actorUserId: 'm1', targetUserId: 'm1')),
          RoleChangeError.notPermitted);
      expect(failed(base().dismissManager(actorUserId: 'o', targetUserId: 'a')),
          RoleChangeError.targetNotManager);
      expect(failed(base().dismissManager(actorUserId: 'o', targetUserId: 'o')),
          RoleChangeError.targetNotManager);
    });
  });

  group('팀장 위임', () {
    test('운영진에게 위임하면 즉시 팀장이 되고 기존 팀장은 운영진', () {
      final r =
          ok(base().transferOwnership(actorUserId: 'o', targetUserId: 'm1'));
      expect(r.ownerUserId, 'm1');
      expect(r.roleOf('o'), TeamRole.manager);
      expect(r.managerCount, 1);
    });
    test('운영진 2명일 때 위임해도 운영진은 2명', () {
      final r = ok(base(twoManagers: true)
          .transferOwnership(actorUserId: 'o', targetUserId: 'm2'));
      expect(r.ownerUserId, 'm2');
      expect(r.managerCount, 2);
      expect(r.roleOf('m1'), TeamRole.manager);
      expect(r.roleOf('o'), TeamRole.manager);
    });
    test('팀원에게는 위임 불가 (먼저 운영진 지정)', () {
      expect(
          failed(base().transferOwnership(actorUserId: 'o', targetUserId: 'a')),
          RoleChangeError.targetNotManager);
    });
    test('운영진이 없으면 위임 불가', () {
      final r = TeamRoster.created(ownerUserId: 'o');
      expect(failed(r.transferOwnership(actorUserId: 'o', targetUserId: 'o')),
          RoleChangeError.targetNotManager);
    });
    test('팀장만 위임 가능', () {
      expect(
          failed(
              base().transferOwnership(actorUserId: 'm1', targetUserId: 'm1')),
          RoleChangeError.notPermitted);
    });
    test('팀 밖 사람에게는 불가', () {
      expect(
          failed(base().transferOwnership(actorUserId: 'o', targetUserId: 'z')),
          RoleChangeError.targetNotInTeam);
    });
  });

  group('탈퇴', () {
    test('팀장은 위임 또는 해체 없이 탈퇴 불가', () {
      expect(failed(base().leave(userId: 'o')),
          RoleChangeError.ownerMustTransferOrDisband);
    });
    test('위임 후에는 기존 팀장(이제 운영진)이 탈퇴 가능', () {
      final r =
          ok(base().transferOwnership(actorUserId: 'o', targetUserId: 'm1'));
      final after = ok(r.leave(userId: 'o'));
      expect(after.roleOf('o'), isNull);
      expect(after.ownerUserId, 'm1');
    });
    test('운영진·팀원은 자진 탈퇴 가능', () {
      expect(ok(base().leave(userId: 'm1')).roleOf('m1'), isNull);
      expect(ok(base().leave(userId: 'a')).roleOf('a'), isNull);
    });
    test('팀 밖 사람은 탈퇴할 것이 없음', () {
      expect(failed(base().leave(userId: 'z')), RoleChangeError.targetNotInTeam);
    });
  });

  group('내보내기', () {
    test('팀장이 팀원을 내보낸다', () {
      expect(
          ok(base().removeMember(actorUserId: 'o', targetUserId: 'a'))
              .roleOf('a'),
          isNull);
    });
    test('운영진·팀원은 내보낼 수 없다', () {
      expect(failed(base().removeMember(actorUserId: 'm1', targetUserId: 'a')),
          RoleChangeError.notPermitted);
    });
    test('팀장은 자신을 내보낼 수 없다', () {
      expect(failed(base().removeMember(actorUserId: 'o', targetUserId: 'o')),
          RoleChangeError.cannotTargetSelf);
    });
  });
}
