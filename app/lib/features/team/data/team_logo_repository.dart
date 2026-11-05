import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/server_error.dart';
import '../domain/logo_image.dart';

/// 로고 사진 저장소 `team-logos` (Q-068 1번, data-model.md 3-1 끝 줄·13장 S-10).
///
/// 순서 규칙 (서버 정책: 지금 로고로 쓰이는 파일은 지울 수 없다):
/// - 바꾸기: 새 파일 올림 → teams.logo_image_path 를 새 경로로 → 이전 파일 삭제
/// - 지우기: teams.logo_image_path 비움 → 파일 삭제 (그러면 글자 로고)
/// - 팀 해체: 서버가 칸을 비운 뒤 해체 당시 관리자가 파일 삭제
/// 이전 파일 삭제가 실패해도 저장은 성공으로 본다. 남은 파일은 서버 함수 team-logo-cleanup 이 지운다.
abstract interface class TeamLogoRepository {
  /// [png] 를 올리고 팀 로고로 지정한다. 새 경로를 돌려준다. 실패는 [ServerFailure].
  Future<String> setLogo(String teamId, Uint8List png, {String? previousPath});

  /// 로고 사진을 지운다 (글자 로고로). 실패는 [ServerFailure].
  Future<void> removeLogo(String teamId, String currentPath);

  /// 파일만 지운다 (팀 해체 직후 등). 실패해도 조용히 넘어간다.
  Future<void> deleteFileQuietly(String path);
}

class SupabaseTeamLogoRepository implements TeamLogoRepository {
  SupabaseTeamLogoRepository(this._client);

  static const bucket = 'team-logos';

  final SupabaseClient _client;

  StorageFileApi get _files => _client.storage.from(bucket);

  @override
  Future<String> setLogo(String teamId, Uint8List png, {String? previousPath}) =>
      guardServer(() async {
        final path = LogoImageRules.newStoragePath(teamId);
        await _files.uploadBinary(
          path,
          png,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
        );
        try {
          await _client.from('teams').update({'logo_image_path': path}).eq('id', teamId);
        } catch (_) {
          await deleteFileQuietly(path);
          rethrow;
        }
        if (previousPath != null && previousPath != path) {
          await deleteFileQuietly(previousPath);
        }
        return path;
      });

  @override
  Future<void> removeLogo(String teamId, String currentPath) => guardServer(() async {
    await _client.from('teams').update({'logo_image_path': null}).eq('id', teamId);
    await deleteFileQuietly(currentPath);
  });

  @override
  Future<void> deleteFileQuietly(String path) async {
    try {
      await _files.remove([path]);
    } catch (_) {
      // 남은 파일은 team-logo-cleanup 이 정리한다.
    }
  }
}
