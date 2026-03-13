import 'app_database.dart';

// ─────────────────────────────────────────────────────────────────
// CODEF 금융기관 Seed Data
//
// 앱 최초 설치 시 또는 관리자 메뉴에서 수동 실행.
// AppDatabase._seedData()에서 호출하거나 별도로 호출 가능.
// ─────────────────────────────────────────────────────────────────
Future<void> seedInstitutions(AppDatabase db) async {
  final data = [
    // ── 은행 (bank)
    InstitutionsCompanion.insert(code: '0010', name: 'KB국민은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0020', name: '우리은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0030', name: '기업은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0040', name: '신한은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0050', name: '하나은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0060', name: '농협은행', type: 'bank'),
    InstitutionsCompanion.insert(code: '0070', name: '카카오뱅크', type: 'bank'),
    InstitutionsCompanion.insert(code: '0080', name: '토스뱅크', type: 'bank'),
    InstitutionsCompanion.insert(code: '0090', name: '케이뱅크', type: 'bank'),

    // ── 카드 (card)
    InstitutionsCompanion.insert(code: '0210', name: 'KB국민카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0220', name: '신한카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0230', name: '삼성카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0240', name: '현대카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0250', name: '롯데카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0260', name: '하나카드', type: 'card'),
    InstitutionsCompanion.insert(code: '0270', name: '우리카드', type: 'card'),

    // ── 증권 (stock)
    InstitutionsCompanion.insert(code: '0410', name: 'KB증권', type: 'stock'),
    InstitutionsCompanion.insert(code: '0420', name: '신한투자증권', type: 'stock'),
    InstitutionsCompanion.insert(code: '0430', name: '키움증권', type: 'stock'),
    InstitutionsCompanion.insert(code: '0440', name: '미래에셋증권', type: 'stock'),
  ];

  await db.batch((b) {
    b.insertAllOnConflictUpdate(db.institutions, data);
  });
}
