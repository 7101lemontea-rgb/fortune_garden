// lib/data/database/tables_with_indexes.dart
//
// Fortune Garden — Drift 인덱스 구현 참고 (v1.1)
//
// ※ 이 파일은 tables.dart에 @TableIndex 어노테이션을 적용한
//    '완성본' 버전입니다. build_runner가 이 파일을 기준으로
//    인덱스를 자동 생성합니다.
//
// ERD v1.1 §5 인덱스 전략 전체 구현:
//   transactions     ×5 (idx_txn_profile_date, idx_txn_account_date,
//                        idx_txn_category, idx_txn_hash UNIQUE, idx_txn_date)
//
// ★ 주의 (v1.2 수정): idx_txn_profile_date의 UNIQUE를 해제했다.
//   은행 거래내역에는 같은 초에 발생한 서로 다른 거래가 존재한다.
//   예) 2026.09.29 10:31:22 다이소 결제 15,200원 + 같은 시각 캐시백 76원
//   (profile_id, txn_date)에 UNIQUE를 걸면 두 번째 행의 삽입이 실패한다.
//   중복 방지는 idx_txn_hash(UNIQUE)가 담당한다.
//   accounts         ×1 (idx_acc_profile)
//   category_rules   ×1 (idx_rule_keyword)
//   import_history   ×1 (idx_import_account_date)           ★ v1.1 신규
//   csv_parser_profiles ×1 (idx_parser_institution)         ★ v1.1 신규
//
// 총 9개 인덱스 (v1.0 대비: idx_sync_profile_start 제거, 2개 신규)

import 'package:drift/drift.dart';

import 'tables.dart';

// ─────────────────────────────────────────────────────────────
// 5. transactions — 인덱스 5개
// ─────────────────────────────────────────────────────────────

/// transactions 테이블에 모든 인덱스를 선언한 확장 클래스.
/// tables.dart의 Transactions 클래스를 그대로 상속하고
/// @TableIndex 어노테이션을 추가한다.
// ※ unique: true 금지. 같은 초에 두 건 이상의 거래가 들어올 수 있다.
@TableIndex(
  name: 'idx_txn_profile_date',
  columns: {#profileId, #txnDate},
)
@TableIndex(
  name: 'idx_txn_account_date',
  columns: {#accountId, #txnDate},
)
@TableIndex(
  name: 'idx_txn_category',
  columns: {#categoryId},
)
@TableIndex(
  name: 'idx_txn_hash',
  columns: {#txnHash},
  unique: true,
)
@TableIndex(
  name: 'idx_txn_date',
  columns: {#txnDate},
)
class TransactionsIndexed extends Transactions {}

// ─────────────────────────────────────────────────────────────
// 3. accounts — 인덱스 1개
// ─────────────────────────────────────────────────────────────

@TableIndex(
  name: 'idx_acc_profile',
  columns: {#profileId},
)
class AccountsIndexed extends Accounts {}

// ─────────────────────────────────────────────────────────────
// 6. category_rules — 인덱스 1개
// ─────────────────────────────────────────────────────────────

@TableIndex(
  name: 'idx_rule_keyword',
  columns: {#keyword},
)
class CategoryRulesIndexed extends CategoryRules {}

// ─────────────────────────────────────────────────────────────
// 8. import_history — 인덱스 1개  ★ v1.1 신규
// ─────────────────────────────────────────────────────────────

@TableIndex(
  name: 'idx_import_account_date',
  columns: {#accountId, #importedAt},
)
class ImportHistoryIndexed extends ImportHistory {}

// ─────────────────────────────────────────────────────────────
// 7. csv_parser_profiles — 인덱스 1개  ★ v1.1 신규
// ─────────────────────────────────────────────────────────────

@TableIndex(
  name: 'idx_parser_institution',
  columns: {#institutionCode},
)
class CsvParserProfilesIndexed extends CsvParserProfiles {}

// ─────────────────────────────────────────────────────────────
// AppDatabase (인덱스 적용 버전)
// ─────────────────────────────────────────────────────────────
//
// tables.dart의 원본 클래스 대신 *Indexed 클래스를 사용.
// app_database.dart의 @DriftDatabase tables 목록을 아래와 같이 교체:
//
// @DriftDatabase(
//   tables: [
//     Profiles,
//     Institutions,
//     AccountsIndexed,           // Accounts → AccountsIndexed
//     Categories,
//     TransactionsIndexed,       // Transactions → TransactionsIndexed
//     CategoryRulesIndexed,      // CategoryRules → CategoryRulesIndexed
//     CsvParserProfilesIndexed,  // CsvParserProfiles → CsvParserProfilesIndexed
//     ImportHistoryIndexed,      // ImportHistory → ImportHistoryIndexed
//     AppSettings,
//   ],
// )
//
// 이 방식 대신 tables.dart에 직접 @TableIndex를 추가하는 것도 동일하게 동작.
