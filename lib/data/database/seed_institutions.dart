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

/// 기관별 파서 프로필 삽입(upsert).
///
/// - CSV 파일 프로필: 주요 기관의 대표 형식(_defaultParserProfiles).
/// - 붙여넣기 프로필: 등록된 **모든 기관**(은행·카드·증권)에 1개씩 자동 생성.
///   열 인식은 CsvParserUseCase가 동의어로 처리하므로 기관별 설정이 필요 없고,
///   기관을 추가해도 여기서 자동으로 붙여넣기 프로필이 생긴다.
///   (은행만 하드코딩하면 증권·카드가 "파서 없음"이 되는 문제를 방지)
///
/// ※ (institution_code, source_type)을 논리 식별자로 삼아 수동 upsert한다.
///   csv_parser_profiles의 PK는 autoIncrement id이므로
///   insertAllOnConflictUpdate()는 충돌 대상이 없어 매 호출마다
///   새 행을 추가해버린다(앱 실행마다 중복 누적).
///   같은 조합의 과거 중복 행은 첫 행만 남기고 정리한다.
Future<void> seedCsvParserProfiles(AppDatabase db) async {
  final profiles = <CsvParserProfilesCompanion>[
    ..._defaultParserProfiles,
    // 등록된 모든 기관에 붙여넣기 프로필 1개씩.
    for (final inst in await db.select(db.institutions).get())
      _genericPaste(inst.code),
  ];

  for (final profile in profiles) {
    await _upsertProfile(db, profile);
  }
}

/// (institution_code, source_type) 기준 수동 upsert + 과거 중복 정리.
Future<void> _upsertProfile(
  AppDatabase db,
  CsvParserProfilesCompanion profile,
) async {
  final code = profile.institutionCode.value;
  final source = profile.sourceType.value;

  final existing = await (db.select(db.csvParserProfiles)
        ..where((t) =>
            t.institutionCode.equals(code) & t.sourceType.equals(source))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  if (existing.isEmpty) {
    await db.into(db.csvParserProfiles).insert(profile);
    return;
  }

  // 첫 행만 최신 기본값으로 갱신
  await (db.update(db.csvParserProfiles)
        ..where((t) => t.id.equals(existing.first.id)))
      .write(profile);

  // 과거에 누적된 중복 행 제거
  if (existing.length > 1) {
    final dupIds = existing.skip(1).map((e) => e.id).toList();
    await (db.delete(db.csvParserProfiles)..where((t) => t.id.isIn(dupIds)))
        .go();
  }
}

/// CSV 파일용 프로필 (단일 금액 컬럼).
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
      sourceType: const Value('file'),
      dateCol: dateCol,
      amountCol: amountCol,
      merchantCol: merchantCol,
      dateFormat: dateFormat,
      encoding: Value(encoding),
      delimiter: Value(delimiter),
      skipRows: Value(skipRows),
      isActive: const Value(1),
    );

/// 텍스트 붙여넣기용 프로필 (출금·입금 분리 + 잔액).
/// 은행 웹 화면의 거래내역 표를 복사해 붙여넣는 형식.
/// 복사 시 열 구분자는 보통 탭이며, 공백으로 변형된 경우도
/// CsvParserUseCase가 자동 보정한다.
CsvParserProfilesCompanion _pasteParser({
  required String institutionCode,
  required String dateCol,
  required String withdrawCol,
  required String depositCol,
  required String merchantCol,
  required String dateFormat,
  String? balanceCol,
  String? txnTypeCol,
  String? headerKeyword,
  String rowOrder = 'desc',
}) =>
    CsvParserProfilesCompanion.insert(
      institutionCode: institutionCode,
      sourceType: const Value('paste'),
      dateCol: dateCol,
      // 입출금 분리 형식이므로 단일 금액 컬럼은 미사용
      amountCol: '',
      withdrawCol: Value(withdrawCol),
      depositCol: Value(depositCol),
      balanceCol: Value(balanceCol),
      txnTypeCol: Value(txnTypeCol),
      merchantCol: merchantCol,
      dateFormat: dateFormat,
      encoding: const Value('UTF-8'),
      delimiter: const Value('\t'),
      headerKeyword: Value(headerKeyword ?? dateCol),
      rowOrder: Value(rowOrder),
      skipRows: const Value(1),
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

// ── 텍스트 붙여넣기 프로필 ★ v1.2 신규 ──────────────────────
// 붙여넣기 프로필은 seedCsvParserProfiles()에서 등록된 모든 기관에 대해
// _genericPaste()로 자동 생성한다(은행·카드·증권 공통).
// 열 인식은 CsvParserUseCase가 동의어로 처리하므로(기재내용/적요/종목 등)
// 기관별로 열 이름을 맞출 필요가 없다.

/// 기관 공통 붙여넣기 프로필. 열 이름은 동의어로 자동 인식되므로
/// 가장 흔한 기본값만 힌트로 둔다.
///
/// · 날짜 형식: 파서가 시간 유무·구분자(./-)를 자동 판별하므로 대표값만 지정.
/// · rowOrder='desc': 대부분의 거래내역 화면이 최신순 → 저장 전 과거순으로 뒤집음.
///   (잔액 열로 정렬 검증도 하므로 혹시 순서가 달라도 중복/금액은 안전)
CsvParserProfilesCompanion _genericPaste(String institutionCode) =>
    _pasteParser(
      institutionCode: institutionCode,
      dateCol:         '거래일시',
      txnTypeCol:      '거래구분',
      merchantCol:     '기재내용',
      withdrawCol:     '출금금액',
      depositCol:      '입금금액',
      balanceCol:      '잔액',
      dateFormat:      'yyyy.MM.dd HH:mm:ss',
      rowOrder:        'desc',
    );
