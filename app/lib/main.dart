import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_services.dart';
import 'core/config/app_config.dart';
import 'features/admin/data/team_admin_repository.dart';
import 'features/auth/data/account_repository.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/auth/presentation/auth_texts.dart';
import 'features/membership/data/membership_repository.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/team/data/recent_team_store.dart';
import 'features/team/data/team_repository.dart';
import 'features/team/presentation/team_home_screen.dart';

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
      ),
    ),
  );
}

class FutsalOnApp extends StatelessWidget {
  const FutsalOnApp({
    required this.authRepository,
    required this.services,
    super.key,
  });

  final AuthRepository authRepository;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AuthTempTexts.appTitle,
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
