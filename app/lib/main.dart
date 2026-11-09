import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_services.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/data/team_admin_repository.dart';
import 'features/auth/data/account_repository.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/auth/presentation/auth_texts.dart';
import 'features/membership/data/membership_repository.dart';
import 'features/notifications/data/notification_repository.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/team/data/logo_picker.dart';
import 'features/team/data/recent_team_store.dart';
import 'features/team/data/team_logo_repository.dart';
import 'features/team/data/team_repository.dart';
import 'features/team/presentation/team_home_screen.dart';
import 'features/team/presentation/team_logo.dart';
import 'features/venue/data/place_search_repository.dart';

/// 풋살ON 앱 진입점.
///
/// 실행: flutter run --dart-define-from-file=config/dev.json
/// (config/dev.json 은 dart run tool/make_dev_config.dart 로 만든다. git 제외.)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig.fromEnvironment();
  if (!config.isComplete) {
    runApp(ConfigMissingApp(missingKeys: config.missingKeys));
    return;
  }

  KakaoSdk.init(nativeAppKey: config.kakaoNativeAppKey);
  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseAnonKey,
  );
  final client = Supabase.instance.client;

  runApp(
    FutsalOnApp(
      authRepository: SupabaseAuthRepository(
        client: client,
        googleServerClientId: config.googleWebClientId,
      ),
      services: AppServices(
        profiles: SupabaseProfileRepository(client),
        teams: SupabaseTeamRepository(client),
        membership: SupabaseMembershipRepository(client),
        accounts: SupabaseAccountRepository(client),
        recentTeams: SharedPrefsRecentTeamStore(),
        admin: SupabaseTeamAdminRepository(client),
        logos: SupabaseTeamLogoRepository(client),
        logoPicker: DeviceLogoPicker(),
        places: SupabasePlaceSearchRepository(client),
        notifications: SupabaseNotificationRepository(client),
      ),
      logoImages: (path) => _logoImage(client, config, path),
    ),
  );
}

/// 로고 사진은 비공개 저장소라 로그인한 사람의 인증 헤더로 받는다 (Q-068 1번).
ImageProvider? _logoImage(SupabaseClient client, AppConfig config, String path) {
  final token = client.auth.currentSession?.accessToken;
  if (token == null) return null;
  return NetworkImage(
    '${config.supabaseUrl}/storage/v1/object/authenticated/${SupabaseTeamLogoRepository.bucket}/$path',
    headers: {'Authorization': 'Bearer $token', 'apikey': config.supabaseAnonKey},
  );
}

class FutsalOnApp extends StatelessWidget {
  const FutsalOnApp({
    required this.authRepository,
    required this.services,
    this.logoImages,
    super.key,
  });

  final AuthRepository authRepository;
  final AppServices services;

  /// 로고 사진 경로 → 이미지 (없으면 글자 로고만)
  final ImageProvider? Function(String path)? logoImages;

  @override
  Widget build(BuildContext context) {
    final images = logoImages;
    return MaterialApp(
      title: AuthTempTexts.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: images == null
          ? null
          : (context, child) => TeamLogoImages(resolve: images, child: child!),
      home: AuthGate(
        authRepository: authRepository,
        profileRepository: services.profiles,
        homeBuilder: (userId, signOut) => TeamHomeScreen(
          key: ValueKey(userId),
          services: services,
          userId: userId,
          onSignOut: signOut,
        ),
      ),
    );
  }
}
/// 설정값 없이 실행했을 때 (개발용).
class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({required this.missingKeys, super.key});

  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '${AuthTempTexts.configMissing}\n${missingKeys.join(', ')}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
