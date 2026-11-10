import 'package:futsal_on/features/records/data/record_repository.dart';
import 'package:futsal_on/features/records/domain/my_records.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 내 기록 흉내: 테스트가 채운 본인 줄을 그대로 돌려준다 (서버 함수는 인자가 없고 본인 것만).
class FakeRecordRepository implements RecordRepository {
  final List<TeamSeasonRecord> rows = [];
  int calls = 0;
  ServerFailure? nextFailure;

  @override
  Future<MyRecords> getMyRecords() async {
    calls++;
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    return MyRecords(List.of(rows));
  }
}
