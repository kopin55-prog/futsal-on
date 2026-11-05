import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/logo_picker.dart';
import 'team_texts.dart';

/// 로고 사진 칸의 상태 (저장 전). 저장 때 [TeamLogoRepository] 로 반영한다.
class LogoPhotoDraft {
  const LogoPhotoDraft({this.currentPath, this.newPng, this.removed = false});

  /// 지금 저장된 사진 경로
  final String? currentPath;

  /// 새로 고른 사진 (저장 전)
  final Uint8List? newPng;

  /// 지금 사진을 지우기로 함
  final bool removed;

  bool get hasPhoto => newPng != null || (!removed && currentPath != null);

  /// 화면에 보일 저장된 사진 경로 (새 사진·지우기면 null)
  String? get shownPath => newPng != null || removed ? null : currentPath;

  bool get changed => newPng != null || (removed && currentPath != null);

  LogoPhotoDraft withNew(Uint8List png) =>
      LogoPhotoDraft(currentPath: currentPath, newPng: png);

  LogoPhotoDraft withRemoved() => LogoPhotoDraft(currentPath: currentPath, removed: true);
}

/// 로고 사진 고르기·바꾸기·지우기 (팀 만들기·팀 정보 수정). 사진을 지우면 글자 로고.
class LogoPhotoField extends StatefulWidget {
  const LogoPhotoField({
    required this.value,
    required this.picker,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final LogoPhotoDraft value;
  final LogoPicker picker;
  final ValueChanged<LogoPhotoDraft> onChanged;
  final bool enabled;

  @override
  State<LogoPhotoField> createState() => _LogoPhotoFieldState();
}

class _LogoPhotoFieldState extends State<LogoPhotoField> {
  String? _error;
  bool _picking = false;

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    final result = await widget.picker.pick(context);
    if (!mounted) return;
    setState(() {
      _picking = false;
      _error = switch (result) {
        LogoPickTooLarge() => TeamTexts.photoTooLarge,
        LogoPickUnsupported() => TeamTexts.photoUnsupported,
        LogoPickFailed() => TeamTexts.photoFailed,
        _ => null,
      };
    });
    if (result case LogoPicked(:final png)) widget.onChanged(widget.value.withNew(png));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = widget.value.hasPhoto;
    final enabled = widget.enabled && !_picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TeamTexts.logoPhoto, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          TeamTexts.logoPhotoNote,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('logo-photo-pick'),
                onPressed: enabled ? _pick : null,
                icon: _picking
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined),
                label: Text(has ? TeamTexts.changePhoto : TeamTexts.pickPhoto),
              ),
            ),
            if (has) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('logo-photo-remove'),
                  onPressed: enabled
                      ? () {
                          setState(() => _error = null);
                          widget.onChanged(widget.value.withRemoved());
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text(TeamTexts.removePhoto),
                ),
              ),
            ],
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            key: const Key('logo-photo-error'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
