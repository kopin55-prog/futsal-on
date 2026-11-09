import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/features/team/domain/team_models.dart';
import 'package:futsal_on/features/team/domain/team_validation.dart';
import 'package:futsal_on/features/team/presentation/regular_schedule_fields.dart';
import 'package:futsal_on/features/team/presentation/team_texts.dart';

/// 정기 운동 입력 (팀 만들기·팀 정보 수정 공통): 시작을 고르면 종료가 시작 2시간 뒤로 채워지고, 종료는 필수 (Q-073 8번).
void main() {
  Future<RegularSchedule Function()> pump(WidgetTester tester, RegularSchedule initial) async {
    var value = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RegularScheduleFields(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    return () => value;
  }

  testWidgets('시작을 고르면 종료가 비어 있을 때 시작 2시간 뒤로 채운다', (tester) async {
    final value = await pump(tester, const RegularSchedule(weekday: 3));
    await tester.tap(find.byKey(const Key('team-start-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(value().start, const ClockTime(20, 0));
    expect(value().end, const ClockTime(22, 0));
    expect(find.text(TeamTexts.scheduleError(RegularScheduleError.endRequired)), findsNothing);
  });

  testWidgets('이미 고른 종료는 그대로 둔다', (tester) async {
    final value = await pump(
      tester,
      const RegularSchedule(weekday: 3, start: ClockTime(19, 0), end: ClockTime(23, 0)),
    );
    await tester.tap(find.byKey(const Key('team-start-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(value().end, const ClockTime(23, 0));
  });

  testWidgets('종료를 지우면 "종료 시각도 골라주세요"', (tester) async {
    await pump(tester, const RegularSchedule(weekday: 3, start: ClockTime(20, 0)));
    expect(find.text(TeamTexts.scheduleError(RegularScheduleError.endRequired)), findsOneWidget);
  });
}
