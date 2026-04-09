// lib/presentation/providers/category_rule_providers.dart
//
// SCR-009 카테고리 규칙 화면용 Provider 모음.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../data/database/app_database.dart';

/// 전체 카테고리 목록 (규칙 폼의 카테고리 선택 드롭다운용)
final allCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).getAll();
});

/// 전체 분류 규칙 목록 (공용 + 모든 프로필)
/// profileId 필터 없이 전체를 가져와 화면에서 뱃지로 구분.
final categoryRulesProvider = FutureProvider<List<CategoryRule>>((ref) {
  return ref.watch(categoryRepositoryProvider).getRules();
});
