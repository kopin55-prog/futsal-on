import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../shared/data/server_error.dart';
import '../../schedule/data/attendance_repository.dart';
import '../../schedule/domain/attendance_models.dart';
import 'injury_consent_screen.dart';
import 'injury_report_screen.dart';
import 'injury_texts.dart';

/// 부상 화면 사이 흐름 (스프린트 04 2단계). 권한(본인만)은 부르는 쪽이 Entitlements 로 이미 확인했다.

/// [부상 등록]: 유효한 동의가 없으면 동의 화면(2-1) → 동의하면 등록 화면(2-2) → 등록되면
/// 참석으로 되어 있는 다가오는 경기 안내(S4-08). 등록했으면 true.
Future<bool> startInjuryReport(
  BuildContext context, {
  required AppServices services,
  required String userId,
  DateTime Function() now = DateTime.now,
}) async {
  final bool consented;
  try {
    consented = await services.injuries.hasActiveConsent(userId);
  } on ServerFailure catch (e) {
    if (context.mounted) _toast(context, InjuryTexts.serverError(e.code));
    return false;
  }
  if (!context.mounted) return false;
  if (!consented) {
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InjuryConsentScreen(injuries: services.injuries)),
    );
    if (agreed != true || !context.mounted) return false;
  }
  final reported = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => InjuryReportScreen(injuries: services.injuries)),
  );
  if (reported != true || !context.mounted) return false;
  _toast(context, InjuryTexts.reported);
  await offerDeclineAfterReport(context, services: services, userId: userId, now: now());
  return true;
}

/// 부상 등록 직후: 참석(또는 대기)으로 응답해 둔 다가오는 경기가 있으면 안내 (S4-08, 자동으로 바꾸지 않음).
/// 마감 전 경기만 [불참으로 바꾸기], 마감 뒤 경기는 운영진에게 알리라는 안내만 (기획서 8장).
Future<void> offerDeclineAfterReport(
  BuildContext context, {
  required AppServices services,
  required String userId,
  required DateTime now,
}) async {
  final List<MyUpcomingResponse> upcoming;
  final Map<String, String> teamNames;
  try {
    upcoming = await services.attendance.listMyUpcomingAttending(userId, now: now);
    if (upcoming.isEmpty) return;
    teamNames = {for (final t in await services.teams.listMyTeams()) t.id: t.name};
  } on ServerFailure {
    return; // 안내일 뿐이라 실패하면 넘어간다
  }
  if (!context.mounted) return;
  final open = [for (final r in upcoming) if (r.match.isRsvpOpenAt(now)) r];
  final closed = [for (final r in upcoming) if (!r.match.isRsvpOpenAt(now)) r];
  String line(MyUpcomingResponse r) => InjuryTexts.matchLine(r.match, teamNames[r.match.teamId] ?? '');

  final decline = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('injury-attending-dialog'),
      title: const Text(InjuryTexts.stillAttendingTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in open) Text(line(r)),
          if (closed.isNotEmpty) ...[
            if (open.isNotEmpty) const SizedBox(height: 12),
            for (final r in closed) Text(line(r)),
            const SizedBox(height: 4),
            Text(InjuryTexts.closedMatchesNote, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('injury-keep-attending'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(InjuryTexts.keepAsIs),
        ),
        if (open.isNotEmpty)
          TextButton(
            key: const Key('injury-change-decline'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(InjuryTexts.changeToDecline),
          ),
      ],
    ),
  );
  if (decline != true) return;
  ServerFailure? failure;
  for (final r in open) {
    try {
      // 부상 중이어도 불참은 확인 없이 된다 (1-5)
      await services.attendance.respond(r.match.id, attending: false);
    } on ServerFailure catch (e) {
      failure = e;
    }
  }
  if (context.mounted) {
    _toast(context, failure == null ? InjuryTexts.changedToDecline : InjuryTexts.serverError(failure.code));
  }
}

/// 참석·불참 응답 (일정 상세 등 공통, 2-5).
///
/// 진행 중 부상이 있는 사람의 [참석]은 서버가 복귀 확인 필요로 거절한다 → "부상에서 복귀하셨나요?" 확인 창.
/// 확인 = 참석(또는 대기, S4-09) + 부상 해제(이력 return_vote), 취소 = 응답 안 바뀜(null).
/// 그 밖의 실패는 [ServerFailure] 그대로 던진다.
Future<AttendanceState?> respondWithReturnConfirm(
  BuildContext context,
  AttendanceRepository attendance,
  String matchId, {
  required bool attending,
}) async {
  try {
    return await attendance.respond(matchId, attending: attending);
  } on ServerFailure catch (e) {
    if (!attending || e.code != ServerErrorCode.returnConfirmationRequired || !context.mounted) rethrow;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('return-confirm-dialog'),
      content: const Text(InjuryTexts.returnConfirmTitle),
      actions: [
        TextButton(
          key: const Key('return-confirm-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(InjuryTexts.cancel),
        ),
        FilledButton(
          key: const Key('return-confirm-ok'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(InjuryTexts.returnConfirmYes),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  return attendance.respond(matchId, attending: true, returnConfirmed: ReturnConfirmation.vote);
}

/// 부상 정보 동의 철회 (2-4): 확인 창 → 서버(동의 철회 + 부상 기록·이력 전부 삭제). 철회했으면 true.
Future<bool> confirmWithdrawInjuryConsent(BuildContext context, {required AppServices services}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text(InjuryTexts.withdrawConfirm),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(InjuryTexts.cancel)),
        TextButton(
          key: const Key('injury-withdraw-confirm'),
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text(InjuryTexts.withdrawButton),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await services.injuries.withdrawConsent();
  } on ServerFailure catch (e) {
    // 이미 철회된 상태(다른 기기 등)면 목적은 이룬 것
    if (e.code != ServerErrorCode.injuryConsentNotFound) {
      if (context.mounted) _toast(context, InjuryTexts.serverError(e.code));
      return false;
    }
  }
  if (context.mounted) _toast(context, InjuryTexts.withdrawn);
  return true;
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
