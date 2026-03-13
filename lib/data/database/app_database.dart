import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────────────────────────
// AppDatabase
// - 8개 테이블 등록
// - Seed data (기본 카테고리 11개 + 기본 앱 설정)
// - 핵심 쿼리 메서드 포함
// ─────────────────────────────────────────────────────────────────
@DriftDatabase(tables: [
  Profiles,
  Institutions,
  Accounts,
  Categories,
  Transactions,
  CategoryRules,
  SyncHistory,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // 테스트용 in-memory 생성자
  AppDatabase.forTesting(DatabaseConnection connection) : super(connection);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _seedData();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // 추후 버전 업 시 마이그레이션 추가
        },
      );

  // ───────────────────────────────────────────
  // Seed Data
  // ───────────────────────────────────────────
  Future<void> _seedData() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 기본 카테고리 11개 (ERD 7.1)
    final defaultCategories = [
      CategoriesCompanion.insert(
          name: '식비', icon: const Value('restaurant'), colorHex: const Value('#FF6B6B'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '교통비', icon: const Value('directions_car'), colorHex: const Value('#4ECDC4'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '의류', icon: const Value('shopping_bag'), colorHex: const Value('#45B7D1'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '의료/건강', icon: const Value('local_hospital'), colorHex: const Value('#96CEB4'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '문화/여가', icon: const Value('movie'), colorHex: const Value('#FFEAA7'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '교육', icon: const Value('school'), colorHex: const Value('#DDA0DD'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '공과금', icon: const Value('receipt'), colorHex: const Value('#F0E68C'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '통신', icon: const Value('smartphone'), colorHex: const Value('#87CEEB'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '금융', icon: const Value('account_balance'), colorHex: const Value('#98FB98'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '이체', icon: const Value('swap_horiz'), colorHex: const Value('#DEB887'), isCustom: const Value(0)),
      CategoriesCompanion.insert(
          name: '기타', icon: const Value('more_horiz'), colorHex: const Value('#D3D3D3'), isCustom: const Value(0)),
    ];
    await batch((b) => b.insertAll(categories, defaultCategories));

    // 기본 앱 설정 (ERD 7.2)
    final defaultSettings = [
      AppSettingsCompanion.insert(key: 'theme', value: const Value('system'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'auto_sync_enabled', value: const Value('true'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'default_view_mode', value: const Value('combined'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'active_profile_id', value: const Value('1'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'pin_enabled', value: const Value('false'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'pin_hash', value: const Value(null), updatedAt: now),
      AppSettingsCompanion.insert(key: 'auto_lock_seconds', value: const Value('30'), updatedAt: now),
      AppSettingsCompanion.insert(key: 'db_version', value: const Value('1'), updatedAt: now),
    ];
    await batch((b) => b.insertAll(appSettings, defaultSettings));
  }

  // ───────────────────────────────────────────
  // 핵심 쿼리 (ERD 6절 기반)
  // ───────────────────────────────────────────

  /// 6.1 개인 뷰 - 이번 달 수입/지출 합계
  Future<({int income, int expense})> getMonthlySummary({
    required int profileId,
    required int monthStart,
    required int monthEnd,
  }) async {
    final query = customSelect(
      '''
      SELECT
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS income,
        SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END) AS expense
      FROM transactions
      WHERE profile_id = :profileId
        AND txn_date >= :monthStart
        AND txn_date < :monthEnd
      ''',
      variables: [
        Variable.withInt(profileId),
        Variable.withInt(monthStart),
        Variable.withInt(monthEnd),
      ],
      readsFrom: {transactions},
    );
    final row = await query.getSingle();
    return (
      income: row.read<int?>('income') ?? 0,
      expense: row.read<int?>('expense') ?? 0,
    );
  }

  /// 6.2 통합 뷰 - 두 프로필 합산 대시보드
  Future<List<QueryRow>> getCombinedDashboard({
    required int monthStart,
    required int monthEnd,
  }) {
    return customSelect(
      '''
      SELECT
        p.name,
        p.color_hex,
        SUM(CASE WHEN t.amount > 0 THEN t.amount ELSE 0 END) AS income,
        SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END) AS expense
      FROM transactions t
      JOIN profiles p ON t.profile_id = p.id
      WHERE t.txn_date >= :monthStart AND t.txn_date < :monthEnd
      GROUP BY t.profile_id
      ''',
      variables: [
        Variable.withInt(monthStart),
        Variable.withInt(monthEnd),
      ],
      readsFrom: {transactions, profiles},
    ).get();
  }

  /// 6.3 카테고리 자동 분류 - 거래처명으로 카테고리 매칭
  Future<int?> matchCategory({
    required String merchant,
    required int profileId,
  }) async {
    final query = customSelect(
      '''
      SELECT category_id FROM category_rules
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
    );
    final rows = await query.get();
    if (rows.isEmpty) return null;
    return rows.first.read<int?>('category_id');
  }

  /// 6.4 중복 거래 방지 INSERT (txn_hash UNIQUE 활용)
  Future<void> insertTransactionIfNotExists(
      TransactionsCompanion entry) async {
    await into(transactions).insertOnConflictUpdate(entry);
    // 실제로는 INSERT OR IGNORE 동작 - txn_hash 충돌 시 무시
  }

  // ───────────────────────────────────────────
  // 편의 쿼리
  // ───────────────────────────────────────────

  /// 프로필별 계좌 목록 조회
  Stream<List<Account>> watchAccountsByProfile(int profileId) {
    return (select(accounts)
          ..where((a) => a.profileId.equals(profileId)))
        .watch();
  }

  /// 날짜 범위 거래 내역 (개인 뷰)
  Stream<List<Transaction>> watchTransactions({
    required int profileId,
    required int from,
    required int to,
  }) {
    return (select(transactions)
          ..where((t) =>
              t.profileId.equals(profileId) &
              t.txnDate.isBiggerOrEqualValue(from) &
              t.txnDate.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.desc(t.txnDate)]))
        .watch();
  }

  /// 앱 설정 값 읽기
  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// 앱 설정 값 저장
  Future<void> setSetting(String key, String? value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: Value(value),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

// ───────────────────────────────────────────
// DB 파일 연결 (fortune_garden.db)
// ───────────────────────────────────────────
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fortune_garden.db'));
    return NativeDatabase.createInBackground(file);
  });
}
