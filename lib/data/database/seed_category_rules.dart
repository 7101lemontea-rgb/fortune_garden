// lib/data/database/seed_category_rules.dart
//
// Fortune Garden — 기본 자동 분류 규칙 Seed  ★ v1.2 신규
//
// 거래구분(예: 타행자동, 체크우리)과 기재내용에서 카테고리가 명확하게
// 결정되는 키워드만 공용 규칙(profile_id IS NULL)으로 등록한다.
//
// ※ 최초 1회만 실행된다 (app_settings의 default_rules_seeded 플래그).
//   사용자가 기본 규칙을 지웠을 때 다시 살아나지 않도록 하기 위함.
//
// ── 키워드 선정 기준 ─────────────────────────────────────────
// CategoryClassifyUseCase는 `merchant.contains(keyword)` 부분 일치로
// 매칭하므로, 다른 단어에 섞여 들어가는 키워드는 넣지 않는다.
//   · '이자' → '이자카야'에 매칭되어 음식점이 금융으로 분류됨 (제외)
//   · '현카구매', '체크우리' → 결제 수단일 뿐 카테고리가 정해지지 않음.
//     넣으면 모든 카드 결제가 한 카테고리로 묶여 미분류 신호가 사라짐 (제외)

import 'package:drift/drift.dart';

import 'app_database.dart';

/// 중복 실행 방지 플래그 키.
const _seededKey = 'default_rules_seeded';

/// 공용 기본 규칙의 우선순위.
/// 사용자가 만든 개인 규칙은 priority와 무관하게 먼저 적용된다
/// (CategoryClassifyUseCase가 개인 규칙을 우선 정렬).
const _defaultPriority = 10;

/// 키워드 → 카테고리 이름 매핑.
/// 카테고리 ID는 autoIncrement이므로 이름으로 조회해 연결한다.
const _defaultRules = <String, String>{
  // 가계 외부로 나가지 않는 돈 → 합계에서 제외되는 '이체'
  '타행자동': '이체',
  '타행이체': '이체',
  '자동이체': '이체',
  '내계좌이체': '이체',

  // 카드 캐시백 등 소액 환급
  '캐쉬백': '기타',
  '캐시백': '기타',

  // 금융 비용
  '수수료': '금융',
};

/// 기본 자동 분류 규칙을 1회 삽입.
/// 카테고리 시드(_seedCategories) 이후에 호출해야 한다.
Future<void> seedCategoryRules(AppDatabase db) async {
  if (await db.getSetting(_seededKey) == 'true') return;

  final categories = await db.select(db.categories).get();
  final idByName = {for (final c in categories) c.name: c.id};

  for (final entry in _defaultRules.entries) {
    final categoryId = idByName[entry.value];
    // 사용자가 해당 기본 카테고리를 지웠다면 건너뛴다.
    if (categoryId == null) continue;

    // 같은 키워드의 공용 규칙이 이미 있으면 건드리지 않는다.
    final existing = await (db.select(db.categoryRules)
          ..where((t) => t.keyword.equals(entry.key) & t.profileId.isNull()))
        .get();
    if (existing.isNotEmpty) continue;

    await db.into(db.categoryRules).insert(
          CategoryRulesCompanion.insert(
            keyword: entry.key,
            categoryId: categoryId,
            priority: const Value(_defaultPriority),
          ),
        );
  }

  await db.setSetting(_seededKey, 'true');
}
