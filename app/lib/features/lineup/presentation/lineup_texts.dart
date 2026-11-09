import '../../../shared/data/server_error.dart';
import '../../schedule/domain/attendance_models.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../domain/bib_color.dart';
import '../domain/lineup_board.dart';
import '../domain/team_split.dart';

/// 팀 나누기 화면 문구.
///
/// 문서 용어(그대로 씀): "팀 나누기", "재조합", "교체", "조끼 색"과 색 이름(Q-075 8번), "게스트".
/// 나머지 버튼·안내 문구는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
/// 실력 등급·점수·포지션·GK 를 담는 문구는 만들지 않는다 (Q-075 5·6번).
abstract final class LineupTexts {
  // ---- 문서 용어 ----
  static const splitTeams = '팀 나누기';
  static const reshuffle = '재조합';
  static const bench = '교체';
  static const bibColor = '조끼 색';
  static const guest = ScheduleTexts.guest;

  static String color(BibColor c) => switch (c) {
    BibColor.red => '빨강',
    BibColor.blue => '파랑',
    BibColor.yellow => '노랑',
    BibColor.green => '초록',
    BibColor.orange => '주황',
    BibColor.navy => '남색',
    BibColor.purple => '보라',
    BibColor.pink => '분홍',
    BibColor.black => '검정',
    BibColor.white => '흰색',
    BibColor.noBib => '노조끼',
  };

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const sectionTitle = '팀 배치';
  static const notYet = '아직 팀 배치 전이에요';
  static const noLineupStaff = '아직 배치를 만들지 않았어요';
  static const draftBadge = '초안';
  static const draftNote = '초안은 팀원에게 보이지 않아요';
  static const confirmedBadge = '확정';
  static const openEditor = '팀 나누기';
  static const editLineup = '배치 고치기';
  static const viewOnly = '배치 보기';

  static String window(LineupWindow w) => switch (w) {
    LineupWindow.beforeDeadline => '참석 마감 뒤에 팀을 나눌 수 있어요',
    LineupWindow.ended => '끝난 경기는 배치를 바꿀 수 없어요',
    LineupWindow.cancelled => '취소된 일정은 팀을 나눌 수 없어요',
    LineupWindow.open => '',
  };

  static const teamCount = '팀 수';
  static const playersPerTeam = '팀당 인원';
  static String teamCountValue(int n) => '$n팀';
  static String playersValue(int n) => '$n명';
  static const autoSplit = '자동 나누기';
  static String poolInfo(int n) => '참석자·게스트 $n명';
  static const emptyBoard = '팀 수와 팀당 인원을 정하고 [자동 나누기]를 눌러 주세요';

  static String squadTitle(BibColor c, int count) => '${color(c)} · $count명';
  static String benchTitle(int count) => '$bench $count명';
  static const nobody = '없음';
  static const addMember = '팀원 추가';
  static const addMemberTitle = '교체 블록에 넣을 사람';
  static const addMemberEmpty = '더 넣을 사람이 없어요';
  static String memberState(AttendanceState? s) => switch (s) {
    AttendanceState.attending => ScheduleTexts.attending,
    AttendanceState.waitlisted => ScheduleTexts.waitlisted,
    AttendanceState.declined => ScheduleTexts.declined,
    null => ScheduleTexts.notResponded,
  };
  static const removedGuest = '배치에서 뺀 게스트';

  static const pickColor = '조끼 색 고르기';
  static const colorInUse = '다른 팀이 쓰는 색';

  static String moveTitle(String name) => '$name 옮기기';
  static String moveTo(BibColor c) => '${color(c)} 팀으로';
  static const moveToBench = '교체 블록으로';
  static const removeFromLineup = '배치에서 빼기';
  static const dragHint = '이름을 길게 눌러 끌거나, 눌러서 옮길 곳을 고르세요';

  static String warning(SplitWarning w) => switch (w.kind) {
    SplitWarningKind.dedicatedGkOverTeams => '한 팀에 전문 골키퍼가 2명 이상 있어요',
    SplitWarningKind.groupSplit => '같은 팀이어야 할 그룹이 나뉘었어요',
    SplitWarningKind.rivalSameTeam => '라이벌이 같은 팀에 있어요',
    SplitWarningKind.benchRemaining => '교체 ${w.count}명, 직접 배치하세요',
    SplitWarningKind.playersShort => '${w.count}명 모자라요',
  };

  static const discardTitle = '직접 옮긴 내용이 사라져요';
  static const discardBody = '다시 나눌까요?';
  static const discardOk = '다시 나누기';
  static const keep = '그대로 두기';
  static const allSeen = '모든 조합을 봤어요. 처음 배치로 돌아갔어요';

  static const saveDraft = '초안 저장';
  static const confirm = '확정';
  static const saveChanges = '변경 저장';
  static const savedDraft = '초안을 저장했어요';
  static const confirmedDone = '배치를 확정했어요. 팀원들에게 알림이 갔어요';
  static const changesSaved = '변경을 저장했어요';
  static const confirmTitle = '배치를 확정할까요?';
  static const confirmBody = '확정하면 팀원들에게 공개되고 알림이 가요. 확정 뒤에도 고칠 수 있어요';
  static const afterStartNote = '경기가 시작돼서 변경 알림은 가지 않아요';
  static const conflict = '다른 운영진이 먼저 바꿨어요. 새로 불러올게요';
  static const unsavedTitle = '저장하지 않은 변경이 있어요';
  static const unsavedBody = '나가면 고친 내용이 사라져요';
  static const leave = '나가기';
  static const ok = '확인';
  static const cancel = '취소';

  static String serverError(ServerErrorCode code) => switch (code) {
    ServerErrorCode.lineupConflict => conflict,
    ServerErrorCode.lineupNotOpen => window(LineupWindow.beforeDeadline),
    ServerErrorCode.matchAlreadyEnded => window(LineupWindow.ended),
    ServerErrorCode.matchCancelled => window(LineupWindow.cancelled),
    ServerErrorCode.invalidLineupSlot => '명단에 넣을 수 없는 사람이 있어요. 새로 불러올게요',
    ServerErrorCode.invalidLineup => '배치 내용을 확인해 주세요',
    _ => ScheduleTexts.serverError(code),
  };
}
