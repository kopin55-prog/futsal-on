import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../../../shared/domain/position.dart';
import '../../auth/domain/signup_consent.dart';
import '../domain/profile_validation.dart';

/// 내 프로필 (이름·자기소개·선호 포지션·전문 골키퍼).
class OwnProfile {
  const OwnProfile({
    required this.displayName,
    required this.positions,
    required this.isDedicatedGk,
    this.bio,
  });

  final String displayName;
  final String? bio;
  final List<Position> positions;
  final bool isDedicatedGk;
}

/// 프로필 조회·만들기·수정. 만들기는 서버 함수 하나(create_profile)가 프로필·선호 포지션·동의 기록을 함께 만든다
/// (data-model.md 2-2, 8-1). 수정은 본인만 (표의 권한 규칙, Q-067 2번: 남의 프로필은 고칠 수 없음).
abstract interface class ProfileRepository {
  /// 로그인한 본인의 프로필이 있는지 (없으면 가입 단계부터, Q-010).
  Future<bool> hasOwnProfile();

  /// 가입 단계 마무리. 실패하면 [ServerFailure].
  Future<void> createProfile(ProfileInput input, SignupConsent consent);

  /// 내 프로필. 실패하면 [ServerFailure].
  Future<OwnProfile> getOwnProfile();

  /// 내 프로필 수정. 실패하면 [ServerFailure].
  Future<void> updateOwnProfile(ProfileInput input);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const ServerFailure(ServerErrorCode.notAuthenticated);
    return id;
  }

  @override
  Future<bool> hasOwnProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    return guardServer(() async {
      final row = await _client
          .from('profiles')
          .select('user_id')
          .eq('user_id', uid)
          .maybeSingle();
      return row != null;
    });
  }

  @override
  Future<void> createProfile(ProfileInput input, SignupConsent consent) {
    final normalized = input.normalized();
    return guardServer(
      () => _client.rpc<void>(
        'create_profile',
        params: {
          'p_display_name': normalized.name,
          'p_bio': normalized.bio,
          'p_positions': [for (final p in normalized.positions) p.name],
          'p_is_dedicated_gk': normalized.isDedicatedGk,
          'p_age_14_confirmed': consent.age14,
          'p_terms_agreed': consent.terms,
          'p_privacy_agreed': consent.privacy,
          'p_injury_info_agreed': consent.injuryInfo,
        },
      ),
    );
  }

  @override
  Future<OwnProfile> getOwnProfile() => guardServer(() async {
    final uid = _uid;
    final profile = await _client
        .from('profiles')
        .select('display_name, bio')
        .eq('user_id', uid)
        .single();
    final prefs = await _client
        .from('profile_play_prefs')
        .select('positions, is_dedicated_gk')
        .eq('user_id', uid)
        .single();
    return OwnProfile(
      displayName: profile['display_name'] as String,
      bio: profile['bio'] as String?,
      positions: [
        for (final p in prefs['positions'] as List) Position.values.byName(p as String),
      ],
      isDedicatedGk: prefs['is_dedicated_gk'] as bool,
    );
  });

  /// 이름·자기소개와 선호 포지션·전문 골키퍼를 서버 함수 하나(update_own_profile)로 한 번에 저장한다.
  /// 둘 중 하나만 저장되는 일이 없다 (202611050015). 실패 코드: invalid_profile / invalid_positions.
  @override
  Future<void> updateOwnProfile(ProfileInput input) {
    final normalized = input.normalized();
    return guardServer(
      () => _client.rpc<void>(
        'update_own_profile',
        params: {
          'p_display_name': normalized.name,
          'p_bio': normalized.bio,
          'p_positions': [for (final p in normalized.positions) p.name],
          'p_is_dedicated_gk': normalized.isDedicatedGk,
        },
      ),
    );
  }
}
