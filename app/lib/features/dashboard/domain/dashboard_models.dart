import '../../injury/domain/injury_models.dart';
import '../../lineup/domain/lineup_board.dart';
import '../../lineup/domain/lineup_models.dart';
import '../../pom_vote/domain/award_models.dart';
import '../../schedule/domain/attendance_models.dart';
import '../../schedule/domain/guest_models.dart';
import '../../schedule/domain/match_models.dart';
import '../../team/domain/team_models.dart';

/// 팀 대시보드(홈) 재료 (스프린트 04 4단계). 새 표 없이 기존 표를 기존 권한 규칙으로 읽어 만든다.
/// 화면은 presentation/dashboard_tab.dart, 읽기는 data/dashboard_loader.dart.
class DashboardData {
  const DashboardData({
    required this.members,
    required this.next,
    required this.lastAward,
    required this.injured,
    required this.todos,
  });

  /// 지금 팀원 (팀장·운영진 포함, 떠난 사람 제외). 헤더 인원 수·이름 찾기에 쓴다.
  final List<MemberEntry> members;

  /// 다음 경기 카드 (없으면 "다가오는 경기가 없어요")
  final NextMatchView? next;

  /// 지난 경기 POM·오늘의 골 (그 경기에 투표가 안 열렸으면 null → 칸 숨김, S4-03)
  final LastAwardView? lastAward;

  /// 부상자 라인업: 남은 기간 짧은 순, 같으면 이름 가나다순 (S4-04). 비면 칸 숨김.
  final List<InjuredMember> injured;

  /// 처리할 일 (팀장·운영진만, 아니면 null)
  final DashboardTodos? todos;

  int get memberCount => members.length;

  Map<String, String> get memberNames => {for (final m in members) m.userId: m.displayName};
}

/// 다음 경기 카드 재료.
class NextMatchView {
  const NextMatchView({
    required this.match,
    required this.roster,
    required this.memberIds,
    required this.myInjured,
    this.lineup,
    this.guests = const [],
  });

  final TeamMatch match;
  final AttendanceRoster roster;

  /// 미투표 수를 세는 지금 팀원
  final List<String> memberIds;

  /// 내가 지금 부상 중인지 (내 상태 자리에 "부상 중", S4-02 (5))
  final bool myInjured;

  /// 확정된 배치 (볼 수 있을 때만, 초안은 들어오지 않는다)
  final Lineup? lineup;
  final List<MatchGuest> guests;

  int get attendingCount => roster.attendingCount;
  int get waitlistCount => roster.waitlist.length;
  int get notRespondedCount => roster.notRespondedAmong(memberIds).length;
}

/// 확정 배치에서 내 자리.
sealed class MySlot {
  const MySlot();
}

/// 팀 블록 안
final class MySquadSlot extends MySlot {
  const MySquadSlot(this.squad);
  final LineupSquad squad;
}

/// 교체 블록 안
final class MyBenchSlot extends MySlot {
  const MyBenchSlot(this.bench);
  final List<LineupPerson> bench;
}

/// 배치에 없음 → "이번 경기 배치에 없어요" + [전체 배치 보기] (S4-02 (4))
final class NotInLineup extends MySlot {
  const NotInLineup();
}

/// 지난 경기 POM·오늘의 골 재료.
class LastAwardView {
  const LastAwardView({required this.match, required this.poll});

  final TeamMatch match;
  final AwardPollView poll;
}

/// 부상자 한 명.
class InjuredMember {
  const InjuredMember({required this.member, required this.injury, required this.remainingWeeks});

  final MemberEntry member;
  final Injury injury;

  /// 남은 회복 기간(주, 올림, 지나면 0)
  final int remainingWeeks;
}

/// 처리할 일 (S4-05 두 가지).
class DashboardTodos {
  const DashboardTodos({required this.pendingJoinRequests, required this.lineupPending});

  /// 가입 신청 대기 수 (가입 신청을 볼 수 없는 사람이면 0)
  final int pendingJoinRequests;

  /// 팀 나누기 대기: 참석 마감 뒤·경기 종료 전·배치 미확정 일정 (시작 순)
  final List<TeamMatch> lineupPending;

  bool get isEmpty => pendingJoinRequests == 0 && lineupPending.isEmpty;
}

/// 대시보드 규칙 (화면과 분리해 테스트한다).
abstract final class DashboardRules {
  /// 다음 경기 (S4-02 (1)): 종료 시각이 안 지난 가장 빠른 일정, 취소된 일정은 건너뜀. 진행 중이면 그 경기.
  static TeamMatch? nextMatch(Iterable<TeamMatch> matches, DateTime now) {
    final list = [
      for (final m in matches)
        if (!m.isCancelled && now.isBefore(m.endsAt)) m,
    ]..sort((a, b) {
        final c = a.startsAt.compareTo(b.startsAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list.firstOrNull;
  }

  /// 진행 중인지 (시작 ≤ 지금 < 종료)
  static bool isInProgress(TeamMatch m, DateTime now) => !now.isBefore(m.startsAt) && now.isBefore(m.endsAt);

  /// 가장 최근에 끝난 경기 (S4-03): 취소되지 않았고 종료 시각이 지난 일정 중 종료가 가장 늦은 것.
  static TeamMatch? lastFinishedMatch(Iterable<TeamMatch> matches, DateTime now) {
    final list = [
      for (final m in matches)
        if (!m.isCancelled && !now.isBefore(m.endsAt)) m,
    ]..sort((a, b) {
        final c = b.endsAt.compareTo(a.endsAt);
        return c != 0 ? c : b.startsAt.compareTo(a.startsAt);
      });
    return list.firstOrNull;
  }

  /// 팀 나누기 대기인지 (S4-05): 참석 마감 뒤·경기 종료 전·취소 아님 + 배치가 없거나 미확정.
  static bool needsLineup(TeamMatch m, Lineup? lineup, DateTime now) =>
      LineupWindow.of(m, now) == LineupWindow.open && (lineup == null || !lineup.isConfirmed);

  /// 확정 배치에서 [userId] 의 자리.
  static MySlot mySlot(Lineup lineup, String userId) {
    for (final q in lineup.squads) {
      if (q.people.any((p) => p.userId == userId)) return MySquadSlot(q);
    }
    if (lineup.bench.any((p) => p.userId == userId)) return MyBenchSlot(lineup.bench);
    return const NotInLineup();
  }

  /// 부상자 라인업 (S4-04): 지금 팀원 중 진행 중 부상만, 남은 기간 짧은 순 → 이름 가나다순 → ID 순.
  static List<InjuredMember> injuredLineup(
    Iterable<MemberEntry> members,
    Iterable<Injury> injuries,
    DateTime todayKst,
  ) {
    final byUser = {for (final i in injuries) if (i.isActive) i.userId: i};
    final list = [
      for (final m in members)
        if (byUser[m.userId] case final i?)
          InjuredMember(member: m, injury: i, remainingWeeks: i.remainingWeeks(todayKst)),
    ]..sort((a, b) {
        final w = a.remainingWeeks.compareTo(b.remainingWeeks);
        if (w != 0) return w;
        final n = a.member.displayName.compareTo(b.member.displayName);
        return n != 0 ? n : a.member.userId.compareTo(b.member.userId);
      });
    return list;
  }

  /// 오늘(한국 날짜)을 남은 주 계산용 날짜 값으로.
  static DateTime todayKst(DateTime now) {
    final d = Kst.dateOf(now);
    return DateTime.utc(d.year, d.month, d.day);
  }
}
