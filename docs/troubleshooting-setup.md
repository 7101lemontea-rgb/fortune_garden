# 개발 환경 문제 해결 기록

작성일: 2026-10-03

## 요약

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `main` 브랜치에 개발 내용이 없음 | 로컬이 `main`을 보고 있었음 (개발은 `develop`에 있음) | `git switch develop` |
| 여러 페이지에 빨간 오류 표시 | 자동 생성 코드(`*.g.dart`, `*.freezed.dart`)가 없음 | `flutter pub get` 후 `build_runner` 실행 |
| `test/widget_test.dart` 오류 | Flutter 기본 카운터 템플릿이 존재하지 않는 `MyApp` 사용 방식을 참조 | 자리표시자 테스트로 교체 |

---

## 1. `main` 브랜치에 개발 내용이 없음

### 증상
GitHub과 로컬의 `main` 브랜치에 초기 설정 커밋 하나만 있고, 실제 개발 코드가 보이지 않았습니다.

### 원인
브랜치가 꼬인 것은 아닙니다.

- `main`: 초기 설정 커밋 `6db6ab0` 하나만 있음
- `develop`: `6db6ab0`에서 갈라져 나와 이후 개발 커밋이 모두 쌓여 있음 (최신: `77418fa`, 2026-04-17)

로컬 작업 폴더가 `main`을 체크아웃하고 있었기 때문에 개발 내용이 보이지 않았습니다.

### 해결
```bash
git fetch --all
git switch develop   # origin/develop을 추적하는 로컬 develop 브랜치 생성
```

`main`은 변경하지 않았습니다.

---

## 2. 여러 페이지에 빨간 오류 표시

### 증상
develop 전환 후 VSCode에서 DB, Provider를 사용하는 대부분의 파일에 오류가 표시됐습니다.

### 원인
이 프로젝트는 drift, riverpod_generator, freezed로 코드를 자동 생성합니다. `.gitignore`가 생성 파일을 저장소에서 제외하고 있습니다.

```gitignore
*.g.dart
*.freezed.dart
```

그래서 저장소를 clone하거나 브랜치를 새로 받은 직후에는 생성 파일이 없고, 이를 참조하는 코드가 모두 오류로 표시됩니다.

### 해결
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

생성 파일 113개가 만들어졌고, `lib/`의 오류는 모두 사라졌습니다.

> VSCode에 빨간 표시가 남아 있으면 `Ctrl+Shift+P` → **Dart: Restart Analysis Server**를 실행하세요.

### 앞으로 주의할 점
다음 경우에는 위 명령을 다시 실행해야 합니다.

- 새 PC에서 clone한 경우
- 테이블(`lib/data/database/`), `@riverpod` provider, `@freezed` 모델을 수정한 경우

개발 중에는 아래 명령을 켜 두면 파일을 저장할 때마다 자동으로 다시 생성됩니다.

```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## 3. `test/widget_test.dart` 오류

### 증상
```
error - The name 'MyApp' isn't a class - test\widget_test.dart:16:35
```

### 원인
Flutter 프로젝트를 만들 때 생성되는 기본 카운터 앱 테스트가 그대로 남아 있었습니다. 이 테스트는 `main.dart`에 `MyApp`과 카운터 버튼이 있다고 가정합니다. 실제 앱에는 카운터가 없고 `MyApp`은 `lib/app.dart`에 있는 `ConsumerStatefulWidget`이어서 맞지 않습니다.

### 해결
의미 없는 템플릿 테스트를 자리표시자 테스트로 교체했습니다. 실제 위젯 테스트는 `ProviderScope`와 DB 목업을 구성한 뒤 추가해야 합니다.

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    expect(true, isTrue);
  });
}
```

---

## 현재 상태

`flutter analyze` 결과: **error 0개**. 실행에 지장 없는 경고·정보 172개가 남아 있습니다.

| 종류 | 개수 | 비고 |
| --- | --- | --- |
| `deprecated_member_use` | 149 | `withOpacity` 등 구버전 API |
| `unused_import` / `unused_local_variable` | 16 | 정리 가능 |
| `unnecessary_non_null_assertion` / `unnecessary_import` | 4 | 정리 가능 |
| `use_build_context_synchronously` | 2 | async 이후 `context` 사용. 확인 권장 |
| `unused_element` | 1 | 정리 가능 |

## 참고: drift 빌드 경고
`build_runner` 실행 시 아래 경고가 나오지만, 빌드는 정상적으로 완료됩니다.

```
Column provided in a single-column uniqueKey set already has a column-level UNIQUE constraint
  lib/data/database/tables.dart:129 (Transactions)
  lib/data/database/drift_indexes.dart:52 (TransactionsIndexed)
```

`Transactions` 테이블의 한 컬럼에 컬럼 단위 `unique()`와 테이블 단위 `uniqueKeys`가 중복으로 지정되어 있다는 뜻입니다. 둘 중 하나를 제거하면 경고가 사라집니다.
