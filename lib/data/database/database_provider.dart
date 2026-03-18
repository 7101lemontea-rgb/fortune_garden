// lib/data/database/database_provider.dart
//
// Fortune Garden — Riverpod Provider (v1.1)
// AppDatabase 싱글톤을 앱 전체에 제공.
//
// 사용 예:
//   final db = ref.read(appDatabaseProvider);
//   final profile = await db.getParserProfile(institutionCode: 'KB');

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

// ─────────────────────────────────────────────────────────────
// 싱글톤 Provider
// ─────────────────────────────────────────────────────────────

/// AppDatabase 싱글톤 Provider.
///
/// - 앱 생명주기 동안 1개 인스턴스만 유지.
/// - 테스트 시 ProviderScope의 overrides로 인메모리 DB 주입 가능.
///
/// ```dart
/// // 테스트 오버라이드 예시
/// ProviderScope(
///   overrides: [
///     appDatabaseProvider.overrideWithValue(AppDatabase(inMemoryDatabase())),
///   ],
///   child: MyApp(),
/// )
/// ```
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();

  // Provider 소멸 시 DB 연결 해제
  ref.onDispose(db.close);

  return db;
});

// ─────────────────────────────────────────────────────────────
// 편의 Provider — 자주 쓰는 쿼리를 StreamProvider로 노출
// ─────────────────────────────────────────────────────────────

/// 모든 카테고리 목록 (Riverpod StreamProvider).
/// UI 레이어에서 ref.watch(categoriesStreamProvider)로 구독.
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.categories).watch();
});

/// 모든 활성 금융기관 목록 (is_active=1).
final activeInstitutionsProvider = StreamProvider<List<Institution>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.institutions)
        ..where((t) => t.isActive.equals(1))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

/// 모든 활성 CSV 파서 프로필 목록 (is_active=1).  ★ v1.1 신규
final activeCsvParserProfilesProvider =
    StreamProvider<List<CsvParserProfile>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.csvParserProfiles)
        ..where((t) => t.isActive.equals(1)))
      .watch();
});
