import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/logo_image.dart';

/// 로고 사진 고르기 결과.
sealed class LogoPickResult {
  const LogoPickResult();
}

/// 사용자가 고르기·자르기를 그만둠.
class LogoPickCancelled extends LogoPickResult {
  const LogoPickCancelled();
}

/// 10MB 넘는 사진.
class LogoPickTooLarge extends LogoPickResult {
  const LogoPickTooLarge();
}

/// JPG·PNG 가 아닌 사진.
class LogoPickUnsupported extends LogoPickResult {
  const LogoPickUnsupported();
}

/// 사진을 읽거나 처리하지 못함 (권한 거부 포함).
class LogoPickFailed extends LogoPickResult {
  const LogoPickFailed();
}

/// 정사각형·축소·위치 정보 제거까지 끝난 PNG.
class LogoPicked extends LogoPickResult {
  const LogoPicked(this.png);

  final Uint8List png;
}

/// 갤러리에서 사진을 골라 정사각형으로 자르고 저장용 PNG 로 만든다. 테스트에서는 가짜로 바꾼다.
abstract interface class LogoPicker {
  Future<LogoPickResult> pick(BuildContext context);
}

class DeviceLogoPicker implements LogoPicker {
  DeviceLogoPicker({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  final ImagePicker _picker;
  final ImageCropper _cropper;

  /// 자르기 결과 상한 (이후 [normalizeLogoImage] 가 512 로 줄인다).
  static const _cropMax = 1024;

  @override
  Future<LogoPickResult> pick(BuildContext context) async {
    final primary = Theme.of(context).colorScheme.primary;
    try {
      // 원본 크기를 재야 하므로 고를 때는 줄이지 않는다.
      final file = await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (file == null) return const LogoPickCancelled();
      if (!LogoImageRules.isAllowedFormat(mimeType: file.mimeType, fileName: file.name)) {
        return const LogoPickUnsupported();
      }
      if (await file.length() > LogoImageRules.maxOriginalBytes) {
        return const LogoPickTooLarge();
      }
      final cropped = await _cropper.cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: _cropMax,
        maxHeight: _cropMax,
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarColor: primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: primary,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(aspectRatioLockEnabled: true, resetAspectRatioEnabled: false),
        ],
      );
      if (cropped == null) return const LogoPickCancelled();
      final bytes = await cropped.readAsBytes();
      return LogoPicked(await normalizeLogoImage(bytes));
    } catch (_) {
      return const LogoPickFailed();
    }
  }
}
