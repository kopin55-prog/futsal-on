import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../domain/region.dart';

/// 시·도 → 시·군·구 고르기 (공용 위젯). 팀 만들기·팀 정보 수정의 활동 지역, 팀 찾기의 지역 필터가 같이 쓴다.
///
/// - 시·도를 고르기 전에는 시·군·구를 고를 수 없다. 시·도를 바꾸면 시·군·구는 비운다.
/// - [emptyLabel]: 아무것도 고르지 않은 상태의 이름 (필터는 "전체", 입력은 "선택 안 함").
/// - 바깥에서 값을 바꾸면(예: 구장 주소로 자동 채움) 그대로 보인다.
/// - 시·군·구가 없는 시·도(세종)는 시·군·구 칸을 끈다.
class RegionPicker extends StatelessWidget {
  const RegionPicker({
    required this.value,
    required this.onChanged,
    required this.emptyLabel,
    required this.sidoLabel,
    required this.sigunguLabel,
    this.enabled = true,
    this.keyPrefix = 'region',
    super.key,
  });

  final Region? value;
  final ValueChanged<Region?> onChanged;
  final String emptyLabel;
  final String sidoLabel;
  final String sigunguLabel;
  final bool enabled;

  /// 테스트·접근성용 키 앞부분 (`<prefix>-sido`, `<prefix>-sigungu`)
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final sido = value?.sido;
    final options = KoreaRegions.sigunguOf(sido);
    final sigungu = options.contains(value?.sigungu) ? value?.sigungu : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: KeyedSubtree(
            key: ValueKey('$keyPrefix-sido-$sido'),
            child: DropdownButtonFormField<String?>(
              key: Key('$keyPrefix-sido'),
              initialValue: sido,
              isExpanded: true,
              decoration: InputDecoration(labelText: sidoLabel),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
                for (final s in KoreaRegions.sidoList) DropdownMenuItem<String?>(value: s, child: Text(s)),
              ],
              onChanged: enabled ? (v) => onChanged(v == null ? null : Region(v)) : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          child: KeyedSubtree(
            key: ValueKey('$keyPrefix-sigungu-$sido-$sigungu'),
            child: DropdownButtonFormField<String?>(
              key: Key('$keyPrefix-sigungu'),
              initialValue: sigungu,
              isExpanded: true,
              decoration: InputDecoration(labelText: sigunguLabel),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
                for (final s in options)
                  DropdownMenuItem<String?>(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: enabled && sido != null && options.isNotEmpty
                  ? (v) => onChanged(Region(sido, v))
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
