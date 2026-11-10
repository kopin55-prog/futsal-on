import '../../../shared/data/server_error.dart';
import '../../schedule/domain/match_models.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../domain/injury_models.dart';

/// 부상 화면 문구 (스프린트 04 2단계).
///
/// 문서에 있는 문구(그대로 씀):
/// - 동의 화면: docs/consent-texts.md (ConsentTexts, 확정 Q-057)
/// - "부상에서 복귀하셨나요?" (기획서 12장), 복귀 확인 알림 문구 (notifications.md 확정)
/// - 버튼 "연장 +1W"·"연장 +2W"·"회복했어요"·"부상 등록", "참석할게요"·"아직 회복 중 +1W"·"+2W"·"닫기"·"마감됐어요" (Q-078 S4-11·작업 표)
/// - "참석으로 되어 있는 경기가 있어요. 불참으로 바꿀까요?" / [불참으로 바꾸기] (Q-078 S4-08)
/// 나머지는 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class InjuryTexts {
  // ---- 문서 문구 ----
  static const reportButton = '부상 등록';
  static const recoverButton = '회복했어요';
  static String extendButton(int weeks) => '연장 +${weeks}W';
  static const returnConfirmTitle = '부상에서 복귀하셨나요?';
  static const returnCheckBody = '부상은 회복되셨나요? 경기가 열렸습니다. 참석하시겠습니까?';
  static const returnCheckAttend = '참석할게요';
  static String returnCheckExtend(int weeks) => weeks == 1 ? '아직 회복 중 +1W' : '+${weeks}W';
  static const returnCheckClose = '닫기';
  static const returnCheckClosed = '마감됐어요';
  static const stillAttendingTitle = '참석으로 되어 있는 경기가 있어요. 불참으로 바꿀까요?';
  static const changeToDecline = '불참으로 바꾸기';

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const sectionTitle = '내 부상';
  static const noInjury = '등록된 부상이 없어요';
  static String remaining(int weeks) => '남은 회복 기간 ${weeks}W';
  static String expectedReturn(DateTime d) =>
      '예상 복귀일 ${ScheduleTexts.date(CalendarDate(d.year, d.month, d.day))}';
  static const editMemo = '메모 수정';
  static const memoLabel = '메모 (선택)';
  static const memoHint = '예: 발목';
  static const save = '저장';
  static const cancel = '취소';
  static const loadFailed = '부상 정보를 불러오지 못했어요';
  static const retry = '다시 시도';

  // 동의 화면
  static const consentTitle = '부상 정보 동의';
  static const consentAgree = '동의하고 계속';

  // 등록 화면
  static const reportTitle = '부상 등록';
  static const weeksLabel = '예상 회복 기간';
  static String weeks(int w) => '${w}W';
  static const longerNote = '12W보다 길면 12W로 등록하고 나중에 연장해 주세요';
  static const submit = '등록';
  static const reported = '부상을 등록했어요';

  // 등록 직후 참석 안내 (S4-08)
  static const keepAsIs = '그대로 두기';
  static const closedMatchesNote = '마감된 경기는 운영진에게 직접 알려주세요';
  static String matchLine(TeamMatch m, String teamName) => '$teamName · ${ScheduleTexts.dateTime(m.startsAt)}';
  static const changedToDecline = '불참으로 바꿨어요';

  // 연장·회복·메모
  static String extended(DateTime d) => '${expectedReturn(d)}로 늦췄어요';
  static const recovered = '회복으로 바꿨어요';
  static const memoSaved = '메모를 고쳤어요';

  // 동의 철회 (2-4)
  static const withdrawMenu = '부상 정보 동의 철회';
  static const withdrawConfirm = '부상 정보 동의를 철회할까요?\n철회하면 부상 기록이 바로 삭제돼요.';
  static const withdrawButton = '철회';
  static const withdrawn = '부상 정보 동의를 철회했어요';

  // 복귀 확인 (2-5)
  static const returnConfirmYes = '복귀했어요';

  static String memoError(InjuryMemoError e) => switch (e) {
    InjuryMemoError.tooLong => '메모는 ${InjuryRules.maxMemoLength}자까지 쓸 수 있어요',
    InjuryMemoError.lineBreak => '메모는 한 줄로 써 주세요',
  };

  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.injuryConsentRequired => '부상 정보 동의가 필요해요',
    ServerErrorCode.injuryAlreadyActive => '이미 등록된 부상이 있어요',
    ServerErrorCode.injuryNotActive => '진행 중인 부상이 없어요',
    ServerErrorCode.injuryConsentNotFound => '동의한 기록이 없어요',
    ServerErrorCode.invalidInjuryMemo => memoError(InjuryMemoError.tooLong),
    ServerErrorCode.injuryInvalidWeeks => '회복 기간을 다시 골라 주세요',
    _ => ScheduleTexts.serverError(code),
  };
}
