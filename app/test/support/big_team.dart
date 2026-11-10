import 'package:futsal_on/core/entitlements/entitlements.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';

/// 큰 팀(20~30명 이상) 화면 테스트용 팀원 30명 (Q-079 3번).
///
/// - ID: p01~p30. p01 팀장, p02·p03 운영진, 나머지 팀원.
/// - 이름: 성 6개 × 이름 5개 = 30개 모두 다르다. "김"으로 검색하면 5명(p01·p07·p13·p19·p25).
const bigTeamSurnames = ['김', '이', '박', '최', '정', '강'];
const bigTeamGivenNames = ['민수', '서준', '도윤', '하준', '지호'];

List<MemberEntry> bigTeam({int count = 30}) => [
  for (var i = 0; i < count; i++)
    MemberEntry(
      userId: bigTeamId(i + 1),
      role: i == 0 ? TeamRole.owner : (i <= 2 ? TeamRole.manager : TeamRole.member),
      displayName: '${bigTeamSurnames[i % 6]}${bigTeamGivenNames[(i ~/ 6) % 5]}',
    ),
];

String bigTeamId(int n) => 'p${n.toString().padLeft(2, '0')}';

/// "김"씨 5명의 ID
const bigTeamKims = ['p01', 'p07', 'p13', 'p19', 'p25'];

TeamSummary bigTeamSummary(TeamRole myRole) => TeamSummary(
  id: 'a',
  name: '큰팀FC',
  teamCode: 'BIG001',
  logoText: '큰팀',
  myRole: myRole,
  isRecruiting: true,
);
