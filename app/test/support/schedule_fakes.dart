import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/schedule/data/attendance_repository.dart';
import 'package:futsal_on/features/schedule/data/guest_repository.dart';
import 'package:futsal_on/features/schedule/data/match_repository.dart';
import 'package:futsal_on/features/schedule/domain/attendance_models.dart';
import 'package:futsal_on/features/schedule/domain/guest_models.dart';
import 'package:futsal_on/features/schedule/domain/match_models.dart';
import 'package:futsal_on/shared/data/server_error.dart';

/// 일정 흉내. 취소는 예정 상태만 (서버와 같게).
class FakeMatchRepository implements MatchRepository {
  final List<TeamMatch> items = [];
  final List<String> calls = [];
  ServerFailure? nextFailure;
  MatchInput? lastInput;
  int _seq = 0;

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<List<TeamMatch>> listMatches(String teamId, {DateTime? from}) async => [
    for (final m in items)
      if (m.teamId == teamId && (from == null || m.endsAt.isAfter(from))) m,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<TeamMatch?> getMatch(String matchId) async => items.where((m) => m.id == matchId).firstOrNull;

  @override
  Future<String> createMatch(String teamId, MatchInput input) async {
    calls.add('create:$teamId');
    _maybeFail();
    lastInput = input;
    final id = 'new${++_seq}';
    items.add(
      TeamMatch(
        id: id,
        teamId: teamId,
        source: MatchSource.manual,
        status: MatchStatus.scheduled,
        startsAt: input.startsAt,
        endsAt: input.endsAt,
        rsvpDeadlineAt: input.startsAt.subtract(Duration(hours: input.rsvpDeadlineHours ?? 2)),
        venue: input.venue,
      ),
    );
    return id;
  }

  @override
  Future<void> cancelMatch(String matchId, {String? reason}) async {
    calls.add('cancel:$matchId:${reason ?? ''}');
    _maybeFail();
    final i = items.indexWhere((m) => m.id == matchId);
    final m = items[i];
    items[i] = TeamMatch(
      id: m.id,
      teamId: m.teamId,
      source: m.source,
      status: MatchStatus.cancelled,
      startsAt: m.startsAt,
      endsAt: m.endsAt,
      rsvpDeadlineAt: m.rsvpDeadlineAt,
      rsvpReminderAt: m.rsvpReminderAt,
      capacity: m.capacity,
      venue: m.venue,
      cancelledAt: DateTime.now(),
      cancelReason: reason,
    );
  }
}

/// 참석 투표 흉내: 정원이 차면 대기 (서버와 같게). 자동 참석은 seed 로 준비한다.
class FakeAttendanceRepository implements AttendanceRepository {
  FakeAttendanceRepository({required this.matches, required this.userId});

  final FakeMatchRepository matches;
  final String Function() userId;
  final Map<String, List<AttendanceResponse>> byMatch = {};
  final List<String> calls = [];
  ServerFailure? nextFailure;
  int _seq = 0;
  DateTime _clock = DateTime.utc(2026, 1, 1);

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  /// 테스트 준비용: 응답 줄을 직접 넣는다. [at] 은 마지막으로 바꾼 시각(대기면 순번 기준).
  void seed(String matchId, String user, AttendanceState state, {DateTime? at}) {
    final t = at ?? _tick();
    if (t.isAfter(_clock)) _clock = t;
    (byMatch[matchId] ??= []).add(
      AttendanceResponse(
        id: 'r${++_seq}',
        matchId: matchId,
        userId: user,
        state: state,
        waitlistedAt: state == AttendanceState.waitlisted ? t : null,
        respondedAt: t,
        updatedAt: t,
      ),
    );
  }

  @override
  Future<List<AttendanceResponse>> listResponses(String matchId) async => List.of(byMatch[matchId] ?? const []);

  @override
  Future<AttendanceState> respond(String matchId, {required bool attending}) async {
    calls.add('respond:$matchId:$attending');
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    final match = (await matches.getMatch(matchId))!;
    final list = byMatch[matchId] ??= [];
    final me = userId();
    final current = list.where((r) => r.userId == me).firstOrNull;
    AttendanceState next;
    if (attending) {
      if (current != null && current.state != AttendanceState.declined) return current.state;
      final count = list.where((r) => r.state == AttendanceState.attending).length;
      final hasWait = list.any((r) => r.state == AttendanceState.waitlisted);
      next = (match.capacity == null || (count < match.capacity! && !hasWait))
          ? AttendanceState.attending
          : AttendanceState.waitlisted;
    } else {
      if (current?.state == AttendanceState.declined) return AttendanceState.declined;
      next = AttendanceState.declined;
    }
    final t = _tick();
    list.removeWhere((r) => r.userId == me);
    list.add(
      AttendanceResponse(
        id: current?.id ?? 'r${++_seq}',
        matchId: matchId,
        userId: me,
        state: next,
        waitlistedAt: next == AttendanceState.waitlisted ? t : null,
        respondedAt: current?.respondedAt ?? t,
        updatedAt: t,
      ),
    );
    return next;
  }
}

/// 게스트 흉내: 번호는 가장 큰 번호 + 1, 12명·같은 표시 이름 거절 (서버와 같게).
class FakeGuestRepository implements GuestRepository {
  final Map<String, List<MatchGuestDetail>> byMatch = {};
  final List<String> calls = [];
  int detailReads = 0;
  int _seq = 0;

  @override
  Future<List<MatchGuest>> listGuests(String matchId) async => [
    for (final g in byMatch[matchId] ?? const <MatchGuestDetail>[])
      MatchGuest(id: g.id, matchId: matchId, guestNo: g.guestNo, name: g.name, createdAt: g.createdAt),
  ];

  @override
  Future<List<MatchGuestDetail>> listGuestDetails(String matchId) async {
    detailReads++;
    return List.of(byMatch[matchId] ?? const []);
  }

  @override
  Future<String> addGuest(String matchId, GuestInput input) async {
    final existing = await listGuests(matchId);
    final errors = input.validate(existing: existing);
    if (errors.contains(GuestInputError.tooManyGuests)) {
      throw const ServerFailure(ServerErrorCode.guestLimitReached);
    }
    if (errors.contains(GuestInputError.duplicateName)) {
      throw const ServerFailure(ServerErrorCode.duplicateGuestName);
    }
    final id = 'g${++_seq}';
    calls.add('add:$matchId:${input.normalizedName ?? ''}');
    (byMatch[matchId] ??= []).add(
      MatchGuestDetail(
        id: id,
        guestNo: GuestInput.nextGuestNo(existing),
        name: input.normalizedName,
        positions: input.positions,
        skillLevel: input.skillLevel ?? SkillLevel.undecided,
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<void> removeGuest(String guestId) async {
    calls.add('remove:$guestId');
    for (final list in byMatch.values) {
      list.removeWhere((g) => g.id == guestId);
    }
  }
}
