import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/domain/venue.dart';
import '../../team/presentation/team_texts.dart';
import '../data/place_search_repository.dart';
import 'venue_picker_screen.dart';

/// 지정 풋살장 칸 (팀 만들기·팀 정보 수정). 누르면 구장 고르기 화면.
class VenueField extends StatelessWidget {
  const VenueField({
    required this.value,
    required this.places,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final Venue? value;
  final PlaceSearchRepository places;
  final ValueChanged<Venue?> onChanged;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final picked = await Navigator.of(context).push<Venue>(
      MaterialPageRoute(builder: (_) => VenuePickerScreen(places: places)),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final subtitle = [
      if (v?.address != null) v!.address!,
      if (v != null && !v.isFromMap) TeamTexts.venueManualBadge,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TeamTexts.venue, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            key: const Key('venue-field'),
            enabled: enabled,
            leading: const Icon(Icons.place_outlined),
            title: Text(v?.name ?? TeamTexts.venueNone),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: v == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    key: const Key('venue-clear'),
                    tooltip: TeamTexts.venueClear,
                    icon: const Icon(Icons.close),
                    onPressed: enabled ? () => onChanged(null) : null,
                  ),
            onTap: () => _open(context),
          ),
        ),
      ],
    );
  }
}
