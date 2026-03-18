// lib/application/category/category_classify_use_case.dart
//
// SAD v1.1 §4.2 — CategoryClassifyUseCase
// 거래처명으로 category_rules 테이블 조회 후 카테고리 반환.
// 개인 규칙 우선, 공용 규칙(profile_id IS NULL) 폴백.
// DB ERD v1.1 §6.3 쿼리 패턴 기준.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/repositories/i_category_repository.dart';

// ── Provider ──────────────────────────────────────────
final categoryClassifyUseCaseProvider =
    Provider<CategoryClassifyUseCase>((ref) {
  return CategoryClassifyUseCase(ref.read(categoryRepositoryProvider));
});

// ── UseCase ───────────────────────────────────────────
class CategoryClassifyUseCase {
  const CategoryClassifyUseCase(this._categoryRepo);
  final ICategoryRepository _categoryRepo;

  /// [merchant] 거래처명을 category_rules에서 LIKE 검색.
  /// 개인 규칙([profileId]) 우선, 공용 규칙(NULL) 폴백.
  /// 반환: 매칭된 categoryId, 없으면 null (미분류).
  Future<int?> classify({
    required String merchant,
    required int profileId,
  }) async {
    // 개인 규칙 + 공용 규칙 모두 가져온 뒤 우선순위 정렬
    final rules = await _categoryRepo.getRules(profileId: profileId);

    // LIKE 매칭: merchant 문자열이 keyword를 포함하는지 확인
    // 개인 규칙(profileId != null)을 먼저, priority 내림차순
    final sorted = [...rules]
      ..sort((a, b) {
        // 개인 규칙 우선
        final aIsPersonal = a.profileId != null ? 1 : 0;
        final bIsPersonal = b.profileId != null ? 1 : 0;
        if (aIsPersonal != bIsPersonal) return bIsPersonal - aIsPersonal;
        // priority 내림차순
        return b.priority.compareTo(a.priority);
      });

    for (final rule in sorted) {
      if (merchant.contains(rule.keyword)) {
        return rule.categoryId;
      }
    }
    return null; // 미분류
  }

  /// 모든 카테고리 반환 (UI 선택용).
  Future<List<Category>> getAllCategories() =>
      _categoryRepo.getAll();
}
