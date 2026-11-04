import 'grants.dart';
import 'team_role.dart';

/// "누가, 어느 팀 맥락에서" 보거나 행동하는지.
class Viewer {
  const Viewer({
    required this.userId,
    required this.role,
    this.grants = const Grants.none(),
  });

  final String userId;

  /// 해당 팀에서의 역할. 팀 소속이 아니면 null.
  final TeamRole? role;

  /// 2차 등급. 1차에서는 판단에 쓰지 않는다.
  final Grants grants;

  bool get isTeamMember => role != null;
}
