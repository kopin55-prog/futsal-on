/// 팀 안에서의 역할. 용어는 docs/glossary.md 기준.
enum TeamRole {
  /// 팀장. 팀당 정확히 1명.
  owner,

  /// 운영진. 팀당 최대 [maxManagers]명.
  manager,

  /// 팀원.
  member;

  /// 팀장 또는 운영진.
  bool get isStaff => this == owner || this == manager;

  /// 운영진 최대 인원 (기획서 6장, glossary).
  static const int maxManagers = 2;
}
