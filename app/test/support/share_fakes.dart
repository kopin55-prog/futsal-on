import 'package:flutter/widgets.dart';
import 'package:futsal_on/features/share_image/data/share_image_service.dart';

/// 가짜 공유: 그림으로 만들지 않고 넘겨받은 이미지 위젯을 기억한다 (테스트에서 다시 그려 내용 검사).
class FakeShareImageService implements ShareImageService {
  final List<({Widget image, String fileName, String? logoImagePath})> shared = [];

  /// true 면 다음 공유를 실패시킨다.
  bool failNext = false;

  @override
  Future<void> share(
    BuildContext context,
    Widget image, {
    required String fileName,
    String? logoImagePath,
    Rect? origin,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('share failed');
    }
    shared.add((image: image, fileName: fileName, logoImagePath: logoImagePath));
  }
}
