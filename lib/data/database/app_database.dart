// lib/data/database/app_database.dart
//
// Fortune Garden — AppDatabase (v1.1)
// SAD v1.1 · DB ERD v1.1 기준
//
// 변경 이력:
//   v1.0 → v1.1 (2026-03-16)
//     - tables 목록에서 SyncHistory 제거
//     - CsvParserProfiles, ImportHistory 추가 (9개 테이블)
//     - 핵심 쿼리: 4개 → 6개
//       · getParserProfile()    신규 (ERD 6.5)
//       · getImportHistory()    신규 (ERD 6.6)
//     - Seed data: auto_sync_enabled 제거 (7개 설정)
//     - _seedData: SyncHistory 관련 로직 제거

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────────────────────
// AppDatabase
// ─────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    Profiles,           // 1. 사용자 프로필
    Institutions,       // 2. 금융기관 코드 마스터
    Accounts,           // 3. 금융기관 계좌
    Categories,         // 4. 카테고리 마스터
    Transactions,       // 5. 거래 내역
    CategoryRules,      // 6. 자동 분류 규칙
    CsvParserProfiles,  // 7. CSV 파서 프로필  ★ v1.1 신규
    ImportHistory,      // 8. CSV 가져오기 이력  ★ v1.1 신규
    AppSettings,        // 9. 앱 전역 설정
  ],
  // ERD v1.1 §5 인덱스 전략 — @Index로 선언
  // (DriftDatabase 어노테이션에서 뷰/트리거 확장 시 views: 파라미터 추가)
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// DB 스키마 버전 — 마이그레이션 분기 기준
  @override
  int get schemaVersion => 2; // v1.1: 9개 테이블

  // ── 마이그레이션 ────────────────────────────────────────────
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedData();
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2: csv_parser_profiles, import_history 추가
          //           sync_history 제거, profiles.connected_id_enc 제거
          if (from < 2) {
            // sync_history 테이블 제거
            await m.database.customStatement('DROP TABLE IF EXISTS sync_history');

            // profiles에서 connected_id_enc 컬럼 제거
            // SQLite ALTER TABLE DROP COLUMN은 3.35.0+ 에서만 지원.
            // 하위 호환을 위해 recreate 방식 사용.
            await m.recreateAllViews();
            await m.addColumn(
              profiles,
              // 이미 없는 컬럼이면 무시; 있으면 skip
              profiles.defaultViewMode,
            ).catchError((_) {}); // 이미 존재 시 무시

            // 신규 테이블 생성
            await m.createTable(csvParserProfiles);
            await m.createTable(importHistory);

            // 인덱스 신규 추가
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_import_account_date '
              'ON import_history (account_id, imported_at DESC)',
            );
            await m.database.customStatement(
              'CREATE INDEX IF NOT EXISTS idx_parser_institution '
              'ON csv_parser_profiles (institution_code)',
            );
          }
        },
        beforeOpen: (details) async {
          // WAL 모드 활성화 (읽기·쓰기 동시성 최대화)
          await customStatement('PRAGMA journal_mode=WAL');
          // FK 제약 활성화
          await customStatement('PRAGMA foreign_keys=ON');
        },
      );

  // ════════════════════════════════════════════════════════════
  // ▣  핵심 쿼리 (ERD v1.1 §6)
  // ════════════════════════════════════════════════════════════

  // ── 6.1 개인 뷰 — 월별 수입/지출 합계 ─────────────────────
  /// [profileId] 프로필의 [monthStart] ~ [monthEnd] 기간 수입/지출 합계.
  /// 반환: ({int income, int expense})
  Future<({int income, int expense})> getMonthlySummary({
    required int profileId,
    required int monthStart,
    required int monthEnd,
  }) async {
    final result = await customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE profile_id = :profileId
        AND txn_date >= :monthStart
        AND txn_date  < :monthEnd
      ''',
      variables: [
        Variable.withInt(profileId),
        Variable.withInt(monthStart),
        Variable.withInt(monthEnd),
      ],
      readsFrom: {transactions},
    ).getSingle();

    return (
      income:  result.read<int>('income'),
      expense: result.read<int>('expense'),
    );
  }

  // ── 6.2 통합 뷰 — 두 프로필 합산 대시보드 ─────────────────
  /// 두 프로필의 수입/지출을 profile_id로 GROUP BY하여 반환.
  /// 반환: [{name, color_hex, income, expense}]
  Future<List<QueryRow>> getCombinedDashboard({
    required int monthStart,
    required int monthEnd,
  }) {
    return customSelect(
      '''
      SELECT
        p.name,
        p.color_hex,
        COALESCE(SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END), 0) AS expense
      FROM transactions t
      JOIN profiles p ON t.profile_id = p.id
      WHERE t.txn_date >= :monthStart
        AND t.txn_date  < :monthEnd
      GROUP BY t.profile_id
      ORDER BY p.id
      ''',
      variables: [
        Variable.withInt(monthStart),
        Variable.withInt(monthEnd),
      ],
      readsFrom: {transactions, profiles},
    ).get();
  }

  // ── 6.3 카테고리 자동 분류 ─────────────────────────────────
  /// [merchant] 거래처명을 category_rules에서 LIKE 검색.
  /// 개인 규칙([profileId]) 우선, 공용 규칙(NULL) 폴백.
  /// 반환: 매칭된 categoryId 또는 null (미분류)
  Future<int?> matchCategory({
    required String merchant,
    required int profileId,
  }) async {
    final result = await customSelect(
      '''
      SELECT category_id
      FROM category_rules
      WHERE :merchant LIKE '%' || keyword || '%'
        AND (profile_id = :profileId OR profile_id IS NULL)
      ORDER BY (profile_id IS NOT NULL) DESC, priority DESC
      LIMIT 1
      ''',
      variables: [
        Variable.withString(merchant),
        Variable.withInt(profileId),
      ],
      readsFrom: {categoryRules},
    ).getSingleOrNull();

    return result?.read<int?>('category_id');
  }

  // ── 6.4 중복 거래 방지 INSERT ──────────────────────────────
  /// txnHash UNIQUE 제약 활용. 충돌 시 기존 레코드 유지(무시).
  /// CSV 가져오기 시 매 거래에 적용.
  Future<void> insertTransactionIfNotExists(
    TransactionsCompanion entry,
  ) async {
    await into(transactions).insertOnConflictUpdate(entry);
    // insertOnConflictUpdate는 txn_hash 충돌 시 아무것도 변경하지 않음
    // (DoNothing 전략을 쓰려면 아래 방식도 가능)
    // await into(transactions).insert(entry, mode: InsertMode.insertOrIgnore);
  }

  // ── 6.5 파서 프로필 자동 매칭  ★ v1.1 신규 ────────────────
  /// [institutionCode] 기준으로 활성화된 CSV 파서 프로필 반환.
  /// SCR-008 CSV 가져오기 화면에서 계좌 선택 시 자동 호출.
  Future<CsvParserProfile?> getParserProfile({
    required String institutionCode,
  }) {
    return (select(csvParserProfiles)
          ..where((t) =>
              t.institutionCode.equals(institutionCode) &
              t.isActive.equals(1))
          ..limit(1))
        .getSingleOrNull();
  }

  // ── 6.6 계좌별 가져오기 이력 조회  ★ v1.1 신규 ───────────
  /// [accountId] 계좌의 가져오기 이력을 최신 순으로 반환.
  /// SCR-007 계좌 관리 화면 ImportHistoryList에서 사용.
  Future<List<ImportHistoryEntry>> getImportHistory({
    required int accountId,
    int limit = 20,
  }) {
    return (select(importHistory)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)])
          ..limit(limit))
        .get();
  }

  // ════════════════════════════════════════════════════════════
  // ▣  편의 메서드
  // ════════════════════════════════════════════════════════════

  /// 설정 값 조회. 없으면 [defaultValue] 반환.
  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final row = await (select(appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value ?? defaultValue;
  }

  /// 설정 값 저장(upsert).
  Future<void> setSetting(String key, String? value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // ▣  Seed Data
  // ════════════════════════════════════════════════════════════

  /// onCreate 시 기본 데이터 삽입.
  Future<void> _seedData() async {
    await _seedCategories();
    await _seedAppSettings();
    // 금융기관 코드는 seed_institutions.dart의 seedInstitutions(db)로 별도 처리
  }

  // ── 6.1 기본 카테고리 ──────────────────────────────────────
  Future<void> _seedCategories() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cats = [
      CategoriesCompanion.insert(
        name: '식비',       icon: const Value('restaurant'),
        colorHex: const Value('#FF6B6B'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '교통비',     icon: const Value('directions_car'),
        colorHex: const Value('#4ECDC4'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '의류',       icon: const Value('shopping_bag'),
        colorHex: const Value('#45B7D1'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '의료/건강',  icon: const Value('local_hospital'),
        colorHex: const Value('#96CEB4'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '문화/여가',  icon: const Value('movie'),
        colorHex: const Value('#FFEAA7'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '교육',       icon: const Value('school'),
        colorHex: const Value('#DDA0DD'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '공과금',     icon: const Value('receipt'),
        colorHex: const Value('#F0E68C'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '통신',       icon: const Value('smartphone'),
        colorHex: const Value('#87CEEB'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '금융',       icon: const Value('account_balance'),
        colorHex: const Value('#98FB98'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '이체',       icon: const Value('swap_horiz'),
        colorHex: const Value('#DEB887'), isCustom: const Value(0),
      ),
      CategoriesCompanion.insert(
        name: '기타',       icon: const Value('more_horiz'),
        colorHex: const Value('#D3D3D3'), isCustom: const Value(0),
      ),
    ];

    await batch((b) {
      b.insertAllOnConflictUpdate(categories, cats);
    });
  }

  // ── 6.2 기본 앱 설정 (7개, v1.1) ──────────────────────────
  /// v1.1 변경: auto_sync_enabled 항목 제거 (자동 동기화 폐기)
  Future<void> _seedAppSettings() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final settings = [
      // 앱 테마: 'light' | 'dark' | 'system'
      _setting('theme',              'system',    now),
      // 기본 대시보드 뷰: 'personal' | 'combined'
      _setting('default_view_mode',  'combined',  now),
      // 개인 뷰 기본 활성 프로필 ID
      _setting('active_profile_id',  '1',         now),
      // PIN 잠금 활성화 여부
      _setting('pin_enabled',        'false',     now),
      // SHA-256 해시된 PIN (활성화 시 설정)
      _setting('pin_hash',           null,        now),
      // 백그라운드 전환 후 자동 잠금 대기 시간(초)
      _setting('auto_lock_seconds',  '30',        now),
      // DB 스키마 버전 (마이그레이션 추적)
      _setting('db_version',         '1',         now),
    ];

    await batch((b) {
      b.insertAllOnConflictUpdate(appSettings, settings);
    });
  }

  AppSettingsCompanion _setting(String key, String? value, int updatedAt) {
    return AppSettingsCompanion.insert(
      key: key,
      value: Value(value),
      updatedAt: updatedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DB 파일 연결 (OS별 표준 경로)
// ─────────────────────────────────────────────────────────────

/// OS별 표준 앱 데이터 디렉터리에 fortune_garden.db 생성.
///   Windows: %APPDATA%\FortuneGarden\fortune_garden.db
///   Android: /data/data/com.fortunegarden.app/databases/fortune_garden.db
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'fortune_garden.db'));
    return NativeDatabase.createInBackground(file);
  });
}
