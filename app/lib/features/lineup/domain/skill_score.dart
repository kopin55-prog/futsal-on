import '../../admin/domain/skill_level.dart';

/// 팀 나누기 계산에만 쓰는 실력 점수 (Q-075 5번, decisions.md 2026-11-09).
///
/// 등급 → 점수 매핑은 이 파일 한 곳에만 둔다. 나중에 등급을 세분(예: 아마추어-1·-2)하면
/// [SkillLevel] 에 값을 늘리고 여기 매핑만 늘리면 된다 (switch 가 빠진 등급을 컴파일 오류로 알려준다).
///
/// 점수는 운영진 기기 안의 계산에만 쓴다. 화면·공유 이미지·서버 저장·API 응답 어디에도 넣지 않는다.
/// (배치 결과 [TeamSplitPlan] 에도 점수·등급이 없다.)
abstract final class SkillScore {
  /// 미정은 아마추어로 계산한다 (기획서 9장).
  static int of(SkillLevel level) => switch (level) {
    SkillLevel.beginner => 10,
    SkillLevel.amateur => 20,
    SkillLevel.semipro => 30,
    SkillLevel.pro => 40,
    SkillLevel.undecided => of(SkillLevel.amateur),
  };
}
