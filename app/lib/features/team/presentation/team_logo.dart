import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 로고 사진을 화면에 불러오는 방법. 앱 맨 위에 하나 둔다 (main.dart).
///
/// 저장소가 비공개라 공개 주소가 없다. 로그인한 사람의 인증 헤더로 받는다 (Q-068 1번).
/// 테스트·설정 없는 화면에서는 없을 수 있고, 그러면 글자 로고만 보인다.
class TeamLogoImages extends InheritedWidget {
  const TeamLogoImages({required this.resolve, required super.child, super.key});

  /// 저장 경로 → 이미지. 불러올 수 없으면 null.
  final ImageProvider? Function(String path) resolve;

  static ImageProvider? of(BuildContext context, String path) =>
      context.dependOnInheritedWidgetOfExactType<TeamLogoImages>()?.resolve(path);

  @override
  bool updateShouldNotify(TeamLogoImages oldWidget) => resolve != oldWidget.resolve;
}

/// 팀 로고. 사진이 있으면 사진, 없거나 못 불러오면 글자 로고 (Q-013).
class TeamLogo extends StatelessWidget {
  const TeamLogo({
    required this.text,
    this.imagePath,
    this.imageBytes,
    this.size = 40,
    super.key,
  });

  final String text;

  /// 저장소 경로 (teams.logo_image_path)
  final String? imagePath;

  /// 아직 저장 전인 새 사진 미리보기 (있으면 [imagePath] 보다 먼저)
  final Uint8List? imageBytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final textLogo = _TextLogo(text: text, size: size);
    final ImageProvider? provider = imageBytes != null
        ? MemoryImage(imageBytes!)
        : (imagePath == null ? null : TeamLogoImages.of(context, imagePath!));
    if (provider == null) return textLogo;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => textLogo,
          frameBuilder: (_, child, frame, wasSync) =>
              wasSync || frame != null ? child : textLogo,
        ),
      ),
    );
  }
}

class _TextLogo extends StatelessWidget {
  const _TextLogo({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
        maxLines: 1,
      ),
    );
  }
}
