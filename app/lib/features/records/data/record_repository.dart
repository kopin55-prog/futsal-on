import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/my_records.dart';

/// 내 기록 읽기 (스프린트 04 3-1). 본인 것만 돌려주는 서버 함수 하나 (get_my_records, 인자 없음).
/// 실패는 [ServerFailure].
abstract interface class RecordRepository {
  Future<MyRecords> getMyRecords();
}

class SupabaseRecordRepository implements RecordRepository {
  SupabaseRecordRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MyRecords> getMyRecords() => guardServer(() async {
    final rows = await _client.rpc<List<dynamic>>('get_my_records');
    return MyRecords([for (final r in rows) TeamSeasonRecord.fromRow(r as Map<String, dynamic>)]);
  });
}
