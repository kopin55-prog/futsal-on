import '../../../shared/data/server_error.dart';
import '../../team/presentation/team_texts.dart';
import '../domain/match_settings.dart';
import '../domain/pairing_rules.dart';
import '../domain/skill_level.dart';

/// 관리 탭 팀 설정 화면 문구 (팀 정보 수정·경기 설정·실력 등급·그룹·라이벌).
///
/// 문서에 있는 용어(그대로 씀): "그룹", "라이벌", "실력 등급", 등급 이름(비기너·아마추어·세미프로·프로·미정),
/// "정원 없음", "대기 순번", "인원 모집" (glossary, data-model.md 3장).
/// 나머지 버튼·안내·오류 문구는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
abstract final class AdminTexts {
  // ---- 문서 용어 ----
  static const group = '그룹';
  static const rival = '라이벌';
  static const skillLevels = '실력 등급';
  static const noCapacity = '정원 없음';

  static String skillLevel(SkillLevel l) => switch (l) {
    SkillLevel.beginner => '비기너',
    SkillLevel.amateur => '아마추어',
    SkillLevel.semipro => '세미프로',
    SkillLevel.pro => '프로',
    SkillLevel.undecided => '미정',
  };

  static String kind(PairingKind k) => switch (k) {
    PairingKind.group => group,
    PairingKind.rival => rival,
  };

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const settingsSection = '팀 설정';
  static const teamInfo = '팀 정보 수정';
  static const matchSettings = '경기 설정';
  static const groupRival = '그룹·라이벌';
  static const save = '저장';
  static const saved = '저장했어요';
  static const delete = '삭제';

  // 팀 정보 수정
  static const recruiting = '인원 모집';
  static const recruitingOnNote = '팀 찾기에서 가입 신청을 받아요';
  static const recruitingOffNote = '팀 찾기에 "모집 마감"으로 보이고, 초대 코드로만 가입할 수 있어요';
  static const logoTextOwnerOnly = '로고 글자는 팀장만 바꿀 수 있어요';
  static String logoTextEditHint(String defaultText) =>
      defaultText.isEmpty ? '비우면 팀 이름 앞 두 글자' : '비우면 "$defaultText"';
  static const logoAutoNote = '팀 이름을 바꾸면 로고 글자도 따라 바뀌어요 (직접 바꾼 글자는 그대로)';

  // 경기 설정
  static const capacitySection = '정원';
  // 대기 사용 (Q-073 7번 참고, 저장은 정원 capacity 그대로)
  static const useWaitlist = '대기 사용';
  static const useWaitlistOffNote = '$noCapacity: 투표한 사람 모두 참석이에요';
  static const useWaitlistOnNote = '정한 인원이 차면 다음 사람부터 대기 순번이 붙어요';
  static const capacityLabel = '참석 인원 (몇 명까지 참석)';
  static String waitlistFrom(int capacity) => '$capacity명까지 참석, ${capacity + 1}번째부터 대기';
  static const deadlineLabel = '참석 투표 마감 (경기 시작 몇 시간 전)';
  // 미투표 알림 (Q-072 1번, 임시 문구)
  static const reminderLabel = '미투표 알림';
  static String reminderOption(int? hours) => hours == null ? '끄기' : '마감 $hours시간 전';
  static const autoCreateSection = '일정 자동 생성';
  static const autoCreateDaysLabel = '경기 며칠 전';
  static String autoCreateTimeButton(String hhmm) => '생성 시각 $hhmm';
  static const settingsKeepNote = '바꾼 설정은 앞으로 만들 일정부터 적용돼요';

  static String settingsError(MatchSettingsError e) => switch (e) {
    MatchSettingsError.capacityRange => '정원은 1~${MatchSettings.maxCapacity}명으로 정해 주세요',
    MatchSettingsError.deadlineRange =>
      '마감은 0~${MatchSettings.maxDeadlineHours}시간 전으로 정해 주세요',
    MatchSettingsError.autoCreateDaysRange =>
      '자동 생성은 0~${MatchSettings.maxAutoCreateDaysBefore}일 전으로 정해 주세요',
    MatchSettingsError.deadlineBeforeAutoCreate => deadlineBeforeAutoCreate,
    MatchSettingsError.reminderRange => '미투표 알림 시간을 골라 주세요',
  };

  static const deadlineBeforeAutoCreate = '참석 투표 마감이 일정 자동 생성보다 늦어야 해요';

  // 실력 등급
  static const skillLevelsNote = '실력 등급은 팀장·운영진만 볼 수 있어요';

  // 그룹·라이벌
  static const groupNote = '항상 같은 팀으로 배치할 사람들';
  static const rivalNote = '항상 다른 팀으로 배치할 사람들';
  static const addGroup = '그룹 추가';
  static const addRival = '라이벌 추가';
  static const noRules = '저장된 그룹·라이벌이 없어요';
  static const enabled = '켜기';
  static const pickMembers = '2명 이상 골라주세요';
  static String confirmDelete(String kindLabel) => '이 $kindLabel 설정을 삭제할까요?';
  static String conflict(String a, String b) =>
      '$a님과 $b님은 켜진 그룹으로 이어져 있어 라이벌로 함께 켤 수 없어요';
  static const conflictGeneric = '켜진 그룹·라이벌 설정끼리 맞지 않아 저장할 수 없어요';
  static const unknownMember = '(팀을 떠난 사람)';

  /// 서버 오류 → 화면 문구. 여기 없는 코드는 팀 화면 공통 문구.
  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.deadlineBeforeAutoCreate => deadlineBeforeAutoCreate,
    ServerErrorCode.invalidTeamSettings => '경기 설정 값을 확인해 주세요',
    ServerErrorCode.invalidTeamInfo => '팀 정보를 확인해 주세요',
    ServerErrorCode.invalidSkillLevel => '등급을 확인해 주세요',
    ServerErrorCode.pairingRuleConflict => conflictGeneric,
    ServerErrorCode.invalidPairingMembers => pickMembers,
    ServerErrorCode.invalidPairingRule => '설정을 확인해 주세요',
    _ => TeamTexts.serverError(code),
  };
}
