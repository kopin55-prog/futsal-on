import 'package:futsal_on/core/app_services.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/admin/data/team_admin_repository.dart';
import 'package:futsal_on/features/admin/domain/match_settings.dart';
import 'package:futsal_on/features/admin/domain/pairing_rules.dart';
import 'package:futsal_on/features/admin/domain/skill_level.dart';
import 'package:futsal_on/features/auth/data/account_repository.dart';
import 'package:futsal_on/features/auth/domain/signup_consent.dart';
import 'package:futsal_on/features/membership/data/membership_repository.dart';
import 'package:futsal_on/features/profile/data/profile_repository.dart';
import 'package:futsal_on/features/profile/domain/profile_validation.dart';
import 'package:futsal_on/features/team/data/recent_team_store.dart';
import 'package:futsal_on/features/team/data/team_repository.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/shared/data/server_error.dart';
import 'package:futsal_on/shared/domain/position.dart';

/// 화면 테스트용 메모리 저장소. 서버 규칙은 필요한 만큼만 흉내 낸다.
class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository({List<TeamSummary>? teams, Map<String, List<MemberEntry>>? members})
    : teams = teams ?? [],
      members = members ?? {};

  final List<TeamSummary> teams;
  final Map<String, List<MemberEntry>> members;
  final List<String> calls = [];
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
  Future<List<TeamSummary>> listMyTeams() async => List.of(teams);

  @override
  Future<String> createTeam({
    required String name,
    RegularSchedule schedule = const RegularSchedule(),
    String? logoText,
  }) async {
    _maybeFail();
    final id = 'new-${++_seq}';
    calls.add('create:$name');
    teams.add(
      TeamSummary(
        id: id,
        name: name,
        teamCode: 'NEWAAA',
        logoText: logoText ?? name.substring(0, 1),
        myRole: TeamRole.owner,
        isRecruiting: true,
        schedule: schedule,
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

  AppServices get services => AppServices(
    profiles: profiles,
    teams: teams,
    membership: membership,
    accounts: accounts,
    recentTeams: recent,
    admin: admin,
  );
}
