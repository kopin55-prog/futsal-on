/// 공유 이미지 문구 (스프린트 03 6단계).
///
/// 문서 용어(그대로 씀): "풋살ON"(이미지 아래 작게, S3-12), "결과 없음".
/// 나머지 버튼·안내 문구는 모두 임시 — TODO(문구 미정): 묶음 테스트 때 kopn 이 화면을 보며 고친다 (Q-067 0번).
/// 득표수·실력·포지션·GK 를 담는 문구는 만들지 않는다 (S3-12, Q-075 5·6번).
abstract final class ShareImageTexts {
  // ---- 문서 용어 ----
  static const brand = '풋살ON';

  // ---- TODO(문구 미정): 아래는 임시 ----
  static const shareLineup = '배치 이미지 공유';
  static const shareResult = '결과 이미지 공유';
  static const failed = '이미지를 공유하지 못했어요';
  static const lineupTitle = '팀 배치';
  static const resultTitle = 'POM·오늘의 골';

  /// 공유 창으로 넘기는 파일 이름 (받는 쪽에 보일 수 있음)
  static const lineupFileName = 'futsalon_lineup.png';
  static const resultFileName = 'futsalon_result.png';
}
