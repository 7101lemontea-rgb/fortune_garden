// lib/data/database/seed_dev_data.dart
//
// 개발/테스트용 임시 계좌 Seed.
// CSV 가져오기 플로우 검증을 위해 프로필 2개 + 계좌 4개를 생성.
//
// app_initializer.dart에서 호출:
//   await seedDevData(db);
//
// ※ 실제 배포 전 제거 또는 설정 플래그로 분기 필요.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'app_database.dart';

Future<void> seedDevData(AppDatabase db) async {
  await _seedProfiles(db);
  await _seedDevAccounts(db);
}

// ── 프로필 (없을 때만 삽입) ────────────────────────────
Future<void> _seedProfiles(AppDatabase db) async {
  final existing = await db.select(db.profiles).get();
  if (existing.isNotEmpty) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  await db.batch((b) {
    b.insertAllOnConflictUpdate(db.profiles, [
      ProfilesCompanion.insert(
        id:              const Value(1),
        name:            '나',
        colorHex:        '#2E6DA4',
        defaultViewMode: const Value('personal'),
        createdAt:       now,
      ),
      ProfilesCompanion.insert(
        id:              const Value(2),
        name:            '파트너',
        colorHex:        '#E65100',
        defaultViewMode: const Value('personal'),
        createdAt:       now,
      ),
    ]);
  });
}

// ── 임시 계좌 4개 ──────────────────────────────────────
// 계좌번호는 AES-256 암호화 BLOB이므로 임시 placeholder 사용.
Future<void> _seedDevAccounts(AppDatabase db) async {
  final existing = await db.select(db.accounts).get();
  if (existing.isNotEmpty) return;

  // 임시 암호화 placeholder (실제 운영 시 flutter_secure_storage + encrypt 사용)
  Uint8List placeholder(String text) =>
      Uint8List.fromList(utf8.encode('DEV:$text'));

  await db.batch((b) {
    b.insertAllOnConflictUpdate(db.accounts, [
      // 프로필 1 — KB국민은행
      AccountsCompanion.insert(
        profileId:        1,
        institutionCode:  'KB',
        accountNumberEnc: placeholder('110-123-456789'),
        alias:            const Value('KB 주거래'),
        balance:          const Value(1500000),
        lastSyncedAt:     const Value(null),
      ),
      // 프로필 1 — 신한카드
      AccountsCompanion.insert(
        profileId:        1,
        institutionCode:  'SHINHAN_CARD',
        accountNumberEnc: placeholder('4123-4567-8901-2345'),
        alias:            const Value('신한카드'),
        balance:          const Value(0),
        lastSyncedAt:     const Value(null),
      ),
      // 프로필 2 — NH농협은행
      AccountsCompanion.insert(
        profileId:        2,
        institutionCode:  'NH',
        accountNumberEnc: placeholder('302-0987-654321'),
        alias:            const Value('NH 급여'),
        balance:          const Value(2300000),
        lastSyncedAt:     const Value(null),
      ),
      // 프로필 2 — KB국민카드
      AccountsCompanion.insert(
        profileId:        2,
        institutionCode:  'KB_CARD',
        accountNumberEnc: placeholder('5678-1234-5678-9012'),
        alias:            const Value('KB카드'),
        balance:          const Value(0),
        lastSyncedAt:     const Value(null),
      ),
    ]);
  });
}
