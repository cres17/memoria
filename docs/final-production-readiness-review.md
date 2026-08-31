# Memoria 최종 프로덕션 준비도·코드 품질 감사

- 감사일: 2026-08-20 KST
- 대상: Memoria 저장소 현재 작업 트리
- 기준 브랜치/HEAD: `agent/fix-ios-lut-target` / `3e894361`
- 관점: PM, 사용자, 소프트웨어 아키텍처, 정적 분석, 동적 테스트, 배포 운영
- 판정 범위: 코드와 저장소 안에서 증명 가능한 사실만 사용했다. 실제 iPhone Photos 저장 완료, App Store 심사, Android 실기기, 인간 블라인드 화질 평가는 수행됐다고 간주하지 않았다.

## 0. 후속 수정 진행 현황

이 절은 최초 감사 뒤 같은 날 진행한 수정 결과다. 아래 본문의 최초 발견 내용은 감사 당시 증거로 보존하며, 현재 상태 판단에서는 이 절과 `PUBLISH_CHECKLIST.md`를 우선한다.

완료:

- 저장소 ignore에 가상환경, 학습 산출물, coverage, dist를 추가했다.
- Original + Fuji 18종 + Leica 5종을 실제 65³ LUT, 고정 장면 썸네일, 브랜드 표시와 연결했다.
- history schema v2에 artistic, selective, dodge/burn strokes, tilt shift, radial focus blur 상태를 포함했다.
- history와 함께 crop bounds, expand, brush strokes, edit session을 draft에 저장·복원한다.
- production `EditorPage`의 원형 초점 흐림 apply → undo → redo와 draft payload 회귀 테스트를 추가했다.
- 과장된 기능명을 `인물 영역`, `틸트 시프트`, `원형 초점 흐림`으로 수정하고 인물 모델 상태·재시도 안내를 추가했다.
- 커스텀 필터 생성은 활성 상태를 유지하되 HOME, Gallery, CREATE 화면에서 명시적으로 `BETA` 표시한다.
- CI Flutter 버전을 3.44.6으로 고정하고 lockfile, analyze, full test, coverage, runtime asset, iOS simulator/release build gate를 추가했다.
- 손상된 `.drift-gate.yml` version key와 CocoaPods Profile xcconfig를 수정했다.
- README와 퍼블리시 체크리스트를 실제 지원 범위로 다시 작성했다.
- production에서 import되지 않고 별도 테스트만 통과하던 Crop/Rotate/Perspective/HDR/Brush standalone panel을 제거했다.
- 전역 Flutter/platform error boundary와 기기 내 최대 500줄 영구 진단 로그를 추가했다.

재검증 결과:

- analyzer: error/warning 0. info lint만 존재.
- 전체 Flutter test: 현재 트리 460개 통과, 로컬 fixture 의존 테스트 1개 조건부 skip.
- iPhone 17 Pro 시뮬레이터 white-box: 3개 통과.
- simulator debug 측정: frame p95 약 9.7ms, preview p95 약 33.7ms, export first-progress 약 188.6ms, cancel 약 280.1ms.
- iOS simulator debug build와 unsigned release build 통과. release Runner.app 137.1MB.
- 마지막 영구 진단 로그 변경까지 포함해 정적 분석과 전체 Flutter test를 다시 통과했다.

아직 출시 차단:

- 작업 트리를 제품 allowlist로 commit하고 clean checkout CI를 통과해야 한다.
- 무선 iPhone은 로컬 네트워크/연결 문제로 profile 성능 테스트를 완료하지 못했다.
- Photos/share complete export, peak RSS, Android signing/build/실기기, privacy contact/HTTPS URL, 광고 정책은 미완료다.
- canonical `EditorRecipe` 분리와 남은 `EditorPage` 내부 legacy UI 제거는 P1 구조 작업으로 남아 있다.

다음 수정 순서:

1. 제품 allowlist를 검토해 lockfile, runtime asset, 테스트, 문서를 한 commit으로 고정하고 clean-checkout CI를 실행한다.
2. 잠금 해제된 iPhone을 USB 또는 정상 Local Network 연결로 붙여 profile 성능·완주 export·Photos/share gate를 실행한다.
3. 그 증거가 통과한 뒤에만 canonical `EditorRecipe`, typed failure, accessibility/localization P1 리팩터링을 진행한다.

실기기와 clean-checkout 증거 없이 3번 구조 리팩터링을 먼저 확대하지 않는다. 현재 출시 판단을 바꾸는 가장 큰 불확실성은 코드 스타일이 아니라 재현 가능한 commit과 실제 기기 export/메모리 결과다.

## 1. 결론

**현재 상태는 내부 베타/제한된 TestFlight 후보이며, 일반 사용자 대상 프로덕션 출시 승인은 불가하다.**

기능 엔진과 단위 테스트는 상당히 축적됐고, 기본 보정·색 도구·그레인·프레임·텍스트·내보내기·Direct MVP 필터 생성의 핵심 계산 경로는 이전보다 분명히 좋아졌다. 전체 단위/위젯 테스트 468개도 통과했다.

그러나 출시를 막는 문제는 테스트 개수가 아니라 실제 제품 연결성이다.

1. 실제 편집 화면의 undo/redo 이력이 부분 보정, 브러시, 아웃포커스, 렌즈 흐림, 드라마/HDR 상태를 저장하지 않는다.
2. 47MB의 Fuji/Leica LUT 자산은 앱 코드에서 사용되지 않는다. 사용자는 요구했던 Fuji/Leica 필터가 아니라 별도의 9개 파라미터 프리셋을 본다.
3. 실제 `EditorPage` 테스트 커버리지는 18.67%인데, 제품에서 쓰지 않는 별도 패널 테스트는 80~100%다. 테스트 숫자가 실제 사용자 안정성을 과대평가한다.
4. 인물 보정은 얼굴/피부 마스크가 아니라 전체 사람 마스크를 사용한다. 렌즈 흐림은 실제 depth가 아니라 화면 중앙 기준 방사형 가짜 depth를 쓴다.
5. 필터 생성 모델은 앱에 연결됐지만 iOS/Android 실기기 latency·peak memory·피부/미관·blind preference gate가 끝나지 않았다. 그럼에도 제품 진입점은 활성화돼 있다.
6. 현재 작업 트리는 tracked 수정 63개, untracked 항목 89개다. 모델, 통합 테스트, 핵심 신규 서비스와 문서 일부가 아직 Git 추적 대상이 아니므로 현재 상태를 CI나 다른 개발자가 재현할 수 없다.
7. Web release 빌드는 실제로 실패한다. README의 Android/iOS/Windows/Web 지원 주장은 현재 검증 범위를 넘어가며 Web은 명백히 사실이 아니다.
8. CI는 iOS 빌드만 수행하고 `flutter analyze`, `flutter test`, integration/performance gate를 실행하지 않는다.

### 종합 점수

이 점수는 절대 품질 수치가 아니라, 동일 기준으로 우선순위를 정하기 위한 PM 위험 점수다.

| 영역 | 점수 | 판정 |
|---|---:|---|
| 제품 기능 완성도 | 56/100 | 기본 도구는 작동하나 고급 도구 품질과 연결성이 부족 |
| 아키텍처·모듈화 | 38/100 | 엔진 모듈은 있으나 실제 orchestration은 대형 화면 클래스에 집중 |
| 상태·파이프라인 연결성 | 42/100 | preview/export는 연결됐지만 history와 canonical player가 분리 |
| 코드 품질·유지보수성 | 52/100 | analyzer error는 없으나 거대 파일, silent catch, 중복 구현이 큼 |
| 오류 복구·관측성 | 40/100 | 일부 사용자 오류 표시는 있으나 전역 crash/error 수집이 없음 |
| 성능 준비도 | 50/100 | 최적화 구조는 있으나 현재 commit의 실기기 전체 gate 증거가 없음 |
| 테스트 신뢰도 | 48/100 | 468개 통과, `lib` 49.46%; 실제 편집 화면 18.67% |
| 사용자 경험 | 57/100 | 기본 편집 UX는 개선됐으나 고급 기능 기대와 실제 수준 차이가 큼 |
| 배포·운영 준비도 | 27/100 | 작업 트리, CI, 서명, 광고/개인정보, 다중 플랫폼 증거가 불완전 |
| **종합** | **46/100** | **내부 베타 가능, 프로덕션 출시 보류** |

## 2. 감사 방법과 실제 실행 결과

### 2.1 저장소 규모

| 항목 | 현재 값 |
|---|---:|
| `lib` Dart 파일 | 96개 |
| `test` Dart 파일 | 71개 |
| `integration_test` 파일 | 2개 |
| `lib` 원시 LOC | 32,146줄 |
| 전체 asset | 91MB |
| 모델 asset | 35MB |
| LUT asset | 47MB |
| frame asset | 3.5MB |
| overlay asset | 3.7MB |
| iOS Simulator `Runner.app` | 236MB, store download 크기가 아님 |

가장 큰 파일은 다음과 같다.

| 파일 | LOC | 평가 |
|---|---:|---|
| `lib/features/editor/editor_page.dart` | 7,818 | UI, 상태, history, preview, export, AI, 파일 I/O가 한 클래스에 혼재 |
| `lib/features/create_filter/create_filter_page.dart` | 2,557 | UI와 생성 workflow orchestration이 과도하게 결합 |
| `lib/engine/custom_lut_core.dart` | 2,168 | 알고리즘 복잡도가 높으나 비교적 엔진 역할은 명확 |
| `lib/engine/lut_engine.dart` | 1,449 | 핵심 LUT 엔진, 테스트 커버리지 양호 |

### 2.2 정적 분석

- `flutter analyze --format machine`: error 0, warning 3, info 184.
- warning 3개는 모두 `tool/`의 unused import/local이다.
- 다만 가장 큰 프로덕션 파일 첫 줄에 `unused_element`, `unused_field`, `unused_element_parameter` ignore가 있어 analyzer가 그 파일의 미사용 코드를 보고하지 못한다.
- `lib`에서 `catch (_)` 형태가 45곳이다. 일부는 haptic/fallback처럼 의도적이나 저장소 손상, asset 누락, 모델 실패도 조용히 기본값/no-op으로 바뀐다.
- `git diff --check`: 공백 오류 없음.

### 2.3 단위·위젯 테스트와 커버리지

- `flutter test --coverage --reporter compact`: **468 passed, 1 skipped, exit 0**.
- skip된 `neural_lut_predictor_test`는 오래된 `assets/models/color_transfer.tflite` 또는 테스트 사진을 찾지 못한다. 현재 번들 모델 계약과 동기화되지 않은 stale test다.
- Direct MVP Flutter wrapper: macOS 테스트에서 628ms. 모바일 latency 수치로 사용할 수 없다.
- 전체 `lib` 라인 커버리지: **49.46% (6,365 / 12,869)**.
- `EditorPage`: **18.67% (692 / 3,707)**.
- `CreateFilterPage`: 63.49%.
- `LutEngine`: 92.33%.
- `CustomLutCore`: 59.28%.
- 실제 화면에서 사용되지 않는 `BrushToolbar`와 `PerspectivePanel`, `RotateFlipPanel`은 100%, `CropPanel`은 80.77%다.

따라서 “468개 통과”는 엔진 회귀 방지에는 긍정적이지만 “모든 사용자 기능이 작동한다”는 증거가 아니다.

### 2.4 iOS 시뮬레이터 동적 테스트

iPhone 17 Pro 시뮬레이터에서 현재 프로덕션 `EditorPage`와 실제 임시 이미지 파일을 사용한 통합 테스트를 실행했다.

- `editor_whitebox_device_test.dart`: 3/3 통과.
  - 기본 보정 초기화와 적용 transaction.
  - 첫 번째 back은 도구 취소, 두 번째 back은 편집 종료 확인.
  - crop 1:1 선택과 자유 비율 초기화.
- `editor_performance_test.dart`: 2/2 통과.
  - 기본 보정 슬라이더 frame/preview sample 수집 경로.
  - 3072×2304 export progress 표시와 취소 overlay 종료.

제한 사항이 중요하다.

- white-box device test는 선택 보정, 브러시, 블러, 인물, 텍스트, 프레임, filter transaction, undo/redo, export 완료를 검사하지 않는다.
- performance test 자체는 첫 progress가 보이고 취소가 끝났는지만 assert한다. p95 latency 임계값은 별도 JSON과 `tool/perf_gate.dart`를 실행해야 적용된다.
- 이번 현재 작업 트리 실행에서는 보존된 performance JSON이 없다.
- 과거 문서에는 실제 iPhone frame p95 0.862ms, warm preview p95 43.599ms, export first progress 457.719ms, cancel 266.456ms가 기록돼 있다. 좋은 결과이지만 현재 commit에 artifact가 묶여 있지 않아 최종 release evidence로 재사용할 수 없다.
- 실제 Photos 저장 완료, share sheet 소비 앱에서의 파일 형식, 완주 export checksum/RSS는 미검증이다.

### 2.5 플랫폼 빌드

| 대상 | 결과 | 해석 |
|---|---|---|
| iOS Simulator | build 및 위 통합 테스트 통과 | iOS 기본 컴파일 가능 |
| Web release | **실패** | `tflite_flutter`가 `dart:ffi`를 직접 import하여 dart2js 컴파일 불가 |
| Android debug | 검증 불가 | 로컬에 Android SDK/`ANDROID_HOME`이 없어 코드 실패로 판정하지 않음 |
| Windows | 미검증 | 현재 CI와 감사 환경에서 증거 없음 |

README에는 Android, iOS, Windows, Web을 지원한다고 적혀 있다. 현재 확실히 승인 가능한 플랫폼은 iOS뿐이며, Web 주장은 제거하거나 조건부 AI 구현을 만든 후 복구해야 한다.

## 3. P0 출시 차단 문제

### P0-1. 편집 history가 모든 출시 도구를 표현하지 못한다

`EditorPage._saveToHistory()`는 다음만 저장한다.

- 누적 `AdjustParams`
- filter/preset 정보
- crop/rotate/flip/perspective/expand snapshot
- portrait의 smooth/spotlight/skin tone 일부
- double exposure/frame/text 일부

다음 사용자 상태는 history operation에 없다.

- 선택 보정의 active, 좌표, 밝기/대비/채도, radius
- 브러시 stroke 목록과 brush mode
- tilt/outfocus의 focus/band/blur
- lens blur의 focus/radius
- `ArtisticEffect`, effect strength, grain variant

`_historyToolForActiveTool()`도 이 도구들을 대부분 `globalAdjust`로 분류하고, `_applyHistorySnapshot()`은 위 상태를 복원하지 않는다.

사용자 영향:

- 효과를 적용한 뒤 다른 도구를 적용하고 undo하면 화면과 history 의미가 달라질 수 있다.
- redo가 사용자가 보았던 부분 보정/브러시/블러 상태를 복원하지 못한다.
- “비파괴 편집 스택과 재현 가능한 세션”이라는 README 약속이 성립하지 않는다.

조치:

1. 한 operation schema가 모든 출시 도구의 완전한 snapshot 또는 명시적 delta를 표현하게 한다.
2. `EditorPage`의 preview/export/history와 `EditOperationPlayer`를 동일한 canonical recipe로 연결한다.
3. 각 도구에 apply → 다른 도구 → undo → redo → draft reload → export pixel test를 추가한다.

### P0-2. 요구한 Fuji/Leica 필터와 실제 제품 필터가 연결되지 않았다

`assets/luts/`에는 Fuji/Leica를 포함한 약 29개의 `.bin`과 총 47MB 자산이 있다. 그러나 production `lib`에는 이 경로를 참조하는 catalog가 없다.

실제 `BuiltinPresets.all`은 `Original`, `Portrait`, `Smooth`, `Pop`, `Accentuate`, `Faded Glow`, `Morning`, `Fine Art`, `Structure`의 9개 params-only 프리셋이다. `REQUIREMENTS.md`의 다음 항목과 다르다.

- Fuji/Leica만 남긴다.
- 브랜드 로고를 표시한다.
- 필터 고유 색감을 고정 샘플에 보여준다.

더 위험한 점은 golden test가 Fuji/Leica LUT 파일을 직접 읽어 엔진을 검증한다는 것이다. 테스트한 LUT 엔진과 사용자가 보는 필터 catalog가 분리돼 있다.

조치 선택지는 둘뿐이다.

- Fuji/Leica가 제품 요구라면 manifest/catalog를 만들고 LUT, 썸네일, 브랜드 표시, intensity, preview/export를 실제 UI에 연결한다.
- 아니라면 요구사항과 README를 수정하고 사용되지 않는 47MB LUT를 bundle에서 제거한다.

현재처럼 자산만 포함하는 상태가 가장 나쁘다. 기능은 없고 앱 크기만 증가한다.

### P0-3. 현재 소스 상태가 재현·배포 불가능하다

현재 `git status`는 tracked 수정 63개, untracked 항목 89개다. 다음 핵심 파일들이 `git ls-files`에 나타나지 않는다.

- 번들 Direct MVP 모델
- 새 create-filter service
- integration tests
- 이번까지 작성된 주요 계획 문서 일부

또한 `.venv-ml-tflite` 2.2GB, `LUT/` 1.2GB, `ml_pipeline/.venv-tflite` 1.4GB, `ml_pipeline/reports` 354MB, `dist` 136MB가 untracked이며 일부는 `.gitignore`에 없다.

사용자 영향:

- 현재 로컬에서 되는 기능이 GitHub Actions checkout에서는 사라진다.
- 실수로 `git add .`를 하면 수 GB의 학습/가상환경/배포 산출물이 포함될 위험이 있다.
- 감사 결과와 release binary가 같은 소스인지 증명할 수 없다.

조치:

1. 먼저 `.gitignore`를 보강한다.
2. 제품 코드, 테스트, 문서, 승인된 runtime asset만 allowlist로 stage한다.
3. 35MB 모델의 배포/LFS 정책과 라이선스·SHA를 확정한다.
4. 깨끗한 checkout에서 pub get → analyze → test → iOS/Android build를 재실행한다.

### P0-4. 필터 생성은 기능 플래그가 켜졌지만 출시 품질 gate가 끝나지 않았다

긍정적인 사실:

- Direct MVP family-holdout 모델, ID/version/SHA, NCHW 입력, 17³ 출력과 Dart 65³ upsample 계약이 코드에 고정됐다.
- 번들 설치의 atomic copy와 SHA 검증 test가 있다.
- 생성 worker는 timeout, cancel, 실패 artifact cleanup을 지원한다.
- 생성 → save → reload → apply roundtrip test가 있다.
- 학습 문서상 family test에서 direct MVP가 interpolation보다 sample ΔE 0.801, LUT-macro ΔE 0.778 낮고 V2보다도 우수했다.

미완료 사실:

- iOS/Android cold/warm latency와 peak memory.
- same-style/different-scene, unseen hue, skin fixture 승인.
- blind preference에서 baseline 우위.
- PhotoKit limited/iCloud 실제 사진 경로.
- 다중 참조는 neural generator가 아니라 algorithmic profile fusion.
- Before/After pair는 geometric alignment와 local-edit masking이 없다.
- 모델을 못 쓰면 조용히 algorithmic fallback을 쓰고, 사용자에게 품질 등급 차이를 명확히 설명하지 않는다.

`kPhotoFilterGenerationEnabled`는 현재 `true`다. 따라서 이 기능은 베타 배지/실험 플래그로 제한하거나, 위 gate를 닫기 전 일반 사용자에게 “AI 필터 생성 완료”로 약속하면 안 된다.

### P0-5. 인물·렌즈 기능의 이름과 실제 알고리즘 수준이 다르다

인물 보정:

- 실제 사용 모델은 binary `SelfieSegmenter`, 즉 배경 대 사람 전체 subject mask다.
- 같은 mask로 skin smoothing, spotlight, skin tone을 처리한다.
- hair/clothes/body와 face skin을 분리하는 `MulticlassSegmenter`는 구현돼 있지만 production에서 사용하지 않는다.
- 얼굴이 아니라 사람 전체에 보정이 번질 수 있다.
- 모델이 다운로드되지 않으면 zero mask로 fail-closed 하는 점은 안전하지만, 사용자는 기능이 왜 적용되지 않는지 알 수 없다.

렌즈 흐림:

- `DepthEstimator`는 구현돼 있지만 production에서 사용하지 않는다.
- 실제 렌즈 흐림은 이미지 중앙에서 거리가 증가하는 synthetic radial map을 depth처럼 사용한다.
- 피사체의 실제 앞뒤 관계와 무관하다.

조치:

- face-skin mask가 연결되기 전에는 “피부 스무딩”을 숨기거나 “인물 영역 부드럽게”처럼 정확히 표시한다.
- lens blur는 depth/subject-aware 구현 전까지 “원형 흐림”으로 이름을 바꾸거나 숨긴다.
- 모델 상태와 재시도/오프라인 안내를 UI에 표시한다.

## 4. 아키텍처·모듈화·연결성 평가

### 4.1 좋은 구조

- `AdjustParams`, `FilterPreset`, `FilterRecipe`, `EditSession` 등 도메인 모델이 존재한다.
- LUT, crop, blur, local adjust, portrait, frame, export encoder가 엔진 파일로 나뉘어 있다.
- preview는 token과 pending flag로 stale async 결과를 버린다.
- slider는 debounce/live GPU 경로를 사용하며, preview worker와 export isolate가 UI thread 부담을 줄인다.
- export는 progress, cancel, temp cleanup, format signature validation, 해상도 fallback을 갖는다.
- custom filter 생성은 isolate, timeout, cancel, transactional cleanup을 갖는다.
- Direct MVP 모델은 ID/version/SHA와 입출력 계약이 명시돼 있다.

### 4.2 핵심 구조 문제

#### 실제 canonical renderer가 없다

`EditOperationPlayer`는 preview/export/replay의 표준 실행기로 설명돼 있고 테스트 커버리지도 78.37%다. 그러나 production `lib`에서 호출되지 않는다. `EditorPage` 안의 별도 preview worker와 export worker가 실제 제품 경로다.

그 결과:

- 엔진 테스트가 통과해도 실제 화면 orchestration이 다를 수 있다.
- operation model과 화면의 mutable fields가 서로 다른 기능 집합을 표현한다.
- layer order와 fallback 정책이 여러 곳에서 어긋날 수 있다.

#### Riverpod session architecture가 실제 화면과 분리됐다

`EditSessionController`와 `EditSessionRepository`는 구현·테스트돼 있지만 `EditorPage`는 이를 사용하지 않고 자체 `_editSession`과 SharedPreferences draft를 관리한다. `ProviderScope`는 존재하지만 핵심 편집 상태는 거대한 `StatefulWidget`에 남아 있다.

#### 화면 클래스가 너무 많은 책임을 가진다

`EditorPage` 한 파일이 다음을 모두 담당한다.

- UI와 도구 panel
- 모든 tool mutable state
- transaction backup/reset/apply
- history와 draft serialization
- GPU live preview 준비
- CPU preview worker parameter 조립
- AI model/mask lifecycle
- export isolate와 native WebP bridge
- gallery/share/error UI

이 구조에서는 한 기능을 고칠 때 preview, export, history, draft 중 하나를 빠뜨리기 쉽다. 실제 history 누락이 그 결과다.

### 4.3 권장 목표 구조

대규모 재작성은 필요하지 않다. 다음 경계를 순차적으로 만든다.

1. `EditorRecipe`: 모든 출시 도구 상태를 담는 immutable 단일 모델.
2. `EditorSessionController`: apply/cancel/reset/undo/redo/draft를 전담.
3. `EditorRenderer`: recipe → preview/export 공통 layer order와 fallback 정책.
4. `EditorAssetService`: LUT/frame/font/model load와 typed error/cache.
5. 각 tool panel: recipe의 해당 slice만 편집하는 얇은 UI.

한 번에 UI를 다시 만들지 말고, 먼저 현재 mutable state를 `EditorRecipe`로 투영하고 기존 renderer를 adapter로 감싸는 방식이 가장 안전하다.

## 5. 만들어 놓고 사용하지 않거나 중복된 코드·자산

### 5.1 production에서 사용되지 않는 UI/상태 모듈

| 항목 | 현재 사용 | 판단 |
|---|---|---|
| `BrushToolbar` | 파일과 test만 참조 | 실제 Editor는 inline UI 사용 |
| `CropPanel` | 파일과 test만 참조 | 실제 Editor는 inline crop 사용 |
| `PerspectivePanel` | 파일과 test만 참조 | 실제 Editor는 inline UI 사용 |
| `RotateFlipPanel` | 파일과 test만 참조 | 실제 Editor는 inline UI 사용 |
| `HdrPanel` | 자체 파일 외 참조 없음 | dead UI |
| `HistogramWidget` | 자체 파일 외 참조 없음 | 사용자 기능 미노출 |
| `EditSessionController` | test만 사용 | 실제 Editor state와 분리 |
| `EditSessionRepository` | 위 controller만 사용 | 실제 draft 저장과 분리 |
| `EditOperationPlayer` | test/정의만 사용 | production preview/export와 분리 |

이 파일들을 무조건 삭제할 필요는 없다. 둘 중 하나를 선택해야 한다.

- 표준 모듈로 실제 Editor에 연결한다.
- inline 구현을 표준으로 유지할 경우 중복 모듈과 그 테스트를 제거한다.

현재는 두 구현을 동시에 유지해 비용과 오판을 만든다.

### 5.2 중복·미연결 AI 구현

- `segmenter.dart`가 실제 사용된다. `segmenter_native.dart`, `segmenter_stub.dart`는 조건부 export 없이 남아 있다.
- `depth_estimator.dart`, `depth_estimator_native.dart`, `depth_estimator_stub.dart`는 모두 production 미사용이다.
- `lut_predictor_native.dart`, `lut_predictor_stub.dart`도 production 미사용이었다. 후속 정리에서 제거하고 검증된 단일 `lut_predictor.dart` 계약만 유지했다.
- `kModelMulticlass`, `kModelDepth`, `MulticlassSegmenter`, `DepthEstimator`는 제품 기능에 연결되지 않는다.

Web 조건부 구현을 의도했다면 실제 conditional import/export를 완성해야 한다. 현재는 중복만 있고 Web build는 실패한다.

### 5.3 사용되지 않는 대형 자산

- 47MB의 `assets/luts/`는 production catalog에서 사용되지 않는다.
- 일부 오래된 thumbnail과 prototype `.npy`도 제품 경로가 없다.
- 35MB Direct MVP는 사용되지만 untracked 상태다.
- 런타임에 쓰지 않는 학습 산출물과 가상환경은 저장소 root에서 명확히 ignore해야 한다.

## 6. 오류 처리·데이터 안전성·관측성

### 6.1 잘된 부분

- preview top-level 오류는 `ErrorLogger`와 Snackbar를 사용한다.
- export는 오류 logging, progress, cancel, temp cleanup과 재시도를 제공한다.
- create-filter worker는 error/exit/timeout/cancel을 구분하고 실패 artifact를 정리한다.
- decode 실패를 일부 경로에서 null-safe하게 처리한다.
- portrait model 부재 시 전체 이미지에 임의 보정을 하지 않고 no-op한다.

### 6.2 부족한 부분

- `FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded` 같은 전역 오류 경계가 없다.
- `ErrorLogger`는 메모리 500줄짜리이고 앱 종료 시 사라진다. 실제 사용자 장애를 수집하거나 export하는 경로가 없다.
- preview/export 두 곳 정도만 `ErrorLogger`를 사용한다.
- repository들은 JSON 손상이나 I/O 실패를 빈 목록/default로 바꾼다. 사용자는 데이터가 사라진 것처럼 보이고 원인을 알 수 없다.
- frame asset load 실패는 null로, blend file read 실패는 no-op로 끝날 수 있다.
- model preload 실패는 `debugPrint`만 남긴다. 피부 보정은 슬라이더가 움직여도 효과가 없을 수 있다.
- selfie/multiclass/depth 원격 모델의 SHA가 비어 있다. 최소한 pinned hash와 실패 UI가 필요하다.
- export OOM 판정에 error 문자열의 `null` 포함 여부가 들어가 있어 unrelated null 오류를 메모리 부족으로 오판하고 해상도를 낮출 수 있다.

권장 오류 체계:

- 사용자 복구 가능: 권한, 네트워크, 모델 미준비, asset 누락을 typed state로 UI에 표시.
- 데이터 손상: 원본 백업, 손상 파일 격리, 사용자 안내, 진단 log.
- 개발 오류: 전역 crash capture와 release-symbol 연계.
- 품질 fallback: 원래 경로와 fallback 경로를 recipe/telemetry에 기록하고 사용자에게 품질 차이를 알림.

## 7. 성능·메모리·앱 크기 평가

### 7.1 긍정적인 구현

- 32ms preview debounce와 stale render token.
- decoded/base/LUT/render cache.
- GPU live slider path.
- worker isolate preview와 export isolate.
- export progress/cancel.
- 4096/2048 OOM fallback.
- 필터 생성 45초 timeout과 cancel.

### 7.2 출시 전 부족한 증거

- 현재 commit의 profile/release 실기기 JSON이 없다.
- 실제 12MP/24MP/48MP 사진의 complete export p50/p95/RSS가 없다.
- noise reduction, HDR, glow, portrait model first/cached, text+frame full stack latency가 없다.
- 저메모리 기기의 앱 종료/메모리 warning 대응이 없다.
- 35MB 모델을 첫 실행에 asset에서 복사하고 SHA-256을 계산하는 비용이 측정되지 않았다.
- asset 91MB 중 47MB가 미사용 LUT다.
- simulator app 236MB는 store size가 아니지만, release IPA/AAB size budget과 추적도 없다.

PM 기준 권장 gate:

- 조작 frame p95 ≤16ms, warm preview p95 ≤80ms.
- 고비용 reduced preview p95 ≤250ms.
- export 첫 progress/interval ≤500ms.
- 12MP/24MP complete export p95와 RSS를 지원 기기별로 기록.
- 첫 모델 준비 시간, warm inference, peak RSS, 앱 bundle/download size를 CI artifact로 보존.

## 8. 사용자 관점 기능별 평가

등급 기준:

- A: 현재 증거로 출시 가능.
- B: 기본 출시 가능하나 실기기 최종 확인 필요.
- C: 베타/부분 기능. 설명 또는 제한이 필요.
- D: 이름·기대에 비해 불완전하거나 핵심 연결 결함. 숨기거나 수정 후 출시.

| 사용자 기능 | 등급 | 사용자 관점 평가 | 근거·남은 문제 |
|---|---:|---|---|
| 기본 필터 목록 | D | 사용자가 요구한 Fuji/Leica가 보이지 않음 | 47MB LUT 미연결, 9개 params-only preset, 브랜드 로고 없음 |
| 필터 썸네일/강도 | B- | 썸네일과 강도 조절은 보임 | 고정 이미지 asset은 있으나 실제 LUT catalog와 분리 |
| 기본 보정 | B+ | 가장 안정적인 핵심 기능 | live preview, reset/apply 통합 test; 실제 Editor coverage는 낮음 |
| 세부 정보/선명도 | B | 작동 가능한 전역 보정 | 강한 값의 halo/noise 실사진 승인 필요 |
| 커브 | B | 전문 도구의 기본 기능 제공 | draft/history/render parity를 실제 화면에서 더 검증해야 함 |
| 화이트 밸런스 | B | 기본 온도/tint 조정 가능 | 다양한 색공간/HEIC 실사진 검증 필요 |
| HSL | B | 채널별 조정 엔진과 test가 양호 | 고채도 경계/피부 보호 실사진 검증 필요 |
| 스플릿 톤 | B | 기본 목적에 맞게 작동 | 실제 Editor E2E가 부족 |
| 크롭 | B | 비율 전환·영역 조절이 개선됨 | 통합 test는 1:1/reset뿐, 모든 비율/export 1px gate 미완료 |
| 회전·좌우/상하 반전 | B | 엔진과 UI 반응 구조는 양호 | 고해상도 실기기 preview/export 방향 재검증 필요 |
| 원근 | B- | 기본 skew 보정 가능 | 실제 UI는 tested standalone panel과 다른 inline 구현 |
| 확장 | C+ | black/white 확장은 제공, smart는 숨김 | 전체 비율·메모리·export dimension E2E 미완료 |
| 부분 보정 | D | 터치 지점 한 곳의 국소 조정은 가능하지만 완성 도구 수준 아님 | 다중 point/선택/삭제 없음, history 누락 |
| 브러시 | D | dodge/burn stroke는 있으나 일반 로컬 브러시 기대에 못 미침 | exposure/saturation/temp/eraser 범위 부족, history 누락 |
| 아웃포커스 | C | 선형 tilt-shift 수준 | subject-aware outfocus가 아니며 history 누락 |
| 렌즈 흐림 | D | 이미지 깊이에 따른 렌즈 효과로 보이지만 실제는 중앙 방사형 blur | DepthEstimator 미연결, history 누락 |
| 비네팅 | B | 목적이 명확하고 구현 단순 | 실제 화면 parity/perf 최종 확인 필요 |
| 그레인 | B | seed/alpha/no-op 엔진 검증이 있음 | preview/export grain scale의 전체 실기기 확인 필요 |
| 노이즈 감소 | C+ | 기본 처리 가능 | 고해상도 latency, 디테일 보존, waxy texture 승인 없음 |
| 글로우 | B- | 효과는 연결됨 | 강한 값의 halo, 실기기 latency 확인 필요 |
| 인물/피부 스무딩 | D | 얼굴 피부만 보정한다고 기대하지만 전체 사람 mask를 사용 | face skin model 미연결, model 실패 안내 없음 |
| 이중 노출 | C+ | 이미지 선택·blend·opacity 기본 동작 | 누락 파일이 조용히 no-op, fit/gesture E2E 부족 |
| 프레임 | B | 사진 위 border overlay로 중앙을 보존 | 13개 asset contract test 양호, 전체 기기 육안 승인 필요 |
| 텍스트 | B- | 입력·이동·크기·회전·색상·export 연결 | multiline/font fallback/bounding parity와 접근성 부족 |
| 광학 유출 | B | preview/export 엔진과 품질 test 있음 | effect realism의 인간 품질 승인 필요 |
| 헐레이션 | B | no-op/alpha/quality contract 있음 | 고해상도 edge artifact 육안 승인 필요 |
| 드라마 | C+ | 과도한 밝은 영역 손상은 test로 개선됨 | effect 상태 history 누락, 다양한 인물/야간 사진 승인 필요 |
| HDR 스케이프 | C+ | luminance 중심 품질 gate가 있음 | effect 상태 history 누락, noise/halo 실사진·성능 gate 미완료 |
| undo/redo | D | 일부 전역/geometry/creative만 신뢰 가능 | 로컬·blur·artistic state가 operation에 없음 |
| 도구 취소/초기화 | B | active tool backup과 상단 적용/하단 초기화 구조가 있음 | 전체 도구 parameterized integration test가 없음 |
| draft 자동 복원 | B- | 대부분의 mutable state를 JSON으로 저장 | 별도 session architecture와 중복, 손상 시 silent reset, schema migration 불명확 |
| 내보내기 JPEG/PNG/TIFF | B | 실제 encoder와 signature test, isolate/cancel 지원 | metadata 미보존, 해상도 선택 UI 없음, 실기기 완료/RSS 미검증 |
| 내보내기 WebP | B-/iOS | iOS native ImageIO와 magic 검증 | Android에서는 숨김, 실제 share consumer 확인 필요 |
| RAW/DNG | D/미노출 | 제품 도구로 사용할 수 없음 | `raw_processor`는 진짜 RAW decoder가 아니며 README/계획과 불일치 |
| 힐링/클론 | D/미노출 | 제품 도구로 사용할 수 없음 | player 내부 v1 inpainting은 평균 edge fill+blur 수준, Editor 미연결 |
| 사용자 필터 Style | C+ | single reference Direct MVP와 실제 Before/After 성공 UI는 연결 | 모바일/피부/미관/blind gate 미완료, fallback 품질 표시 부족 |
| 사용자 필터 Before/After | C | pair fitting은 가능 | alignment, motion, local-edit mask가 없어 잘못 일반화할 수 있음 |
| 다중 참조 필터 | C | 공통 색감 융합은 가능 | neural multi-reference가 아니라 algorithmic fusion |
| Gallery/나의 컬렉션 | B- | UI 구획과 새 필터 진입은 개선 | 필터 catalog 요구 불일치, custom filter 관리 E2E 부족 |
| 설정/내보내기 품질 | B | JPEG/WebP quality와 포맷 선택이 실제 encoder에 연결 | 해상도·metadata 옵션 없음 |
| 오프라인 사용 | C+ | 기본 편집은 로컬, 광고는 network check | selfie model 첫 준비가 네트워크 의존, 상태 UI 없음 |

## 9. 기존 MD 문서 대비 구현 누락·과대 체크

### 9.1 `REQUIREMENTS.md`

| 요구 | 판정 | 설명 |
|---|---|---|
| Fuji/Leica만 남기기 | 미구현 | 실제 UI는 9개 params-only builtin |
| 고정 필터 샘플 | 부분 구현 | 고정 thumbnail asset은 있으나 요구 LUT catalog와 분리 |
| 브랜드 로고 | 미구현 | preset name text만 표시 |
| 인물 버튼 정렬 | 구현 정황 있음 | 사용자 육안/다양한 화면 최종 승인 필요 |
| blend 선택 버튼 축소 | 구현 정황 있음 | E2E는 부족 |
| 다양한 비율 레이아웃 | 부분 구현 | portrait 고정, landscape gate 미통과 |
| crop/rotate/perspective 실시간성 | 부분 구현 | 최적화와 과거 수치는 좋으나 현재 full artifact 없음 |
| curve 선택 상태 가시성 | 구현 정황 있음 | golden/accessibility 대비 gate 부족 |
| 필터 생성 색 반전 | 엔진 계약 개선 | LUT axis/channel test는 강함, 실제 다양한 사진 최종 승인 필요 |

### 9.2 `editor-filter-repair-plan.md`

실제로 진전된 항목:

- 도구 apply/cancel/reset UI.
- crop interactive rect와 비율 reset.
- rotate/flip, frame, text, grain, light leak, halation, drama/HDR 엔진 연결.
- export isolate/progress/cancel.
- 제한된 iPhone performance 측정 기록.

아직 닫히지 않은 핵심:

- 부분 보정의 다중 point와 완전한 history.
- subject-aware outfocus와 실제 depth lens blur.
- face/skin-aware portrait.
- 모든 도구 preview/export/undo/draft parity.
- 고해상도 complete export checksum/RSS.
- 전체 235개 수준 white-box matrix.

문서의 “history를 filter/crop/portrait/creative로 바로잡았다”는 기록은 그 범주에는 맞지만, 출시 도구 전체를 다루지 않으므로 완료 표현이 과하다.

### 9.3 `editor-whitebox-validation-plan.md`

계획 자체는 촘촘하고 방향이 맞다. 문제는 실행률이다.

- 최종 checklist 10개가 모두 `[ ]`다.
- 문서가 요구한 38개 missing target, 모든 tool CM-01~12, 전체 asset/font/LUT/model fallback, iOS/Android/small/landscape/low-memory/offline, 동일 commit evidence가 아직 닫히지 않았다.
- 현재 device white-box는 3개 scenario, 4개 ID 정도만 직접 기록한다.
- feature checklist의 691개 항목 중 355개 완료, 336개 미완료로 문서상 51.4%다.
- brush, crop, expand, portrait, double exposure, frame, text, vignette, glow, HDR/drama, light leak, halation, selective, healing, RAW, custom filter, quality gate가 대거 0% 체크 상태다.

결론: 더 큰 새 테스트 계획 문서를 만들 필요는 없다. 기존 계획이 충분하다. 지금 필요한 것은 실제 production path에 test ID를 연결하고 evidence를 채우는 일이다.

### 9.4 `editor-ux-media-export-repair-plan.md`

16개 최종 항목 중 15개가 `[x]`지만 다음은 재오픈해야 한다.

- “도구 적용/취소/history transaction”: local/blur/artistic history가 빠졌으므로 미완료.
- “관련 integration/static warning gate”: integration 범위가 좁고 analyzer warning 3개가 남아 있어 완전 완료로 보기 어려움.
- 실제 iPhone Photos/share 확인은 문서에서도 `[ ]`다.

프레임 중앙 보존, 텍스트 기본 연결, HDR/drama engine quality, export format/magic/quality 연결은 실제 코드와 test로 확인됐다.

### 9.5 `create-filter-gap-review.md`와 ML 문서

`create-filter-gap-review.md` 최종 10개 항목 중 5개 완료, 5개 미완료다.

완료로 인정:

- single-reference Direct MVP 경로.
- 모델 ID/version/SHA/axis 계약.
- 실패·취소 cleanup.
- 최근 사진/권한/빈 상태 UX.
- 성공 화면의 실제 Before/After.

미완료 또는 재검증:

- save/reload/editor/export 허용 오차 evidence를 동일 release commit에 묶기.
- CF-01~16 전체 evidence.
- iOS/Android mobile latency/peak memory.
- same-style, unseen hue, skin fixture.
- blind preference baseline 우위.

학습 쪽 객관적 결론은 긍정적이다. family-holdout에서 Direct MVP가 V2와 interpolation보다 우수했고, 구조화 decoder와 semantic pooled 실험의 negative result도 과장 없이 기록했다. 불필요한 추가 architecture sweep은 하지 않아도 된다. 다음 비용은 모델 재학습보다 **모바일 제품 검증과 사용자 품질 검증**에 써야 한다.

다만 `TRAINING_PROGRESS.md` 뒤쪽의 “모델 URL/SHA가 없어 앱 노출 금지” 같은 일부 문장은 현재 번들 SHA 모델 연결 이후 상태와 맞지 않는다. 문서의 current status section을 한 번 정리해야 한다.

### 9.6 `PUBLISH_CHECKLIST.md`

체크리스트가 일부 stale하다.

- connectivity offline check는 코드에 구현됐는데 문서에는 미완료다.
- targetSdk는 35인데 문서는 34 확인 미완료다.
- 개인정보처리방침 파일은 생겼지만 contact email이 TODO이고 앱 설정 링크/HTTPS hosted URL은 확인되지 않는다.
- Android release는 여전히 debug signing을 사용한다.
- AdMob ID는 test ID이고 모든 광고 flag 기본값은 off다. 출시 전에 실제 광고를 쓸지 완전히 끌지 결정해야 한다.
- create filter UI 숨김 항목은 `[x]`지만 현재 상수는 `true`다. 지금의 제품 결정에 맞게 체크리스트를 갱신해야 한다.

## 10. README와 실제 제품의 차이

출시 전에 다음 문구를 수정하거나 기능을 완성해야 한다.

| README 주장 | 실제 상태 |
|---|---|
| Android, iOS, Windows, Web | iOS만 이번에 검증, Web release 실패, Android/Windows 미검증 |
| custom Dart/C++ pipeline | 저장소의 실제 주요 구현은 Dart와 iOS Swift; C++ 근거 없음 |
| 모든 편집 stack undo/redo | local/blur/artistic history 누락 |
| healing/clone | 실제 Editor에 미노출, v1 inpainting 품질도 낮음 |
| 다양한 해상도와 metadata 보존 옵션 | 포맷/quality는 있으나 해상도 UI와 metadata 보존 없음 |
| 모바일·데스크톱 일관된 고품질 | 플랫폼별 build/quality evidence 없음 |

문서 정확성은 마케팅 문제가 아니라 QA 범위와 사용자 기대를 결정하는 제품 계약이다.

## 11. CI/CD와 배포 운영 평가

현재 GitHub Actions는 iOS build/IPA 생성만 한다.

문제:

- analyze/test/integration/performance gate가 없다.
- Flutter 3.24.0을 고정하지만 현재 로컬 감사 build는 Flutter 3.44.6이었다.
- workflow가 `pubspec.lock`을 삭제한 뒤 dependency를 다시 해석한다.
- 현재 핵심 변경이 uncommitted/untracked라 CI에서 재현되지 않는다.
- Android workflow가 없다.
- release asset size, model SHA, privacy/ads config gate가 없다.
- `.drift-gate.yml` 첫 key가 `ㅁversion`으로 손상돼 있다.

최소 CI 순서:

1. clean checkout과 lockfile 정책 확정.
2. `flutter pub get`.
3. `flutter analyze` warning gate.
4. `flutter test --coverage`, 전체 및 핵심 파일 최소 coverage gate.
5. iOS simulator production-path integration smoke.
6. Web을 지원할 때만 Web build; 현재는 지원 목록에서 제거.
7. Android SDK runner에서 debug/release compile과 signing configuration check.
8. tagged release에서 iPhone profile benchmark JSON, export checksum/RSS, IPA/AAB size artifact 보존.

## 12. 권장 실행 순서

### Release Blocker 단계

1. **소스 상태 고정**
   - `.gitignore` 보강.
   - 제품 파일 allowlist commit.
   - 깨끗한 checkout 재현.
2. **필터 제품 계약 결정**
   - Fuji/Leica LUT를 실제 연결하거나 47MB 자산과 요구를 제거.
3. **canonical recipe/history 수정**
   - 모든 출시 도구 state를 operation에 포함.
   - apply/undo/redo/draft/export parity test.
4. **과장된 고급 기능 제한**
   - portrait, lens blur, healing, RAW를 구현 수준에 맞게 rename/hide.
5. **필터 생성 베타 gate**
   - mobile latency/RSS와 필수 품질 fixture 완료 전 beta flag.
6. **실기기 release gate**
   - iPhone Photos/share complete export, 12/24MP, checksum, RSS.
   - Android SDK/실기기 permission/export/build.

### P1 안정화 단계

1. `EditorRecipe`/controller/renderer 경계 도입.
2. dead panel/AI duplicate를 연결하거나 제거.
3. global error boundary, typed failure state, persistent diagnostic log.
4. CI analyze/test/coverage/integration gate 추가.
5. 사용되지 않는 LUT와 asset 정리, release 크기 예산 도입.
6. export metadata 정책을 “보존” 또는 “제거” 중 하나로 명시하고 구현.

### P2 제품 완성도 단계

1. localization과 hardcoded Korean/English 정리.
2. accessibility label, Dynamic Type, contrast, 작은 화면 검증.
3. landscape/iPad를 지원할지 portrait-only로 명확히 결정.
4. custom filter duplicate/rename/delete와 iCloud/limited PhotoKit UX.
5. 실제 사진군과 인간 평가를 통한 HDR/portrait/filter 품질 승인.

## 13. 추가 개발이 불필요한 부분

불필요한 리소스 낭비를 피하기 위해 다음은 당장 새로 만들 필요가 없다.

- 새로운 대형 white-box 계획서: 기존 문서가 이미 충분히 상세하다.
- 새로운 LUT 모델 architecture sweep: family-holdout Direct MVP가 현재 후보 중 우수하며 최근 structured/semantic 실험의 negative result도 충분하다.
- 또 다른 standalone tool panel: 기존 중복 panel부터 정리해야 한다.
- 새 export 포맷: JPEG/PNG/TIFF와 iOS WebP 연결부터 실기기 완료 검증하면 된다.
- 새로운 고급 기능 추가: undo/redo, 필터 catalog, portrait/lens blur 정직성, release evidence가 먼저다.

## 14. 최종 PM 승인 조건

다음이 모두 충족되기 전에는 일반 사용자 프로덕션 출시를 승인하지 않는다.

- [ ] 깨끗한 Git checkout에서 현재 제품이 재현된다.
- [ ] Fuji/Leica 필터 요구와 bundle/UI가 일치하거나 요구가 공식 변경된다.
- [ ] 모든 노출 도구의 apply/cancel/reset/undo/redo/draft/export가 동일 recipe로 검증된다.
- [ ] portrait/lens blur의 명칭과 실제 알고리즘이 일치한다.
- [ ] create-filter mobile latency/RSS 및 핵심 품질 fixture가 통과하거나 beta로 제한된다.
- [ ] `EditorPage` production-path 통합 커버리지가 핵심 도구 전체를 포함한다.
- [ ] iPhone Photos 저장/share complete export와 Android 권한/export가 통과한다.
- [ ] CI가 analyze/test/integration을 자동 차단한다.
- [ ] release signing, privacy URL/contact, 광고 on/off 정책이 확정된다.
- [ ] README 플랫폼·기능 주장이 실제 증거와 일치한다.

이 조건을 기준으로 보면 현재는 **내부 베타 가능 / 스토어 프로덕션 보류**다. 기능을 더 많이 추가하는 것보다 이미 만든 기능을 하나의 상태·렌더링 계약에 연결하고, 실제 사용자 경로에서 증명하는 것이 다음 단계다.

## 부록 A. 핵심 증거 파일

- `lib/features/editor/editor_page.dart`
- `lib/engine/edit_operation_player.dart`
- `lib/domain/models/edit_operation.dart`
- `lib/domain/models/edit_session.dart`
- `lib/features/editor/edit_session_controller.dart`
- `lib/features/create_filter/create_filter_page.dart`
- `lib/features/create_filter/create_filter_services.dart`
- `lib/ai/ai_manager.dart`
- `lib/ai/models/segmenter.dart`
- `lib/domain/models/filter_preset.dart`
- `lib/features/editor/widgets/filter_strip.dart`
- `lib/core/services/export_preferences.dart`
- `lib/engine/export_encoder.dart`
- `integration_test/editor_whitebox_device_test.dart`
- `integration_test/editor_performance_test.dart`
- `tool/perf_gate.dart`
- `REQUIREMENTS.md`
- `PUBLISH_CHECKLIST.md`
- `docs/editor-filter-repair-plan.md`
- `docs/editor-whitebox-validation-plan.md`
- `docs/editor-ux-media-export-repair-plan.md`
- `docs/create-filter-gap-review.md`
- `ml_pipeline/TRAINING_PROGRESS.md`

## 부록 B. 재검증 명령

```bash
flutter analyze --format machine
flutter test --coverage --reporter compact
flutter test integration_test/editor_whitebox_device_test.dart -d <ios-device>
flutter test integration_test/editor_performance_test.dart -d <ios-device>
dart run tool/perf_gate.dart --report <profile-report.json> --scope full
flutter build web --release
flutter build apk --debug
flutter build ipa --release
git diff --check
git status --short
```

주의: performance 승인에는 debug simulator가 아니라 profile/release 실기기 JSON이 필요하다.
