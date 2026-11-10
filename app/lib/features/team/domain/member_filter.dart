import '../../../shared/domain/name_search.dart';
import '../../admin/domain/skill_level.dart';
import 'team_models.dart';

/// 팀원 탭 필터 칩 (Q-079 3번 a). "실력 미정"은 실력 등급을 볼 수 있는 사람에게만 보인다
/// (Entitlements.showSkillUndecidedFilter 가 정하고, 화면은 그 결과로 칩을 넣고 뺀다).
enum MemberFilter { all, staff, injured, skillUndecided }

/// 이름 검색 + 필터 칩을 순서대로 적용한다. 순수 함수 (화면과 무관).
///
/// - [query] 는 [NameSearch] 규칙으로 "포함" 검색. 빈 검색어면 모두.
/// - [injuredIds] = 지금 보이는 진행 중 부상자 (부상 표시를 볼 수 있는 사람만, 화면이 Entitlements 로 거른 것).
/// - [skillLevels] = 팀원별 실력 등급 (줄이 없으면 미정). 볼 수 없는 사람은 null 을 넘기고, 그러면 "실력 미정"은 아무도 안 나온다.
List<MemberEntry> filterMembers(
  Iterable<MemberEntry> members, {
  required MemberFilter filter,
  String query = '',
  Set<String> injuredIds = const {},
  Map<String, SkillLevel>? skillLevels,
}) {
  final key = NameSearch.key(query);
  bool keep(MemberEntry m) => switch (filter) {
    MemberFilter.all => true,
    MemberFilter.staff => m.role.isStaff,
    MemberFilter.injured => injuredIds.contains(m.userId),
    MemberFilter.skillUndecided => isSkillUndecided(m.userId, skillLevels),
  };
  return [
    for (final m in members)
      if (keep(m) && NameSearch.matchesKey(NameSearch.key(m.displayName), key)) m,
  ];
}

/// 실력 등급이 미정인지. [skillLevels] 가 null 이면 (볼 수 없으면) 모두 아니오.
bool isSkillUndecided(String userId, Map<String, SkillLevel>? skillLevels) =>
    skillLevels != null && (skillLevels[userId] ?? SkillLevel.undecided) == SkillLevel.undecided;
