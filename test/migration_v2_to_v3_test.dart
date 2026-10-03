// test/migration_v2_to_v3_test.dart
//
// schemaVersion 2 → 3 마이그레이션 검증.
//
// 기존 사용자의 DB는 v2 상태로 존재하므로, 업그레이드가 실패하면
// 앱이 열리지 않거나 데이터가 깨진다. 실제 파일 DB를 v2 모양으로
// 되돌린 뒤 drift의 onUpgrade를 통과시켜 확인한다.
//
// 검증 범위:
//   - csv_parser_profiles 신규 컬럼 7개가 추가되는지
//   - 기존 파서 프로필 행이 source_type = 'file'로 채워지는지
//   - categories.exclude_from_totals가 추가되고 '이체'가 1이 되는지
//   - 기존 행의 데이터가 보존되는지

import 'dart:io';

// isNull: drift의 컬럼 표현식과 matcher의 isNull이 충돌하므로 matcher 쪽을 쓴다.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fortune_garden/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// v2 시점의 categories DDL (exclude_from_totals 없음).
const _categoriesV2 = '''
CREATE TABLE categories (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  icon TEXT NULL,
  color_hex TEXT NULL,
  is_custom INTEGER NOT NULL DEFAULT 0,
  parent_id INTEGER NULL
)
''';

/// v2 시점의 csv_parser_profiles DDL (신규 컬럼 7개 없음).
const _parserProfilesV2 = '''
CREATE TABLE csv_parser_profiles (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  institution_code TEXT NOT NULL
    REFERENCES institutions (code) ON DELETE RESTRICT,
  date_col TEXT NOT NULL,
  amount_col TEXT NOT NULL,
  merchant_col TEXT NOT NULL,
  date_format TEXT NOT NULL,
  encoding TEXT NOT NULL DEFAULT 'UTF-8',
  delimiter TEXT NOT NULL DEFAULT ',',
  skip_rows INTEGER NOT NULL DEFAULT 1,
  is_active INTEGER NOT NULL DEFAULT 1
)
''';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fg_migration_');
    dbFile = File('${tempDir.path}/fortune_garden.db');

    // 1. 현재(v3) 스키마로 파일을 한 번 만든다.
    final fresh = AppDatabase(NativeDatabase(dbFile));
    await fresh.getSetting('theme'); // 실제 연결·onCreate 유발
    await fresh.close();

    // 2. 변경된 두 테이블만 v2 모양으로 되돌리고 user_version을 2로 내린다.
    final sqlite = raw.sqlite3.open(dbFile.path);
    sqlite.execute('PRAGMA foreign_keys = OFF');

    sqlite.execute('DROP TABLE categories');
    sqlite.execute(_categoriesV2);
    sqlite.execute(
      "INSERT INTO categories (name, icon, color_hex, is_custom) "
      "VALUES ('이체', 'swap_horiz', '#DEB887', 0)",
    );
    sqlite.execute(
      "INSERT INTO categories (name, icon, color_hex, is_custom) "
      "VALUES ('식비', 'restaurant', '#FF6B6B', 0)",
    );

    sqlite.execute('DROP TABLE csv_parser_profiles');
    sqlite.execute(_parserProfilesV2);
    sqlite.execute(
      "INSERT INTO csv_parser_profiles "
      "(institution_code, date_col, amount_col, merchant_col, "
      " date_format, encoding, delimiter, skip_rows, is_active) "
      "VALUES ('KB', '거래일시', '거래금액', '내용', "
      " 'yyyy.MM.dd HH:mm:ss', 'EUC-KR', ',', 1, 1)",
    );

    sqlite.execute('PRAGMA user_version = 2');
    sqlite.dispose();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v2 DB가 v3으로 업그레이드된다', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    // 연결을 열면 drift가 onUpgrade(2 → 3)를 실행한다.
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 3);
  });

  test('기존 파서 프로필에 source_type = file이 채워진다', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    final profiles = await db.select(db.csvParserProfiles).get();
    expect(profiles.length, 1);

    final kb = profiles.single;
    expect(kb.institutionCode, 'KB');
    expect(kb.sourceType, 'file');
    expect(kb.rowOrder, 'asc');
    // 신규 nullable 컬럼은 비어 있어야 한다
    expect(kb.withdrawCol, isNull);
    expect(kb.depositCol, isNull);
    expect(kb.balanceCol, isNull);
    expect(kb.txnTypeCol, isNull);
    expect(kb.headerKeyword, isNull);
    // 기존 값은 보존된다
    expect(kb.dateCol, '거래일시');
    expect(kb.amountCol, '거래금액');
    expect(kb.encoding, 'EUC-KR');
  });

  test("기존 '이체' 카테고리가 합계 제외로 전환된다", () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    final transfer = await (db.select(db.categories)
          ..where((t) => t.name.equals('이체')))
        .getSingle();
    expect(transfer.excludeFromTotals, 1);
    // 기존 값 보존
    expect(transfer.icon, 'swap_horiz');

    final food = await (db.select(db.categories)
          ..where((t) => t.name.equals('식비')))
        .getSingle();
    expect(food.excludeFromTotals, 0);
  });

  test('업그레이드 후 집계 쿼리가 동작한다', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

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
          accountNumberEnc: Uint8List.fromList([1]),
        ));

    final transfer = await (db.select(db.categories)
          ..where((t) => t.name.equals('이체')))
        .getSingle();

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          profileId: 1,
          accountId: 1,
          txnHash: 'h1',
          txnDate: DateTime(2026, 9, 15).millisecondsSinceEpoch,
          amount: -15200,
          merchant: '다이소',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          profileId: 1,
          accountId: 1,
          txnHash: 'h2',
          txnDate: DateTime(2026, 9, 16).millisecondsSinceEpoch,
          amount: 350000,
          merchant: '정*권',
          categoryId: Value(transfer.id),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));

    final summary = await db.getMonthlySummary(
      profileId: 1,
      monthStart: DateTime(2026, 9, 1).millisecondsSinceEpoch,
      monthEnd: DateTime(2026, 10, 1).millisecondsSinceEpoch,
    );
    expect(summary.income, 0);
    expect(summary.expense, -15200);
  });
}
