import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/attendance_models.dart';
import '../domain/match_models.dart';

/// 참석 투표 (data-model.md 4-2). 읽기는 표(그 팀 팀원 전체), 응답은 서버 함수(본인만).
///
/// 대리 응답·미투표로 되돌리기는 없다 (Q-071 5번). 마감 정각부터 서버가 거절한다(rsvp_closed).
/// 실패는 모두 [ServerFailure].
abstract interface class AttendanceRepository {
  /// 한 일정의 응답 전체.
  Future<List<AttendanceResponse>> listResponses(String matchId);

  /// 여러 일정의 응답 전체 (일정 탭 목록의 "참석 N"·"나:" 표시, S4-13). 일정 ID → 응답 목록, 응답이 없으면 빈 목록.
  Future<Map<String, List<AttendanceResponse>>> listResponsesFor(List<String> matchIds);

  /// 본인 응답. [attending] 이 true 면 참석(정원이 차면 대기), false 면 불참. 저장된 상태를 돌려준다.
  ///
  /// 진행 중 부상이 있는 사람의 참석은 서버가 [ServerErrorCode.returnConfirmationRequired] 로 거절한다(기획서 12장).
  /// "부상에서 복귀하셨나요?" 확인을 받은 뒤 [returnConfirmed] 를 주고 다시 부르면 한 처리 안에서
  /// 참석(또는 대기) + 부상 회복. 불참에는 확인이 필요 없다 (스프린트 04 1-5).
  Future<AttendanceState> respond(String matchId, {required bool attending, ReturnConfirmation? returnConfirmed});

  /// 내가 참석·대기로 응답해 둔 다가오는(시작 전, 취소 안 된) 일정, 시작 순. 지금 소속 팀 것만 읽힌다.
  /// 부상 등록 직후 "참석으로 되어 있는 경기" 안내에 쓴다 (S4-08).
  Future<List<MyUpcomingResponse>> listMyUpcomingAttending(String userId, {required DateTime now});
}

/// 내 응답 한 줄 + 그 일정.
class MyUpcomingResponse {
  const MyUpcomingResponse({required this.match, required this.state});

  final TeamMatch match;
  final AttendanceState state;
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
  Future<Map<String, List<AttendanceResponse>>> listResponsesFor(List<String> matchIds) => guardServer(() async {
    final out = {for (final id in matchIds) id: <AttendanceResponse>[]};
    if (matchIds.isEmpty) return out;
    final rows = await _client
        .from('attendance_responses')
        .select(AttendanceResponse.columns)
        .inFilter('match_id', matchIds);
    for (final r in rows) {
      final response = AttendanceResponse.fromRow(r);
      (out[response.matchId] ??= []).add(response);
    }
    return out;
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

  @override
  Future<List<MyUpcomingResponse>> listMyUpcomingAttending(String userId, {required DateTime now}) =>
      guardServer(() async {
        final rows = await _client
            .from('attendance_responses')
            .select('state, matches!inner(${TeamMatch.columns})')
            .eq('user_id', userId)
            .inFilter('state', ['attending', 'waitlisted'])
            .eq('matches.status', 'scheduled')
            .gt('matches.starts_at', now.toUtc().toIso8601String());
        final list = [
          for (final r in rows)
            MyUpcomingResponse(
              match: TeamMatch.fromRow(r['matches'] as Map<String, dynamic>),
              state: AttendanceState.fromServer(r['state'] as String),
            ),
        ]..sort((a, b) => a.match.startsAt.compareTo(b.match.startsAt));
        return list;
      });
}
