// lib/data/repositories/category_repository.dart

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../domain/repositories/i_category_repository.dart';

class CategoryRepository implements ICategoryRepository {
  const CategoryRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Category>> getAll() =>
      (_db.select(_db.categories)
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  @override
  Future<Category?> getById(int id) =>
      (_db.select(_db.categories)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<int> upsert(CategoriesCompanion companion) =>
      _db.into(_db.categories).insertOnConflictUpdate(companion);

  @override
  Future<void> delete(int id) {
    // ※ categories.parentId 자기 참조는 Drift가 FK 처리 미지원.
    //   상위 카테고리 삭제 전 하위 카테고리의 parentId를 NULL로 초기화.
    return _db.transaction(() async {
      // 하위 카테고리 parentId → NULL
      await (_db.update(_db.categories)
            ..where((t) => t.parentId.equals(id)))
          .write(const CategoriesCompanion(parentId: Value(null)));

      // 카테고리 삭제 (transactions.category_id는 DB FK SET NULL 처리)
      await (_db.delete(_db.categories)
            ..where((t) => t.id.equals(id)))
          .go();
    });
  }

  @override
  Future<List<CategoryRule>> getRules({int? profileId}) {
    final query = _db.select(_db.categoryRules);

    if (profileId != null) {
      // 해당 프로필 규칙 + 공용 규칙(NULL) 모두 반환
      query.where((t) =>
          t.profileId.equals(profileId) | t.profileId.isNull());
    }

    query.orderBy([
      (t) => OrderingTerm.desc(t.priority),
    ]);

    return query.get();
  }

  @override
  Future<int> upsertRule(CategoryRulesCompanion companion) =>
      _db.into(_db.categoryRules).insertOnConflictUpdate(companion);

  @override
  Future<void> deleteRule(int id) =>
      (_db.delete(_db.categoryRules)
            ..where((t) => t.id.equals(id)))
          .go();
}
