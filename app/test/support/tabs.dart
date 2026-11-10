import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 팀 화면 아래 탭 [label] 을 누른다 (홈이 첫 탭이 된 뒤 다른 탭 화면을 시험할 때, S4-01).
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// 위쪽 팀 이름(팀 전환 버튼) 안의 [name]. 홈 대시보드 머리에도 팀 이름이 있어 위쪽만 찾는다.
Finder teamTitle(String name) =>
    find.descendant(of: find.byKey(const Key('team-title')), matching: find.text(name));
