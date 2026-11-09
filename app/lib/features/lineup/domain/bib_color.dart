/// 조끼 색 (data-model.md 5-2 bib_color). 선언 순서 = 자동 배정 순서 (Q-075 8번):
/// 빨강·파랑·노랑·초록·주황·남색·보라·분홍·검정·흰색·노조끼.
/// 운영진이 팀마다 바꿀 수 있고(노조끼 포함), 한 배치 안에서 같은 색은 한 번만 (서버도 거절).
enum BibColor {
  red('red'),
  blue('blue'),
  yellow('yellow'),
  green('green'),
  orange('orange'),
  navy('navy'),
  purple('purple'),
  pink('pink'),
  black('black'),
  white('white'),
  noBib('no_bib');

  const BibColor(this.serverValue);

  /// 서버 enum 값.
  final String serverValue;

  static BibColor fromServer(String value) =>
      BibColor.values.firstWhere((e) => e.serverValue == value);

  /// 팀 수만큼 자동 배정 순서대로. 팀 수는 2~11 (조끼 색 11개).
  static List<BibColor> defaults(int teamCount) {
    RangeError.checkValueInInterval(teamCount, 0, BibColor.values.length, 'teamCount');
    return BibColor.values.take(teamCount).toList();
  }
}
