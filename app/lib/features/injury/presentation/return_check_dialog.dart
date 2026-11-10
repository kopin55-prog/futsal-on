import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../../schedule/data/attendance_repository.dart';
import '../../schedule/domain/match_models.dart';
import '../../schedule/presentation/schedule_texts.dart';
import '../domain/injury_models.dart';
import 'injury_texts.dart';

/// 복귀 확인 알림을 눌렀을 때 일정 상세 위에 뜨는 창 (스프린트 04 2-6, Q-078 S4-11 A).
///
/// [참석할게요] → 참석(정원이 차면 대기, S4-09) + 부상 해제(이력 return_check)
/// [아직 회복 중 +1W] [+2W] → 연장(이력 extended/return_check, 늦은 날짜 기준 S4-07)
/// [닫기]·바깥 누름 → 부상·응답 그대로 (다음 일정이 열릴 때 다시 알림)
/// 참석 마감이 지났으면 [참석할게요] 대신 "마감됐어요".
///
/// 창을 띄울지는 [shouldShowReturnCheck] 가 정한다: 지금도 진행 중 부상이 있고 그 일정에 아직 응답 전일 때만
/// (푸시 건너뛰기 규칙과 같음, 202611050065). 그 밖이면 일정 상세만 연다.
enum ReturnCheckOutcome { attended, extended, closed }

/// 창을 띄울 조건. [hasResponse] = 그 일정에 내 참석 투표 응답이 있는지.
bool shouldShowReturnCheck({
  required Entitlements entitlements,
  required Viewer viewer,
  required TeamMatch match,
  required Injury? myInjury,
  required bool hasResponse,
}) =>
    myInjury != null &&
    myInjury.isActive &&
    entitlements.canManageInjury(viewer, subjectUserId: myInjury.userId) &&
    entitlements.canPerform(viewer, TeamAction.voteAttendance) &&
    !match.isCancelled &&
    !hasResponse;

/// 창을 띄우고 고른 처리를 서버에 보낸다. 결과 문구는 스낵바로.
Future<ReturnCheckOutcome> showReturnCheckDialog(
  BuildContext context, {
  required AppServices services,
  required TeamMatch match,
  required DateTime now,
}) async {
  final open = match.isRsvpOpenAt(now);
  final choice = await showDialog<_Choice>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        key: const Key('return-check-dialog'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(InjuryTexts.returnCheckBody),
            const SizedBox(height: 8),
            Text(ScheduleTexts.matchTime(match), style: theme.textTheme.bodySmall),
          ],
        ),
        actionsOverflowButtonSpacing: 4,
        actions: [
          if (open)
            FilledButton(
              key: const Key('return-check-attend'),
              onPressed: () => Navigator.pop(context, const _Choice.attend()),
              child: const Text(InjuryTexts.returnCheckAttend),
            )
          else
            const TextButton(
              key: Key('return-check-closed'),
              onPressed: null,
              child: Text(InjuryTexts.returnCheckClosed),
            ),
          for (final w in InjuryRules.extendWeeks)
            OutlinedButton(
              key: Key('return-check-extend-$w'),
              onPressed: () => Navigator.pop(context, _Choice.extend(w)),
              child: Text(InjuryTexts.returnCheckExtend(w)),
            ),
          TextButton(
            key: const Key('return-check-close'),
            onPressed: () => Navigator.pop(context),
            child: const Text(InjuryTexts.returnCheckClose),
          ),
        ],
      );
    },
  );
  if (choice == null) return ReturnCheckOutcome.closed;
  try {
    if (choice.extendWeeks case final w?) {
      final next = await services.injuries.extend(w, fromReturnCheck: true);
      if (context.mounted) _toast(context, InjuryTexts.extended(next));
      return ReturnCheckOutcome.extended;
    }
    await services.attendance.respond(match.id, attending: true, returnConfirmed: ReturnConfirmation.notification);
    return ReturnCheckOutcome.attended;
  } on ServerFailure catch (e) {
    if (context.mounted) _toast(context, InjuryTexts.serverError(e.code));
    return ReturnCheckOutcome.closed;
  }
}

class _Choice {
  const _Choice.attend() : extendWeeks = null;
  const _Choice.extend(int this.extendWeeks);

  final int? extendWeeks;
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
