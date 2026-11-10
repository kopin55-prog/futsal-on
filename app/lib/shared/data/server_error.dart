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
  invalidVenue('invalid_venue'),
  invalidLogoImage('invalid_logo_image'),
  invalidMatchTime('invalid_match_time'),
  matchInPast('match_in_past'),
  invalidMatchSettings('invalid_match_settings'),
  matchAlreadyCancelled('match_already_cancelled'),
  matchAlreadyStarted('match_already_started'),
  invalidCancelReason('invalid_cancel_reason'),
  invalidAttendance('invalid_attendance'),
  matchCancelled('match_cancelled'),
  rsvpClosed('rsvp_closed'),
  // 부상 중 참석 → 복귀 확인 필요 (respond_attendance, 스프린트 04 1-5)
  returnConfirmationRequired('return_confirmation_required'),
  invalidGuestName('invalid_guest_name'),
  guestLimitReached('guest_limit_reached'),
  duplicateGuestName('duplicate_guest_name'),
  reservedGuestName('reserved_guest_name'),
  // 팀 배치 (save_lineup)
  lineupNotOpen('lineup_not_open'),
  matchAlreadyEnded('match_already_ended'),
  lineupConflict('lineup_conflict'),
  invalidLineup('invalid_lineup'),
  invalidLineupSlot('invalid_lineup_slot'),
  // 투표 설정·POM·오늘의 골 투표 (update_award_settings, cast_award_vote)
  invalidAwardSettings('invalid_award_settings'),
  awardPollNotFound('award_poll_not_found'),
  awardNotParticipant('award_not_participant'),
  awardPollClosed('award_poll_closed'),
  awardInvalidCategory('award_invalid_category'),
  awardSelfVote('award_self_vote'),
  awardInvalidCandidate('award_invalid_candidate'),
  awardAlreadyVoted('award_already_voted'),
  // 부상 동의·부상 기록 (agree_injury_consent, withdraw_consent, report_injury, extend_injury, recover_injury,
  // update_injury_memo — 스프린트 04 1-2·1-3)
  injuryConsentExists('injury_consent_exists'),
  injuryConsentNotFound('injury_consent_not_found'),
  consentNotWithdrawable('consent_not_withdrawable'),
  injuryConsentRequired('injury_consent_required'),
  injuryAlreadyActive('injury_already_active'),
  injuryNotActive('injury_not_active'),
  injuryInvalidWeeks('injury_invalid_weeks'),
  injuryInvalidVia('injury_invalid_via'),
  invalidInjuryMemo('invalid_injury_memo'),

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
