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
//       · getParserProfile()      신규 (ERD 6.5)
//       · getImportHistory()      신규 (ERD 6.6)
//     - Seed data: auto_sync_enabled 제거 (7개 설정)
//     - _seedData: SyncHistory 관련 로직 제거
//   v1.2 (테마 동적 적용)
//     - watchSetting()            신규 (편의 메서드)
//   v1.3 (대시보드 차트)
//     - getCategoryExpenses()     신규 (DonutChart용)
//     - getMonthlyTrend()         신규 (BarChart용)

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────────────────────
// 차트용 데이터 클래스
// ─────────────────────────────────────────────────────────────

/// DonutChart용 — 카테고리별 지출 합계
class CategoryExpense {
  const CategoryExpense({
    required this.categoryId,
    required this.categoryName,
    required this.colorHex,
    required this.totalExpense,
  });

  final int? categoryId; // null = 미분류
  final String categoryName;
  final String colorHex;
  final int totalExpense; // 양수 (abs 처리됨)
}

/// BarChart용 — 월별 수입/지출
class MonthlyTrend {
  const MonthlyTrend({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  final int year;
  final int month;
  final int income; // 양수
  final int expense; // 양수 (abs 처리됨)
}

// ─────────────────────────────────────────────────────────────
// AppDatabase
// ─────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    Profiles,
    Institutions,
    Accounts,
    Categories,
    Transactions,
    CategoryRules,
    CsvParserProfiles,
    ImportHistory,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  // ── 마이그레이션 ────────────────────────────────────────────
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedData();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.database
                .customStatement('DROP TABLE IF EXISTS sync_history');
            await m.recreateAllViews();
            await m
                .addColumn(profiles, profiles.defaultViewMode)
                .catchError((_) {});
            await m.createTable(csvParserProfiles);
            await m.createTable(importHistory);
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
          await customStatement('PRAGMA journal_mode=WAL');
          await customStatement('PRAGMA foreign_keys=ON');
        },
      );

  // ════════════════════════════════════════════════════════════
  // ▣  핵심 쿼리 (ERD v1.1 §6)
  // ════════════════════════════════════════════════════════════

  // ── 6.1 개인 뷰 — 월별 수입/지출 합계 ─────────────────────
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
      income: result.read<int>('income'),
      expense: result.read<int>('expense'),
    );
  }

  // ── 6.2 통합 뷰 — 두 프로필 합산 대시보드 ─────────────────
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
  Future<void> insertTransactionIfNotExists(
    TransactionsCompanion entry,
  ) async {
    await into(transactions).insertOnConflictUpdate(entry);
  }

  // ── 6.5 파서 프로필 자동 매칭 ──────────────────────────────
  Future<CsvParserProfile?> getParserProfile({
    required String institutionCode,
  }) {
    return (select(csvParserProfiles)
          ..where((t) =>
              t.institutionCode.equals(institutionCode) & t.isActive.equals(1))
          ..limit(1))
        .getSingleOrNull();
  }

  // ── 6.6 계좌별 가져오기 이력 조회 ──────────────────────────
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

  // ── 6.7 카테고리별 지출 합계 ★ v1.3 신규 ──────────────────
  /// DonutChart용. [monthStart]~[monthEnd] 기간의 카테고리별 지출 합계.
  /// [profileId]가 null이면 전체 프로필 합산.
  /// 미분류 거래는 '미분류' 항목으로 합산.
  Future<List<CategoryExpense>> getCategoryExpenses({
    required int monthStart,
    required int monthEnd,
    int? profileId,
  }) async {
    final profileFilter =
        profileId != null ? 'AND t.profile_id = $profileId' : '';

    final rows = await customSelect(
      '''
      SELECT
        c.id        AS category_id,
        COALESCE(c.name,      '미분류') AS category_name,
        COALESCE(c.color_hex, '#D3D3D3') AS color_hex,
        ABS(SUM(t.amount))              AS total_expense
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.amount < 0
        AND t.txn_date >= :monthStart
        AND t.txn_date  < :monthEnd
        $profileFilter
      GROUP BY t.category_id
      ORDER BY total_expense DESC
      ''',
      variables: [
        Variable.withInt(monthStart),
        Variable.withInt(monthEnd),
      ],
      readsFrom: {transactions, categories},
    ).get();

    return rows
        .map((r) => CategoryExpense(
              categoryId: r.readNullable<int>('category_id'),
              categoryName: r.read<String>('category_name'),
              colorHex: r.read<String>('color_hex'),
              totalExpense: r.read<int>('total_expense'),
            ))
        .toList();
  }

  // ── 6.8 월별 수입/지출 추이 ★ v1.3 신규 ───────────────────
  /// BarChart용. 최근 [months]개월의 월별 수입/지출 합계.
  /// [profileId]가 null이면 전체 프로필 합산.
  /// [baseYear], [baseMonth]: 기준 연/월. null이면 현재 연/월 사용. ★ v1.4
  Future<List<MonthlyTrend>> getMonthlyTrend({
    required int months,
    int? profileId,
    int? baseYear, // ★ v1.4 신규
    int? baseMonth, // ★ v1.4 신규
  }) async {
    // 기준: 지정된 달 포함 과거 N개월 (미지정 시 현재 달)
    final now = DateTime.now();
    final year = baseYear ?? now.year;
    final month = baseMonth ?? now.month;
    final start = DateTime(year, month - (months - 1), 1);
    final startMs = start.millisecondsSinceEpoch;
    final endMs = DateTime(year, month + 1, 1).millisecondsSinceEpoch;

    final profileFilter =
        profileId != null ? 'AND profile_id = $profileId' : '';

    final rows = await customSelect(
      '''
      SELECT
        CAST(strftime('%Y', datetime(txn_date / 1000, 'unixepoch')) AS INTEGER) AS yr,
        CAST(strftime('%m', datetime(txn_date / 1000, 'unixepoch')) AS INTEGER) AS mo,
        COALESCE(SUM(CASE WHEN amount > 0 THEN  amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE txn_date >= :startMs
        AND txn_date  < :endMs
        $profileFilter
      GROUP BY yr, mo
      ORDER BY yr, mo
      ''',
      variables: [
        Variable.withInt(startMs),
        Variable.withInt(endMs),
      ],
      readsFrom: {transactions},
    ).get();

    // 데이터가 없는 달도 0으로 채워서 반환 (차트 축 유지)
    final resultMap = {
      for (final r in rows)
        (r.read<int>('yr'), r.read<int>('mo')): MonthlyTrend(
          year: r.read<int>('yr'),
          month: r.read<int>('mo'),
          income: r.read<int>('income'),
          expense: r.read<int>('expense'),
        ),
    };

    return List.generate(months, (i) {
      final d = DateTime(year, month - (months - 1 - i), 1);
      return resultMap[(d.year, d.month)] ??
          MonthlyTrend(year: d.year, month: d.month, income: 0, expense: 0);
    });
  }

  // ════════════════════════════════════════════════════════════
  // ▣  편의 메서드
  // ════════════════════════════════════════════════════════════

  /// 설정 값 조회. 없으면 [defaultValue] 반환.
  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
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

  /// 설정 값 실시간 구독. ★ v1.2 테마 동적 적용용
  Stream<String?> watchSetting(String key, {String? defaultValue}) {
    return (select(appSettings)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value ?? defaultValue);
  }

  // ════════════════════════════════════════════════════════════
  // ▣  Seed Data
  // ════════════════════════════════════════════════════════════

  Future<void> _seedData() async {
    await _seedCategories();
    await _seedAppSettings();
  }

  Future<void> _seedCategories() async {
    final cats = [
      CategoriesCompanion.insert(
          name: '식비',
          icon: const Value('restaurant'),
          colorHex: const Value('#FF6B6B'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '교통비',
          icon: const Value('directions_car'),
          colorHex: const Value('#4ECDC4'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '의류',
          icon: const Value('shopping_bag'),
          colorHex: const Value('#45B7D1'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '의료/건강',
          icon: const Value('local_hospital'),
          colorHex: const Value('#96CEB4'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '문화/여가',
          icon: const Value('movie'),
          colorHex: const Value('#FFEAA7'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '교육',
          icon: const Value('school'),
          colorHex: const Value('#DDA0DD'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '공과금',
          icon: const Value('receipt'),
          colorHex: const Value('#F0E68C'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '통신',
          icon: const Value('smartphone'),
          colorHex: const Value('#87CEEB'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '금융',
          icon: const Value('account_balance'),
          colorHex: const Value('#98FB98'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '이체',
          icon: const Value('swap_horiz'),
          colorHex: const Value('#DEB887'),
          isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '기타',
          icon: const Value('more_horiz'),
          colorHex: const Value('#D3D3D3'),
          isCustom: const Value(0)),
    ];
    await batch((b) => b.insertAllOnConflictUpdate(categories, cats));
  }

  Future<void> _seedAppSettings() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final settings = [
      _setting('theme', 'system', now),
      _setting('default_view_mode', 'combined', now),
      _setting('active_profile_id', '1', now),
      _setting('pin_enabled', 'false', now),
      _setting('pin_hash', null, now),
      _setting('auto_lock_seconds', '30', now),
      _setting('db_version', '1', now),
    ];
    await batch((b) => b.insertAllOnConflictUpdate(appSettings, settings));
  }

  AppSettingsCompanion _setting(String key, String? value, int updatedAt) =>
      AppSettingsCompanion.insert(
        key: key,
        value: Value(value),
        updatedAt: updatedAt,
      );
}

// ─────────────────────────────────────────────────────────────
// DB 파일 연결
// ─────────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'fortune_garden.db'));
    return NativeDatabase.createInBackground(file);
  });
}
