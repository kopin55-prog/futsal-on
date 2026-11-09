import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/attendance_models.dart';

/// 참석 투표 (data-model.md 4-2). 읽기는 표(그 팀 팀원 전체), 응답은 서버 함수(본인만).
///
/// 대리 응답·미투표로 되돌리기는 없다 (Q-071 5번). 마감 정각부터 서버가 거절한다(rsvp_closed).
/// 실패는 모두 [ServerFailure].
abstract interface class AttendanceRepository {
  /// 한 일정의 응답 전체.
  Future<List<AttendanceResponse>> listResponses(String matchId);

  /// 본인 응답. [attending] 이 true 면 참석(정원이 차면 대기), false 면 불참. 저장된 상태를 돌려준다.
  Future<AttendanceState> respond(String matchId, {required bool attending});
}

class SupabaseAttendanceRepository implements AttendanceRepository {
  SupabaseAttendanceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AttendanceResponse>> listResponses(String matchId) => guardServer(() async {
    final rows = await _client
        .from('attendance_responses')
        .select(AttendanceResponse.columns)
        .eq('match_id', matchId);
    return [for (final r in rows) AttendanceResponse.fromRow(r)];
  });

  @override
  Future<AttendanceState> respond(String matchId, {required bool attending}) => guardServer(() async {
    final state = await _client.rpc<String>(
      'respond_attendance',
      params: {'p_match_id': matchId, 'p_attending': attending},
    );
    return AttendanceState.fromServer(state);
  });
}
