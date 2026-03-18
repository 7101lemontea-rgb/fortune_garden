// lib/domain/repositories/i_profile_repository.dart

import '../../data/database/app_database.dart';

/// 프로필 데이터 접근 추상 인터페이스.
/// UseCase는 이 인터페이스에만 의존하며,
/// 테스트 시 Mock으로 교체 가능.
abstract interface class IProfileRepository {
  /// 모든 프로필 목록 반환 (최대 2개).
  Future<List<Profile>> getAll();

  /// id로 특정 프로필 반환. 없으면 null.
  Future<Profile?> getById(int id);

  /// 프로필 삽입 또는 업데이트 (upsert).
  Future<void> upsert(ProfilesCompanion companion);

  /// 프로필 삭제. CASCADE로 accounts·transactions도 삭제됨.
  Future<void> delete(int id);
}
