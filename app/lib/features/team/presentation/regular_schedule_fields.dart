import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/team_models.dart';
import '../domain/team_validation.dart';
import 'team_texts.dart';

/// 정기 운동일 입력 (요일 → 시작 → 종료). 팀 만들기·팀 정보 수정 공통.
/// 요일을 지우면 시각도, 시작을 지우면 종료도 함께 지운다. 자정 넘김은 허용 (Q-067 4번).
class RegularScheduleFields extends StatelessWidget {
  const RegularScheduleFields({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final RegularSchedule value;
  final ValueChanged<RegularSchedule> onChanged;

  Future<void> _pickTime(BuildContext context, {required bool start}) async {
    final current = start ? value.start : value.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current?.hour ?? (start ? 20 : 22),
        minute: current?.minute ?? 0,
      ),
    );
    if (picked == null) return;
    final t = ClockTime(picked.hour, picked.minute);
    onChanged(
      start
          ? RegularSchedule(weekday: value.weekday, start: t, end: value.end)
          : RegularSchedule(weekday: value.weekday, start: value.start, end: t),
    );
  }

  Widget _timeButton(BuildContext context, {required bool start}) {
    final time = start ? value.start : value.end;
    final label = start ? TeamTexts.startTime : TeamTexts.endTime;
    final enabled = start ? value.weekday != null : value.start != null;
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: Key(start ? 'team-start-time' : 'team-end-time'),
              onPressed: enabled ? () => _pickTime(context, start: start) : null,
              child: Text(time == null ? label : '$label ${time.hhmm}'),
            ),
          ),
          if (time != null)
            IconButton(
              tooltip: TeamTexts.clearTime,
              icon: const Icon(Icons.clear),
              onPressed: () => onChanged(
                start
                    ? RegularSchedule(weekday: value.weekday)
                    : RegularSchedule(weekday: value.weekday, start: value.start),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final errors = TeamValidator.validateRegularSchedule(
      weekday: value.weekday,
      start: value.start,
      end: value.end,
    );
    final crosses = value.start != null &&
        value.end != null &&
        TeamValidator.crossesMidnight(value.start!, value.end!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int?>(
          key: const Key('team-weekday'),
          initialValue: value.weekday,
          decoration: const InputDecoration(labelText: TeamTexts.regularDay),
          items: [
            const DropdownMenuItem(value: null, child: Text(TeamTexts.noWeekday)),
            for (var d = 1; d <= 7; d++)
              DropdownMenuItem(value: d, child: Text(TeamTexts.weekday(d))),
          ],
          onChanged: (v) => onChanged(
            v == null
                ? const RegularSchedule()
                : RegularSchedule(weekday: v, start: value.start, end: value.end),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _timeButton(context, start: true),
            _timeButton(context, start: false),
          ],
        ),
        if (crosses)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(TeamTexts.schedule(value) ?? ''),
          ),
        for (final e in errors)
          Text(TeamTexts.scheduleError(e), style: TextStyle(color: errorColor)),
      ],
    );
  }
}
