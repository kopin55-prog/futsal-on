import '../features/auth/data/account_repository.dart';
import '../features/membership/data/membership_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/team/data/recent_team_store.dart';
import '../features/team/data/team_repository.dart';
import 'entitlements/entitlements.dart';

/// 화면이 쓰는 저장소 묶음. 테스트에서는 가짜 저장소로 바꿔 끼운다.
class AppServices {
  const AppServices({
    required this.profiles,
    required this.teams,
    required this.membership,
    required this.accounts,
    required this.recentTeams,
    this.entitlements = const Entitlements(),
  });

  final ProfileRepository profiles;
  final TeamRepository teams;
  final MembershipRepository membership;
  final AccountRepository accounts;
  final RecentTeamStore recentTeams;

  /// 권한 판단은 여기 하나로만 (app/lib/core/entitlements).
  final Entitlements entitlements;
}
