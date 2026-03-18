// lib/application/profile/view_mode_use_case.dart
//
// SAD v1.1 §4.2 — ViewModeUseCase
// 개인 뷰 / 통합 뷰 전환 상태 관리.
// app_settings DB에 영속 저장.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../../domain/entities/view_mode.dart';

// ── Provider ──────────────────────────────────────────
final viewModeUseCaseProvider = Provider<ViewModeUseCase>((ref) {
  return ViewModeUseCase(ref.read(settingsRepositoryProvider));
});

// ── UseCase ───────────────────────────────────────────
class ViewModeUseCase {
  const ViewModeUseCase(this._settingsRepo);
  final ISettingsRepository _settingsRepo;

  static const _key = 'default_view_mode';

  /// 현재 뷰 모드 반환. 기본값: combined.
  Future<ViewMode> getMode() async {
    final val = await _settingsRepo.get(_key, defaultValue: 'combined');
    return ViewMode.fromString(val ?? 'combined');
  }

  /// 뷰 모드 저장.
  Future<void> setMode(ViewMode mode) =>
      _settingsRepo.set(_key, mode.value);
}
