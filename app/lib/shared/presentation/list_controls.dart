import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 목록 위 공용 조작 위젯 (Q-079 1·2번 디자인 개편, 3번 큰 팀 관리에서 이어 쓴다).
///
/// - [AppSearchField]: 이름 검색 칸 (돋보기 + 지우기 버튼, 48dp 이상).
/// - [FilterChipBar]: 위쪽 필터 칩 한 줄 (하나만 고름, 가로 스크롤).
/// 문구는 부르는 쪽이 넘긴다(이 파일에 화면 문구 없음).

/// 이름 검색 칸. 글자를 바꿀 때마다 [onChanged] (정리는 부르는 쪽, 예: shared/domain/name_search.dart).
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.clearTooltip,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  /// 지우기 버튼 설명 (화면 읽기용). 없으면 버튼 설명 없음.
  final String? clearTooltip;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        maxLines: 1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('search-clear'),
                  tooltip: widget.clearTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

/// 필터 칩 하나 (값 + 이름 + 선택 숫자).
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.count});

  final T value;
  final String label;

  /// 칩 뒤에 붙는 숫자 (예: "부상 2"). 없으면 이름만.
  final int? count;
}

/// 위쪽 필터 칩 한 줄. 하나만 고른다. 칸이 모자라면 가로로 민다.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'filter',
    super.key,
  });

  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// 칩 키: `<prefix>-<index>`
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            ChoiceChip(
              key: Key('$keyPrefix-$i'),
              label: Text(
                options[i].count == null ? options[i].label : '${options[i].label} ${options[i].count}',
              ),
              selected: options[i].value == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(options[i].value),
            ),
          ],
        ],
      ),
    );
  }
}
