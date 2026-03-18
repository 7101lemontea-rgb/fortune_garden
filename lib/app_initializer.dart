// lib/app_initializer.dart
//
// 앱 최초 실행 시 필요한 초기화 작업을 담당.
// main.dart를 단순하게 유지하기 위해 분리.
//
// 호출 순서:
//   1. DB 열기 (Riverpod Provider가 처리)
//   2. 금융기관 코드 Seed 삽입
//   3. CSV 파서 프로필 Seed 삽입

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/database_provider.dart';
import 'data/database/seed_institutions.dart';

/// 앱 시작 시 1회 실행되는 초기화 함수.
/// ProviderContainer를 받아 DB에 접근한다.
Future<void> initializeApp(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);

  // 금융기관 코드 20개 upsert (중복 실행 안전)
  await seedInstitutions(db);

  // CSV 파서 프로필 기본값 upsert (중복 실행 안전)
  await seedCsvParserProfiles(db);
}
