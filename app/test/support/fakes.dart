import 'package:futsal_on/core/app_services.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/data/team_admin_repository.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/auth/data/account_repository.dart';
import 'package:futsal_on/features/auth/domain/signup_consent.dart';
import 'package:futsal_on/features/membership/data/membership_repository.dart';
import 'package:futsal_on/features/notifications/data/notification_repository.dart';
import 'package:futsal_on/features/notifications/domain/notification_models.dart';
import 'package:futsal_on/features/profile/data/profile_repository.dart';
import 'package:futsal_on/features/profile/domain/profile_validation.dart';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:futsal_on/features/team/data/logo_picker.dart';
import 'package:futsal_on/features/team/data/recent_team_store.dart';
import 'package:futsal_on/features/team/data/team_logo_repository.dart';
import 'package:futsal_on/features/team/data/team_repository.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/notifications/data/push_controller.dart';
import 'package:futsal_on/features/venue/data/place_search_repository.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/position.dart';
import 'package:futsal_on/shared/domain/venue.dart';

import 'award_fakes.dart';
import 'lineup_fakes.dart';
import 'share_fakes.dart';
import 'schedule_fakes.dart';

export 'lineup_fakes.dart';
export 'schedule_fakes.dart';
export 'share_fakes.dart';

/// 화면 테스트용 메모리 저장소. 서버 규칙은 필요한 만큼만 흉내 낸다.
class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository({List<TeamSummary>? teams, Map<String, List<MemberEntry>>? members})
    : teams = teams ?? [],
      members = members ?? {};

  final List<TeamSummary> teams;
  final Map<String, List<MemberEntry>> members;
  final List<String> calls = [];
  ServerFailure? nextFailure;
  Venue? lastCreatedVenue;
  int _seq = 0;

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<List<TeamSummary>> listMyTeams() async => List.of(teams);

  @override
  Future<String> createTeam({
    required String name,
    RegularSchedule schedule = const RegularSchedule(),
    String? logoText,
    Venue? venue,
  }) async {
    _maybeFail();
    final id = 'new-${++_seq}';
    calls.add('create:$name');
    lastCreatedVenue = venue;
    teams.add(
      TeamSummary(
        id: id,
        name: name,
        teamCode: 'NEWAAA',
        logoText: logoText ?? name.substring(0, 1),
        myRole: TeamRole.owner,
        isRecruiting: true,
        schedule: schedule,
        venue: venue,
      ),
    );
    return id;
  }

  @override
  Future<List<MemberEntry>> listMembers(String teamId) async =>
      sortMembers(members[teamId] ?? const []);

  @override
  Future<PlayPrefs?> getPlayPrefs(String userId) async => const PlayPrefs(
    positions: [Position.forward],
    isDedicatedGk: false,
  );

  /// 팀 나누기 계산용 선호 포지션·전문 골키퍼 (테스트가 채움)
  final Map<String, PlayPrefs> playPrefs = {};

  @override
  Future<Map<String, PlayPrefs>> listPlayPrefs(List<String> userIds) async => {
    for (final id in userIds)
      if (playPrefs[id] case final p?) id: p,
  };

  @override
  Future<void> leaveTeam(String teamId) async {
    _maybeFail();
    calls.add('leave:$teamId');
    teams.removeWhere((t) => t.id == teamId);
  }

  @override
  Future<void> dissolveTeam(String teamId, String confirmName) async {
    _maybeFail();
    calls.add('dissolve:$teamId:$confirmName');
    teams.removeWhere((t) => t.id == teamId);
  }
}

class FakeMembershipRepository implements MembershipRepository {
  final List<String> calls = [];
  Map<String, TeamSearchResult> byCode = {};
  List<TeamSearchResult> searchResults = [];
  List<MyJoinRequest> myRequests = [];
  List<IncomingJoinRequest> incoming = [];
  ServerFailure? nextFailure;
  ServerFailure? findFailure;

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<TeamSearchResult?> findTeamByCode(String code) async {
    final f = findFailure;
    if (f != null) throw f;
    return byCode[code.toUpperCase()];
  }

  @override
  Future<List<TeamSearchResult>> searchTeams(String query) async => searchResults;

  @override
  Future<void> requestJoin(String teamCode, {required bool viaSearch}) async {
    _maybeFail();
    calls.add('request:$teamCode:${viaSearch ? 'search' : 'code'}');
  }

  @override
  Future<InviteTeam> getInviteTeam(String inviteCode) async {
    _maybeFail();
    return const InviteTeam(name: '초대팀', teamCode: 'INVT22', logoText: '초대');
  }

  @override
  Future<void> requestJoinByInvite(String inviteCode) async {
    _maybeFail();
    calls.add('invite:$inviteCode');
  }

  @override
  Future<List<MyJoinRequest>> listMyPendingRequests() async => List.of(myRequests);

  @override
  Future<void> cancelJoinRequest(String requestId) async {
    calls.add('cancel:$requestId');
    myRequests.removeWhere((r) => r.requestId == requestId);
  }

  @override
  Future<String> issueInvite(String teamId) async {
    calls.add('issue:$teamId');
    return 'INVITE-CODE-123';
  }

  @override
  Future<List<IncomingJoinRequest>> listPendingRequests(String teamId) async =>
      List.of(incoming);

  @override
  Future<void> decideJoinRequest(String requestId, {required bool approve}) async {
    calls.add('decide:$requestId:$approve');
    incoming.removeWhere((r) => r.requestId == requestId);
  }

  @override
  Future<void> appointManager(String teamId, String userId) async =>
      calls.add('appoint:$userId');

  @override
  Future<void> dismissManager(String teamId, String userId) async =>
      calls.add('dismiss:$userId');

  @override
  Future<void> transferOwnership(String teamId, String userId) async =>
      calls.add('transfer:$userId');

  @override
  Future<void> removeMember(String teamId, String userId) async =>
      calls.add('remove:$userId');
}

class FakeOwnProfileRepository implements ProfileRepository {
  FakeOwnProfileRepository(this.profile);

  OwnProfile profile;
  ProfileInput? updated;

  @override
  Future<bool> hasOwnProfile() async => true;

  @override
  Future<void> createProfile(ProfileInput input, SignupConsent consent) async {}

  @override
  Future<OwnProfile> getOwnProfile() async => profile;

  @override
  Future<void> updateOwnProfile(ProfileInput input) async {
    final n = input.normalized();
    updated = n;
    profile = OwnProfile(
      displayName: n.name,
      bio: n.bio,
      positions: n.positions,
      isDedicatedGk: n.isDedicatedGk,
    );
  }
}

class FakeTeamAdminRepository implements TeamAdminRepository {
  final List<String> calls = [];
  TeamInfoInput? lastInfo;
  MatchSettings settings = MatchSettings.defaults;
  MatchSettings? savedSettings;
  Map<String, SkillLevel> levels = {};
  List<PairingRule> rules = [];
  ServerFailure? nextFailure;
  int _seq = 0;

  void _maybeFail() {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  @override
  Future<void> updateTeamInfo(String teamId, TeamInfoInput input) async {
    _maybeFail();
    calls.add('info:$teamId');
    lastInfo = input;
  }

  @override
  Future<MatchSettings> getMatchSettings(String teamId) async => settings;

  @override
  Future<void> updateMatchSettings(String teamId, MatchSettings s) async {
    _maybeFail();
    calls.add('settings:$teamId');
    savedSettings = s;
    settings = s;
  }

  @override
  Future<Map<String, SkillLevel>> listSkillLevels(String teamId) async => Map.of(levels);

  @override
  Future<void> setSkillLevel(String teamId, String userId, SkillLevel level) async {
    _maybeFail();
    calls.add('skill:$userId:${level.name}');
    if (level == SkillLevel.undecided) {
      levels.remove(userId);
    } else {
      levels[userId] = level;
    }
  }

  @override
  Future<List<PairingRule>> listPairingRules(String teamId) async => List.of(rules);

  @override
  Future<String> savePairingRule(String teamId, PairingRule rule) async {
    _maybeFail();
    final id = rule.id ?? 'rule-${++_seq}';
    calls.add('save-rule:$id:${rule.kind.name}:${rule.userIds.join(',')}:${rule.enabled}');
    final saved = PairingRule(id: id, kind: rule.kind, enabled: rule.enabled, userIds: rule.userIds);
    rules = [for (final r in rules) if (r.id != id) r, saved];
    return id;
  }

  @override
  Future<void> setPairingRuleEnabled(String ruleId, {required bool enabled}) async {
    _maybeFail();
    calls.add('enable-rule:$ruleId:$enabled');
    rules = [for (final r in rules) r.id == ruleId ? r.copyWith(enabled: enabled) : r];
  }

  @override
  Future<void> deletePairingRule(String ruleId) async {
    _maybeFail();
    calls.add('delete-rule:$ruleId');
    rules = [for (final r in rules) if (r.id != ruleId) r];
  }
}

class FakeAccountRepository implements AccountRepository {
  ServerFailure? nextFailure;
  int deleteCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final f = nextFailure;
    if (f != null) throw f;
  }
}

TeamSummary team(String id, String name, TeamRole role, {bool recruiting = true}) =>
    TeamSummary(
      id: id,
      name: name,
      teamCode: 'CODE${id.toUpperCase()}',
      logoText: name.substring(0, 1),
      myRole: role,
      isRecruiting: recruiting,
    );

/// 로고 사진 저장소 흉내. 호출 기록만 남긴다.
class FakeTeamLogoRepository implements TeamLogoRepository {
  final List<String> calls = [];
  ServerFailure? nextFailure;
  int _seq = 0;

  @override
  Future<String> setLogo(String teamId, Uint8List png, {String? previousPath}) async {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    final path = '$teamId/logo-${++_seq}.png';
    calls.add('set:$teamId:${png.length}:${previousPath ?? '-'}');
    return path;
  }

  @override
  Future<void> removeLogo(String teamId, String currentPath) async {
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
    calls.add('remove:$teamId:$currentPath');
  }

  @override
  Future<void> deleteFileQuietly(String path) async => calls.add('delete:$path');
}

/// 사진 고르기 흉내: [next] 를 돌려준다.
class FakeLogoPicker implements LogoPicker {
  LogoPickResult next = LogoPicked(Uint8List.fromList([1, 2, 3]));
  int calls = 0;

  @override
  Future<LogoPickResult> pick(BuildContext context) async {
    calls++;
    return next;
  }
}

/// 장소 검색 흉내. [failure] 가 있으면 그 오류.
class FakePlaceSearchRepository implements PlaceSearchRepository {
  FakePlaceSearchRepository({this.failure});

  PlaceSearchFailure? failure;
  List<PlaceResult> results = const [
    PlaceResult(placeId: 'k1', name: '강남 풋살파크', address: '서울 강남구 1', category: '풋살장', lat: 37.5, lng: 127.0),
    PlaceResult(placeId: 'k2', name: '역삼 풋살장', lat: 37.4, lng: 127.1),
  ];
  bool isEnd = true;
  final List<String> queries = [];

  @override
  Future<PlacePage> search(String query, {int page = 1}) async {
    queries.add('$query:$page');
    final f = failure;
    if (f != null) throw f;
    return PlacePage(places: results, isEnd: isEnd);
  }
}

/// 알림함 흉내. 읽음은 되돌릴 수 없고 처음 읽은 시각을 유지한다 (서버와 같게).
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<AppNotification>? items}) : items = items ?? [];

  List<AppNotification> items;

  AppNotification _read(AppNotification n) => n.isRead
      ? n
      : AppNotification(
          id: n.id,
          kind: n.kind,
          teamId: n.teamId,
          refType: n.refType,
          refId: n.refId,
          title: n.title,
          body: n.body,
          createdAt: n.createdAt,
          readAt: DateTime.now(),
        );

  @override
  Future<List<AppNotification>> listNotifications({int limit = 200}) async =>
      ([...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList();

  @override
  Future<AppNotification?> getNotification(String notificationId) async =>
      items.where((n) => n.id == notificationId).firstOrNull;

  @override
  Future<int> unreadCount() async => items.where((n) => !n.isRead).length;

  @override
  Future<void> markRead(String notificationId) async {
    items = [for (final n in items) n.id == notificationId ? _read(n) : n];
  }

  @override
  Future<int> markAllRead() async {
    final count = items.where((n) => !n.isRead).length;
    items = [for (final n in items) _read(n)];
    return count;
  }
}

class TestServices {
  TestServices({
    List<TeamSummary>? teams,
    Map<String, List<MemberEntry>>? members,
  }) : teams = FakeTeamRepository(teams: teams, members: members);

  final FakeTeamRepository teams;
  final membership = FakeMembershipRepository();
  final profiles = FakeOwnProfileRepository(
    const OwnProfile(
      displayName: '나',
      bio: '안녕',
      positions: [Position.forward],
      isDedicatedGk: false,
    ),
  );
  final accounts = FakeAccountRepository();
  final admin = FakeTeamAdminRepository();
  final recent = MemoryRecentTeamStore();
  final logos = FakeTeamLogoRepository();
  final logoPicker = FakeLogoPicker();
  final places = FakePlaceSearchRepository();
  final notifications = FakeNotificationRepository();
  final matches = FakeMatchRepository();
  late final attendance = FakeAttendanceRepository(matches: matches, userId: () => currentUserId);
  final guests = FakeGuestRepository();
  final lineups = FakeLineupRepository();
  final awards = FakeAwardRepository();
  final shareImages = FakeShareImageService();

  /// 휴대폰 푸시 (없으면 푸시 없음)
  PushController? push;

  /// 참석 응답을 하는 로그인 사용자 (화면 테스트)
  String currentUserId = 'me';

  AppServices get services => AppServices(
    profiles: profiles,
    teams: teams,
    membership: membership,
    accounts: accounts,
    recentTeams: recent,
    admin: admin,
    logos: logos,
    logoPicker: logoPicker,
    places: places,
    notifications: notifications,
    matches: matches,
    attendance: attendance,
    guests: guests,
    lineups: lineups,
    awards: awards,
    push: push,
    shareImages: shareImages,
  );
}
