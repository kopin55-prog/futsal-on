import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/domain/venue.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../team/presentation/team_texts.dart';
import '../data/place_search_repository.dart';

/// 지정 풋살장 고르기: 카카오맵 장소 검색 결과 목록에서 고르거나, 없으면 직접 입력 (기획서 5장, Q-032).
/// 지도 표시는 하지 않는다 (목록 선택). 고른 [Venue] 를 돌려주며 닫힌다.
///
/// 장소 검색 서버 함수(place-search)가 배포 전이면 "준비 중" 안내와 직접 입력만 보인다.
class VenuePickerScreen extends StatefulWidget {
  const VenuePickerScreen({required this.places, super.key});

  final PlaceSearchRepository places;

  @override
  State<VenuePickerScreen> createState() => _VenuePickerScreenState();
}

class _VenuePickerScreenState extends State<VenuePickerScreen> {
  final _query = TextEditingController();
  String? _lastQuery;
  List<PlaceResult> _results = const [];
  int _page = 1;
  bool _isEnd = true;
  bool _loading = false;
  PlaceSearchError? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _normalized => _query.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  bool get _tooLong => _normalized.characters.length > maxPlaceQueryLength;

  Future<void> _search({bool more = false}) async {
    final q = more ? _lastQuery : _normalized;
    if (q == null || q.isEmpty || _tooLong || _loading) return;
    FocusScope.of(context).unfocus();
    final page = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.places.search(q, page: page);
      if (!mounted) return;
      setState(() {
        _lastQuery = q;
        _page = page;
        _isEnd = res.isEnd;
        _results = more ? [..._results, ...res.places] : res.places;
      });
    } on PlaceSearchFailure catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manual() async {
    final venue = await showDialog<Venue>(
      context: context,
      builder: (_) => _ManualVenueDialog(initialName: _normalized),
    );
    if (venue != null && mounted) Navigator.of(context).pop(venue);
  }

  @override
  Widget build(BuildContext context) {
    final unavailable = _error == PlaceSearchError.unavailable;
    return Scaffold(
      appBar: AppBar(title: const Text(TeamTexts.venueTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.md),
              child: TextField(
                key: const Key('venue-search-input'),
                controller: _query,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                enabled: !unavailable,
                decoration: InputDecoration(
                  labelText: TeamTexts.venueSearchLabel,
                  errorText: _tooLong ? TeamTexts.venueSearchTooLong : null,
                  suffixIcon: IconButton(
                    key: const Key('venue-search-submit'),
                    icon: const Icon(Icons.search),
                    onPressed: unavailable ? null : () => _search(),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
              ),
            ),
            Expanded(child: _body()),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.lg),
              child: OutlinedButton.icon(
                key: const Key('venue-manual'),
                onPressed: _manual,
                icon: const Icon(Icons.edit_outlined),
                label: const Text(TeamTexts.venueManual),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error == PlaceSearchError.unavailable) {
      return const EmptyState(
        key: Key('venue-search-unavailable'),
        icon: Icons.construction_outlined,
        message: TeamTexts.venueSearchUnavailable,
      );
    }
    if (_loading && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error == PlaceSearchError.failed && _results.isEmpty) {
      return EmptyState(
        key: const Key('venue-search-failed'),
        icon: Icons.wifi_off_outlined,
        message: TeamTexts.venueSearchFailed,
        actions: [
          TextButton(onPressed: () => _search(), child: const Text(TeamTexts.retry)),
        ],
      );
    }
    if (_lastQuery == null) {
      return const EmptyState(icon: Icons.search, message: TeamTexts.venueSearchGuide);
    }
    if (_results.isEmpty) {
      return const EmptyState(
        key: Key('venue-no-result'),
        icon: Icons.location_off_outlined,
        message: TeamTexts.venueNoResult,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      itemCount: _results.length + (_isEnd ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TextButton(
              key: const Key('venue-more'),
              onPressed: _loading ? null : () => _search(more: true),
              child: _loading
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(TeamTexts.venueMore),
            ),
          );
        }
        final p = _results[i];
        final sub = [if (p.address != null) p.address!, if (p.category != null) p.category!.split('>').last.trim()];
        return ListTile(
          key: Key('venue-result-${p.placeId}'),
          leading: const Icon(Icons.place_outlined),
          title: Text(p.name),
          subtitle: sub.isEmpty ? null : Text(sub.join(' · ')),
          onTap: () => Navigator.of(context).pop(p.toVenue()),
        );
      },
    );
  }
}

/// 구장 직접 입력: 이름(필수, 200자)과 주소(선택, 300자). 한 줄.
class _ManualVenueDialog extends StatefulWidget {
  const _ManualVenueDialog({required this.initialName});

  final String initialName;

  @override
  State<_ManualVenueDialog> createState() => _ManualVenueDialogState();
}

class _ManualVenueDialogState extends State<_ManualVenueDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  final _address = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String? get _nameError {
    final n = _clean(_name.text);
    if (n.characters.length > Venue.maxNameLength) return TeamTexts.venueNameTooLong;
    if (_submitted && n.isEmpty) return TeamTexts.venueNameRequired;
    return null;
  }

  String? get _addressError =>
      _clean(_address.text).characters.length > Venue.maxAddressLength ? TeamTexts.venueAddressTooLong : null;

  void _done() {
    setState(() => _submitted = true);
    if (_nameError != null || _addressError != null) return;
    final address = _clean(_address.text);
    Navigator.of(context).pop(
      Venue.manual(name: _clean(_name.text), address: address.isEmpty ? null : address),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(TeamTexts.venueManualTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('venue-manual-name'),
            controller: _name,
            maxLines: 1,
            autofocus: true,
            decoration: InputDecoration(labelText: TeamTexts.venueName, errorText: _nameError),
            onChanged: (_) => setState(() {}),
          ),
          AppSpacing.fieldGap,
          TextField(
            key: const Key('venue-manual-address'),
            controller: _address,
            maxLines: 1,
            decoration: InputDecoration(labelText: TeamTexts.venueAddress, errorText: _addressError),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(TeamTexts.cancel)),
        TextButton(
          key: const Key('venue-manual-done'),
          onPressed: _done,
          child: const Text(TeamTexts.confirm),
        ),
      ],
    );
  }
}
