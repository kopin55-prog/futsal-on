import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/injury_models.dart';

/// 부상 동의·부상 기록 (data-model.md v4.6 8-1·8-2, 스프린트 04 1-2·1-3). 모두 본인만, 서버 함수로.
///
/// 참석 투표로 복귀하는 경로는 AttendanceRepository.respond(returnConfirmed: ...) (1-5).
/// 실패는 모두 [ServerFailure]. 화면은 AppServices.injuries 로 쓴다 (스프린트 04 2단계).
abstract interface class InjuryRepository {
  /// 나중에 부상 동의 (유효한 동의가 있으면 [ServerErrorCode.injuryConsentExists]).
  Future<void> agreeConsent();

  /// 부상 동의 철회: 부상 기록·이력 전부 삭제 (Q-052).
  Future<void> withdrawConsent();

  /// 부상 등록. [weeks] 1~12, [memo] 선택. 새 부상 ID.
  Future<String> report({required int weeks, String? memo});

  /// 연장 +1W·+2W. [fromReturnCheck] 면 복귀 확인 알림 창에서 연장(이력 via return_check). 새 예상 복귀일.
  Future<DateTime> extend(int weeks, {bool fromReturnCheck = false});

  /// 회복했어요.
  Future<void> recover();

  /// 진행 중 부상의 메모 수정 (비우면 없음, 이력 없음).
  Future<void> updateMemo(String? memo);

  /// 내 진행 중 부상 (없으면 null).
  Future<Injury?> myActiveInjury(String userId);

  /// 유효한(철회 안 한) 부상 동의가 있는지 (user_consents, 본인 줄만 읽힘).
  Future<bool> hasActiveConsent(String userId);

  /// [userIds] 중 진행 중 부상 (홈 부상자 라인업, 스프린트 04 4-5). 서버 권한 규칙이 "지금 같은 팀 팀원 +
  /// 주인의 부상 동의가 유효한 진행 중 부상"만 돌려준다 (S-07). 본인 것도 포함될 수 있다.
  Future<List<Injury>> listActiveInjuries(List<String> userIds);
}

class SupabaseInjuryRepository implements InjuryRepository {
  SupabaseInjuryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> agreeConsent() => guardServer(() => _client.rpc<void>('agree_injury_consent'));

  @override
  Future<void> withdrawConsent() =>
      guardServer(() => _client.rpc<void>('withdraw_consent', params: {'p_consent_type': 'injury_info'}));

  @override
  Future<String> report({required int weeks, String? memo}) => guardServer(
    () => _client.rpc<String>('report_injury', params: {'p_weeks': weeks, 'p_memo': memo}),
  );

  @override
  Future<DateTime> extend(int weeks, {bool fromReturnCheck = false}) => guardServer(() async {
    final date = await _client.rpc<String>(
      'extend_injury',
      params: {'p_weeks': weeks, 'p_via': fromReturnCheck ? 'return_check' : 'self'},
    );
    return DateTime.parse(date);
  });

  @override
  Future<void> recover() => guardServer(() => _client.rpc<void>('recover_injury'));

  @override
  Future<void> updateMemo(String? memo) =>
      guardServer(() => _client.rpc<void>('update_injury_memo', params: {'p_memo': memo}));

  @override
  Future<Injury?> myActiveInjury(String userId) => guardServer(() async {
    final row = await _client
        .from('injuries')
        .select(Injury.columns)
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle();
    return row == null ? null : Injury.fromRow(row);
  });

  @override
  Future<List<Injury>> listActiveInjuries(List<String> userIds) => guardServer(() async {
    if (userIds.isEmpty) return const <Injury>[];
    final rows = await _client
        .from('injuries')
        .select(Injury.columns)
        .inFilter('user_id', userIds)
        .eq('status', 'active');
    return [for (final r in rows) Injury.fromRow(r)];
  });

  @override
  Future<bool> hasActiveConsent(String userId) => guardServer(() async {
    final row = await _client
        .from('user_consents')
        .select('id')
        .eq('user_id', userId)
        .eq('consent_type', 'injury_info')
        .isFilter('withdrawn_at', null)
        .maybeSingle();
    return row != null;
  });
}
