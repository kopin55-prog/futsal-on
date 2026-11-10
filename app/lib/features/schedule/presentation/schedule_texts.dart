import '../../../shared/data/server_error.dart';
import '../../admin/presentation/admin_texts.dart';
import '../../profile/presentation/profile_texts.dart';
import '../../team/domain/team_validation.dart';
import '../../team/presentation/team_texts.dart';
import '../domain/attendance_models.dart';
import '../domain/guest_models.dart';
import '../domain/match_models.dart';

/// 일정·참석 투표·게스트 화면 문구 (스프린트 02 4단계, 기능 확인용 화면).
///
/// 문서 용어(그대로 씀): "참석", "불참", "대기", "미투표", "게스트", "정원 없음", "취소됨".
/// 나머지는 모두 임시 매니저 말투 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class ScheduleTexts {
  // ---- 문서 용어 ----
  static const attending = '참석';
  static const declined = '불참';
  static const waitlisted = '대기';
  static const notResponded = '미투표';
  static const guest = '게스트';
  static const cancelled = '취소됨';
  static const noCapacity = AdminTexts.noCapacity;

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const tabSchedule = '일정';
  static const upcoming = '다가오는 일정';
  static const noUpcoming = '다가오는 일정이 없어요';
  static const pastMatches = '지난 경기';
  static const noPastMatches = '지난 경기가 없어요';
  static const addMatch = '일정 추가';
  static const matchDetail = '일정';
  static const matchUnavailable = '볼 수 없는 일정이에요';
  static const loadFailed = TeamTexts.loadFailed;
  static const retry = TeamTexts.retry;
  static const autoBadge = '정기';

  static String cancelReason(String reason) => '사유: $reason';

  /// "11월 12일(수) 10:00" (한국 시간)
  static String dateTime(DateTime t) {
    final f = Kst.fields(t);
    return '${date(Kst.dateOf(t))} ${_two(f.hour)}:${_two(f.minute)}';
  }

  /// "11월 12일(수)"
  static String date(CalendarDate d) => '${d.month}월 ${d.day}일(${TeamTexts.weekday(d.weekday)})';

  static String time(ClockTime t) => t.hhmm;

  /// "11월 12일(수) 10:00 ~ 12:00", 날짜가 바뀌면 "~ 다음날 00:30", 그 이상이면 종료 날짜까지.
  static String matchTime(TeamMatch m) {
    final startDate = Kst.dateOf(m.startsAt);
    final endDate = Kst.dateOf(m.endsAt);
    final end = Kst.timeOf(m.endsAt).hhmm;
    final endText = endDate == startDate
        ? end
        : endDate == startDate.plusDays(1)
        ? '다음날 $end'
        : '${date(endDate)} $end';
    return '${dateTime(m.startsAt)} ~ $endText';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const venueNone = '장소 미정';
  static String capacity(int? capacity) => capacity == null ? '$noCapacity (모두 참석)' : '정원 $capacity명';
  static String deadline(DateTime t) => '${dateTime(t)}까지 투표';
  static const deadlinePassed = '투표가 마감됐어요';
  static String attendingCount(int n, int? capacity) => capacity == null ? '참석 $n명' : '참석 $n / $capacity명';

  // 내 상태
  static const myStatus = '내 상태';
  static String state(AttendanceState? s, int? waitPosition) => switch (s) {
    AttendanceState.attending => attending,
    AttendanceState.waitlisted => '$waitlisted ${waitPosition ?? ''}번'.trim(),
    AttendanceState.declined => declined,
    null => notResponded,
  };
  static const attendButton = '참석할게요';
  static const declineButton = '이번엔 불참';
  static const respondFailed = '저장하지 못했어요. 다시 시도해 주세요.';
  static const cancelledLocked = '취소된 일정이라 투표할 수 없어요';

  // 명단
  static String rosterTitle(String label, int n) => '$label $n';
  static const nobody = '아직 없어요';
  static const leftMember = AdminTexts.unknownMember;

  // 게스트
  static String guestsTitle(int n) => '$guest $n';
  static const guestNote = '게스트는 정원과 따로 세요';
  static const addGuest = '게스트 추가';
  static const guestName = '이름 (선택, 1~8자)';
  static String guestNameHint(int nextNo) => '비우면 "$guestDefaultNamePrefix$nextNo"';
  static const guestPositions = '포지션 (선택, 최대 3개)';
  static const guestSkill = '대략 실력 (선택)';
  static const guestMaxPositions = '최대 3개까지 고를 수 있어요';
  static const removeGuest = '게스트 삭제';
  static String confirmRemoveGuest(String name) => '$name 게스트를 삭제할까요?';
  static String guestError(GuestInputError e) => switch (e) {
    GuestInputError.nameTooLong => '이름은 8자까지 쓸 수 있어요',
    GuestInputError.nameHasLineBreak => '이름은 한 줄로 써주세요',
    // 임시 문구 (Q-074 2번, 확정 전)
    GuestInputError.reservedName => '"게스트+숫자" 이름은 쓸 수 없어요. 비우면 자동으로 붙어요',
    GuestInputError.tooManyPositions => guestMaxPositions,
    GuestInputError.duplicatePositions => '포지션이 겹쳐요',
    GuestInputError.allrounderNotAlone => ProfileTexts.allrounderSelected,
    GuestInputError.duplicateName => '이 일정에 같은 이름의 게스트가 있어요',
    GuestInputError.tooManyGuests => '게스트는 한 일정에 ${GuestInput.maxGuestsPerMatch}명까지예요',
  };

  // 일정 취소
  static const cancelMatch = '일정 취소';
  static const cancelTitle = '이 일정을 취소할까요?';
  static const cancelNote = '취소하면 되돌릴 수 없어요. 투표한 팀원에게 알림이 가요.';
  static const cancelReasonLabel = '사유 (선택, 20자까지)';
  static const cancelConfirm = '취소하기';
  static const keep = '그대로 두기';
  static const cancelledDone = '일정을 취소했어요';

  // 일정 추가
  static const startDate = '시작 날짜';
  static const startTime = '시작 시각';
  static const endDate = '종료 날짜';
  static const endTime = '종료 시각';
  static const venueLabel = '장소 (선택)';
  static const deadlineLabel = AdminTexts.deadlineLabel;
  static const reminderLabel = AdminTexts.reminderLabel;
  static String reminderOption(int? hours) => AdminTexts.reminderOption(hours);
  static const settingsDefaultNote = '마감·미투표 알림은 팀 경기 설정 값이 먼저 채워져 있어요. 이 일정만 바꿀 수 있어요.';
  static const pastDeadlineNote = '마감 시각이 이미 지났으면 경기 시작 전까지 투표를 받아요.';
  static const capacityNote = '정원은 팀 경기 설정을 따라요.';
  static const create = '추가하기';
  static const created = '일정을 추가했어요';
  static String inputError(MatchInputError e) => switch (e) {
    MatchInputError.timeRequired => '날짜와 시각을 모두 골라주세요',
    MatchInputError.endNotAfterStart => '종료가 시작보다 늦어야 해요 (자정을 넘기면 종료 날짜를 다음날로)',
    MatchInputError.tooLong => '일정은 24시간을 넘을 수 없어요',
    MatchInputError.startInPast => '이미 지난 시각이에요',
    MatchInputError.deadlineRange => '마감은 0~${MatchInput.maxDeadlineHours}시간 전으로 정해 주세요',
  };

  /// 서버 오류 → 화면 문구.
  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.rsvpClosed => deadlinePassed,
    ServerErrorCode.matchCancelled => cancelledLocked,
    ServerErrorCode.matchAlreadyCancelled => '이미 취소된 일정이에요',
    ServerErrorCode.matchAlreadyStarted => '이미 시작한 경기예요',
    ServerErrorCode.matchInPast => inputError(MatchInputError.startInPast),
    ServerErrorCode.invalidMatchTime => inputError(MatchInputError.endNotAfterStart),
    ServerErrorCode.invalidMatchSettings => '마감·알림 시간을 확인해 주세요',
    ServerErrorCode.invalidCancelReason => '사유는 20자까지 쓸 수 있어요',
    ServerErrorCode.invalidGuestName => guestError(GuestInputError.nameTooLong),
    ServerErrorCode.invalidPositions => ProfileTexts.serverError(code),
    // TODO(문구 미정): 임시. 보통은 복귀 확인 창(2-5)이 먼저 떠서 이 문구는 거의 안 보인다.
    ServerErrorCode.returnConfirmationRequired => '부상 중이에요. 복귀 확인 후 참석할 수 있어요',
    ServerErrorCode.guestLimitReached => guestError(GuestInputError.tooManyGuests),
    ServerErrorCode.duplicateGuestName => guestError(GuestInputError.duplicateName),
    ServerErrorCode.reservedGuestName => guestError(GuestInputError.reservedName),
    ServerErrorCode.invalidVenue => '장소 정보를 확인해 주세요',
    _ => AdminTexts.serverError(code),
  };
}
