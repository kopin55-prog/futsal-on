import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../domain/team_models.dart';
import '../domain/team_validation.dart';

/// 팀·가입·관리 화면 문구.
///
/// 문서에 있는 문구 (그대로 씀):
/// - "모집 마감" (Q-021), "없는 코드예요" (Q-051), "만료된 초대 코드예요" (3-5),
///   "이미 소속된 팀이에요"·"이미 신청했어요" (Q-067 10번), "가입할 수 없는 팀이에요" (Q-067 8번),
///   "모든 기록이 지워지고 되돌릴 수 없어요" (Q-067 12번), "이름을 입력해주세요" (11장 14번).
/// 나머지는 모두 임시 문구 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class TeamTexts {
  // ---- 문서 확정 문구 ----
  static const recruitingClosed = '모집 마감';
  static const codeNotFound = '없는 코드예요';
  static const inviteExpired = '만료된 초대 코드예요';
  static const alreadyMember = '이미 소속된 팀이에요';
  static const alreadyRequested = '이미 신청했어요';
  static const cannotJoinTeam = '가입할 수 없는 팀이에요';
  static const deleteAccountWarning = '모든 기록이 지워지고 되돌릴 수 없어요';
  static const nameRequired = '이름을 입력해주세요';

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const owner = '팀장';
  static const manager = '운영진';
  static const member = '팀원';

  static String role(TeamRole r) => switch (r) {
    TeamRole.owner => owner,
    TeamRole.manager => manager,
    TeamRole.member => member,
  };

  static const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String weekday(int isoWeekday) => weekdays[isoWeekday - 1];

  /// 예: "매주 수 20:00~22:00", 자정 넘김이면 "매주 금 22:00~다음날 00:30"
  static String? schedule(RegularSchedule s) {
    if (s.weekday == null) return null;
    final buf = StringBuffer('매주 ${weekday(s.weekday!)}');
    if (s.start != null) {
      buf.write(' ${s.start!.hhmm}');
      if (s.end != null) {
        final next = TeamValidator.crossesMidnight(s.start!, s.end!);
        buf.write('~${next ? '다음날 ' : ''}${s.end!.hhmm}');
      }
    }
    return buf.toString();
  }

  // 팀 전환·홈
  static const noTeamTitle = '아직 소속된 팀이 없어요';
  static const createTeam = '팀 만들기';
  static const findTeam = '팀 찾기';
  static const switchTeam = '팀 전환';
  static const tabMembers = '팀원';
  static const tabAdmin = '관리';
  static const tabMy = '내 정보';
  static const loadFailed = '정보를 불러오지 못했어요.';
  static const retry = '다시 시도';
  static const cancel = '취소';
  static const confirm = '확인';
  static const close = '닫기';

  // 팀 만들기
  static const teamName = '팀 이름';
  static const regularDay = '정기 운동 요일 (선택)';
  static const noWeekday = '정하지 않음';
  static const startTime = '시작 시각';
  static const endTime = '종료 시각';
  static const clearTime = '지우기';
  static const logoText = '로고 글자 (선택, 1~2자)';
  static String logoTextHint(String preview) =>
      preview.isEmpty ? '비우면 팀 이름 앞 두 글자' : '비우면 "$preview"';
  // 로고 사진 (Q-068 1번)
  static const logoPhoto = '로고 사진 (선택)';
  static const logoPhotoNote = 'JPG·PNG, 10MB 이하. 정사각형으로 잘라 저장해요.';
  static const pickPhoto = '사진 고르기';
  static const changePhoto = '사진 바꾸기';
  static const removePhoto = '사진 지우기';
  static const photoTooLarge = '10MB 이하 사진만 쓸 수 있어요';
  static const photoUnsupported = 'JPG·PNG 사진만 쓸 수 있어요';
  static const photoFailed = '사진을 불러오지 못했어요';
  static const logoPhotoSaveFailed = '로고 사진은 저장하지 못했어요. 팀 정보 수정에서 다시 해 주세요.';

  // 지정 풋살장 (Q-032, Q-068 2번)
  static const venue = '지정 풋살장 (선택)';
  static const venueNone = '정하지 않음';
  static const venueTitle = '지정 풋살장';
  static const venueClear = '지우기';
  static const venueSearchLabel = '구장 이름이나 주소';
  static const venueSearchTooLong = '50자까지 입력할 수 있어요';
  static const venueSearchUnavailable = '구장 검색은 준비 중이에요. 직접 입력해 주세요.';
  static const venueSearchFailed = '검색하지 못했어요. 다시 시도해 주세요.';
  static const venueNoResult = '검색 결과가 없어요';
  static const venueSearchGuide = '구장 이름으로 검색해 고르거나 직접 입력해요';
  static const venueMore = '더 보기';
  static const venueManual = '찾는 구장이 없으면 직접 입력';
  static const venueManualTitle = '구장 직접 입력';
  static const venueName = '구장 이름';
  static const venueAddress = '주소 (선택)';
  static const venueNameRequired = '구장 이름을 입력해 주세요';
  static const venueNameTooLong = '200자까지 입력할 수 있어요';
  static const venueAddressTooLong = '300자까지 입력할 수 있어요';
  static const venueManualBadge = '직접 입력';
  static const create = '만들기';
  static const nameTooLong = '팀 이름은 10자까지 쓸 수 있어요';
  static const nameHasLineBreak = '팀 이름은 한 줄로 써주세요';
  static const logoEmpty = '로고 글자를 확인해 주세요';
  static const logoTooLong = '로고 글자는 2자까지 쓸 수 있어요';

  static String scheduleError(RegularScheduleError e) => switch (e) {
    RegularScheduleError.weekdayRequired => '요일을 먼저 골라주세요',
    RegularScheduleError.startRequired => '시작 시각을 먼저 골라주세요',
    RegularScheduleError.sameStartEnd => '시작과 종료 시각이 같아요',
    RegularScheduleError.endRequired => '종료 시각도 골라주세요',
  };

  // 팀 찾기
  static const teamCodeLabel = '팀 식별코드 (6자리)';
  static const nameSearchLabel = '팀 이름 (2자 이상)';
  static const inviteCodeLabel = '초대 코드 붙여넣기';
  static const search = '찾기';
  static const paste = '붙여넣기';
  static const searchTooShort = '2자 이상 입력해 주세요';
  static const noSearchResult = '찾는 팀이 없어요';
  static const requestJoin = '가입 신청';
  static const requestSent = '가입 신청을 보냈어요';
  static String membersCount(int n) => '팀원 $n명';
  static const myRequests = '보낸 가입 신청';
  static const cancelRequest = '신청 취소';
  static const requestCancelled = '신청을 취소했어요';

  // 팀원 명단·프로필
  static const teamCode = '팀 식별코드';
  static const copied = '복사했어요';
  static const positions = '선호 포지션';
  static const dedicatedGk = '전문 골키퍼';
  static const noBio = '';

  // 관리
  static const inviteSection = '초대 코드';
  static const issueInvite = '새 초대 코드 만들기';
  static const issueInviteNote = '새로 만들면 이전 코드는 쓸 수 없어요. 코드는 24시간 동안 쓸 수 있어요.';
  static const inviteIssuedTitle = '초대 코드';
  static const inviteIssuedNote = '이 화면을 닫으면 다시 볼 수 없어요. 지금 복사해 두세요.';
  static const copy = '복사';
  static const requestsSection = '가입 신청';
  static const noRequests = '대기 중인 신청이 없어요';
  static const approve = '승인';
  static const reject = '거절';
  static const membersSection = '팀원 관리';
  static const appointManager = '운영진으로 지정';
  static const dismissManager = '운영진에서 해제';
  static const transferOwnership = '팀장 위임';
  static const removeMember = '내보내기';
  static String confirmAction(String action, String name) => '$name님을 $action할까요?';
  static String confirmTransfer(String name) =>
      '$name님에게 팀장을 넘길까요? 나는 운영진이 돼요.';
  static String confirmRemove(String name) => '$name님을 팀에서 내보낼까요?';
  static const dissolveSection = '팀 해체';
  static const dissolve = '팀 해체';
  static String dissolveGuide(String teamName) =>
      '해체하면 되돌릴 수 없어요. 확인을 위해 팀 이름 "$teamName"을 입력해 주세요.';
  static const dissolveInputLabel = '팀 이름';
  static const done = '처리했어요';

  // 내 정보
  static const editProfile = '프로필 수정';
  static const leaveTeam = '팀 탈퇴';
  static String confirmLeave(String teamName) => '$teamName에서 탈퇴할까요?';
  static const ownerCannotLeave = '팀장은 위임하거나 해체한 뒤 탈퇴할 수 있어요';
  static const signOut = '로그아웃';
  static const deleteAccount = '회원 탈퇴';
  static const deleteAccountConfirm = '회원 탈퇴';
  static const deleteAccountTitle = '회원 탈퇴';
  static const save = '저장';
  static const saved = '저장했어요';

  /// 서버 오류 → 화면 문구.
  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.alreadyMember => alreadyMember,
    ServerErrorCode.requestAlreadyPending => alreadyRequested,
    ServerErrorCode.teamDissolved => cannotJoinTeam,
    ServerErrorCode.inviteInvalid => inviteExpired,
    ServerErrorCode.teamNotFound => codeNotFound,
    // TODO(문구 미정): 아래는 임시.
    ServerErrorCode.teamNotRecruiting => '모집이 마감된 팀이에요',
    ServerErrorCode.teamLimitReached => '팀은 10개까지 소속할 수 있어요',
    ServerErrorCode.teamFull => '팀 인원이 가득 찼어요 (최대 100명)',
    ServerErrorCode.managerLimitReached => '운영진은 2명까지 지정할 수 있어요',
    ServerErrorCode.ownerMustTransferOrDissolve => ownerCannotLeave,
    ServerErrorCode.dissolveConfirmationMismatch => '팀 이름이 맞지 않아요',
    ServerErrorCode.invalidTeamName => '팀 이름을 확인해 주세요',
    ServerErrorCode.invalidLogoText => logoEmpty,
    ServerErrorCode.invalidRegularSchedule => '정기 운동 시간을 확인해 주세요',
    ServerErrorCode.invalidVenue => '지정 풋살장 정보를 확인해 주세요',
    ServerErrorCode.invalidLogoImage => photoFailed,
    ServerErrorCode.invalidSearchQuery => searchTooShort,
    ServerErrorCode.requestNotPending => '이미 처리된 신청이에요',
    ServerErrorCode.notPermitted => '권한이 없어요',
    ServerErrorCode.targetNotMember ||
    ServerErrorCode.targetNotManager ||
    ServerErrorCode.alreadyManager => '팀원 정보가 바뀌었어요. 새로고침해 주세요',
    _ => '처리하지 못했어요. 다시 시도해 주세요.',
  };
}
