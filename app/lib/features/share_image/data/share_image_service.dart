import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../presentation/share_images.dart';
import '../presentation/widget_image_renderer.dart';

/// 공유 이미지를 그림으로 만들어 휴대폰 공유 창으로 넘긴다 (스프린트 03 6단계).
///
/// 공유 방식은 휴대폰 공유 창 (S3-11 A, Q-075 11번 share_plus 승인). 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class ShareImageService {
  /// [image] 를 그림으로 만들어 공유 창을 연다. [origin] 은 아이패드에서 공유 창이 뜰 위치(버튼 자리).
  Future<void> share(
    BuildContext context,
    Widget image, {
    required String fileName,
    String? logoImagePath,
    Rect? origin,
  });
}

class SharePlusShareImageService implements ShareImageService {
  const SharePlusShareImageService();

  @override
  Future<void> share(
    BuildContext context,
    Widget image, {
    required String fileName,
    String? logoImagePath,
    Rect? origin,
  }) async {
    final png = await WidgetImageRenderer.toPng(
      context,
      image,
      width: shareImageWidth,
      pixelRatio: ShareImageFrame.pixelRatio,
      logoImagePath: logoImagePath,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
        sharePositionOrigin: origin,
      ),
    );
  }
}
