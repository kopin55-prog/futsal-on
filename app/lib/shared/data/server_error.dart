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
