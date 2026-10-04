// test/seed_paste_profiles_test.dart
//
// 붙여넣기 파서 프로필이 등록된 모든 기관(은행·카드·증권)에
// 생성되는지 검증한다. 키움증권 등 증권사가 "파서 없음"이 되지 않아야 한다.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fortune_garden/data/database/app_database.dart';
import 'package:fortune_garden/data/database/seed_institutions.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedInstitutions(db);
    await seedCsvParserProfiles(db);
  });

  tearDown(() => db.close());

  test('모든 기관에 붙여넣기(paste) 프로필이 1개씩 있다', () async {
    final institutions = await db.select(db.institutions).get();
    expect(institutions, isNotEmpty);

    for (final inst in institutions) {
      final profile = await db.getParserProfile(
        institutionCode: inst.code,
        sourceType: 'paste',
      );
      expect(profile, isNotNull,
          reason: '${inst.code}(${inst.name}) 붙여넣기 프로필 없음');
    }
  });

  test('키움증권(KIWOOM) 붙여넣기 프로필이 존재한다', () async {
    final profile = await db.getParserProfile(
      institutionCode: 'KIWOOM',
      sourceType: 'paste',
    );
    expect(profile, isNotNull);
    expect(profile!.sourceType, 'paste');
  });

  test('seed를 여러 번 실행해도 기관당 붙여넣기 프로필은 1개 (중복 누적 없음)',
      () async {
    await seedCsvParserProfiles(db);
    await seedCsvParserProfiles(db);

    final rows = await (db.select(db.csvParserProfiles)
          ..where((t) =>
              t.institutionCode.equals('KIWOOM') & t.sourceType.equals('paste')))
        .get();
    expect(rows, hasLength(1));
  });
}
