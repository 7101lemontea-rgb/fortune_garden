// lib/app_initializer.dart
//
// 앱 시작 시 1회 실행되는 초기화 함수.
// main.dart를 단순하게 유지하기 위해 분리.
//
// 호출 순서:
//   1. 금융기관 코드 Seed
//   2. CSV 파서 프로필 Seed
//   3. [kDebugMode 전용] 임시 프로필·계좌 Seed

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/database_provider.dart';
import 'data/database/seed_institutions.dart';
import 'data/database/seed_dev_data.dart';

/// 앱 시작 시 1회 실행되는 초기화 함수.
Future<void> initializeApp(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);

  // 금융기관 코드 20개 upsert
  await seedInstitutions(db);

  // CSV 파서 프로필 기본값 upsert
  await seedCsvParserProfiles(db);

  // 개발 모드 전용: 임시 프로필 2개 + 계좌 4개 생성
  // 이미 데이터가 있으면 자동으로 건너뜀
  if (kDebugMode) {
    await seedDevData(db);
  }
}
