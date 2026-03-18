// lib/domain/repositories/i_category_repository.dart

import '../../data/database/app_database.dart';

/// 카테고리 및 자동 분류 규칙 데이터 접근 추상 인터페이스.
abstract interface class ICategoryRepository {
  /// 모든 카테고리 반환 (기본 11개 + 사용자 정의).
  Future<List<Category>> getAll();

  /// id로 특정 카테고리 반환. 없으면 null.
  Future<Category?> getById(int id);

  /// 카테고리 삽입 또는 업데이트 (upsert).
  Future<int> upsert(CategoriesCompanion companion);

  /// 카테고리 삭제.
  /// 해당 카테고리의 transactions.category_id는 SET NULL 처리됨.
  Future<void> delete(int id);

  /// 모든 자동 분류 규칙 반환.
  /// profileId가 null이면 공용 규칙, 값이 있으면 해당 프로필 규칙만.
  Future<List<CategoryRule>> getRules({int? profileId});

  /// 분류 규칙 삽입 또는 업데이트 (upsert).
  Future<int> upsertRule(CategoryRulesCompanion companion);

  /// 분류 규칙 삭제.
  Future<void> deleteRule(int id);
}
