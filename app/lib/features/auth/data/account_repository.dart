import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';

/// 회원 탈퇴 (data-model.md 2-5). 서버 함수(Edge Function account-delete)가 본인 확인·외부 연결 해제·
/// 데이터 삭제를 한 번에 한다. 앱은 다른 사람 ID 를 넘기지 않는다.
abstract interface class AccountRepository {
  /// 실패하면 [ServerFailure]. 팀장인 팀이 있으면 [ServerErrorCode.ownerMustTransferOrDissolve] (Q-037).
  Future<void> deleteAccount();
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('account-delete', method: HttpMethod.post);
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      throw ServerFailure(ServerErrorCode.fromCode(code));
    } catch (_) {
      throw const ServerFailure(ServerErrorCode.unknown);
    }
  }
}
