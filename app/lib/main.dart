import 'package:flutter/material.dart';

/// 풋살ON 앱 진입점.
///
/// 스프린트 01 시점에는 화면 구성이 승인 전이므로 빈 자리표시만 둔다.
/// TODO(Q-대기): 화면 구성·문구 승인 후 실제 앱 셸(탭·라우팅)로 교체.
void main() {
  runApp(const FutsalOnApp());
}

class FutsalOnApp extends StatelessWidget {
  const FutsalOnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
  }
}
