// lib/data/database/seed_institutions.dart
//
// Fortune Garden — 금융기관 코드 Seed Data (v1.1)
//
// 변경 이력:
//   v1.0 → v1.1 (2026-03-16)
//     - 기관 코드 형식 변경: '0010' 숫자 코드 → 'KB', 'SHINHAN' 등 식별자 코드
//       (CODEF API 방식 폐기 후 자체 식별자 체계로 전환)
//     - 20개 기관 유지 (은행 9, 카드 7, 증권 4)
//
// insertAllOnConflictUpdate()로 중복 없이 재실행 가능.
// main.dart 또는 onUpgrade에서 1회 호출:
//   await seedInstitutions(db);

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

// ─────────────────────────────────────────────────────────────
// 금융기관 Seed Data 삽입
// ─────────────────────────────────────────────────────────────

/// 금융기관 코드 20개를 DB에 삽입(upsert).
/// 이미 존재하는 코드는 name, type, isActive를 업데이트.
Future<void> seedInstitutions(AppDatabase db) async {
  await db.batch((b) {
    b.insertAllOnConflictUpdate(db.institutions, _institutions);
  });
}

// ─────────────────────────────────────────────────────────────
// 기관 목록 정의
// ─────────────────────────────────────────────────────────────

InstitutionsCompanion _inst(String code, String name, String type) =>
    InstitutionsCompanion.insert(
      code: code,
      name: name,
      type: type,
      isActive: const Value(1),
    );

final List<InstitutionsCompanion> _institutions = [
  // ── 은행 (9개) ──────────────────────────────────────────────
  _inst('KB',       'KB국민은행',  'bank'),
  _inst('WOORI',    '우리은행',    'bank'),
  _inst('IBK',      'IBK기업은행', 'bank'),
  _inst('SHINHAN',  '신한은행',    'bank'),
  _inst('HANA',     '하나은행',    'bank'),
  _inst('NH',       'NH농협은행',  'bank'),
  _inst('KAKAO',    '카카오뱅크',  'bank'),
  _inst('TOSS',     '토스뱅크',   'bank'),
  _inst('KBANK',    '케이뱅크',   'bank'),

  // ── 카드 (7개) ──────────────────────────────────────────────
  _inst('KB_CARD',      'KB국민카드',  'card'),
  _inst('SHINHAN_CARD', '신한카드',    'card'),
  _inst('SAMSUNG_CARD', '삼성카드',    'card'),
  _inst('HYUNDAI_CARD', '현대카드',    'card'),
  _inst('LOTTE_CARD',   '롯데카드',    'card'),
  _inst('HANA_CARD',    '하나카드',    'card'),
  _inst('WOORI_CARD',   '우리카드',    'card'),

  // ── 증권 (4개) ──────────────────────────────────────────────
  _inst('KB_SEC',       'KB증권',       'stock'),
  _inst('SHINHAN_SEC',  '신한투자증권', 'stock'),
  _inst('KIWOOM',       '키움증권',     'stock'),
  _inst('MIRAE',        '미래에셋증권', 'stock'),
];

// ─────────────────────────────────────────────────────────────
// CSV 파서 프로필 기본 Seed (은행별 대표 CSV 형식)  ★ v1.1 신규
// ─────────────────────────────────────────────────────────────

/// 주요 기관의 기본 CSV 파서 프로필 삽입(upsert).
/// 실제 기관별 CSV 형식이 확정되면 이 함수를 확장하여 관리.
Future<void> seedCsvParserProfiles(AppDatabase db) async {
  await db.batch((b) {
    b.insertAllOnConflictUpdate(
      db.csvParserProfiles,
      _defaultParserProfiles,
    );
  });
}

CsvParserProfilesCompanion _parser({
  required String institutionCode,
  required String dateCol,
  required String amountCol,
  required String merchantCol,
  required String dateFormat,
  String encoding = 'EUC-KR',
  String delimiter = ',',
  int skipRows = 1,
}) =>
    CsvParserProfilesCompanion.insert(
      institutionCode: institutionCode,
      dateCol: dateCol,
      amountCol: amountCol,
      merchantCol: merchantCol,
      dateFormat: dateFormat,
      encoding: Value(encoding),
      delimiter: Value(delimiter),
      skipRows: Value(skipRows),
      isActive: const Value(1),
    );

final List<CsvParserProfilesCompanion> _defaultParserProfiles = [
  // KB국민은행 — 거래 내역 내보내기 기본 형식
  _parser(
    institutionCode: 'KB',
    dateCol:         '거래일시',
    amountCol:       '거래금액',
    merchantCol:     '내용',
    dateFormat:      'yyyy.MM.dd HH:mm:ss',
    encoding:        'EUC-KR',
  ),
  // NH농협은행
  _parser(
    institutionCode: 'NH',
    dateCol:         '거래일자',
    amountCol:       '거래금액',
    merchantCol:     '적요',
    dateFormat:      'yyyyMMdd',
    encoding:        'EUC-KR',
  ),
  // 신한은행
  _parser(
    institutionCode: 'SHINHAN',
    dateCol:         '거래날짜',
    amountCol:       '거래금액',
    merchantCol:     '거래내용',
    dateFormat:      'yyyy-MM-dd',
    encoding:        'UTF-8',
  ),
  // 하나은행
  _parser(
    institutionCode: 'HANA',
    dateCol:         '거래일시',
    amountCol:       '출금금액',
    merchantCol:     '적요',
    dateFormat:      'yyyy-MM-dd HH:mm:ss',
    encoding:        'EUC-KR',
  ),
  // 우리은행
  _parser(
    institutionCode: 'WOORI',
    dateCol:         '거래일자',
    amountCol:       '출금액',
    merchantCol:     '거래내용',
    dateFormat:      'yyyyMMdd',
    encoding:        'EUC-KR',
  ),
  // KB국민카드
  _parser(
    institutionCode: 'KB_CARD',
    dateCol:         '이용일',
    amountCol:       '이용금액',
    merchantCol:     '이용가맹점',
    dateFormat:      'yyyy.MM.dd',
    encoding:        'EUC-KR',
  ),
  // 신한카드
  _parser(
    institutionCode: 'SHINHAN_CARD',
    dateCol:         '이용일자',
    amountCol:       '이용금액',
    merchantCol:     '가맹점명',
    dateFormat:      'yyyyMMdd',
    encoding:        'EUC-KR',
  ),
];
