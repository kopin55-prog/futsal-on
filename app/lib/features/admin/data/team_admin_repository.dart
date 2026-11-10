import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../../../shared/domain/region.dart';
import '../../../shared/domain/venue.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/team_validation.dart';
import '../domain/match_settings.dart';
import '../domain/pairing_rules.dart';
import '../domain/skill_level.dart';

/// 팀 정보 수정에 보낼 값. [logoText] 가 null 이면 로고 글자는 건드리지 않는다
/// (이름이 바뀌면 서버 트리거가 Q-047 규칙으로 갱신). 로고 글자는 팀장만 보낼 수 있다.
class TeamInfoInput {
  const TeamInfoInput({
    required this.name,
    required this.schedule,
    required this.isRecruiting,
    this.venue,
    this.logoText,
    this.region,
  });

  final String name;
  final RegularSchedule schedule;
  final bool isRecruiting;

  /// 지정 풋살장. 항상 화면의 현재 값을 보낸다 (null = 없음, 지움).
  final Venue? venue;
  final String? logoText;

  /// 활동 지역. 항상 화면의 현재 값을 보낸다 (null = 없음, 지움).
  final Region? region;
}

/// 관리 탭의 팀 설정 (팀 정보·경기 설정·실력 등급·그룹·라이벌). 모두 서버 함수로 쓰고,
/// 서버가 권한(팀장·운영진, 로고 글자는 팀장)을 다시 확인한다. 실패는 모두 [ServerFailure].
abstract interface class TeamAdminRepository {
  Future<void> updateTeamInfo(String teamId, TeamInfoInput input);

  Future<MatchSettings> getMatchSettings(String teamId);

  Future<void> updateMatchSettings(String teamId, MatchSettings settings);

  /// 팀원별 실력 등급. 줄이 없는 사람은 목록에 없다(= 미정).
  Future<Map<String, SkillLevel>> listSkillLevels(String teamId);

  Future<void> setSkillLevel(String teamId, String userId, SkillLevel level);

  /// 여러 명 한 번에 같은 등급으로 (Q-079 3번 b). 서버가 단건과 같은 검사를 하고, 하나라도 어긋나면 아무것도 쓰지 않는다.
  Future<void> setSkillLevels(String teamId, List<String> userIds, SkillLevel level);

  Future<List<PairingRule>> listPairingRules(String teamId);

  /// 새로 만들기(rule.id == null)·고치기. 저장한 설정 ID.
  Future<String> savePairingRule(String teamId, PairingRule rule);

  Future<void> setPairingRuleEnabled(String ruleId, {required bool enabled});

  Future<void> deletePairingRule(String ruleId);
}

class SupabaseTeamAdminRepository implements TeamAdminRepository {
  SupabaseTeamAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> updateTeamInfo(String teamId, TeamInfoInput input) => guardServer(
    () => _client.rpc<void>(
      'update_team_info',
      params: {
        'p_team_id': teamId,
        'p_name': input.name,
        'p_regular_weekday': input.schedule.weekday,
        'p_regular_start_time': input.schedule.start?.hhmm,
        'p_regular_end_time': input.schedule.end?.hhmm,
        'p_is_recruiting': input.isRecruiting,
        'p_venue': input.venue?.toServerJson(),
        'p_logo_text': input.logoText,
        'p_region_sido': input.region?.sido,
        'p_region_sigungu': input.region?.sigungu,
      },
    ),
  );

  @override
  Future<MatchSettings> getMatchSettings(String teamId) => guardServer(() async {
    final row = await _client
        .from('team_settings')
        .select('capacity, rsvp_deadline_hours, auto_create_days_before, auto_create_time, rsvp_reminder_hours')
        .eq('team_id', teamId)
        .maybeSingle();
    if (row == null) return MatchSettings.defaults;
    return MatchSettings(
      capacity: row['capacity'] as int?,
      rsvpDeadlineHours: row['rsvp_deadline_hours'] as int,
      autoCreateDaysBefore: row['auto_create_days_before'] as int,
      autoCreateTime: ClockTime.parse(row['auto_create_time'] as String),
      rsvpReminderHours: row['rsvp_reminder_hours'] as int?,
    );
  });

  @override
  Future<void> updateMatchSettings(String teamId, MatchSettings s) => guardServer(
    () => _client.rpc<void>(
      'update_team_settings',
      params: {
        'p_team_id': teamId,
        'p_capacity': s.capacity,
        'p_rsvp_deadline_hours': s.rsvpDeadlineHours,
        'p_auto_create_days_before': s.autoCreateDaysBefore,
        'p_auto_create_time': s.autoCreateTime.hhmm,
        'p_rsvp_reminder_hours': s.rsvpReminderHours,
      },
    ),
  );

  @override
  Future<Map<String, SkillLevel>> listSkillLevels(String teamId) => guardServer(() async {
    final rows = await _client
        .from('skill_ratings')
        .select('user_id, level')
        .eq('team_id', teamId)
        .not('user_id', 'is', null);
    return {
      for (final r in rows)
        r['user_id'] as String: SkillLevel.fromServer(r['level'] as String?),
    };
  });

  @override
  Future<void> setSkillLevel(String teamId, String userId, SkillLevel level) => guardServer(
    () => _client.rpc<void>(
      'set_skill_level',
      params: {'p_team_id': teamId, 'p_user_id': userId, 'p_level': level.name},
    ),
  );

  @override
  Future<void> setSkillLevels(String teamId, List<String> userIds, SkillLevel level) => guardServer(
    () => _client.rpc<void>(
      'set_skill_levels',
      params: {'p_team_id': teamId, 'p_user_ids': userIds, 'p_level': level.name},
    ),
  );

  @override
  Future<List<PairingRule>> listPairingRules(String teamId) => guardServer(() async {
    final rows = await _client
        .from('pairing_rules')
        .select('id, kind, is_enabled, updated_at, pairing_rule_members(user_id)')
        .eq('team_id', teamId)
        .order('updated_at');
    return [
      for (final r in rows)
        PairingRule(
          id: r['id'] as String,
          kind: PairingKind.values.byName(r['kind'] as String),
          enabled: r['is_enabled'] as bool,
          userIds: [
            for (final m in r['pairing_rule_members'] as List)
              (m as Map<String, dynamic>)['user_id'] as String,
          ],
        ),
    ];
  });

  @override
  Future<String> savePairingRule(String teamId, PairingRule rule) => guardServer(
    () => _client.rpc<String>(
      'save_pairing_rule',
      params: {
        'p_team_id': teamId,
        'p_rule_id': rule.id,
        'p_kind': rule.kind.name,
        'p_user_ids': rule.userIds,
        'p_enabled': rule.enabled,
      },
    ),
  );

  @override
  Future<void> setPairingRuleEnabled(String ruleId, {required bool enabled}) => guardServer(
    () => _client.rpc<void>(
      'set_pairing_rule_enabled',
      params: {'p_rule_id': ruleId, 'p_enabled': enabled},
    ),
  );

  @override
  Future<void> deletePairingRule(String ruleId) => guardServer(
    () => _client.rpc<void>('delete_pairing_rule', params: {'p_rule_id': ruleId}),
  );
}
