import 'package:flutter/material.dart';

/// 공유 이미지 버튼 (스프린트 03 6-1·6-2). 보일지는 부르는 쪽이 Entitlements 로 정한다.
///
/// 누르면 [onShare] 에 버튼 자리(아이패드 공유 창 위치)를 넘기고, 끝날 때까지 버튼을 잠근다.
class ShareImageButton extends StatefulWidget {
  const ShareImageButton({required this.label, required this.onShare, super.key});

  final String label;
  final Future<void> Function(Rect? origin) onShare;

  @override
  State<ShareImageButton> createState() => _ShareImageButtonState();
}

class _ShareImageButtonState extends State<ShareImageButton> {
  bool _busy = false;

  Rect? _origin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _tap() async {
    setState(() => _busy = true);
    try {
      await widget.onShare(_origin());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _busy ? null : _tap,
    icon: _busy
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.share_outlined),
    label: Text(widget.label),
  );
}
