import '../../../core/entitlements/entitlements.dart';
import '../../../shared/domain/position.dart';
import 'team_validation.dart';

/// 정기 운동일 (요일 1=월 … 7=일, ISO).
class RegularSchedule {
  const RegularSchedule({this.weekday, this.start, this.end});

  final int? weekday;
  final ClockTime? start;
  final ClockTime? end;

  bool get isEmpty => weekday == null && start == null && end == null;
}

/// 내가 소속된 팀 하나 (팀 전환 목록·팀 화면 머리).
class TeamSummary {
  const TeamSummary({
    required this.id,
    required this.name,
    required this.teamCode,
    required this.logoText,
    required this.myRole,
    required this.isRecruiting,
    this.logoImagePath,
    this.schedule = const RegularSchedule(),
  });

  final String id;
  final String name;
  final String teamCode;
  final String logoText;
  final String? logoImagePath;
  final TeamRole myRole;
  final bool isRecruiting;
  final RegularSchedule schedule;
}

/// 팀원 명단의 한 사람 (이름·역할·자기소개). 선호 포지션은 따로 읽는다 (Q-017).
class MemberEntry {
  const MemberEntry({
    required this.userId,
    required this.role,
    required this.displayName,
    this.bio,
  });

  final String userId;
  final TeamRole role;
  final String displayName;
  final String? bio;
}

/// 선호 포지션·전문 골키퍼 (본인·관리자만 읽기).
class PlayPrefs {
  const PlayPrefs({required this.positions, required this.isDedicatedGk});

  final List<Position> positions;
  final bool isDedicatedGk;
}

/// 팀 찾기 결과 (이름 검색·식별코드). 내부 ID·주소·좌표는 서버가 주지 않는다.
class TeamSearchResult {
  const TeamSearchResult({
    required this.teamCode,
    required this.name,
    required this.logoText,
    required this.memberCount,
    required this.isRecruiting,
    this.logoImagePath,
    this.schedule = const RegularSchedule(),
    this.venueName,
  });

  final String teamCode;
  final String name;
  final String logoText;
  final String? logoImagePath;
  final RegularSchedule schedule;
  final String? venueName;
  final int memberCount;
  final bool isRecruiting;
}

/// 초대 코드로 확인한 팀 (이름·식별코드·로고만).
class InviteTeam {
  const InviteTeam({
    required this.name,
    required this.teamCode,
    required this.logoText,
    this.logoImagePath,
  });

  final String name;
  final String teamCode;
  final String logoText;
  final String? logoImagePath;
}

/// 내가 낸 대기 중 가입 신청.
class MyJoinRequest {
  const MyJoinRequest({
    required this.requestId,
    required this.teamName,
    required this.teamCode,
    required this.logoText,
    required this.createdAt,
  });

  final String requestId;
  final String teamName;
  final String teamCode;
  final String logoText;
  final DateTime createdAt;
}

/// 관리자가 보는 대기 중 가입 신청.
class IncomingJoinRequest {
  const IncomingJoinRequest({
    required this.requestId,
    required this.userId,
    required this.displayName,
    required this.createdAt,
    this.bio,
  });

  final String requestId;
  final String userId;
  final String displayName;
  final String? bio;
  final DateTime createdAt;
}
