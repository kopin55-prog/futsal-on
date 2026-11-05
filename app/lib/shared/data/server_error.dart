import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// 서버 함수 오류 코드 (supabase/migrations 의 `raise exception '<code>'`).
///
/// 서버는 오류 메시지에 코드만 담는다. 화면 문구는 앱이 코드로 고른다.
enum ServerErrorCode {
  notAuthenticated('not_authenticated'),
  profileRequired('profile_required'),
  profileExists('profile_exists'),
  age14Required('age_14_required'),
  requiredConsentsMissing('required_consents_missing'),
  invalidProfile('invalid_profile'),
  invalidPositions('invalid_positions'),
  invalidTeamName('invalid_team_name'),
  invalidLogoText('invalid_logo_text'),
  notPermitted('not_permitted'),
  inviteInvalid('invite_invalid'),
  invalidSearchQuery('invalid_search_query'),
  teamNotFound('team_not_found'),
  teamNotRecruiting('team_not_recruiting'),
  alreadyMember('already_member'),
  requestAlreadyPending('request_already_pending'),
  requestNotPending('request_not_pending'),
  targetNotMember('target_not_member'),
  targetNotManager('target_not_manager'),
  alreadyManager('already_manager'),
  managerLimitReached('manager_limit_reached'),
  cannotTargetSelf('cannot_target_self'),
  notMember('not_member'),
  ownerMustTransferOrDissolve('owner_must_transfer_or_dissolve'),
  invalidJoinVia('invalid_join_via'),
  invalidDecision('invalid_decision'),
  invalidRegularSchedule('invalid_regular_schedule'),
  invalidTeamInfo('invalid_team_info'),
  invalidTeamSettings('invalid_team_settings'),
  deadlineBeforeAutoCreate('deadline_before_auto_create'),
  invalidSkillLevel('invalid_skill_level'),
  invalidPairingRule('invalid_pairing_rule'),
  invalidPairingMembers('invalid_pairing_members'),
  pairingRuleConflict('pairing_rule_conflict'),
  teamLimitReached('team_limit_reached'),
  teamFull('team_full'),
  teamDissolved('team_dissolved'),
  dissolveConfirmationMismatch('dissolve_confirmation_mismatch'),

  /// 목록에 없는 오류 (네트워크·알 수 없는 서버 오류 포함).
  unknown('unknown');

  const ServerErrorCode(this.code);

  final String code;

  static ServerErrorCode fromCode(String? code) => ServerErrorCode.values
      .firstWhere((e) => e.code == code, orElse: () => ServerErrorCode.unknown);
}

/// 서버 함수 호출 실패.
class ServerFailure implements Exception {
  const ServerFailure(this.code);

  final ServerErrorCode code;

  @override
  String toString() => 'ServerFailure(${code.code})';
}

/// 서버 호출을 감싸 오류를 [ServerFailure] 로 바꾼다. 화면은 [ServerFailure] 만 다룬다.
Future<T> guardServer<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ServerFailure {
    rethrow;
  } on PostgrestException catch (e) {
    throw ServerFailure(ServerErrorCode.fromCode(e.message));
  } catch (_) {
    throw const ServerFailure(ServerErrorCode.unknown);
  }
}
