import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../../auth/domain/signup_consent.dart';
import '../domain/profile_validation.dart';

/// 프로필 조회·만들기. 만들기는 서버 함수 하나(create_profile)가 프로필·선호 포지션·동의 기록을 함께 만든다
/// (data-model.md 2-2, 8-1).
abstract interface class ProfileRepository {
  /// 로그인한 본인의 프로필이 있는지 (없으면 가입 단계부터, Q-010).
  Future<bool> hasOwnProfile();

  /// 가입 단계 마무리. 실패하면 [ServerFailure].
  Future<void> createProfile(ProfileInput input, SignupConsent consent);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> hasOwnProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final row = await _client
          .from('profiles')
          .select('user_id')
          .eq('user_id', uid)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (e) {
      throw ServerFailure(ServerErrorCode.fromCode(e.message));
    } catch (_) {
      throw const ServerFailure(ServerErrorCode.unknown);
    }
  }

  @override
  Future<void> createProfile(ProfileInput input, SignupConsent consent) async {
    final normalized = input.normalized();
    try {
      await _client.rpc<void>(
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
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(ServerErrorCode.fromCode(e.message));
    } catch (_) {
      throw const ServerFailure(ServerErrorCode.unknown);
    }
  }
}
