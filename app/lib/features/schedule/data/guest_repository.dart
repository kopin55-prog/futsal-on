import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/guest_models.dart';

/// 게스트 (data-model.md 4-3). 이름은 표(그 팀 팀원 전체), 포지션·대략 실력은 관리자용 서버 함수.
///
/// 추가·삭제는 관리자만, 경기 시작 전까지, 취소된 일정 불가 (Q-071 6번). 버튼 노출은
/// Entitlements(TeamAction.manageSchedule, GuestPositionInfo)로 판단하고 서버가 다시 거절한다.
/// 실패는 모두 [ServerFailure].
abstract interface class GuestRepository {
  /// 한 일정의 게스트 이름 목록 (팀원용).
  Future<List<MatchGuest>> listGuests(String matchId);

  /// 관리자용: 포지션·대략 실력 포함.
  Future<List<MatchGuestDetail>> listGuestDetails(String matchId);

  /// 추가. 새 게스트 ID.
  Future<String> addGuest(String matchId, GuestInput input);

  /// 삭제 (대략 실력도 같이 삭제).
  Future<void> removeGuest(String guestId);
}

class SupabaseGuestRepository implements GuestRepository {
  SupabaseGuestRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MatchGuest>> listGuests(String matchId) => guardServer(() async {
    final rows = await _client
        .from('match_guests')
        .select(MatchGuest.columns)
        .eq('match_id', matchId)
        .order('created_at');
    return [for (final r in rows) MatchGuest.fromRow(r)];
  });

  @override
  Future<List<MatchGuestDetail>> listGuestDetails(String matchId) => guardServer(() async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_match_guest_details',
      params: {'p_match_id': matchId},
    );
    return [for (final r in rows) MatchGuestDetail.fromRow(r as Map<String, dynamic>)];
  });

  @override
  Future<String> addGuest(String matchId, GuestInput input) => guardServer(
    () async => await _client.rpc<String>('add_match_guest', params: input.toServerParams(matchId)),
  );

  @override
  Future<void> removeGuest(String guestId) => guardServer(
    () => _client.rpc<void>('remove_match_guest', params: {'p_guest_id': guestId}),
  );
}
