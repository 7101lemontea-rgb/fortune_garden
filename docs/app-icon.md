# 앱 아이콘 설정

작성일: 2026-10-04 · 브랜치: `develop`

노란 꽃 이미지를 Windows·Android 앱 아이콘으로 설정한 작업 기록.

## 요약

| 항목 | 내용 |
| --- | --- |
| 원본 이미지 | `assets/icon/app_icon.png` (512×512 RGBA) |
| 생성 도구 | `flutter_launcher_icons` (dev_dependency) |
| Windows | `windows/runner/resources/app_icon.ico` (256×256) 교체 |
| Android | `mipmap-*/ic_launcher.png` + 적응형 아이콘(배경 `#EAE2BF`) |
| 핵심 함정 | **Windows 아이콘 캐시** — exe는 바뀌어도 바로가기가 옛 아이콘 표시 |

---

## 1. 설정 방법

### 도구
표준 패키지 `flutter_launcher_icons`로 한 소스 이미지에서 플랫폼별 아이콘을
생성한다. 수동으로 `.ico`를 만들지 않아도 되고 유지보수가 쉽다.

### pubspec.yaml

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.1

flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"
  windows:
    generate: true
    icon_size: 256          # Windows .ico 최대 256
  android: true
  adaptive_icon_background: "#EAE2BF"   # 아이콘 배경색(베이지)
  adaptive_icon_foreground: "assets/icon/app_icon.png"
```

### 생성 명령

```bash
flutter pub get
dart run flutter_launcher_icons
```

생성물:
- `windows/runner/resources/app_icon.ico`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `android/app/src/main/res/mipmap-anydpi-v26/` (적응형)
- `android/app/src/main/res/values/colors.xml` (적응형 배경색)

변경 후 **Windows는 재빌드 필요**: `flutter build windows --release`.

---

## 2. 아이콘을 바꾸고 싶을 때

1. `assets/icon/app_icon.png`를 새 이미지로 교체 (정사각형, 512px 이상 권장)
2. `dart run flutter_launcher_icons`
3. `flutter build windows --release`
4. (바로가기가 안 바뀌면) 아래 **아이콘 캐시** 절 참고

---

## 3. Windows 아이콘 캐시 함정 ★중요

### 증상
exe에는 새 아이콘이 들어갔는데도, 바탕화면 **바로가기**는 예전 아이콘(Flutter
기본 로고)을 계속 보여준다. exe에서 바로가기를 **새로 만들어도** 옛 아이콘이 나온다.

### 원인
exe 자체의 아이콘은 정상이다. 문제는 Windows가 **exe 경로 → 아이콘**을
아이콘 캐시 DB에 저장해 두는 것. 같은 경로의 exe로 바로가기를 만들면
캐시된 옛 아이콘을 그대로 가져온다.

확인 방법(새 아이콘이 exe에 박혔는지):
```powershell
Add-Type -AssemblyName System.Drawing
$ico = [System.Drawing.Icon]::ExtractAssociatedIcon("경로\fortune_garden.exe")
$bmp = $ico.ToBitmap(); $bmp.GetPixel(16,16)   # 노랑이면 새 아이콘, 파랑이면 Flutter 기본
```

### 해결 (약한 것부터)

1. **바로가기 재저장 + 캐시 새로고침** (탐색기 안 끔)
   ```powershell
   ie4uinit.exe -show
   ie4uinit.exe -ClearIconCache
   ```

2. **아이콘 캐시 DB 삭제 + 탐색기 재시작** (확실, 화면 1~2초 깜빡임)
   ```powershell
   Stop-Process -Name explorer -Force
   Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -EA SilentlyContinue
   Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force -EA SilentlyContinue
   Start-Process explorer.exe
   ```
   > 탐색기를 끄는 동안 캐시 파일 잠금이 풀린다. 재시작은 try/finally로
   > 반드시 보장할 것(안 그러면 작업 표시줄이 사라진 채로 남는다).

3. **재부팅** — 캐시가 완전히 새로 만들어진다. 위가 다 안 들으면 최후 수단.

### 이번 작업에서
- exe 임베드 아이콘이 새 것임을 색 샘플로 확인(평균 RGB 249,226,84 = 노랑).
- 바로가기 타깃은 Release exe로 정상.
- 1·2번을 실행(캐시 DB 16개 삭제 + 탐색기 재시작)했다.
- **최종 표시 결과는 직접 눈으로 확인하지 못했다.** 바뀌지 않으면 3번(재부팅).

---

## 4. Android 참고 (미검증)

원본이 **원형 디자인**이다. Android 적응형 아이콘은 기기에 따라 바깥을
잘라내고(안전 영역 약 66%), 바깥쪽 꽃잎·장식이 잘릴 수 있다.
배경을 베이지(`#EAE2BF`)로 채워 자연스럽게 보이도록 했으나,
**Android 빌드로 실제 확인은 하지 못했다.** 잘림이 거슬리면:
- 여백을 둔 별도 전경 이미지를 `adaptive_icon_foreground`로 지정하거나
- 꽃을 더 작게 배치한 1024px 소스를 쓴다.

Windows는 마스킹이 없어 원본 그대로 나온다.

---

## 5. 변경 파일

**신규**
- `assets/icon/app_icon.png`
- `android/app/src/main/res/drawable-*/`, `mipmap-anydpi-v26/`, `values/colors.xml`

**수정**
- `pubspec.yaml` — flutter_launcher_icons 의존성·설정
- `windows/runner/resources/app_icon.ico`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`

> 아직 커밋하지 않았다.

## 참고: 창 제목
아이콘과 별개로 **창 제목**은 `windows/runner/main.cpp`의 `CreateAndShow`
호출 인자에서 바꾼다(현재 기본값 `fortune_garden`).
