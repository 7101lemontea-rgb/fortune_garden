import 'package:drift/drift.dart';

// ─────────────────────────────────────────────
// 4.1 profiles — 사용자 프로필 (최대 2개)
// ─────────────────────────────────────────────
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()(); // 예: #2E6DA4
  BlobColumn get connectedIdEnc =>
      blob().nullable()(); // AES-256-GCM 암호화된 CODEF Connected ID
  TextColumn get defaultViewMode => text()
      .withDefault(const Constant('personal'))(); // 'personal' | 'combined'
  IntColumn get createdAt => integer()(); // Unix timestamp (ms)
}

// ─────────────────────────────────────────────
// 4.6 institutions — 금융기관 코드 마스터
// ─────────────────────────────────────────────
class Institutions extends Table {
  TextColumn get code => text()(); // CODEF 금융기관 코드 (예: 0010)
  TextColumn get name => text()(); // 기관명 (예: KB국민은행)
  TextColumn get type => text()(); // 'bank' | 'card' | 'stock'
  IntColumn get isActive =>
      integer().withDefault(const Constant(1))(); // 1=활성, 0=비활성

  @override
  Set<Column> get primaryKey => {code};
}

// ─────────────────────────────────────────────
// 4.2 accounts — 금융기관 계좌
// ─────────────────────────────────────────────
@TableIndex(name: 'idx_acc_profile', columns: {#profileId})
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get institutionCode =>
      text().references(Institutions, #code, onDelete: KeyAction.restrict)();
  BlobColumn get accountNumberEnc => blob()(); // AES-256-GCM 암호화된 계좌번호
  TextColumn get alias => text().nullable()(); // 사용자 지정 계좌 별명
  IntColumn get balance =>
      integer().withDefault(const Constant(0))(); // 최종 잔액 (원 단위)
  IntColumn get lastSyncedAt =>
      integer().nullable()(); // 마지막 동기화 Unix timestamp (ms)
}

// ─────────────────────────────────────────────
// 4.4 categories — 카테고리 마스터 (자기 참조)
// ─────────────────────────────────────────────
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()(); // 예: 식비, 교통비
  TextColumn get icon => text().nullable()(); // Flutter Icon 코드포인트
  TextColumn get colorHex => text().nullable()(); // 카테고리 색상 HEX
  IntColumn get isCustom =>
      integer().withDefault(const Constant(0))(); // 0: 기본, 1: 커스텀
  IntColumn get parentId => integer().nullable()(); // 자기 참조 (쿼리 레벨에서 JOIN 처리)
}

// ─────────────────────────────────────────────
// 4.3 transactions — 거래 내역 (핵심 테이블)
// ─────────────────────────────────────────────
@TableIndex(
    name: 'idx_txn_profile_date', columns: {#profileId, #txnDate}, unique: true)
@TableIndex(name: 'idx_txn_account_date', columns: {#accountId, #txnDate})
@TableIndex(name: 'idx_txn_category', columns: {#categoryId})
@TableIndex(name: 'idx_txn_date', columns: {#txnDate})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get txnHash =>
      text().unique()(); // SHA-256 해시 — .unique()가 idx_txn_hash 역할
  IntColumn get txnDate => integer()(); // 거래 일시 Unix timestamp (ms)
  IntColumn get amount => integer()(); // 지출: 음수(-), 수입: 양수(+)
  TextColumn get merchant => text()(); // 거래처명 (CODEF 원문)
  IntColumn get balanceAfter => integer().nullable()(); // 거래 후 계좌 잔액
  IntColumn get categoryId => integer()
      .nullable()
      .references(Categories, #id, onDelete: KeyAction.setNull)(); // NULL = 미분류
  TextColumn get memo => text().nullable()(); // 사용자 메모
  IntColumn get isManual =>
      integer().withDefault(const Constant(0))(); // 0: 자동수집, 1: 수동입력
  IntColumn get createdAt => integer()(); // 레코드 생성 Unix timestamp (ms)
}

// ─────────────────────────────────────────────
// 4.5 category_rules — 자동 분류 규칙
// ─────────────────────────────────────────────
@TableIndex(name: 'idx_rule_keyword', columns: {#keyword})
class CategoryRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get keyword => text()(); // 거래처명 매칭 키워드 (LIKE 검색)
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  IntColumn get profileId => integer().nullable().references(Profiles, #id,
      onDelete: KeyAction.setNull)(); // NULL = 두 프로필 공용 규칙
  IntColumn get priority =>
      integer().withDefault(const Constant(0))(); // 높을수록 먼저 적용
}

// ─────────────────────────────────────────────
// 4.7 sync_history — 동기화 이력
// ─────────────────────────────────────────────
@TableIndex(name: 'idx_sync_profile_start', columns: {#profileId, #startedAt})
class SyncHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  IntColumn get startedAt => integer()(); // 동기화 시작 Unix timestamp (ms)
  IntColumn get completedAt => integer().nullable()(); // NULL = 진행 중
  TextColumn get status =>
      text()(); // 'running' | 'success' | 'partial' | 'failed'
  IntColumn get txnCount =>
      integer().withDefault(const Constant(0))(); // 수집된 거래 건수
  TextColumn get errorMsg => text().nullable()(); // 오류 메시지
}

// ─────────────────────────────────────────────
// 4.8 app_settings — 앱 전역 설정 (Key-Value)
// ─────────────────────────────────────────────
class AppSettings extends Table {
  TextColumn get key => text()(); // 설정 키 (예: theme, auto_sync, pin_enabled)
  TextColumn get value => text().nullable()(); // 설정 값 (JSON 직렬화 허용)
  IntColumn get updatedAt => integer()(); // 최종 수정 Unix timestamp (ms)

  @override
  Set<Column> get primaryKey => {key};
}
