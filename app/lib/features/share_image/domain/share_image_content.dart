import '../../pom_vote/domain/award_models.dart';

/// 결과 공유 이미지에 넣을 [category] 1위 이름 (스프린트 03 6-2).
///
/// - 마감 뒤 1위만 (공동 1위는 모두). 득표수·순위는 없다.
/// - 팀을 떠난 1위는 빈칸 대신 뺀다 (S3-12, decisions 2026-11-09 lead 정리. 결과 화면은 빈칸 자리).
/// - 이름 가나다순 (같은 이름이면 ID 순으로 고정).
/// [memberNames] 는 지금 팀원 ID → 이름.
List<String> shareableWinnerNames(
  AwardPollView poll,
  AwardCategory category,
  Map<String, String> memberNames,
) {
  final ids = poll.winnersOf(category).where(memberNames.containsKey).toList()
    ..sort((a, b) {
      final c = memberNames[a]!.compareTo(memberNames[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final id in ids) memberNames[id]!];
}
