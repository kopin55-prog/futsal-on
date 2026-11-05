import 'package:flutter/material.dart';

import '../../../core/app_services.dart';
import '../../../core/entitlements/entitlements.dart';
import '../../../shared/data/server_error.dart';
import '../../profile/presentation/profile_texts.dart';
import '../domain/team_models.dart';
import 'team_texts.dart';

/// 팀원 목록: 이름·역할 배지·자기소개. 누르면 프로필 보기.
/// 선호 포지션·전문 골키퍼는 본인과 팀장·운영진만 본다 (Q-017, Entitlements 판단).
class RosterTab extends StatefulWidget {
  const RosterTab({
    required this.services,
    required this.team,
    required this.viewer,
    super.key,
  });

  final AppServices services;
  final TeamSummary team;
  final Viewer viewer;

  @override
  State<RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends State<RosterTab> {
  late Future<List<MemberEntry>> _members = widget.services.teams.listMembers(widget.team.id);

  Future<void> _reload() async {
    setState(() => _members = widget.services.teams.listMembers(widget.team.id));
    await _members.catchError((_) => const <MemberEntry>[]);
  }

  void _openMember(MemberEntry m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MemberProfileSheet(
        services: widget.services,
        viewer: widget.viewer,
        member: m,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MemberEntry>>(
      future: _members,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: TextButton(onPressed: _reload, child: const Text(TeamTexts.retry)),
          );
        }
        final members = snap.data;
        if (members == null) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = members[i];
              return ListTile(
                key: Key('member-${m.userId}'),
                title: Row(
                  children: [
                    Flexible(child: Text(m.displayName, overflow: TextOverflow.ellipsis)),
                    if (m.role != TeamRole.member) ...[
                      const SizedBox(width: 8),
                      RoleBadge(role: m.role),
                    ],
                  ],
                ),
                subtitle: (m.bio == null || m.bio!.isEmpty) ? null : Text(m.bio!),
                onTap: () => _openMember(m),
              );
            },
          ),
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: owner ? scheme.primary : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        TeamTexts.role(role),
        style: TextStyle(
          fontSize: 12,
          color: owner ? scheme.onPrimary : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 다른 팀원 프로필 보기. 수정은 본인만이고 "내 정보" 탭에서 한다 (Q-067 2번).
class MemberProfileSheet extends StatelessWidget {
  const MemberProfileSheet({
    required this.services,
    required this.viewer,
    required this.member,
    super.key,
  });

  final AppServices services;
  final Viewer viewer;
  final MemberEntry member;

  @override
  Widget build(BuildContext context) {
    final canSeePrefs = services.entitlements.canView(
      viewer,
      PreferredPositionsInfo(subjectUserId: member.userId),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    member.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 8),
                if (member.role != TeamRole.member) RoleBadge(role: member.role),
              ],
            ),
            if (member.bio != null && member.bio!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(member.bio!),
            ],
            if (canSeePrefs) ...[
              const SizedBox(height: 16),
              _PrefsView(services: services, userId: member.userId),
            ],
            const SizedBox(height: 8),
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
      future: services.teams.getPlayPrefs(userId).catchError(
        (Object _) => null,
        test: (e) => e is ServerFailure,
      ),
      builder: (context, snap) {
        final prefs = snap.data;
        if (prefs == null) return const SizedBox.shrink();
        return Column(
          key: const Key('member-prefs'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TeamTexts.positions, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
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
