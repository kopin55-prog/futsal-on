import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/server_error.dart';
import '../../../shared/presentation/common_widgets.dart';
import '../../dashboard/domain/dashboard_models.dart' show DashboardRules;
import '../../injury/domain/injury_models.dart';
import '../../profile/presentation/profile_texts.dart';
import '../data/team_repository.dart' show sortMembers;
import '../domain/team_models.dart';
import 'team_texts.dart';

/// 팀원 탭 (스프린트 04 6-1, 기획서 11장, S4-14).
///
/// - 위에 "팀원 N명". 순서는 팀장 → 운영진 → 팀원, 각각 이름 가나다순.
/// - 한 줄: 이름, 역할 배지(팀장·운영진), 이름 옆 작은 "부상 2W" 표시, 한줄 자기소개.
///   부상 메모는 목록에 보이지 않는다 (홈 부상자·프로필 보기에서만). 선호 포지션·실력 등급도 목록에 없다.
/// - 누르면 프로필 보기. 선호 포지션·전문 골키퍼는 본인과 팀장·운영진만 본다 (Q-017, Entitlements 판단).
/// - 부상은 서버가 "지금 같은 팀 + 동의가 유효한 진행 중 부상"만 주고, 앱 표시 판단은 Entitlements(InjuryInfo).
class RosterTab extends StatefulWidget {
  const RosterTab({
    required this.services,
    required this.team,
    required this.viewer,
    this.now = DateTime.now,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;

  /// 남은 회복 기간 계산 기준 시각 (테스트에서 바꿔 끼운다)
  final DateTime Function() now;

  @override
  State<RosterTab> createState() => _RosterTabState();
}

class _RosterData {
  const _RosterData(this.members, this.injuries, this.today);

  /// 정렬된 팀원
  final List<MemberEntry> members;

  /// userId → 진행 중 부상. 부상 표시를 볼 수 있는 것만.
  final Map<String, Injury> injuries;

  /// 남은 회복 기간 계산 기준 (한국 날짜)
  final DateTime today;
}

class _RosterTabState extends State<RosterTab> {
  late Future<_RosterData> _data = _read();

  Future<_RosterData> _read() async {
    final s = widget.services;
    final members = sortMembers(await s.teams.listMembers(widget.team.id));
    final injuries = await s.injuries.listActiveInjuries([for (final m in members) m.userId]);
    final visible = <String, Injury>{
      for (final i in injuries)
        if (s.entitlements.canView(
          widget.viewer,
          InjuryInfo(subjectUserId: i.userId, subjectConsented: true, isActive: i.isActive),
        ))
          i.userId: i,
    };
    return _RosterData(members, visible, DashboardRules.todayKst(widget.now()));
  }

  Future<void> _reload() async {
    setState(() => _data = _read());
    await _data.then<void>((_) {}, onError: (Object _) {});
  }

  void _openMember(MemberEntry m, Injury? injury, DateTime today) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MemberProfileSheet(
        services: widget.services,
        viewer: widget.viewer,
        member: m,
        injury: injury,
        injuryWeeks: injury?.remainingWeeks(today),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RosterData>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            message: TeamTexts.loadFailed,
            actions: [TextButton(onPressed: _reload, child: const Text(TeamTexts.retry))],
          );
        }
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        final members = data.members;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxl),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: members.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SectionHeader(TeamTexts.memberCount(members.length), key: const Key('roster-count')),
                );
              }
              final m = members[i - 1];
              final injury = data.injuries[m.userId];
              final weeks = injury?.remainingWeeks(data.today);
              // 카드형 목록 (Q-079 1·2번): 한 사람 = 카드 한 장
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  child: ListTile(
                    key: Key('member-${m.userId}'),
                    leading: _Initial(name: m.displayName),
                    title: Row(
                      children: [
                        Flexible(child: Text(m.displayName, overflow: TextOverflow.ellipsis)),
                        if (m.role != TeamRole.member) ...[
                          const SizedBox(width: AppSpacing.sm),
                          RoleBadge(role: m.role),
                        ],
                        if (weeks != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          InjuryMark(weeks: weeks, key: Key('member-injury-${m.userId}')),
                        ],
                      ],
                    ),
                    subtitle: (m.bio == null || m.bio!.isEmpty)
                        ? null
                        : Text(m.bio!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _openMember(m, injury, data.today),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 이름 옆 작은 "부상 2W" 표시 (S4-14). 메모는 보이지 않는다.
class InjuryMark extends StatelessWidget {
  const InjuryMark({required this.weeks, super.key});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.error),
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.healing_outlined, size: 12, color: scheme.error),
          const SizedBox(width: 2),
          Text(
            TeamTexts.injuryMark(weeks),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.error),
          ),
        ],
      ),
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({required this.role, super.key});

  final TeamRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final owner = role == TeamRole.owner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: owner ? scheme.primary : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
      ),
      child: Text(
        TeamTexts.role(role),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: owner ? scheme.onPrimary : scheme.onSecondaryContainer),
      ),
    );
  }
}

/// 팀원 목록 왼쪽의 이름 첫 글자 원 (사진 없음, 모양만).
class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = name.characters.isEmpty ? '' : name.characters.first;
    return CircleAvatar(
      radius: 20,
      backgroundColor: scheme.surfaceContainerHighest,
      child: Text(
        first,
        style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 다른 팀원 프로필 보기. 수정은 본인만이고 "내 정보" 탭에서 한다 (Q-067 2번).
/// 진행 중 부상이 보이면 "부상 2W" + 메모 (S4-14: 메모는 프로필 보기·홈 부상자에서만).
class MemberProfileSheet extends StatelessWidget {
  const MemberProfileSheet({
    required this.services,
    required this.viewer,
    required this.member,
    this.injury,
    this.injuryWeeks,
    super.key,
  });

  final AppServices services;
  final Viewer viewer;
  final MemberEntry member;

  /// 볼 수 있는 진행 중 부상 (Entitlements 로 이미 거른 것)
  final Injury? injury;
  final int? injuryWeeks;

  @override
  Widget build(BuildContext context) {
    final canSeePrefs = services.entitlements.canView(viewer, PreferredPositionsInfo(subjectUserId: member.userId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(member.displayName, style: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(width: 8),
                if (member.role != TeamRole.member) RoleBadge(role: member.role),
              ],
            ),
            if (member.bio != null && member.bio!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(member.bio!),
            ],
            if (injuryWeeks case final weeks?) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                key: const Key('member-profile-injury'),
                children: [
                  InjuryMark(weeks: weeks),
                  if (injury?.memo case final memo? when memo.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(memo, key: const Key('member-profile-injury-memo'))),
                  ],
                ],
              ),
            ],
            if (canSeePrefs) ...[AppSpacing.fieldGap, _PrefsView(services: services, userId: member.userId)],
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _PrefsView extends StatelessWidget {
  const _PrefsView({required this.services, required this.userId});

  final AppServices services;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlayPrefs?>(
      future: services.teams.getPlayPrefs(userId).catchError((Object _) => null, test: (e) => e is ServerFailure),
      builder: (context, snap) {
        final prefs = snap.data;
        if (prefs == null) return const SizedBox.shrink();
        return Column(
          key: const Key('member-prefs'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(TeamTexts.positions),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              children: [
                for (final p in prefs.positions) Chip(label: Text(ProfileTexts.position(p))),
                if (prefs.isDedicatedGk) const Chip(label: Text(TeamTexts.dedicatedGk)),
              ],
            ),
          ],
        );
      },
    );
  }
}
