/// 팀 전환: 마지막으로 본 팀 기억 (기기 안, 계정별).
///
/// - 앱을 열면 가장 최근에 본 팀이 열린다.
/// - 팀을 떠나거나 팀이 해체되면 가장 최근에 본 **다른** 팀이 열리고, 없으면 "팀 만들기 / 팀 찾기" 홈 (Q-067 6번).
abstract final class RecentTeams {
  /// 기억해 둘 최대 개수 (소속 최대 10팀, Q-067 5번보다 넉넉하게).
  static const int maxKept = 20;

  /// [teamId]를 맨 앞으로.
  static List<String> touch(List<String> recent, String teamId) =>
      [teamId, ...recent.where((id) => id != teamId)].take(maxKept).toList();

  /// [teamId]를 목록에서 뺀다 (떠난 팀·해체된 팀).
  static List<String> forget(List<String> recent, String teamId) =>
      recent.where((id) => id != teamId).toList();

  /// 지금 소속된 팀 [myTeamIds] 중 열 팀. 최근 본 순서가 먼저, 기록에 없으면 목록 첫 팀.
  /// 소속 팀이 없으면 null.
  static String? pick({
    required List<String> recent,
    required List<String> myTeamIds,
  }) {
    for (final id in recent) {
      if (myTeamIds.contains(id)) return id;
    }
    return myTeamIds.isEmpty ? null : myTeamIds.first;
  }
}
