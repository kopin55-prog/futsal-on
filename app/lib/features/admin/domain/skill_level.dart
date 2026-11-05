/// 실력 등급 (glossary: 비기너·아마추어·세미프로·프로·미정). 서버 값과 이름이 같다.
///
/// 서버에 줄이 없으면 [undecided]. 누가 볼 수 있는지는 Entitlements(SkillLevelInfo)에서만 판단한다.
enum SkillLevel {
  beginner,
  amateur,
  semipro,
  pro,
  undecided;

  static SkillLevel fromServer(String? value) => value == null
      ? undecided
      : SkillLevel.values.firstWhere((e) => e.name == value, orElse: () => undecided);
}
