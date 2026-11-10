import '../features/admin/data/team_admin_repository.dart';
import '../features/auth/data/account_repository.dart';
import '../features/injury/data/injury_repository.dart';
import '../features/lineup/data/lineup_repository.dart';
import '../features/membership/data/membership_repository.dart';
import '../features/notifications/data/notification_repository.dart';
import '../features/notifications/data/push_controller.dart';
import '../features/pom_vote/data/award_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/records/data/record_repository.dart';
import '../features/schedule/data/attendance_repository.dart';
import '../features/schedule/data/guest_repository.dart';
import '../features/schedule/data/match_repository.dart';
import '../features/share_image/data/share_image_service.dart';
import '../features/team/data/logo_picker.dart';
import '../features/team/data/recent_team_store.dart';
import '../features/team/data/team_logo_repository.dart';
import '../features/team/data/team_repository.dart';
import '../features/venue/data/place_search_repository.dart';
import 'entitlements/entitlements.dart';

/// 화면이 쓰는 저장소 묶음. 테스트에서는 가짜 저장소로 바꿔 끼운다.
class AppServices {
  const AppServices({
    required this.profiles,
    required this.teams,
    required this.membership,
    required this.accounts,
    required this.recentTeams,
    required this.admin,
    required this.logos,
    required this.logoPicker,
    required this.places,
    required this.notifications,
    required this.matches,
    required this.attendance,
    required this.guests,
    required this.lineups,
    required this.awards,
    required this.injuries,
    required this.records,
    this.push,
    this.shareImages = const SharePlusShareImageService(),
    this.entitlements = const Entitlements(),
  });

  final ProfileRepository profiles;
  final TeamRepository teams;
  final MembershipRepository membership;
  final AccountRepository accounts;
  final RecentTeamStore recentTeams;

  /// 관리 탭의 팀 설정 (팀 정보·경기 설정·실력 등급·그룹·라이벌)
  final TeamAdminRepository admin;

  /// 로고 사진 저장소 (team-logos)
  final TeamLogoRepository logos;

  /// 로고 사진 고르기·자르기
  final LogoPicker logoPicker;

  /// 지정 풋살장 검색 (서버 함수 place-search)
  final PlaceSearchRepository places;

  /// 알림함 (본인 알림만)
  final NotificationRepository notifications;

  /// 일정 (읽기: 팀원, 추가·취소: 관리자)
  final MatchRepository matches;

  /// 참석 투표 (본인 응답, 명단은 팀원 전체)
  final AttendanceRepository attendance;

  /// 게스트 (이름: 팀원, 포지션·대략 실력·추가·삭제: 관리자)
  final GuestRepository guests;

  /// 팀 배치 (읽기: 관리자는 항상·팀원은 확정만, 저장·확정·수정: 관리자)
  final LineupRepository lineups;

  /// POM·오늘의 골 투표와 투표 설정 (읽기: 팀원, 투표: 대상자, 설정 바꾸기: 관리자)
  final AwardRepository awards;

  /// 부상 동의·부상 기록 (모두 본인만, 스프린트 04 2단계)
  final InjuryRepository injuries;

  /// 내 기록 (본인 것만, 서버 함수 get_my_records, 스프린트 04 3-1)
  final RecordRepository records;

  /// 휴대폰 푸시 (기기 등록·해제, 받은 푸시). 없으면 푸시 없음(테스트 등).
  final PushController? push;

  /// 공유 이미지 만들기·휴대폰 공유 창 (스프린트 03 6단계)
  final ShareImageService shareImages;

  /// 권한 판단은 여기 하나로만 (app/lib/core/entitlements).
  final Entitlements entitlements;
}
