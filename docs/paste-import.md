# 텍스트 붙여넣기 가져오기 (v1.2)

작성일: 2026-10-03 · 브랜치: `develop` · schemaVersion: 2 → 3

## 배경

CSV 파일 방식은 은행 화면 → 엑셀 → CSV 저장 → 가져오기 단계를 거쳐야 하고,
한국어 윈도우의 기본 CSV 인코딩(EUC-KR) 문제도 따라온다.

은행 인터넷뱅킹의 거래내역 표를 **복사해서 바로 붙여넣는** 방식을 추가했다.
엑셀 변환과 인코딩 변환이 사라지고, 잔액 열을 함께 받을 수 있어
중복 방지와 누락 검증이 가능해진다.

기준으로 삼은 형식은 우리은행 '계좌거래내역' 화면이다.

```
거래일시              거래구분   기재내용              출금금액   입금금액   잔액          취급점
2026.09.29 10:31:22  현카구매   현카캐쉬백            0원        76원       1,382,942원   098150
2026.09.29 10:31:22  현카구매   주식회사 아성다이소   15,200원   0원        1,382,866원   098150
2026.09.29 09:42:14  체크우리   할리스커피 유성       5,900원    0원        1,398,066원   리테일영업총괄부(카드)
2026.09.28 09:48:47  타행자동   정*권                 0원        350,000원  1,403,966원   신한은행
```

---

## 1. 데이터 계층

### csv_parser_profiles 확장 (컬럼 7개)

| 컬럼 | 용도 |
| --- | --- |
| `sourceType` | `file`(CSV 파일) / `paste`(붙여넣기) 구분. 기본값 `file` |
| `withdrawCol` | 출금금액 컬럼명. NULL이면 단일 `amountCol` 방식 |
| `depositCol` | 입금금액 컬럼명 |
| `balanceCol` | 거래 후 잔액 컬럼명 |
| `txnTypeCol` | 거래구분 컬럼명 (분류 보조 키) |
| `headerKeyword` | 헤더 행 탐색 키워드. 표 위 메타 줄을 건너뛴다 |
| `rowOrder` | `asc`(과거순) / `desc`(최신순). 기본값 `asc` |

**`sourceType`을 둔 이유**: 같은 우리은행이라도 CSV 파일 형식(`거래일자`/`출금액`/`거래내용`)과
웹 화면 복사 형식(`거래일시`/`출금금액`/`기재내용`)의 컬럼 구성이 다르다.
한 기관에 프로필이 하나뿐이면 둘 중 하나만 지원할 수 있다.
`(institutionCode, sourceType)`이 프로필의 논리적 식별자가 되었다.

**`amountCol` 처리**: 입출금 분리 형식에서는 단일 금액 컬럼이 없다.
`amountCol`을 nullable로 바꾸려면 SQLite에서 테이블 재생성(`TableMigration`)이 필요하므로,
NOT NULL을 유지하고 빈 문자열(`''`)을 "미사용"으로 쓴다.
마이그레이션을 추가 전용으로 유지하려는 선택이다.

### categories.excludeFromTotals 추가

수입·지출 합계에서 제외할지 여부 (0: 포함, 1: 제외). 기본 카테고리 `이체`가 1로 시드된다.

이름(`name = '이체'`) 비교가 아니라 플래그로 둔 이유:

- 사용자가 카테고리 이름을 바꿔도 동작이 유지된다
- 나중에 다른 카테고리(예: 대출 상환)도 제외 대상으로 지정할 수 있다

### 마이그레이션 (schemaVersion 2 → 3)

전부 `addColumn`과 `UPDATE`뿐인 **추가 전용** 마이그레이션이다. 테이블 재생성이 없어
기존 데이터가 옮겨지는 경로가 생기지 않는다.

```dart
// categories는 v1부터 존재하므로 from < 3 전체에 적용
if (from < 3) {
  await m.addColumn(categories, categories.excludeFromTotals);
  await m.database.customStatement(
    "UPDATE categories SET exclude_from_totals = 1 WHERE name = '이체'");
}

// from < 2 경로는 csv_parser_profiles를 현재 스키마로 새로 만들기 때문에
// 이미 신규 컬럼을 갖고 있다. 중복 addColumn을 피하려고 from >= 2 조건을 둔다.
if (from >= 2 && from < 3) {
  await m.addColumn(csvParserProfiles, csvParserProfiles.sourceType);
  // ... 나머지 6개
}
```

---

## 2. 파서

[csv_parser_use_case.dart](../lib/application/csv_import/csv_parser_use_case.dart)의
`parseFromString()`을 CSV 파일과 붙여넣기가 공유한다.
Isolate에서 호출되므로 네이티브 플러그인(charset_converter)을 쓰지 않는 제약은 그대로 유지했다.

### 처리 순서

1. 줄바꿈 정규화 (`\r\n`, `\r` → `\n`)
2. 구분자 후보를 순서대로 시도 → 필수 컬럼을 찾아내는 첫 후보 채택
3. `headerKeyword`로 헤더 행 탐색 → 그 위 메타 줄은 버림
4. 컬럼 인덱스 매핑 (정확히 일치 우선, 없으면 부분 일치)
5. 행별 변환
6. `rowOrder == 'desc'`면 뒤집어 과거순으로 반환

### 주요 결정

**구분자 자동 보정**
웹 표를 복사하면 보통 탭으로 구분되지만, 탭이 공백으로 변형되는 경우가 있다.
탭을 먼저 시도하고 실패하면 **공백 2칸 이상**으로 다시 시도한다.

공백 1칸이 아니라 2칸 이상인 이유: `주식회사 아성다이소`, `2026.09.29 10:31:22`처럼
셀 내부의 단일 공백을 보존해야 한다.

**금액 부호**
`amount = 입금 - 출금`. 프로젝트 규칙(지출 음수, 수입 양수)을 그대로 따른다.
`원`·`₩`·쉼표·`△`·`▲`·괄호·부호를 처리하고, 빈 값과 `-`는 0으로 본다.

**정렬 뒤집기**
원본은 최신순이다. 샘플의 같은 초 거래(`10:31:22`)는 잔액 흐름
(1,398,066 → 1,382,866 → 1,382,942)을 보면 **결제가 먼저, 캐시백이 나중**이다.
파일 순서를 뒤집으면 올바른 순서가 된다.

**실패 처리**
필수 컬럼을 못 찾으면 `FormatException`에 필요 컬럼과 입력 앞부분을 담아 던진다.
개별 행의 파싱 실패(합계 줄, 주석 줄 등)는 건너뛴다.

---

## 3. 가져오기

[csv_import_use_case.dart](../lib/application/csv_import/csv_import_use_case.dart)에
`executeFromText()`를 추가하고, 파일 경로와 공통 저장 로직(`_store()`)을 분리했다.

### 중복 해시에 잔액 포함

```
잔액 있음: SHA-256(accountId|txnDate|amount|merchant|balanceAfter)
잔액 없음: SHA-256(accountId|txnDate|amount|merchant)
```

일시·금액·내용만으로는 같은 초의 서로 다른 거래를 구분하지 못한다.
잔액을 넣으면 구분된다.

**잔액이 없을 때 과거 형식을 그대로 쓰는 이유**: 조건 없이 `|` + 빈 값을 덧붙이면
해시가 바뀌어 **이미 저장된 거래가 중복으로 인식되지 않는다**.
잔액 컬럼이 없는 기존 CSV 프로필의 해시는 건드리지 않는다.

### 잔액 연속성 검증

이전 행의 잔액 + 현재 행의 금액 == 현재 행의 잔액이어야 한다.
어긋나는 구간은 조회 기간 사이에 누락된 거래가 있다는 신호다.

실패로 처리하지 않고 `ImportResult.warnings`에 담아 결과 카드에 안내로 띄운다.
저장은 그대로 진행된다.

### 분류 폴백

기재내용으로 먼저 분류하고, 미분류면 거래구분으로 한 번 더 시도한다.
`타행자동 / 정*권`처럼 상대방 이름만으로는 알 수 없고 거래구분이 성격을 말해주는 경우를 위한 것.

### 계좌 잔액 갱신

가져오기 후 가장 최신 잔액을 `accounts.balance`에, 현재 시각을 `lastSyncedAt`에 기록한다.
`IAccountRepository.updateBalance()`의 `balance`를 nullable로 바꿔
잔액 컬럼이 없는 형식에서는 시각만 갱신한다 (`Value.absent()`로 컬럼 제외).

---

## 4. 분류 정책

### 이체는 합계에서 제외

부부 간 송금은 가계 외부로 나가는 돈이 아니다. `이체` 카테고리로 분류하고
대시보드·리포트 합계에서 뺀다. 그렇지 않으면 서로 송금할 때마다
수입과 지출이 함께 부풀어 보인다.

집계 쿼리 **4개 전부**에 제외 조건을 넣었다.

| 쿼리 | 용도 |
| --- | --- |
| `getMonthlySummary` | 개인 뷰 월별 합계 |
| `getCombinedDashboard` | 통합 뷰 대시보드 |
| `getCategoryExpenses` | DonutChart |
| `getMonthlyTrend` | BarChart |

```sql
LEFT JOIN categories c ON t.category_id = c.id
WHERE ... AND COALESCE(c.exclude_from_totals, 0) = 0
```

`COALESCE`를 쓰는 이유: 미분류 거래(`category_id IS NULL`)는 합계에 포함되어야 한다.

### 기본 자동 분류 규칙

[seed_category_rules.dart](../lib/data/database/seed_category_rules.dart) 신규.
공용 규칙(`profile_id IS NULL`), priority 10.

| 키워드 | 카테고리 |
| --- | --- |
| 타행자동, 타행이체, 자동이체, 내계좌이체 | 이체 |
| 캐쉬백, 캐시백 | 기타 |
| 수수료 | 금융 |

`app_settings`의 `default_rules_seeded` 플래그로 **최초 1회만** 실행된다.
사용자가 기본 규칙을 지웠을 때 다시 살아나지 않게 하기 위함.

**의도적으로 넣지 않은 키워드**

`CategoryClassifyUseCase`는 `merchant.contains(keyword)` 부분 일치로 매칭한다.

- `현카구매`, `체크우리` — 결제 수단일 뿐 카테고리가 정해지지 않는다.
  넣으면 모든 카드 결제가 한 카테고리로 묶여 **미분류 신호가 사라진다**.
  미분류로 남아야 어디에 규칙이 필요한지 보인다.
- `이자` — `이자카야`에 매칭되어 음식점이 금융으로 분류된다.

---

## 5. UI (SCR-008)

[import_screen.dart](../lib/presentation/screens/import/import_screen.dart)

화면 제목을 'CSV 파일 가져오기' → '거래내역 가져오기'로 바꾸고 3단계로 재구성했다.

| 단계 | 내용 |
| --- | --- |
| 1 | 입력 방식 — `SegmentedButton` (붙여넣기 / CSV 파일). 기본값 붙여넣기 |
| 2 | 계좌 선택 — 선택한 방식의 파서 프로필 유무를 체크 아이콘으로 표시 |
| 3 | 붙여넣기 입력창 또는 파일 선택 |

붙여넣기 입력창(`_PasteInput`)은 여러 줄 `TextField`에 예시 형식을 힌트로 넣고,
클립보드 버튼·지우기 버튼·입력 줄 수를 함께 표시한다.

계좌 카드의 파서 유무 표시가 선택한 입력 방식에 따라 달라지므로,
`_AccountWithParser`가 `hasFileParser`/`hasPasteParser`를 각각 들고
`hasParserFor(mode)`로 꺼내 쓴다.

결과 카드에는 잔액 검증 경고를 `warnings`로 표시한다.

---

## 6. 함께 고친 것

### seed 중복 누적 버그

`seedCsvParserProfiles()`가 `insertAllOnConflictUpdate()`를 썼지만
`csv_parser_profiles`의 PK는 autoIncrement `id`다.
Companion에 `id`가 없으면 **충돌 대상이 없어 매 호출마다 새 행이 추가된다**.
`app_initializer.dart`가 앱 실행마다 이 함수를 부르므로
파서 프로필 7개가 계속 쌓이고 있었다.

`(institutionCode, sourceType)` 기준 수동 upsert로 바꾸고,
같은 조합의 과거 중복 행은 첫 행만 남기고 정리한다.

### drift_indexes.dart의 UNIQUE 함정

`idx_txn_profile_date`가 `(profileId, txnDate)`에 `unique: true`로 선언되어 있었다.

이 파일은 현재 참고용이고 `@DriftDatabase`에 연결되어 있지 않아 적용되지 않는다.
하지만 그대로 적용하면 **같은 초 거래의 두 번째 삽입이 실패한다**
(샘플의 다이소 15,200원 + 캐시백 76원).
UNIQUE를 풀고 이유를 주석으로 남겼다. 중복 방지는 `idx_txn_hash`(UNIQUE)가 담당한다.

---

## 7. 검증

`flutter analyze`: **error 0개** (경고·정보 168개는 기존 `withOpacity` 등)
`flutter test`: **21개 전부 통과**

| 파일 | 개수 | 범위 |
| --- | --- | --- |
| [csv_parser_use_case_test.dart](../test/csv_parser_use_case_test.dart) | 10 | 실제 샘플의 탭/공백 두 버전, 메타 줄 건너뛰기, 금액 부호, 정렬 뒤집기, 잔액 연속성, 헤더 없을 때 예외 |
| [totals_exclusion_test.dart](../test/totals_exclusion_test.dart) | 6 | 인메모리 SQLite로 집계 쿼리 4개의 이체 제외 |
| [migration_v2_to_v3_test.dart](../test/migration_v2_to_v3_test.dart) | 4 | 실제 파일 DB를 v2로 되돌린 뒤 업그레이드·데이터 보존 |
| [widget_test.dart](../test/widget_test.dart) | 1 | 자리표시자 |

**집계 쿼리를 테스트한 이유**: `customSelect()` 안의 SQL 문자열은 분석기가 검사하지 못한다.
컬럼명 오타나 JOIN 누락은 런타임에만 드러나므로 실제 SQLite로 실행해 확인했다.

**마이그레이션을 테스트한 이유**: 기존 사용자의 DB는 v2 상태로 존재한다.
업그레이드가 실패하면 앱이 열리지 않는다.
마이그레이션 테스트에서 v2 스키마를 직접 만들기 위해 `sqlite3`를 dev_dependencies에 추가했다.

**검증하지 못한 것**: Windows 실제 실행.
`flutter build windows`가 심볼릭 링크 권한을 요구한다
(`start ms-settings:developers`에서 개발자 모드 활성화 필요).
이 프로젝트 변경과 무관한 환경 설정 문제이고, Dart 코드 컴파일은 분석기와 테스트로 확인했다.

---

## 8. 변경 파일

**신규**
- `lib/data/database/seed_category_rules.dart`
- `test/csv_parser_use_case_test.dart`
- `test/totals_exclusion_test.dart`
- `test/migration_v2_to_v3_test.dart`

**수정**
- `lib/data/database/tables.dart` — 컬럼 8개 추가
- `lib/data/database/app_database.dart` — schemaVersion 3, 마이그레이션, 집계 쿼리 4개, `getParserProfile()`
- `lib/data/database/seed_institutions.dart` — upsert 수정, 우리은행 붙여넣기 프로필
- `lib/data/database/drift_indexes.dart` — UNIQUE 해제
- `lib/application/csv_import/csv_parser_use_case.dart` — 파서 재작성
- `lib/application/csv_import/csv_import_use_case.dart` — `executeFromText()`, 해시, 검증
- `lib/domain/entities/parsed_transaction.dart` — `txnType`, `warnings`
- `lib/domain/repositories/i_csv_parser_profile_repository.dart` — `sourceType`
- `lib/domain/repositories/i_account_repository.dart` — `updateBalance()` 시그니처
- `lib/data/repositories/csv_parser_profile_repository.dart`
- `lib/data/repositories/account_repository.dart`
- `lib/presentation/providers/app_providers.dart` — `executeFromText()`
- `lib/presentation/screens/import/import_screen.dart` — 3단계 재구성
- `lib/app_initializer.dart` — `seedCategoryRules()` 호출
- `pubspec.yaml` — dev_dependencies에 `sqlite3`

---

## 9. 남은 작업

| 우선순위 | 항목 | 비고 |
| --- | --- | --- |
| 🟡 중간 | `excludeFromTotals` 토글 UI | 현재 `이체`만 시드로 1. 카테고리 편집 시트에 스위치 추가하면 사용자 카테고리도 제외 가능 |
| 🟡 중간 | 실제 붙여넣기 동작 확인 | 개발자 모드 활성화 후 Windows에서 실행 |
| 🟡 중간 | 규칙 우선순위 UI 개선 | 숫자 입력 → `ReorderableListView` 드래그 정렬 |
| 🟢 낮음 | 다른 은행 붙여넣기 프로필 | 현재 우리은행 1개 |
| 🟢 낮음 | `accountNumberEnc` DEV placeholder | `flutter_secure_storage` + `encrypt` 실제 구현 |
| 🟢 낮음 | 라우트 경로 하드코딩 | `/import`, `/accounts` → 경로 상수로 교체 |
| 🟢 낮음 | Android 백업 내보내기 권한 | `permission_handler`, 배포 시점 |

### 계좌 자동 매칭은 하지 않는다

붙여넣은 내용의 계좌번호는 `1002-84*-******`처럼 마스킹되어 있어
자동 매칭이 불안정하다. 가져오기 화면에서 계좌를 직접 선택하는 방식을 유지한다.
