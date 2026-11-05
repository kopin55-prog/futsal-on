import 'package:flutter/material.dart';

/// 글자 로고 (Q-013). 로고 사진은 저장소 승인 후 (TODO(로고 사진 단계)).
class TeamLogo extends StatelessWidget {
  const TeamLogo({required this.text, this.size = 40, super.key});

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
          fontWeight: FontWeight.bold,
          fontSize: size * 0.36,
        ),
        maxLines: 1,
      ),
    );
  }
}
