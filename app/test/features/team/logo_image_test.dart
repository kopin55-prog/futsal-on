import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/team/domain/logo_image.dart';

/// 단색 PNG 만들기 (dart:ui).
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const Color(0xFF2E6B4F),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : crc >>> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// PNG 의 IHDR 뒤에 위치 정보가 든 eXIf 조각을 끼워 넣는다 (휴대폰 사진 흉내).
Uint8List _withExif(Uint8List png) {
  final payload = utf8.encode('MM\u0000*GPSLatitude=37.4979;GPSLongitude=127.0276');
  final type = ascii.encode('eXIf');
  final chunk = <int>[
    ..._u32(payload.length),
    ...type,
    ...payload,
    ..._u32(_crc32([...type, ...payload])),
  ];
  const ihdrEnd = 8 + 4 + 4 + 13 + 4;
  return Uint8List.fromList([...png.sublist(0, ihdrEnd), ...chunk, ...png.sublist(ihdrEnd)]);
}

bool _hasChunk(Uint8List png, String type) {
  var i = 8;
  final bd = png.buffer.asByteData(png.offsetInBytes);
  while (i + 8 <= png.length) {
    final len = bd.getUint32(i);
    if (ascii.decode(png.sublist(i + 4, i + 8)) == type) return true;
    i += 12 + len;
  }
  return false;
}

Future<(int, int)> _size(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final r = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return r;
}

void main() {
  group('normalizeLogoImage (Q-067 3번, S-10)', () {
    testWidgets('가로로 긴 큰 사진 → 512 정사각형 PNG, 위치 정보 조각 없음', (tester) async {
      await tester.runAsync(() async {
        final src = _withExif(await _png(1200, 800));
        expect(_hasChunk(src, 'eXIf'), isTrue, reason: '입력에 위치 정보가 있어야 의미 있는 시험');
        final out = await normalizeLogoImage(src);
        expect(out.sublist(1, 4), ascii.encode('PNG'));
        expect(await _size(out), (512, 512));
        expect(_hasChunk(out, 'eXIf'), isFalse);
        expect(_hasChunk(out, 'tEXt'), isFalse);
        expect(_hasChunk(out, 'iTXt'), isFalse);
      });
    });

    testWidgets('작은 세로 사진은 키우지 않고 짧은 변 정사각형', (tester) async {
      await tester.runAsync(() async {
        final out = await normalizeLogoImage(await _png(60, 100));
        expect(await _size(out), (60, 60));
      });
    });

    testWidgets('사진이 아니면 실패', (tester) async {
      await tester.runAsync(() async {
        await expectLater(normalizeLogoImage(Uint8List.fromList([1, 2, 3, 4])), throwsA(anything));
      });
    });
  });

  group('LogoImageRules', () {
    test('JPG·PNG 만 (형식 정보 우선, 없으면 파일 이름)', () {
      expect(LogoImageRules.isAllowedFormat(mimeType: 'image/jpeg', fileName: 'a.heic'), isTrue);
      expect(LogoImageRules.isAllowedFormat(mimeType: 'image/png', fileName: 'a'), isTrue);
      expect(LogoImageRules.isAllowedFormat(mimeType: 'image/heic', fileName: 'a.jpg'), isFalse);
      expect(LogoImageRules.isAllowedFormat(mimeType: 'image/gif', fileName: 'a.gif'), isFalse);
      expect(LogoImageRules.isAllowedFormat(fileName: 'A.JPEG'), isTrue);
      expect(LogoImageRules.isAllowedFormat(mimeType: '', fileName: 'a.png'), isTrue);
      expect(LogoImageRules.isAllowedFormat(fileName: 'a.svg'), isFalse);
      expect(LogoImageRules.isAllowedFormat(fileName: 'a.webp'), isFalse);
    });

    test('원본 상한 10MB', () {
      expect(LogoImageRules.maxOriginalBytes, 10 * 1024 * 1024);
    });

    test('저장 경로는 서버 정책과 같은 모양 (팀ID/UUIDv4.png), 매번 다르다', () {
      // supabase/migrations/202611050016 private.team_logo_path_team_id 와 같은 식
      final serverPattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
        r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png)$',
      );
      const teamId = '0b6f9c1e-3d2a-4c5b-9e8f-112233445566';
      final seen = <String>{};
      final rng = Random(7);
      for (var i = 0; i < 200; i++) {
        final p = LogoImageRules.newStoragePath(teamId, random: rng);
        expect(serverPattern.hasMatch(p), isTrue, reason: p);
        expect(p.startsWith('$teamId/'), isTrue);
        seen.add(p);
      }
      expect(seen.length, 200);
      expect(serverPattern.hasMatch(LogoImageRules.newStoragePath(teamId)), isTrue);
    });
  });
}
