# 붙여넣기 가져오기 — 릴리스 테스트 후 수정 (v1.2.x)

작성일: 2026-10-03 · 브랜치: `develop`

Windows 릴리스 빌드로 실제 사용하며 발견한 문제 4건을 정리한다.
[paste-import.md](paste-import.md)의 후속 수정이다.

## 요약

| # | 문제 | 원인 | 상태 |
| --- | --- | --- | --- |
| 1 | 계좌 삭제 시 화면이 검게 변하고 앱 멈춤 | 삭제 확인 다이얼로그가 바깥 context로 pop | 커밋 `ac6989f` |
| 2 | 날짜만 있는 거래가 "완료 0건" | 날짜 형식을 `yyyy.MM.dd HH:mm:ss`로 고정 | 작업 트리 |
| 3 | 농협·토스 등 다른 은행 미지원 | 우리은행 열 이름에 고정된 파서 | 작업 트리 |
| 4 | 키움증권 "파서 없음" | 붙여넣기 프로필을 은행만 시드 | 작업 트리 |

검증: `flutter analyze` error 0개, `flutter test` 33개 통과.

---

## 1. 계좌 삭제 시 화면이 검게 변함  (커밋 `ac6989f`)

### 증상
계좌를 삭제하면 화면 전체가 검게 되고 더 이상 조작이 안 됐다.

### 원인
삭제 확인 다이얼로그의 버튼이 **다이얼로그 자신이 아니라 바깥 화면의 `context`**로
`Navigator.pop(context)`를 호출했다. 앱은 `ShellRoute` 안에서 화면을 보여주는데,
바깥 context로 pop하면 다이얼로그가 아니라 **현재 페이지가 스택에서 빠진다**.
결과적으로 보여줄 페이지가 없어져(`You have popped the last page off of the stack`)
빈 화면이 됐다.

### 수정
`builder: (dialogContext) => ...`로 받아 **다이얼로그 자신의 context로 pop**하도록 바꿨다.
같은 실수가 거래 삭제 확인에도 있어 함께 고쳤다.

- [accounts_screen.dart](../lib/presentation/screens/accounts/accounts_screen.dart) — 계좌 삭제
- [transactions_screen.dart](../lib/presentation/screens/transactions/transactions_screen.dart) — 거래 삭제

다른 다이얼로그들은 이미 올바른 방식(`ctx`)이라 건드리지 않았다.

### 검증
[accounts_screen_test.dart](../test/accounts_screen_test.dart) — 실제 화면을 `ShellRoute`에
올려 삭제/취소 흐름 검증. 수정을 되돌려 보니 두 테스트 모두
`popped the last page off of the stack`으로 실패 → 실제 버그를 잡는 테스트임을 확인.

> **참고(되돌린 변경):** 조사 중 "계좌 등록 폼 기본 프로필을 활성 프로필로",
> "거래 목록에 프로필 필터"도 손댔으나, 2번째 증상(프로필 미적용)이 실제로는
> **저장을 안 누른 것**이어서 두 변경 모두 되돌렸다. 삭제 버그 수정만 남았다.

---

## 2. 날짜만 있는 거래가 "완료 0건"

### 증상
탭으로 구분해 넣어도 `2026.09.22`(시간 없음) 같은 행이 0건으로 안 들어갔다.
헤더는 인식되어 "완료"는 떴다.

### 원인
파서 프로필의 날짜 형식이 `yyyy.MM.dd HH:mm:ss`(시:분:초 포함)로 고정돼 있었다.
실제 우리은행 화면은 날짜만(`2026.09.22`) 오기도 하는데, 이를 시간 포함 형식으로
파싱하려다 실패해 그 행을 버렸다. 처음 샘플엔 시간이 있어서(`10:31:22`)
그 기준으로 만든 게 실제와 어긋났다.

### 수정
[csv_parser_use_case.dart](../lib/application/csv_import/csv_parser_use_case.dart)의
`_parseDate`를 **형식 고정 → 여러 형식 순차 시도**로 변경.
지정 형식을 먼저 쓰고, 실패하면 한국 은행에서 흔한 형식을 차례로 시도한다.

```
yyyy.MM.dd HH:mm:ss · yyyy.MM.dd HH:mm · yyyy.MM.dd
yyyy-MM-dd HH:mm:ss · yyyy-MM-dd HH:mm · yyyy-MM-dd
yyyy/MM/dd HH:mm:ss · yyyy/MM/dd · yyyyMMdd
```

`parseStrict`로 **문자열 전체가 맞을 때만** 인정한다.
(`yyyy.MM.dd`로 `2026.09.22 15:00:00`을 부분 매칭해 시간을 버리는 것 방지)
어떤 형식으로도 안 되면 그 행만 건너뛴다(전체 중단 아님).

### 검증
[csv_parser_use_case_test.dart](../test/csv_parser_use_case_test.dart) '날짜 형식 유연성' —
날짜만/시간 포함 둘 다 파싱, 날짜가 깨진 행은 안전하게 건너뜀.

---

## 3. 농협·토스 등 다른 은행 지원

### 증상
우리은행 외 다른 은행 거래내역을 붙여넣으면 열을 못 찾았다.

### 원인
파서가 우리은행 열 이름(`기재내용` 등)에 맞춰져 있었다.
은행마다 열 이름이 다르다(농협 `적요`, 토스 단일 `거래금액` 등).

### 수정
열 이름을 고정하지 않고 **뜻(동의어)으로 인식**하도록 일반화했다.
파일 모드는 기존대로 두고, 붙여넣기 모드에만 적용(`_resolvePasteLayout`).

| 뜻 | 인식하는 표현(일부) |
| --- | --- |
| 날짜 | 거래일시, 거래일자, 거래날짜, 일자, 날짜, 이용일 |
| 상대방 | 기재내용, 적요, 거래내용, 내용, 가맹점명, 받는분/보내는분 |
| 출금 | 출금금액, 출금액, 출금, 지급 |
| 입금 | 입금금액, 입금액, 입금, 받은금액 |
| 금액(단일 +/-) | 거래금액, 금액 |
| 잔액 | 거래후잔액, 잔액, 잔고 |

핵심 동작:
- **헤더 자동 탐색**: 날짜 열 + 금액류 열이 함께 있는 줄을 헤더로. 위 메타 줄은 건너뜀.
- **형식 자동 판별**: 출금/입금 분리(우리·농협) vs 단일 금액 +/-(토스).
- **오인식 방지**: 출금/입금이 있으면 단일 '금액'은 찾지 않음
  (`출금금액`이 `금액` 부분일치에 걸리는 것 차단). 또 서로 다른 열이 같은 셀로
  매칭되면(구분자 오류로 한 줄이 1셀로 뭉개짐) 그 후보를 버리고 다음 구분자로 재시도.
- **실패 시 명확한 안내**: 열을 못 찾으면 "완료 0건" 대신
  "열을 인식하지 못했습니다. 탭 구분인지 확인하세요" + 입력 앞부분을 표시.

### 검증
[csv_parser_use_case_test.dart](../test/csv_parser_use_case_test.dart) '은행 공통 동의어 인식' —
농협 형식(거래일자/적요/거래후잔액, 거래구분 없음), 토스 형식(단일 금액 +/-),
`받는분/보내는분` 상대방, `출금금액`이 `금액`으로 오인식되지 않음.

> **미확인:** 토스·농협의 실제 붙여넣기 머리글은 직접 확인하지 못했다.
> 흔한 표현을 동의어로 넣은 것이라, 벗어나면 에러 메시지에 실제 머리글이 보인다.
> 그 머리글을 동의어 목록에 추가하면 된다(한 줄).

---

## 4. 전 기관 붙여넣기 프로필 (키움증권 등)

### 증상
키움증권 계좌에서 "파서가 없다"고 나왔다.

### 원인
붙여넣기 프로필을 **은행 9개만 하드코딩**해서 시드했다.
증권·카드는 빠졌다.

### 수정
[seed_institutions.dart](../lib/data/database/seed_institutions.dart)의
`seedCsvParserProfiles()`를 **등록된 모든 기관에 붙여넣기 프로필을 자동 생성**하도록
변경. DB의 기관 목록을 읽어 각각 `_genericPaste()`로 만든다.

- 은행 9 + 카드 7 + 증권 4(키움 포함) 전부 커버.
- 앞으로 기관을 추가해도 자동으로 붙여넣기 프로필이 생김.
- upsert 로직을 `_upsertProfile()`로 분리. `(기관, source_type)` 기준이라
  앱 실행마다 호출돼도 중복이 안 쌓임.

**DB 마이그레이션 불필요** — 테이블 구조 변경 없음(seed 데이터만).
기존 설치도 다음 실행 때 `seedCsvParserProfiles()`가 빠진 기관 프로필을 채운다.

### 검증
[seed_paste_profiles_test.dart](../test/seed_paste_profiles_test.dart) —
모든 기관에 붙여넣기 프로필 존재 / 키움증권 포함 / seed 반복 실행해도 중복 없음.

> **미확인:** 증권사 거래내역은 형식이 은행과 다를 수 있다(종목명·수량·단가 등).
> 프로필은 생겼으니 시도는 되고, 인식 안 되면 에러에 실제 머리글이 보인다.

---

## 변경 파일

**수정 (작업 트리, 2·3·4)**
- `lib/application/csv_import/csv_parser_use_case.dart` — 날짜 유연 처리, 동의어 인식
- `lib/data/database/seed_institutions.dart` — 전 기관 프로필 자동 생성
- `test/csv_parser_use_case_test.dart` — 날짜·다중은행 테스트 추가

**신규 (작업 트리)**
- `test/seed_paste_profiles_test.dart`

**커밋됨 (`ac6989f`, 1)**
- `lib/presentation/screens/accounts/accounts_screen.dart`
- `lib/presentation/screens/transactions/transactions_screen.dart`
- `test/accounts_screen_test.dart`

> 2·3·4는 아직 커밋하지 않았다.

---

## 남은 것 / 확인 필요

- **증권·카드 실제 형식 확인**: 키움 등에서 가져와 보고, 안 되면 에러에 뜨는
  머리글을 동의어에 반영.
- **"탭 아닌 공백" 함정**: 데이터가 공백으로 들어오고 날짜·상대방에 공백이 섞이면
  여전히 인식이 어렵다. 지금은 탭으로 넣으면 동작하고, 실패 시 안내 메시지가 뜬다.
- **버전 미증가**: `pubspec.yaml`이 `1.0.0+1` 그대로라 앱 안에서 빌드 구분 불가.
  배포 시 `version`을 올리면 설정 화면(`package_info_plus`)에 반영된다.
