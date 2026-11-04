import '../../../core/entitlements/entitlements.dart';

/// 역할 변경 실패 이유.
enum RoleChangeError {
  /// 행동하는 사람에게 권한이 없음 (Entitlements 판단).
  notPermitted,

  /// 대상이 팀에 없음.
  targetNotInTeam,

  /// 운영진이 이미 최대 인원.
  managerLimitReached,

  /// 대상이 이미 운영진.
  alreadyManager,

  /// 대상이 운영진이 아님 (운영진 해제, 위임 대상 조건).
  targetNotManager,

  /// 자기 자신을 대상으로 할 수 없음.
  cannotTargetSelf,

  /// 팀장은 위임 또는 해체 없이 탈퇴할 수 없음.
  ownerMustTransferOrDisband,
}

sealed class RoleChangeResult {
  const RoleChangeResult();
}

final class RoleChangeOk extends RoleChangeResult {
  const RoleChangeOk(this.roster);
  final TeamRoster roster;
}

final class RoleChangeFailed extends RoleChangeResult {
  const RoleChangeFailed(this.error);
  final RoleChangeError error;
}

/// 한 팀의 역할 명단과 역할 규칙 (기획서 6장).
///
/// 불변 객체. 모든 변경은 새 [TeamRoster]를 담은 [RoleChangeOk]를 돌려준다.
/// 권한 판단은 직접 하지 않고 [Entitlements]에 묻는다.
/// 저장 구조와 무관한 순수 규칙이며, 서버(RLS·서버 함수)에서도 같은 규칙을 강제해야 한다.
class TeamRoster {
  TeamRoster(Map<String, TeamRole> roles, {Entitlements? entitlements})
      : _roles = Map.unmodifiable(roles),
        _entitlements = entitlements ?? const Entitlements() {
    final owners = _roles.values.where((r) => r == TeamRole.owner).length;
    final managers = _roles.values.where((r) => r == TeamRole.manager).length;
    if (owners != 1) {
      throw ArgumentError('팀장은 정확히 1명이어야 함 (현재 $owners명)');
    }
    if (managers > TeamRole.maxManagers) {
      throw ArgumentError(
          '운영진은 최대 ${TeamRole.maxManagers}명 (현재 $managers명)');
    }
  }

  /// 팀을 만든 사람이 팀장인 새 명단.
  factory TeamRoster.created({required String ownerUserId}) =>
      TeamRoster({ownerUserId: TeamRole.owner});

  final Map<String, TeamRole> _roles;
  final Entitlements _entitlements;

  Map<String, TeamRole> get roles => _roles;

  TeamRole? roleOf(String userId) => _roles[userId];

  String get ownerUserId =>
      _roles.entries.firstWhere((e) => e.value == TeamRole.owner).key;

  int get managerCount =>
      _roles.values.where((r) => r == TeamRole.manager).length;

  Viewer _viewer(String userId) => Viewer(userId: userId, role: roleOf(userId));

  bool _can(String actorUserId, TeamAction action) =>
      _entitlements.canPerform(_viewer(actorUserId), action);

  TeamRoster _with(Map<String, TeamRole> roles) =>
      TeamRoster(roles, entitlements: _entitlements);

  // 가입 승인으로 팀원을 추가하는 규칙은 초대·가입 작업(BLOCKED, Q-002)에서 추가한다.

  /// 운영진 지정: 팀장만, 운영진 최대 2명.
  RoleChangeResult appointManager({
    required String actorUserId,
    required String targetUserId,
  }) {
    if (!_can(actorUserId, TeamAction.appointOrDismissManager)) {
      return const RoleChangeFailed(RoleChangeError.notPermitted);
    }
    final target = roleOf(targetUserId);
    if (target == null) {
      return const RoleChangeFailed(RoleChangeError.targetNotInTeam);
    }
    if (targetUserId == actorUserId) {
      return const RoleChangeFailed(RoleChangeError.cannotTargetSelf);
    }
    if (target == TeamRole.manager) {
      return const RoleChangeFailed(RoleChangeError.alreadyManager);
    }
    if (managerCount >= TeamRole.maxManagers) {
      return const RoleChangeFailed(RoleChangeError.managerLimitReached);
    }
    return RoleChangeOk(_with({..._roles, targetUserId: TeamRole.manager}));
  }

  /// 운영진 해제: 팀장만. 해제된 운영진은 팀원이 된다.
  RoleChangeResult dismissManager({
    required String actorUserId,
    required String targetUserId,
  }) {
    if (!_can(actorUserId, TeamAction.appointOrDismissManager)) {
      return const RoleChangeFailed(RoleChangeError.notPermitted);
    }
    final target = roleOf(targetUserId);
    if (target == null) {
      return const RoleChangeFailed(RoleChangeError.targetNotInTeam);
    }
    if (target != TeamRole.manager) {
      return const RoleChangeFailed(RoleChangeError.targetNotManager);
    }
    return RoleChangeOk(_with({..._roles, targetUserId: TeamRole.member}));
  }

  /// 팀장 위임: 운영진에게만, 수락 없이 즉시. 기존 팀장은 운영진이 된다.
  ///
  /// 운영진 수는 (대상 1명 빠지고 기존 팀장 1명 들어와) 변하지 않으므로 최대 인원을 넘지 않는다.
  RoleChangeResult transferOwnership({
    required String actorUserId,
    required String targetUserId,
  }) {
    if (!_can(actorUserId, TeamAction.transferOwnership)) {
      return const RoleChangeFailed(RoleChangeError.notPermitted);
    }
    final target = roleOf(targetUserId);
    if (target == null) {
      return const RoleChangeFailed(RoleChangeError.targetNotInTeam);
    }
    if (target != TeamRole.manager) {
      return const RoleChangeFailed(RoleChangeError.targetNotManager);
    }
    return RoleChangeOk(_with({
      ..._roles,
      targetUserId: TeamRole.owner,
      actorUserId: TeamRole.manager,
    }));
  }

  /// 팀원 내보내기: 팀장만. 자기 자신은 내보낼 수 없다.
  RoleChangeResult removeMember({
    required String actorUserId,
    required String targetUserId,
  }) {
    if (!_can(actorUserId, TeamAction.removeMember)) {
      return const RoleChangeFailed(RoleChangeError.notPermitted);
    }
    if (targetUserId == actorUserId) {
      return const RoleChangeFailed(RoleChangeError.cannotTargetSelf);
    }
    if (!_roles.containsKey(targetUserId)) {
      return const RoleChangeFailed(RoleChangeError.targetNotInTeam);
    }
    // TODO(Q-대기): 운영진도 바로 내보낼 수 있는지(먼저 해제해야 하는지) 미정
    //   → 가장 덜 제한적으로 바로 내보낼 수 있게 둔다.
    return RoleChangeOk(_with({..._roles}..remove(targetUserId)));
  }

  /// 자진 탈퇴. 팀장은 위임 또는 해체 없이 탈퇴할 수 없다.
  RoleChangeResult leave({required String userId}) {
    final role = roleOf(userId);
    if (role == null) {
      return const RoleChangeFailed(RoleChangeError.targetNotInTeam);
    }
    if (role == TeamRole.owner) {
      return const RoleChangeFailed(RoleChangeError.ownerMustTransferOrDisband);
    }
    return RoleChangeOk(_with({..._roles}..remove(userId)));
  }
}
