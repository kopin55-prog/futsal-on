import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/domain/position.dart';
import '../../../shared/domain/venue.dart';
import '../domain/team_models.dart';
import '../domain/team_validation.dart';

/// 팀 만들기·내 팀 목록·팀원 명단·팀 탈퇴·해체. 실패는 모두 [ServerFailure].
abstract interface class TeamRepository {
  /// 지금 소속된 팀 (해체된 팀 제외).
  Future<List<TeamSummary>> listMyTeams();

  /// 팀 만들기. 만든 팀의 내부 ID.
  Future<String> createTeam({
    required String name,
    RegularSchedule schedule = const RegularSchedule(),
    String? logoText,
    Venue? venue,
  });

  /// 현재 팀원 명단 (팀장 → 운영진 → 팀원, 같은 역할은 이름순).
  Future<List<MemberEntry>> listMembers(String teamId);

  /// 선호 포지션·전문 골키퍼. 권한이 없으면(일반 팀원이 남의 것) null.
  Future<PlayPrefs?> getPlayPrefs(String userId);

  Future<void> leaveTeam(String teamId);

  Future<void> dissolveTeam(String teamId, String confirmName);
}

TeamRole _role(String value) => TeamRole.values.byName(value);

ClockTime? _time(Object? value) =>
    value == null ? null : ClockTime.parse(value as String);

RegularSchedule scheduleFromRow(Map<String, dynamic> row) => RegularSchedule(
  weekday: row['regular_weekday'] as int?,
  start: _time(row['regular_start_time']),
  end: _time(row['regular_end_time']),
);

int _roleOrder(TeamRole r) => switch (r) {
  TeamRole.owner => 0,
  TeamRole.manager => 1,
  TeamRole.member => 2,
};

/// 명단 정렬: 팀장 → 운영진 → 팀원, 같은 역할은 이름순.
List<MemberEntry> sortMembers(Iterable<MemberEntry> members) =>
    members.toList()..sort((a, b) {
      final byRole = _roleOrder(a.role).compareTo(_roleOrder(b.role));
      return byRole != 0 ? byRole : a.displayName.compareTo(b.displayName);
    });

class SupabaseTeamRepository implements TeamRepository {
  SupabaseTeamRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const ServerFailure(ServerErrorCode.notAuthenticated);
    return id;
  }

  @override
  Future<List<TeamSummary>> listMyTeams() => guardServer(() async {
    final rows = await _client
        .from('team_members')
        .select(
          'role, joined_at, teams(id, name, team_code, logo_text, logo_image_path, '
          'is_recruiting, regular_weekday, regular_start_time, regular_end_time, '
          'venue_name, venue_address, venue_lat, venue_lng, venue_map_provider, venue_map_place_id)',
        )
        .eq('user_id', _uid)
        .eq('status', 'active')
        .order('joined_at');
    return [
      for (final row in rows)
        if (row['teams'] case final Map<String, dynamic> t)
          TeamSummary(
            id: t['id'] as String,
            name: t['name'] as String,
            teamCode: t['team_code'] as String,
            logoText: t['logo_text'] as String,
            logoImagePath: t['logo_image_path'] as String?,
            isRecruiting: t['is_recruiting'] as bool,
            myRole: _role(row['role'] as String),
            schedule: scheduleFromRow(t),
            venue: Venue.fromRow(t),
          ),
    ];
  });

  @override
  Future<String> createTeam({
    required String name,
    RegularSchedule schedule = const RegularSchedule(),
    String? logoText,
    Venue? venue,
  }) => guardServer(() async {
    final id = await _client.rpc<String>(
      'create_team',
      params: {
        'p_name': name,
        'p_regular_weekday': schedule.weekday,
        'p_regular_start_time': schedule.start?.hhmm,
        'p_regular_end_time': schedule.end?.hhmm,
        'p_logo_text': logoText,
        'p_venue': venue?.toServerJson(),
      },
    );
    return id;
  });

  @override
  Future<List<MemberEntry>> listMembers(String teamId) => guardServer(() async {
    final rows = await _client
        .from('team_members')
        .select('user_id, role, profiles!team_members_user_id_fkey(display_name, bio)')
        .eq('team_id', teamId)
        .eq('status', 'active');
    return sortMembers([
      for (final row in rows)
        if (row['profiles'] case final Map<String, dynamic> p)
          MemberEntry(
            userId: row['user_id'] as String,
            role: _role(row['role'] as String),
            displayName: p['display_name'] as String,
            bio: p['bio'] as String?,
          ),
    ]);
  });

  @override
  Future<PlayPrefs?> getPlayPrefs(String userId) => guardServer(() async {
    final row = await _client
        .from('profile_play_prefs')
        .select('positions, is_dedicated_gk')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return PlayPrefs(
      positions: [
        for (final p in row['positions'] as List) Position.values.byName(p as String),
      ],
      isDedicatedGk: row['is_dedicated_gk'] as bool,
    );
  });

  @override
  Future<void> leaveTeam(String teamId) => guardServer(
    () => _client.rpc<void>('leave_team', params: {'p_team_id': teamId}),
  );

  @override
  Future<void> dissolveTeam(String teamId, String confirmName) => guardServer(
    () => _client.rpc<void>(
      'dissolve_team',
      params: {'p_team_id': teamId, 'p_confirm_name': confirmName},
    ),
  );
}
