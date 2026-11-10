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
  ///
  /// 진행 중 부상이 있는 사람의 참석은 서버가 [ServerErrorCode.returnConfirmationRequired] 로 거절한다(기획서 12장).
  /// "부상에서 복귀하셨나요?" 확인을 받은 뒤 [returnConfirmed] 를 주고 다시 부르면 한 처리 안에서
  /// 참석(또는 대기) + 부상 회복. 불참에는 확인이 필요 없다 (스프린트 04 1-5).
  Future<AttendanceState> respond(String matchId, {required bool attending, ReturnConfirmation? returnConfirmed});
}

/// 부상 복귀 확인을 받은 곳 (서버 injury_event_via).
enum ReturnConfirmation {
  /// 일정 상세·홈 카드의 [참석] 확인 창 (2-5)
  vote('return_vote'),

  /// 복귀 확인 알림을 눌러 연 창의 [참석할게요] (2-6)
  notification('return_check');

  const ReturnConfirmation(this.serverValue);

  final String serverValue;
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
  Future<AttendanceState> respond(String matchId, {required bool attending, ReturnConfirmation? returnConfirmed}) =>
      guardServer(() async {
    final state = await _client.rpc<String>(
      'respond_attendance',
      params: {
        'p_match_id': matchId,
        'p_attending': attending,
        if (returnConfirmed != null) 'p_return_via': returnConfirmed.serverValue,
      },
    );
    return AttendanceState.fromServer(state);
  });
}
