# Memoria — 퍼블리시 체크리스트

> 커스텀 필터 기능 비활성화 상태로 Google Play / App Store 출시 기준
> 기준일: 2026-05-11

---

## 요약

| 등급 | 건수 | 설명 |
|------|------|------|
| CRITICAL | 5 | 미해결 시 100% 스토어 거절 |
| HIGH | 6 | 1점 리뷰 유발, 출시 전 필수 |
| MEDIUM | 6 | 완성도·폴리시 |
| 직접 작업 | 6 | 코드 외 운영 작업 (본인만 가능) |

---

## CRITICAL — 스토어 거절 블로킹

### C1. AdMob 테스트 ID 교체
- `lib/monetization/banner_ad_widget.dart:22`
- `lib/monetization/fullscreen_ad_service.dart:14-15`
- `android/app/src/main/AndroidManifest.xml:22`
- `ios/Runner/Info.plist:52`

현재 Google 공식 테스트 ID 4개가 그대로 박혀 있음. 프로덕션 빌드에 테스트 ID → AdMob 정책 위반으로 자동 거절.

```
교체 대상:
  배너       ca-app-pub-3940256099942544/6300978111  → 실제 배너 ID
  전면       ca-app-pub-3940256099942544/1033173712  → 실제 전면 ID
  보상형     ca-app-pub-3940256099942544/5224354917  → 실제 보상형 ID
  앱ID(AOS)  ca-app-pub-3940256099942544~3347511713  → 실제 앱 ID
  앱ID(iOS)  ca-app-pub-3940256099942544~1458002511  → 실제 앱 ID
```

- [ ] AdMob 콘솔에서 앱 등록 후 실제 ID 발급
- [ ] 5곳 전부 교체
- [ ] 실기기에서 실제 광고 노출 확인

---

### C2. Android 릴리즈 서명 미설정
- `android/app/build.gradle:48`

```gradle
// 현재 (잘못됨)
release {
    signingConfig signingConfigs.debug
}
```

debug 키로 서명된 APK는 Play Store 업로드 자체가 불가.

```bash
# keystore 생성
keytool -genkey -v -keystore memoria-release.jks \
  -alias memoria -keyalg RSA -keysize 2048 -validity 10000
```

```gradle
// build.gradle 수정
signingConfigs {
    release {
        storeFile file(System.getenv("KEYSTORE_PATH"))
        storePassword System.getenv("KEYSTORE_PASS")
        keyAlias "memoria"
        keyPassword System.getenv("KEY_PASS")
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

- [ ] `memoria-release.jks` 생성 (저장소 외부에 보관)
- [ ] 환경변수 3개 설정
- [ ] `flutter build apk --release` 후 `jarsigner -verify` 확인

---

### C3. 개인정보처리방침 없음
두 스토어 모두 제출 시 필수 URL 요구. 없으면 심사 반려.

작성 필요 항목:
- 수집 데이터: 광고 식별자, 기기 정보, 크래시 로그
- 이용 목적: 광고 제공(AdMob), 기능 개선
- 제3자 제공: Google AdMob
- 보관 기간 및 파기
- 사용자 권리 (열람·삭제 요청)
- GDPR / 개인정보보호법 준수

- [ ] 한국어 + 영어 개인정보처리방침 작성
- [ ] HTTPS 도메인에 호스팅 (GitHub Pages / Notion 공개페이지 가능)
- [ ] 앱 설정 화면에 링크 추가
- [ ] Play Console / App Store Connect 제출 폼에 URL 입력

---

### C4. 런타임 권한 요청 없음
- `lib/features/home/home_page.dart:36-41` (갤러리)
- `lib/features/home/home_page.dart:44-50` (카메라)
- `lib/features/filters/filters_page.dart:167-175` (갤러리)

Android 6+ / iOS 10+: 권한을 런타임에 요청하지 않으면 크래시 또는 조용한 실패.
Android 13+는 `READ_MEDIA_IMAGES` 필수.

```dart
// pubspec.yaml 추가
permission_handler: ^11.0.0

// 사용 전 요청
final status = await Permission.photos.request();
if (!status.isGranted) {
  _showSnackBar(S.get('permission.photos_denied'));
  return;
}
final file = await ImagePicker().pickImage(...);
```

- [x] `permission_handler` 패키지 추가
- [x] 갤러리 열기 전 권한 요청 (3곳: home/filters/filters_page)
- [x] 카메라 열기 전 권한 요청 (1곳: home)
- [x] 권한 거부 시 스낵바 표시 (크래시 없이)
- [x] Android 13+ `READ_MEDIA_IMAGES` 매니페스트 확인

---

### C5. 내보내기 — 앱 내부 폴더에 저장 (사용자 접근 불가)
- `lib/features/editor/editor_page.dart:378`

```dart
// 현재 (잘못됨)
final docsDir = await getApplicationDocumentsDirectory();
final outPath = '${docsDir.path}/export_${timestamp}.jpg';
```

사용자가 내보낸 사진을 찾을 수 없음 → "저장이 안 된다" 1점 리뷰.

```dart
// 수정: gal 패키지 (경량)
await Gal.putImageBytes(imageBytes, name: 'memoria_$uuid.jpg');
```

- [x] `gal` 패키지 추가
- [x] 내보내기 완료 후 갤러리에 저장
- [x] "사진 앱에 저장되었습니다" 토스트 표시
- [x] Android `WRITE_EXTERNAL_STORAGE` 권한 (API 28 이하) 처리
- [x] iOS `NSPhotoLibraryAddUsageDescription` Info.plist 확인

---

## HIGH — 출시 전 필수

### H1. 커스텀 필터 UI 숨기기
- `lib/features/home/home_page.dart:286-292`
- 하단 탭 내 Create Filter 진입점

`kPhotoFilterGenerationEnabled = false`인데 UI는 그대로 노출 → 탭하면 "준비 중" 메시지 → 불완성 인상.

```dart
if (kPhotoFilterGenerationEnabled)
  _FilterStudioCard(),
```

- [x] 홈 "필터 스튜디오" 카드 조건부 숨김 (kPhotoFilterGenerationEnabled)
- [x] 필터 페이지 Create Filter 카드 조건부 숨김
- [x] 라우트는 유지 (내부 테스트용), UI 진입점만 제거

---

### H2. `decodeImage()` null-assert 크래시
- `lib/features/editor/editor_page.dart:241`
- `lib/features/create_filter/create_filter_page.dart:68-69`

```dart
// 현재 (크래시 위험)
var image = img.decodeImage(bytes)!;

// 수정
final image = img.decodeImage(bytes);
if (image == null) {
  _showSnackBar(S.get('editor.invalid_image'));
  if (mounted) context.pop();
  return;
}
```

- [x] 두 파일 모두 null 체크 후 에러 처리 (editor_page.dart _renderPreview + _export)

---

### H3. 내보내기 취소 불가 + 메인 스레드 블로킹
- `lib/features/editor/editor_page.dart:316-402`

대용량 이미지(8MP+) 내보내기 시 20초 이상 멈춤, 취소 버튼 없음.

```dart
// isolate로 이동
final result = await compute(_exportIsolate, exportParams);

// 취소 버튼
if (_exporting)
  TextButton(
    onPressed: _cancelExport,
    child: Text(S.get('editor.cancel')),
  ),
```

- [x] 내보내기 로직 `compute()` 또는 Isolate로 분리
- [x] 진행 중 취소 버튼 표시
- [x] 취소 시 임시 파일 정리

---

### H4. 슬라이더 드래그마다 전체 렌더링
- `lib/features/editor/editor_page.dart` 슬라이더 onChange 전체

슬라이더를 움직일 때마다 `_renderPreview()` 호출 → 대용량 이미지에서 버벅임.

```dart
Timer? _debounce;

void _onSliderChanged(double v) {
  setState(() => _params = _params.copyWith(...));
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 250), _renderPreview);
}
```

- [x] 모든 슬라이더 onChange에 250ms 디바운스 적용 (_debouncedPreview)

---

### H5. Settings 페이지 한국어 하드코딩
- `lib/features/settings/settings_page.dart:37-40, 97-115, 183-222`

영어로 전환해도 Settings는 한국어 그대로.

- [x] 하드코딩 한국어 문자열 전부 `S.get()` 으로 교체
- [x] `strings.dart`에 EN 번역 추가
- [x] 언어 전환 후 Settings 재진입 확인 (ValueListenableBuilder로 전체 리빌드 처리)

---

### H6. 에디터 빈 상태 한국어 하드코딩
- `lib/features/editor/editor_page.dart:723`

```dart
// 현재
Text('사진을 선택하세요')

// 수정
Text(S.get('editor.no_image_selected'))
```

- [x] `S.get()` 교체 (editor.no_image_selected)
- [x] 빈 상태에서 뒤로가기 또는 이미지 선택 버튼 표시

---

## MEDIUM — 완성도

### M1. 필터 페이지 로딩·에러 상태 없음
- `lib/features/filters/filters_page.dart:49`

- [x] 로딩 중 `CircularProgressIndicator` 표시
- [x] 로드 실패 시 재시도 버튼 표시

---

### M2. 내보내기 파일명 충돌 가능
- `lib/features/editor/editor_page.dart:378`

```dart
// 수정
final name = 'memoria_${DateTime.now().microsecondsSinceEpoch}';
```

- [x] `millisecondsSinceEpoch` → `microsecondsSinceEpoch` 또는 UUID

---

### M3. 네트워크 없을 때 광고 처리
- `lib/monetization/fullscreen_ad_service.dart`

- [ ] `connectivity_plus` 로 오프라인 감지
- [ ] 오프라인 시 광고 요청 스킵, 앱 기능은 정상 진행

---

### M4. 안 쓰는 폰트 정리
- `pubspec.yaml`

현재 7개 폰트 번들 (Domine, NotoSerif, Montserrat, Oswald, Raleway, AmaticSC, Pacifico).
실제 사용하는 폰트만 남기면 앱 용량 ~300KB 절감.

- [ ] 실제 사용 폰트 확인 후 미사용 제거

---

### M5. Target SDK API 34 확인
- `android/app/build.gradle`

2025년 Play Store 신규 앱 기준 API 34 필수.

- [ ] `targetSdkVersion 34` 설정 확인
- [ ] API 34 동작 테스트

---

### M6. 64bit TFLite 네이티브 라이브러리
- `android/`

- [ ] `arm64-v8a` ABI 포함 여부 확인
- [ ] Play Store 64bit 요구사항 충족 확인

---

## 직접 해야 하는 작업 (코드 외)

| # | 항목 | 비고 |
|---|------|------|
| A | **AdMob 계정 생성** + 앱 등록 → 실제 Unit ID 5개 발급 | admob.google.com |
| B | **Android 릴리즈 키스토어 생성** (`keytool`) + 안전한 곳에 백업 | 분실 시 앱 업데이트 불가 |
| C | **개인정보처리방침 작성** + HTTPS 호스팅 | GitHub Pages 무료 가능 |
| D | **실기기 테스트** — Pixel/Samsung(Android 13+), iPhone(iOS 15+) | 권한·내보내기·광고 중점 |
| E | **Play Console / App Store Connect 앱 등록** + 콘텐츠 등급·스크린샷·아이콘 준비 | |
| F | **iOS 코드 서명** — Apple Developer 팀 ID + 프로비저닝 프로파일 (Xcode) | Apple Developer 계정 필요 |

---

## 권장 작업 순서

```
1단계 (2~3일) — 크래시·거절 방지 (코드)
  H2  decodeImage null 크래시 제거
  C4  런타임 권한 요청 추가
  C5  내보내기 갤러리 저장
  H1  커스텀 필터 UI 숨김
  H3  내보내기 isolate + 취소 버튼
  H4  슬라이더 디바운스
  H5  Settings 한국어 하드코딩 제거
  H6  에디터 빈 상태 로컬라이즈

2단계 (직접, 병행 가능)
  A   AdMob 실제 ID 발급
  B   Android 키스토어 생성
  C   개인정보처리방침 작성·호스팅

3단계 (1~2일) — 운영 설정 코드 반영
  C1  AdMob ID 5곳 교체
  C2  build.gradle 서명 설정
  C3  앱 내 개인정보 링크 추가
  M1~M4 폴리시

4단계 — 실기기 QA + 스토어 제출
  D   실기기 테스트
  E   스토어 등록
  F   iOS 서명
```

---

## 앱 크기 현황

| 구성 | 크기 |
|------|------|
| Flutter 베이스 + 플러그인 | ~50MB |
| 내장 LUT 7개 | ~11MB |
| 폰트 (현재 7종) | ~3MB |
| 프레임·오버레이 에셋 | ~5MB |
| **합계 (현재 추정)** | **~70MB** |
| 앱 용량 상한 | 200MB |

ML 모델 미번들 기준. 200MB 상한까지 여유 충분.
