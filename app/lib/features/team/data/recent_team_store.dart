import 'package:shared_preferences/shared_preferences.dart';

/// 최근 본 팀 목록 저장소 (계정별, 기기 안). 팀 내부 ID 만 저장한다.
abstract interface class RecentTeamStore {
  Future<List<String>> load(String userId);

  Future<void> save(String userId, List<String> teamIds);
}

class SharedPrefsRecentTeamStore implements RecentTeamStore {
  static String _key(String userId) => 'recent_teams.$userId';

  @override
  Future<List<String>> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key(userId)) ?? const [];
    } catch (_) {
      // 기억을 못 읽어도 첫 팀을 열면 되므로 무시한다.
      return const [];
    }
  }

  @override
  Future<void> save(String userId, List<String> teamIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(userId), teamIds);
    } catch (_) {
      // 저장 실패는 다음 실행 때 첫 팀이 열리는 정도라 무시한다.
    }
  }
}

/// 테스트·설정 없는 실행용.
class MemoryRecentTeamStore implements RecentTeamStore {
  final Map<String, List<String>> _data = {};

  @override
  Future<List<String>> load(String userId) async => _data[userId] ?? const [];

  @override
  Future<void> save(String userId, List<String> teamIds) async =>
      _data[userId] = List.of(teamIds);
}
