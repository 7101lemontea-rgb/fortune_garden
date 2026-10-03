// test/totals_exclusion_test.dart
//
// 합계 제외(categories.exclude_from_totals) 동작 검증.
//
// 분석기는 customSelect() 안의 SQL 문법을 검사하지 못하므로,
// 인메모리 SQLite로 실제 쿼리를 실행해 확인한다.
//
// 검증 범위:
//   - 기본 카테고리 '이체'가 exclude_from_totals = 1로 시드되는지
//   - getMonthlySummary / getCombinedDashboard /
//     getCategoryExpenses / getMonthlyTrend 4개 쿼리가
//     '이체' 거래를 합계에서 빼는지
//   - 미분류 거래(category_id IS NULL)는 합계에 포함되는지

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fortune_garden/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  // 2026년 9월
  final monthStart = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final monthEnd = DateTime(2026, 10, 1).millisecondsSinceEpoch;

  late int transferCategoryId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    await db.into(db.profiles).insert(ProfilesCompanion.insert(
          name: '나',
          colorHex: '#2E6DA4',
          createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        ));
    await db.into(db.institutions).insert(InstitutionsCompanion.insert(
          code: 'WOORI',
          name: '우리은행',
          type: 'bank',
        ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          profileId: 1,
          institutionCode: 'WOORI',
          accountNumberEnc: Uint8List.fromList([1, 2, 3]),
        ));

    final transfer = await (db.select(db.categories)
          ..where((t) => t.name.equals('이체')))
        .getSingle();
    transferCategoryId = transfer.id;
  });

  tearDown(() => db.close());

  Future<void> addTxn({
    required String hash,
    required int amount,
    int? categoryId,
    String merchant = '테스트',
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            profileId: 1,
            accountId: 1,
            txnHash: hash,
            txnDate: DateTime(2026, 9, 15, 12).millisecondsSinceEpoch,
            amount: amount,
            merchant: merchant,
            categoryId: Value(categoryId),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));

  test("기본 카테고리 '이체'는 합계 제외로 시드된다", () async {
    final transfer = await (db.select(db.categories)
          ..where((t) => t.name.equals('이체')))
        .getSingle();
    expect(transfer.excludeFromTotals, 1);

    final food = await (db.select(db.categories)
          ..where((t) => t.name.equals('식비')))
        .getSingle();
    expect(food.excludeFromTotals, 0);
  });

  test('getMonthlySummary가 이체를 제외한다', () async {
    await addTxn(hash: 'a', amount: -15200); // 미분류 지출
    await addTxn(hash: 'b', amount: 350000, categoryId: transferCategoryId);
    await addTxn(hash: 'c', amount: -50000, categoryId: transferCategoryId);

    final summary = await db.getMonthlySummary(
      profileId: 1,
      monthStart: monthStart,
      monthEnd: monthEnd,
    );

    // 이체 2건은 빠지고, 미분류 지출만 남는다
    expect(summary.income, 0);
    expect(summary.expense, -15200);
  });

  test('getCombinedDashboard가 이체를 제외한다', () async {
    await addTxn(hash: 'a', amount: -15200);
    await addTxn(hash: 'b', amount: 350000, categoryId: transferCategoryId);

    final rows = await db.getCombinedDashboard(
      monthStart: monthStart,
      monthEnd: monthEnd,
    );

    expect(rows.length, 1);
    expect(rows.first.read<int>('income'), 0);
    expect(rows.first.read<int>('expense'), -15200);
  });

  test('getCategoryExpenses가 이체를 제외한다', () async {
    await addTxn(hash: 'a', amount: -15200, merchant: '다이소');
    await addTxn(hash: 'b', amount: -50000, categoryId: transferCategoryId);

    final rows = await db.getCategoryExpenses(
      monthStart: monthStart,
      monthEnd: monthEnd,
    );

    expect(rows.length, 1);
    expect(rows.first.categoryName, '미분류');
    expect(rows.first.totalExpense, 15200);
  });

  test('getMonthlyTrend가 이체를 제외한다', () async {
    await addTxn(hash: 'a', amount: -15200);
    await addTxn(hash: 'b', amount: 350000, categoryId: transferCategoryId);

    final trend = await db.getMonthlyTrend(
      months: 1,
      baseYear: 2026,
      baseMonth: 9,
    );

    expect(trend.length, 1);
    expect(trend.first.income, 0);
    expect(trend.first.expense, 15200);
  });

  test('프로필 필터가 적용된 getMonthlyTrend도 동작한다', () async {
    await addTxn(hash: 'a', amount: -15200);
    await addTxn(hash: 'b', amount: 350000, categoryId: transferCategoryId);

    final trend = await db.getMonthlyTrend(
      months: 1,
      profileId: 1,
      baseYear: 2026,
      baseMonth: 9,
    );

    expect(trend.first.expense, 15200);
    expect(trend.first.income, 0);
  });
}
