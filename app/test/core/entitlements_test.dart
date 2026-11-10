import 'package:flutter_test/flutter_test.dart';
import 'package:futsal_on/core/entitlements/entitlements.dart';

void main() {
  const e = Entitlements();
  const owner = Viewer(userId: 'o', role: TeamRole.owner);
  const manager = Viewer(userId: 'm', role: TeamRole.manager);
  const member = Viewer(userId: 'u', role: TeamRole.member);
  const outsider = Viewer(userId: 'x', role: null);
  final allGrants = Grants(
    personalPlan: true,
    teamPlan: true,
    adUnlocks: {const AdUnlock(matchId: 'g1', category: VoteCategory.pom)},
  );

  group('행동 권한 (permissions.md 역할별 권한 표)', () {
    const staffOnly = {
      TeamAction.reviewJoinRequests,
      TeamAction.editTeamInfo,
      TeamAction.setSkillLevel,
      TeamAction.editMatchSettings,
      TeamAction.editAwardSettings,
      TeamAction.editGroupRivalRules,
      TeamAction.manageSchedule,
      TeamAction.manageLineup,
      TeamAction.copyShareImage,
    };
    const ownerOnly = {
      TeamAction.editLogoText,
      TeamAction.appointOrDismissManager,
      TeamAction.removeMember,
      TeamAction.transferOwnership,
      TeamAction.disbandTeam,
    };
    const everyone = {TeamAction.voteAttendance, TeamAction.voteAwards};
    const exceptOwner = {TeamAction.leaveTeam};

    test('모든 행동이 네 분류 중 하나에 들어 있다', () {
      expect({
        ...staffOnly,
        ...ownerOnly,
        ...everyone,
        ...exceptOwner,
      }, TeamAction.values.toSet());
    });

    test('팀 탈퇴: 팀장은 위임·해체 전 불가 (Q-037)', () {
      expect(e.canPerform(owner, TeamAction.leaveTeam), isFalse);
      expect(e.canPerform(manager, TeamAction.leaveTeam), isTrue);
      expect(e.canPerform(member, TeamAction.leaveTeam), isTrue);
      expect(e.canPerform(outsider, TeamAction.leaveTeam), isFalse);
    });

    test('관리 탭은 팀장·운영진만', () {
      expect(e.showAdminTab(owner), isTrue);
      expect(e.showAdminTab(manager), isTrue);
      expect(e.showAdminTab(member), isFalse);
      expect(e.showAdminTab(outsider), isFalse);
    });

    test('팀 식별코드는 팀원 전체 (Q-051)', () {
      expect(e.canViewTeamCode(member), isTrue);
      expect(e.canViewTeamCode(outsider), isFalse);
    });

    group('팀원 관리 메뉴 (3-3, Q-018)', () {
      Set<TeamAction> on(Viewer v, String target, TeamRole role) =>
          e.memberActions(v, targetUserId: target, targetRole: role);

      test('팀장: 팀원 → 운영진 지정·내보내기', () {
        expect(on(owner, 'u', TeamRole.member), {
          TeamAction.appointOrDismissManager,
          TeamAction.removeMember,
        });
      });
      test('팀장: 운영진 → 해제·위임·내보내기 (먼저 해제할 필요 없음)', () {
        expect(on(owner, 'm', TeamRole.manager), {
          TeamAction.appointOrDismissManager,
          TeamAction.transferOwnership,
          TeamAction.removeMember,
        });
      });
      test('자기 자신에게는 메뉴 없음', () {
        expect(on(owner, 'o', TeamRole.owner), isEmpty);
      });
      test('운영진·팀원은 메뉴 없음', () {
        expect(on(manager, 'u', TeamRole.member), isEmpty);
        expect(on(member, 'm', TeamRole.manager), isEmpty);
      });
      test('위임은 운영진에게만', () {
        expect(
          on(owner, 'u', TeamRole.member).contains(TeamAction.transferOwnership),
          isFalse,
        );
      });
    });

    for (final action in staffOnly) {
      test('$action: 팀장·운영진만', () {
        expect(e.canPerform(owner, action), isTrue);
        expect(e.canPerform(manager, action), isTrue);
        expect(e.canPerform(member, action), isFalse);
        expect(e.canPerform(outsider, action), isFalse);
      });
    }
    for (final action in ownerOnly) {
      test('$action: 팀장만', () {
        expect(e.canPerform(owner, action), isTrue);
        expect(e.canPerform(manager, action), isFalse);
        expect(e.canPerform(member, action), isFalse);
        expect(e.canPerform(outsider, action), isFalse);
      });
    }
    for (final action in everyone) {
      test('$action: 팀원 전체, 팀 밖은 불가', () {
        expect(e.canPerform(owner, action), isTrue);
        expect(e.canPerform(manager, action), isTrue);
        expect(e.canPerform(member, action), isTrue);
        expect(e.canPerform(outsider, action), isFalse);
      });
    }

    test('프로필(선호 포지션·전문 골키퍼) 수정은 본인만', () {
      expect(e.canEditProfile(member, subjectUserId: 'u'), isTrue);
      expect(e.canEditProfile(owner, subjectUserId: 'u'), isFalse);
      expect(e.canEditProfile(manager, subjectUserId: 'u'), isFalse);
    });
  });

  group('정보 공개 (permissions.md 정보별 공개 범위)', () {
    test('실력 등급: 팀장·운영진만, 팀원은 본인 것도 불가', () {
      const info = SkillLevelInfo(subjectUserId: 'u');
      expect(e.canView(owner, info), isTrue);
      expect(e.canView(manager, info), isTrue);
      expect(e.canView(member, info), isFalse);
      expect(e.canView(outsider, info), isFalse);
      expect(
        e.canView(member, const SkillLevelInfo(subjectUserId: 'other')),
        isFalse,
      );
    });

    test('실력 등급: 팀장·운영진은 본인 등급도 볼 수 있다 (Q-016)', () {
      expect(
        e.canView(owner, const SkillLevelInfo(subjectUserId: 'o')),
        isTrue,
      );
      expect(
        e.canView(manager, const SkillLevelInfo(subjectUserId: 'm')),
        isTrue,
      );
    });

    test('선호 포지션·전문 골키퍼: 다른 사람 것은 팀장·운영진만 (Q-017)', () {
      const info = PreferredPositionsInfo(subjectUserId: 'other');
      expect(e.canView(owner, info), isTrue);
      expect(e.canView(manager, info), isTrue);
      expect(e.canView(outsider, info), isFalse);
    });

    test('그룹·라이벌 설정, 배치 변경 이력, 게스트 포지션: 팀장·운영진만 (Q-017)', () {
      const infos = <Info>[
        GroupRivalSettingsInfo(),
        LineupChangeHistoryInfo(),
        GuestPositionInfo(),
      ];
      for (final info in infos) {
        expect(e.canView(owner, info), isTrue);
        expect(e.canView(manager, info), isTrue);
        expect(e.canView(member, info), isFalse);
        expect(e.canView(outsider, info), isFalse);
      }
    });

    test('로고 글자 변경은 팀장만, 나머지 팀 정보 수정은 팀장·운영진 (Q-014)', () {
      expect(e.canPerform(owner, TeamAction.editLogoText), isTrue);
      expect(e.canPerform(manager, TeamAction.editLogoText), isFalse);
      expect(e.canPerform(manager, TeamAction.editTeamInfo), isTrue);
    });

    test('선호 포지션: 다른 팀원은 볼 수 없다', () {
      const info = PreferredPositionsInfo(subjectUserId: 'other');
      expect(e.canView(member, info), isFalse);
      expect(
        e.canView(member, const PreferredPositionsInfo(subjectUserId: 'u')),
        isTrue,
      );
    });

    test('참석 명단: 팀원 전체', () {
      expect(e.canView(member, const AttendanceListInfo()), isTrue);
      expect(e.canView(outsider, const AttendanceListInfo()), isFalse);
    });

    test('투표 결과: 팀원 전체, 1위까지만', () {
      for (final c in VoteCategory.values) {
        expect(e.canView(member, VoteWinnerInfo(category: c)), isTrue);
        expect(e.voteResultMaxRank(member, c), 1);
        expect(e.voteResultMaxRank(owner, c), 1);
        expect(e.voteResultMaxRank(outsider, c), 0);
      }
    });

    test('득표수: 1차에서는 본인 것 포함 아무도 불가', () {
      for (final v in [owner, manager, member]) {
        expect(
          e.canView(
            v,
            VoteCountInfo(
              subjectUserId: v.userId,
              matchId: 'g1',
              category: VoteCategory.pom,
            ),
          ),
          isFalse,
        );
        expect(e.showVoteCountButton(v), isFalse);
      }
    });

    test('누가 누구를 찍었는지: 아무도 불가', () {
      for (final v in [owner, manager, member]) {
        expect(e.canView(v, const VoterChoiceInfo()), isFalse);
      }
    });

    test('부상: 동의하면 팀원 전체, 동의 전에는 본인만', () {
      const consented = InjuryInfo(subjectUserId: 'a', subjectConsented: true, isActive: true);
      const notConsented = InjuryInfo(
        subjectUserId: 'u',
        subjectConsented: false,
        isActive: true,
      );
      expect(e.canView(member, consented), isTrue);
      expect(e.canView(outsider, consented), isFalse);
      expect(e.canView(member, notConsented), isTrue); // 본인
      expect(e.canView(owner, notConsented), isFalse);
    });

    test('부상: 다른 사람은 진행 중인 것만, 본인 지난 기록도 1차 화면에는 안 보임 (2-7, S4-06 (4))', () {
      const othersPast = InjuryInfo(subjectUserId: 'a', subjectConsented: true, isActive: false);
      const myPast = InjuryInfo(subjectUserId: 'u', subjectConsented: true, isActive: false);
      for (final v in [owner, manager]) {
        expect(e.canView(v, othersPast), isFalse);
      }
      expect(e.canView(member, myPast), isFalse);
      // 내 진행 중 부상은 팀 소속과 무관하게 본인이 본다
      const myActive = InjuryInfo(subjectUserId: 'u', subjectConsented: true, isActive: true);
      expect(e.canView(const Viewer(userId: 'u', role: null), myActive), isTrue);
    });

    test('부상 등록·연장·회복·동의 철회 버튼: 본인만, 철회는 동의가 있을 때만', () {
      expect(e.canManageInjury(member, subjectUserId: 'u'), isTrue);
      expect(e.canManageInjury(owner, subjectUserId: 'u'), isFalse);
      expect(e.canWithdrawInjuryConsent(member, subjectUserId: 'u', hasConsent: true), isTrue);
      expect(e.canWithdrawInjuryConsent(member, subjectUserId: 'u', hasConsent: false), isFalse);
      expect(e.canWithdrawInjuryConsent(owner, subjectUserId: 'u', hasConsent: true), isFalse);
    });

    test('내 기록: 본인만 (팀장도 불가)', () {
      expect(
        e.canView(member, const PersonalRecordInfo(subjectUserId: 'u')),
        isTrue,
      );
      expect(
        e.canView(owner, const PersonalRecordInfo(subjectUserId: 'u')),
        isFalse,
      );
    });

    test('팀 리포트: 1차에서는 숨김', () {
      expect(e.canView(owner, const TeamReportInfo()), isFalse);
      expect(e.showTeamReportMenu(owner), isFalse);
    });
  });

  group('2차 등급 자리', () {
    test('1차에서는 등급이 있어도 판단이 바뀌지 않는다', () {
      final paidOwner = Viewer(
        userId: 'o',
        role: TeamRole.owner,
        grants: allGrants,
      );
      expect(
        e.canView(
          paidOwner,
          const VoteCountInfo(
            subjectUserId: 'o',
            matchId: 'g1',
            category: VoteCategory.pom,
          ),
        ),
        isFalse,
      );
      expect(e.voteResultMaxRank(paidOwner, VoteCategory.pom), 1);
      expect(e.showVoteCountButton(paidOwner), isFalse);
      expect(e.showTeamReportMenu(paidOwner), isFalse);
      expect(e.canView(paidOwner, const VoterChoiceInfo()), isFalse);
    });

    test('기본 등급은 none', () {
      expect(member.grants.personalPlan, isFalse);
      expect(member.grants.teamPlan, isFalse);
      expect(member.grants.adUnlocks, isEmpty);
    });

    test('AdUnlock은 경기·항목으로 같음을 판단한다', () {
      expect(
        const AdUnlock(matchId: 'g1', category: VoteCategory.pom),
        const AdUnlock(matchId: 'g1', category: VoteCategory.pom),
      );
      expect(
        const AdUnlock(matchId: 'g1', category: VoteCategory.pom) ==
            const AdUnlock(matchId: 'g1', category: VoteCategory.goalOfTheDay),
        isFalse,
      );
    });
  });
}
