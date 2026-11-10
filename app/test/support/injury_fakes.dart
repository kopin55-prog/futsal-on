import 'package:futsal_on/features/injury/data/injury_repository.dart';
import 'package:futsal_on/features/injury/domain/injury_models.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 부상 흉내: 본인 것만, 동의가 있어야 등록, 진행 중 1건, 철회하면 기록 삭제 (서버와 같게).
class FakeInjuryRepository implements InjuryRepository {
  FakeInjuryRepository({required this.userId});

  final String Function() userId;

  /// 사람별 유효한 부상 동의
  final Set<String> consented = {};

  /// 사람별 진행 중 부상
  final Map<String, Injury> active = {};

  final List<String> calls = [];
  ServerFailure? nextFailure;

  /// 오늘(한국 날짜) — 테스트에서 고정
  DateTime today = DateTime.utc(2026, 11, 10);
  int _seq = 0;

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  /// 테스트 준비용: 진행 중 부상을 직접 넣는다 (동의도 함께).
  Injury seedActive(String user, {required DateTime expectedReturnOn, String? memo}) {
    consented.add(user);
    final i = Injury(
      id: 'i${++_seq}',
      userId: user,
      startedOn: today,
      expectedReturnOn: expectedReturnOn,
      isActive: true,
      memo: memo,
    );
    active[user] = i;
    return i;
  }

  /// 참석 투표로 복귀 (FakeAttendanceRepository 가 부른다)
  void recoverByReturn(String user) => active.remove(user);

  @override
  Future<void> agreeConsent() async {
    calls.add('agree');
    _maybeFail();
    if (!consented.add(userId())) throw const ServerFailure(ServerErrorCode.injuryConsentExists);
  }

  @override
  Future<void> withdrawConsent() async {
    calls.add('withdraw');
    _maybeFail();
    if (!consented.remove(userId())) throw const ServerFailure(ServerErrorCode.injuryConsentNotFound);
    active.remove(userId());
  }

  @override
  Future<String> report({required int weeks, String? memo}) async {
    calls.add('report:$weeks:${memo ?? ''}');
    _maybeFail();
    final me = userId();
    if (!consented.contains(me)) throw const ServerFailure(ServerErrorCode.injuryConsentRequired);
    if (active.containsKey(me)) throw const ServerFailure(ServerErrorCode.injuryAlreadyActive);
    if (weeks < InjuryRules.minWeeks || weeks > InjuryRules.maxWeeks) {
      throw const ServerFailure(ServerErrorCode.injuryInvalidWeeks);
    }
    final i = Injury(
      id: 'i${++_seq}',
      userId: me,
      startedOn: today,
      expectedReturnOn: today.add(Duration(days: weeks * 7)),
      isActive: true,
      memo: memo,
    );
    active[me] = i;
    return i.id;
  }

  @override
  Future<DateTime> extend(int weeks, {bool fromReturnCheck = false}) async {
    calls.add('extend:$weeks${fromReturnCheck ? ':return_check' : ''}');
    _maybeFail();
    final cur = active[userId()];
    if (cur == null) throw const ServerFailure(ServerErrorCode.injuryNotActive);
    final base = cur.expectedReturnOn.isAfter(today) ? cur.expectedReturnOn : today;
    final next = base.add(Duration(days: weeks * 7));
    active[userId()] = Injury(
      id: cur.id,
      userId: cur.userId,
      startedOn: cur.startedOn,
      expectedReturnOn: next,
      isActive: true,
      memo: cur.memo,
    );
    return next;
  }

  @override
  Future<void> recover() async {
    calls.add('recover');
    _maybeFail();
    if (active.remove(userId()) == null) throw const ServerFailure(ServerErrorCode.injuryNotActive);
  }

  @override
  Future<void> updateMemo(String? memo) async {
    calls.add('memo:${memo ?? ''}');
    _maybeFail();
    final cur = active[userId()];
    if (cur == null) throw const ServerFailure(ServerErrorCode.injuryNotActive);
    active[userId()] = Injury(
      id: cur.id,
      userId: cur.userId,
      startedOn: cur.startedOn,
      expectedReturnOn: cur.expectedReturnOn,
      isActive: true,
      memo: memo,
    );
  }

  @override
  Future<Injury?> myActiveInjury(String userId) async => active[userId];

  @override
  Future<bool> hasActiveConsent(String userId) async => consented.contains(userId);
}
