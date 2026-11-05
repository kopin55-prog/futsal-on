import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../../team/data/team_repository.dart' show scheduleFromRow;
import '../../team/domain/team_models.dart';

/// 팀 찾기·가입 신청(신청자 쪽)과 초대·신청 처리·역할 변경(관리자 쪽).
/// 권한 최종 판단은 서버 함수가 한다. 실패는 모두 [ServerFailure].
abstract interface class MembershipRepository {
  // ---- 신청자 쪽 ----
  /// 팀 식별코드로 찾기. 없으면 null. 해체된 팀이면 [ServerErrorCode.teamDissolved].
  Future<TeamSearchResult?> findTeamByCode(String code);

  /// 팀 이름 일부로 찾기 (2자 이상, Q-067 11번).
  Future<List<TeamSearchResult>> searchTeams(String query);

  /// 검색·식별코드 경로 신청 (모집 중일 때만).
  Future<void> requestJoin(String teamCode, {required bool viaSearch});

  /// 초대 코드 확인.
  Future<InviteTeam> getInviteTeam(String inviteCode);

  Future<void> requestJoinByInvite(String inviteCode);

  Future<List<MyJoinRequest>> listMyPendingRequests();

  Future<void> cancelJoinRequest(String requestId);

  // ---- 관리자 쪽 ----
  /// 새 초대 코드 (이전 코드는 무효). 원본은 이번 한 번만 받는다 (Q-020).
  Future<String> issueInvite(String teamId);

  Future<List<IncomingJoinRequest>> listPendingRequests(String teamId);

  Future<void> decideJoinRequest(String requestId, {required bool approve});

  Future<void> appointManager(String teamId, String userId);

  Future<void> dismissManager(String teamId, String userId);

  Future<void> transferOwnership(String teamId, String userId);

  Future<void> removeMember(String teamId, String userId);
}

TeamSearchResult _searchResult(Map<String, dynamic> row) => TeamSearchResult(
  teamCode: row['team_code'] as String,
  name: row['name'] as String,
  logoText: row['logo_text'] as String,
  logoImagePath: row['logo_image_path'] as String?,
  schedule: scheduleFromRow(row),
  venueName: row['venue_name'] as String?,
  memberCount: row['member_count'] as int,
  isRecruiting: row['is_recruiting'] as bool,
);

class SupabaseMembershipRepository implements MembershipRepository {
  SupabaseMembershipRepository(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> _rows(String fn, Map<String, dynamic> params) async {
    final result = await _client.rpc<List<dynamic>>(fn, params: params);
    return result.cast<Map<String, dynamic>>();
  }

  @override
  Future<TeamSearchResult?> findTeamByCode(String code) => guardServer(() async {
    final rows = await _rows('find_team_by_code', {'p_team_code': code});
    return rows.isEmpty ? null : _searchResult(rows.first);
  });

  @override
  Future<List<TeamSearchResult>> searchTeams(String query) => guardServer(() async {
    final rows = await _rows('search_teams', {'p_query': query});
    return rows.map(_searchResult).toList();
  });

  @override
  Future<void> requestJoin(String teamCode, {required bool viaSearch}) => guardServer(
    () => _client.rpc<dynamic>(
      'request_join',
      params: {'p_team_code': teamCode, 'p_via': viaSearch ? 'search' : 'code'},
    ),
  );

  @override
  Future<InviteTeam> getInviteTeam(String inviteCode) => guardServer(() async {
    final rows = await _rows('get_invite_team', {'p_code': inviteCode.trim()});
    if (rows.isEmpty) throw const ServerFailure(ServerErrorCode.inviteInvalid);
    final r = rows.first;
    return InviteTeam(
      name: r['team_name'] as String,
      teamCode: r['team_code'] as String,
      logoText: r['logo_text'] as String,
      logoImagePath: r['logo_image_path'] as String?,
    );
  });

  @override
  Future<void> requestJoinByInvite(String inviteCode) => guardServer(
    () => _client.rpc<dynamic>(
      'request_join_by_invite',
      params: {'p_code': inviteCode.trim()},
    ),
  );

  @override
  Future<List<MyJoinRequest>> listMyPendingRequests() => guardServer(() async {
    final rows = await _rows('list_my_pending_join_requests', {});
    return [
      for (final r in rows)
        MyJoinRequest(
          requestId: r['request_id'] as String,
          teamName: r['team_name'] as String,
          teamCode: r['team_code'] as String,
          logoText: r['logo_text'] as String,
          logoImagePath: r['logo_image_path'] as String?,
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  });

  @override
  Future<void> cancelJoinRequest(String requestId) => guardServer(
    () => _client.rpc<void>('cancel_join_request', params: {'p_request_id': requestId}),
  );

  @override
  Future<String> issueInvite(String teamId) => guardServer(
    () => _client.rpc<String>('issue_team_invite', params: {'p_team_id': teamId}),
  );

  @override
  Future<List<IncomingJoinRequest>> listPendingRequests(String teamId) =>
      guardServer(() async {
        final rows = await _client
            .from('join_requests')
            .select('id, user_id, created_at, profiles!join_requests_user_id_fkey(display_name, bio)')
            .eq('team_id', teamId)
            .eq('status', 'pending')
            .order('created_at');
        return [
          for (final r in rows)
            if (r['profiles'] case final Map<String, dynamic> p)
              IncomingJoinRequest(
                requestId: r['id'] as String,
                userId: r['user_id'] as String,
                displayName: p['display_name'] as String,
                bio: p['bio'] as String?,
                createdAt: DateTime.parse(r['created_at'] as String),
              ),
        ];
      });

  @override
  Future<void> decideJoinRequest(String requestId, {required bool approve}) =>
      guardServer(
        () => _client.rpc<void>(
          'decide_join_request',
          params: {'p_request_id': requestId, 'p_approve': approve},
        ),
      );

  Future<void> _roleCall(String fn, String teamId, String userId) => guardServer(
    () => _client.rpc<void>(fn, params: {'p_team_id': teamId, 'p_user_id': userId}),
  );

  @override
  Future<void> appointManager(String teamId, String userId) =>
      _roleCall('appoint_manager', teamId, userId);

  @override
  Future<void> dismissManager(String teamId, String userId) =>
      _roleCall('dismiss_manager', teamId, userId);

  @override
  Future<void> transferOwnership(String teamId, String userId) =>
      _roleCall('transfer_ownership', teamId, userId);

  @override
  Future<void> removeMember(String teamId, String userId) =>
      _roleCall('remove_member', teamId, userId);
}
