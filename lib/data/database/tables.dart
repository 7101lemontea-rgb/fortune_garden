// lib/data/database/tables.dart
//
// Fortune Garden — Drift ORM 테이블 정의 (v1.1)
// SAD v1.1 · DB ERD v1.1 기준
//
// 변경 이력:
//   v1.0 → v1.1 (2026-03-16)
//     - profiles.connectedIdEnc 컬럼 제거 (CODEF 방식 폐기)
//     - sync_history 테이블 제거
//     - csv_parser_profiles 테이블 신규 추가
//     - import_history 테이블 신규 추가
//     - accounts.balance 설명 수정 (동기화 → 가져오기)
//     - transactions.isManual 설명 수정
//
// ※ 컬럼명 규칙: Dart lowerCamelCase → Drift가 SQL snake_case로 자동 변환
//   예) colorHex → color_hex,  txnDate → txn_date

import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────
// 1. profiles — 사용자 프로필
// ─────────────────────────────────────────────────────────────
/// 2인 가구 각 사용자의 프로필. id는 1 또는 2로 운용.
/// 모든 사용자 데이터(accounts, transactions 등)의 루트 엔티티.
class Profiles extends Table {
  /// 프로필 고유 ID (1 또는 2)
  IntColumn get id => integer().autoIncrement()();

  /// 프로필 표시 이름 (예: 남편, 아내)
  TextColumn get name => text()();

  /// 프로필 구분 색상 HEX (예: #2E6DA4)
  TextColumn get colorHex => text()();

  /// 기본 뷰 모드: 'personal' | 'combined'
  TextColumn get defaultViewMode =>
      text().withDefault(const Constant('personal'))();

  /// 생성 시각 Unix timestamp (ms)
  IntColumn get createdAt => integer()();
}

// ─────────────────────────────────────────────────────────────
// 2. institutions — 금융기관 코드 마스터
// ─────────────────────────────────────────────────────────────
/// 지원 금융기관 코드를 DB로 관리. code가 TEXT PK.
/// is_active=0으로 비활성화 처리(삭제 대신 사용).
@DataClassName('Institution')
class Institutions extends Table {
  /// 금융기관 코드 (TEXT PK, 예: KB, SHINHAN)
  TextColumn get code => text()();

  /// 기관명 (예: KB국민은행)
  TextColumn get name => text()();

  /// 기관 유형: 'bank' | 'card' | 'stock'
  TextColumn get type => text()();

  /// 활성 여부. 0이면 신규 연동 불가.
  /// ON DELETE RESTRICT 대신 is_active=0으로 비활성화
  IntColumn get isActive => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {code};
}

// ─────────────────────────────────────────────────────────────
// 3. accounts — 금융기관 계좌
// ─────────────────────────────────────────────────────────────
/// 프로필별 금융 계좌 정보. 계좌번호는 AES-256-GCM 암호화 BLOB.
class Accounts extends Table {
  /// 계좌 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// FK → profiles.id (ON DELETE CASCADE)
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  /// FK → institutions.code (ON DELETE RESTRICT)
  TextColumn get institutionCode =>
      text().references(Institutions, #code, onDelete: KeyAction.restrict)();

  /// AES-256-GCM 암호화된 계좌번호 BLOB
  BlobColumn get accountNumberEnc => blob()();

  /// 사용자 지정 계좌 별명
  TextColumn get alias => text().nullable()();

  /// 최종 CSV 가져오기 잔액 (원 단위 정수)
  IntColumn get balance => integer().withDefault(const Constant(0))();

  /// 마지막 CSV 가져오기 Unix timestamp (ms)
  IntColumn get lastSyncedAt => integer().nullable()();
}

// ─────────────────────────────────────────────────────────────
// 4. categories — 카테고리 마스터
// ─────────────────────────────────────────────────────────────
/// 지출 카테고리. 기본 11개 + 사용자 정의.
/// parentId 자기 참조로 계층 구조 지원.
/// ※ Drift는 자기 참조 FK 어노테이션 미지원 → parentId는 일반 IntColumn.
///   상위 카테고리 삭제 시 SET NULL은 Repository 레이어에서 처리.
class Categories extends Table {
  /// 카테고리 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// 카테고리 이름 (UNIQUE, 예: 식비, 교통비)
  TextColumn get name => text().unique()();

  /// 아이콘 식별자 (Flutter Icons 코드포인트 문자열)
  TextColumn get icon => text().nullable()();

  /// 카테고리 색상 HEX
  TextColumn get colorHex => text().nullable()();

  /// 사용자 정의 여부 (0: 기본 11개, 1: 커스텀)
  IntColumn get isCustom => integer().withDefault(const Constant(0))();

  /// 자기 참조 상위 카테고리 ID (NULL = 최상위)
  IntColumn get parentId => integer().nullable()();

  /// 수입·지출 합계에서 제외할지 여부 (0: 포함, 1: 제외)  ★ v1.2 신규
  ///
  /// 부부 간 송금처럼 가계 외부로 나가지 않는 돈은 '이체'로 분류한 뒤
  /// 대시보드·리포트 합계에서 빼야 실제 소비액이 드러난다.
  /// 기본 카테고리 '이체'는 1로 시드된다.
  IntColumn get excludeFromTotals =>
      integer().withDefault(const Constant(0))();
}

// ─────────────────────────────────────────────────────────────
// 5. transactions — 거래 내역
// ─────────────────────────────────────────────────────────────
/// 거래 데이터 핵심 테이블. CSV 가져오기·수동 입력 모두 저장.
/// txnHash UNIQUE로 중복 자동 방지.
/// amount: 지출 음수(-), 수입 양수(+).
class Transactions extends Table {
  /// 거래 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// FK → profiles.id (성능 역정규화, ON DELETE CASCADE)
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  /// FK → accounts.id (ON DELETE CASCADE)
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// 중복 방지 SHA-256 해시 (account_id+date+amount+merchant)
  TextColumn get txnHash => text().unique()();

  /// 거래 일시 Unix timestamp (ms)
  IntColumn get txnDate => integer()();

  /// 금액 (원). 지출 음수(-), 수입 양수(+)
  IntColumn get amount => integer()();

  /// 거래처명 (CSV 원문)
  TextColumn get merchant => text()();

  /// 거래 후 계좌 잔액
  IntColumn get balanceAfter => integer().nullable()();

  /// FK → categories.id (NULL = 미분류, ON DELETE SET NULL)
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.setNull).nullable()();

  /// 사용자 메모
  TextColumn get memo => text().nullable()();

  /// 입력 구분 (0: CSV 가져오기, 1: 수동입력)
  IntColumn get isManual => integer().withDefault(const Constant(0))();

  /// 레코드 생성 Unix timestamp (ms)
  IntColumn get createdAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {txnHash},
      ];
}

// ─────────────────────────────────────────────────────────────
// 6. category_rules — 자동 분류 규칙
// ─────────────────────────────────────────────────────────────
/// 거래처명 키워드 LIKE 검색으로 카테고리 자동 분류.
/// profileId=NULL은 두 프로필 공용 규칙.
class CategoryRules extends Table {
  /// 규칙 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// 거래처명 매칭 키워드 (LIKE 검색)
  TextColumn get keyword => text()();

  /// FK → categories.id (ON DELETE CASCADE)
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  /// FK → profiles.id (NULL = 공용 규칙, ON DELETE SET NULL)
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.setNull).nullable()();

  /// 규칙 우선순위 (높을수록 먼저 적용)
  IntColumn get priority => integer().withDefault(const Constant(0))();
}

// ─────────────────────────────────────────────────────────────
// 7. csv_parser_profiles — CSV 파서 프로필  ★ v1.1 신규
// ─────────────────────────────────────────────────────────────
/// 기관별 CSV 파싱 설정. 앱 업데이트 없이 신규 기관 대응 가능.
/// institution_code FK → institutions.code.
///
/// v1.2 확장 (텍스트 붙여넣기 가져오기 지원):
///   - sourceType: 'file'(CSV 파일) / 'paste'(텍스트 붙여넣기) 구분.
///     같은 기관이라도 파일 형식과 웹 화면 복사 형식이 달라 프로필을 분리한다.
///   - withdrawCol / depositCol: 출금·입금이 별도 컬럼인 형식 지원.
///   - balanceCol: 거래 후 잔액. 중복 해시 보강 + 누락 행 검증에 사용.
///   - txnTypeCol: 거래구분(예: 현카구매, 타행자동). 분류 보조 키.
///   - headerKeyword: 표 위에 붙은 메타 줄을 건너뛰기 위한 헤더 탐색 키워드.
///   - rowOrder: 원본 행 정렬 방향. 'desc'면 저장 전 과거순으로 뒤집는다.
@DataClassName('CsvParserProfile')
class CsvParserProfiles extends Table {
  /// 파서 프로필 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// FK → institutions.code (ON DELETE RESTRICT)
  TextColumn get institutionCode =>
      text().references(Institutions, #code, onDelete: KeyAction.restrict)();

  /// 입력 방식: 'file' | 'paste'  ★ v1.2 신규
  /// (institutionCode, sourceType) 조합이 프로필의 논리적 식별자.
  TextColumn get sourceType =>
      text().withDefault(const Constant('file'))();

  /// 거래일시 컬럼명 (CSV 헤더 문자열)
  TextColumn get dateCol => text()();

  /// 단일 금액 컬럼명.
  /// ※ withdrawCol·depositCol을 쓰는 입출금 분리 형식에서는 빈 문자열('').
  TextColumn get amountCol => text()();

  /// 출금금액 컬럼명. NULL이면 amountCol 단일 컬럼 방식.  ★ v1.2 신규
  TextColumn get withdrawCol => text().nullable()();

  /// 입금금액 컬럼명. NULL이면 amountCol 단일 컬럼 방식.  ★ v1.2 신규
  TextColumn get depositCol => text().nullable()();

  /// 거래 후 잔액 컬럼명. NULL이면 잔액 미사용.  ★ v1.2 신규
  TextColumn get balanceCol => text().nullable()();

  /// 거래구분 컬럼명. NULL이면 미사용.  ★ v1.2 신규
  TextColumn get txnTypeCol => text().nullable()();

  /// 거래처명 컬럼명
  TextColumn get merchantCol => text()();

  /// 날짜 파싱 형식 (예: yyyy-MM-dd HH:mm:ss)
  TextColumn get dateFormat => text()();

  /// 파일 인코딩 (UTF-8, EUC-KR 등)
  TextColumn get encoding =>
      text().withDefault(const Constant('UTF-8'))();

  /// 컬럼 구분자
  TextColumn get delimiter =>
      text().withDefault(const Constant(','))();

  /// 헤더 행 탐색 키워드. NULL이면 첫 행을 헤더로 간주.  ★ v1.2 신규
  TextColumn get headerKeyword => text().nullable()();

  /// 원본 행 정렬 방향: 'asc'(과거순) | 'desc'(최신순)  ★ v1.2 신규
  TextColumn get rowOrder =>
      text().withDefault(const Constant('asc'))();

  /// 헤더 행 수 (건너뛸 행 수). headerKeyword 사용 시 무시됨.
  IntColumn get skipRows => integer().withDefault(const Constant(1))();

  /// 활성화 여부 (0이면 비활성)
  IntColumn get isActive => integer().withDefault(const Constant(1))();
}

// ─────────────────────────────────────────────────────────────
// 8. import_history — CSV 가져오기 이력  ★ v1.1 신규
// ─────────────────────────────────────────────────────────────
/// CSV 가져오기 이력 로그. v1.0 sync_history를 대체.
/// 파일명, 신규/중복/오류 건수 기록.
@DataClassName('ImportHistoryEntry')
class ImportHistory extends Table {
  /// 이력 고유 ID
  IntColumn get id => integer().autoIncrement()();

  /// FK → profiles.id (ON DELETE CASCADE)
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  /// FK → accounts.id (ON DELETE CASCADE)
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// 원본 파일명
  TextColumn get fileName => text()();

  /// 가져오기 일시 Unix timestamp (ms)
  IntColumn get importedAt => integer()();

  /// 전체 파싱 행 수
  IntColumn get totalRows => integer().withDefault(const Constant(0))();

  /// 신규 저장 건수
  IntColumn get newRows => integer().withDefault(const Constant(0))();

  /// 중복으로 건너뛴 건수
  IntColumn get duplicateRows => integer().withDefault(const Constant(0))();

  /// 오류 건수
  IntColumn get errorRows => integer().withDefault(const Constant(0))();
}

// ─────────────────────────────────────────────────────────────
// 9. app_settings — 앱 전역 설정
// ─────────────────────────────────────────────────────────────
/// Key-Value 설정 저장소. key가 TEXT PK.
/// value는 JSON 직렬화 허용.
@DataClassName('AppSetting')
class AppSettings extends Table {
  /// 설정 키 (예: theme, pin_enabled)
  TextColumn get key => text()();

  /// 설정 값 (JSON 직렬화 허용)
  TextColumn get value => text().nullable()();

  /// 최종 수정 Unix timestamp (ms)
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
