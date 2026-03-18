// lib/application/profile/profile_use_case.dart
//
// SAD v1.1 §4.2 — ProfileUseCase
// 활성 프로필 전환 및 프로필 CRUD.

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_profile_repository.dart';
import '../../domain/repositories/i_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Provider ──────────────────────────────────────────
final profileUseCaseProvider = Provider<ProfileUseCase>((ref) {
  return ProfileUseCase(
    profileRepo:  ref.read(profileRepositoryProvider),
    settingsRepo: ref.read(settingsRepositoryProvider),
  );
});

// ── UseCase ───────────────────────────────────────────
class ProfileUseCase {
  const ProfileUseCase({
    required IProfileRepository profileRepo,
    required ISettingsRepository settingsRepo,
  })  : _profileRepo  = profileRepo,
        _settingsRepo = settingsRepo;

  final IProfileRepository  _profileRepo;
  final ISettingsRepository _settingsRepo;

  // ── 조회 ──────────────────────────────────────────

  /// 모든 프로필 반환.
  Future<List<Profile>> getAll() => _profileRepo.getAll();

  /// 현재 활성 프로필 반환.
  /// app_settings의 active_profile_id 기준.
  Future<Profile?> getActiveProfile() async {
    final idStr = await _settingsRepo.get(
      'active_profile_id',
      defaultValue: '1',
    );
    final id = int.tryParse(idStr ?? '1') ?? 1;
    return _profileRepo.getById(id);
  }

  // ── 전환 ──────────────────────────────────────────

  /// 활성 프로필 전환.
  Future<void> switchProfile(int id) =>
      _settingsRepo.set('active_profile_id', id.toString());

  // ── CRUD ──────────────────────────────────────────

  /// 프로필 생성 또는 수정.
  Future<void> upsert({
    required int id,
    required String name,
    required String colorHex,
    String defaultViewMode = 'personal',
  }) =>
      _profileRepo.upsert(ProfilesCompanion(
        id:              Value(id),
        name:            Value(name),
        colorHex:        Value(colorHex),
        defaultViewMode: Value(defaultViewMode),
        createdAt:       Value(DateTime.now().millisecondsSinceEpoch),
      ));

  /// 프로필 삭제.
  Future<void> delete(int id) => _profileRepo.delete(id);
}
