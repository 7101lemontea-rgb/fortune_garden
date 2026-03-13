import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

// ─────────────────────────────────────────────────────────────────
// DB Provider — Riverpod으로 AppDatabase 싱글톤 관리
//
// 사용법:
//   final db = ref.watch(appDatabaseProvider);
//   final accounts = await db.watchAccountsByProfile(1).first;
// ─────────────────────────────────────────────────────────────────
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // Provider 소멸 시 DB 연결 해제
  ref.onDispose(db.close);
  return db;
});
