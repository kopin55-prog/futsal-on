import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 로고 사진 규칙 (Q-067 3번, Q-068 1번, data-model.md 13장 S-10).
abstract final class LogoImageRules {
  /// 고를 수 있는 원본 사진 크기 상한 (10MB).
  static const maxOriginalBytes = 10 * 1024 * 1024;

  /// 저장하는 정사각형 한 변 (픽셀). 화면 로고는 최대 64~96 논리 픽셀이라 고해상도 화면에도 충분하다.
  static const outputSize = 512;

  /// 고를 수 있는 형식: JPG·PNG.
  static bool isAllowedFormat({String? mimeType, required String fileName}) {
    final mime = mimeType?.toLowerCase();
    if (mime != null && mime.isNotEmpty) {
      return mime == 'image/jpeg' || mime == 'image/jpg' || mime == 'image/png';
    }
    final name = fileName.toLowerCase();
    return name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png');
  }

  /// 저장 경로 "팀ID/무작위UUIDv4.png" (추측 불가, 서버 정책과 같은 모양).
  static String newStoragePath(String teamId, {Random? random}) =>
      '$teamId/${_uuidV4(random ?? Random.secure())}.png';

  static String _uuidV4(Random r) {
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// 고른 사진을 가운데 기준 정사각형으로 자르고 [LogoImageRules.outputSize] 로 줄여 PNG 로 다시 만든다.
///
/// 픽셀만 다시 그려 새로 인코딩하므로 원본의 위치(GPS) 등 메타데이터는 남지 않는다 (S-10).
/// 자르기 화면(image_cropper)이 이미 정사각형으로 자른 사진도 이 단계를 반드시 거친다.
Future<Uint8List> normalizeLogoImage(Uint8List source) async {
  final codec = await ui.instantiateImageCodec(source);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  codec.dispose();
  try {
    final side = min(image.width, image.height);
    final out = min(side, LogoImageRules.outputSize);
    final src = ui.Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side.toDouble(),
      side.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final squared = await picture.toImage(out, out);
    picture.dispose();
    try {
      final data = await squared.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('encode failed');
      return data.buffer.asUint8List();
    } finally {
      squared.dispose();
    }
  } finally {
    image.dispose();
  }
}
