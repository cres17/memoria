# Memoria 구현 검증 및 남은 구조 작업

> 2026-08-26 release-candidate 작업 트리 기준. 완료 사실은 짧게 증거만 남기고, 외부 권한이 필요한 출시 gate를 분리해 유지한다.

## 결론

- 판정: **코드·CI release candidate. signed store release는 외부 설정과 실기기 evidence가 필요**.
- 렌더링 기준 객체, preview/export 경계, 공간 변환, 실패 전달, 손상 데이터 보존은 이전보다 명확하고 테스트 가능하게 분리됐다.
- 거대 화면 파일을 책임별 library part로 분해했다. `editor_page.dart`는 408줄의 state/lifecycle 중심 파일이고 history, runtime, controls, shell, menus, widgets는 개별 모듈이다. `create_filter_page.dart`도 967줄로 줄이고 단계 UI와 결과 UI를 별도 모듈로 분리했다.
- iOS 26.5 시뮬레이터의 ImageIO는 WebP destination encoder를 제공하지 않았다. v1의 제품 결정은 **WebP를 지원하지 않음**이다. capability false일 때 선택지를 숨기고 저장값을 JPEG로 정규화해 가짜 WebP를 방지한다.

## 검증 기준과 결과

- branch/HEAD: `main` / `964e14cac` + release-candidate 로컬 변경.
- simulator: `iPhone 17`, iOS 26.5, `4CCB786A-8BA7-40FB-AA91-6B0CCAA25FD1`.
- `flutter test --reporter compact`: 502 pass. 선택형 로컬 모델 fixture 1건은 기존 조건부 경로로 건너뛴다. (`EditorEditState` 전체 상태군 round-trip, 26개 도구 reset/apply, preview stale-result 차단, transaction, gesture, startup, 접근성 포함)
- `flutter analyze --no-fatal-infos`: error 0, warning 0, info 0.
- iOS integration: iPhone 17 / iOS 26.5 simulator에서 설정 복구, WebP capability/가짜 `.webp` 방지, 편집 transaction·crop·v3 draft 재생성 복원, preview sampling, export 진행·취소의 8개 시나리오가 **pass**.
- iOS runtime: iOS 26.5 `iPhone 17` simulator에서 현재 작업 트리의 debug build 설치·실행이 성공했다. Xcode가 직접 만든 `Runner.app`도 simulator에 설치·launch한 뒤 프로세스가 유지되는 것을 확인했다. `runApp` 이전의 GPU texture/storage/locale await는 iOS에서 splash 정체를 만들 수 있어 first frame 이후 초기화로 이관했다.
- iOS UIScene/SPM: `UIApplicationSceneManifest`와 `FlutterImplicitEngineDelegate` 등록으로 UIScene 전환을 완료했다. `SceneDelegate.swift`가 Runner target에서 컴파일되는 것도 확인했다. CocoaPods를 deintegrate하고 `google_mobile_ads 9.1.0`, `share_plus 10.1.4`, `flutter_litert 3.8.0`을 SwiftPM으로 해석했다. `xcodebuild` Runner Debug simulator build와 `flutter build ios --no-codesign --release`가 모두 통과했다.
- GitHub Actions: run `32927516139`의 단일 실패는 ARM macOS runner에서 x64 Flutter를 Rosetta로 실행하면서 `custom_filter_roundtrip_test`가 기본 30초를 초과한 것이었다. 세 iOS workflow를 arm64 Flutter로 통일했고, 실제 neural LUT를 생성하는 round-trip test에는 2분의 명시적 test budget을 부여했다. iOS build workflow는 simulator를 부팅해 `integration_test/`의 8개 시나리오도 실행한다. production worker의 30/45초 timeout 계약은 바꾸지 않았다. 원격 재실행은 수정 commit을 push한 뒤 확인한다.
- `git diff --check`: pass.
- signed release workflow는 certificate/profile secret, public privacy-policy URL, privacy contact, `ADVERTISING_RELEASE_MODE=disabled`를 모두 확인한 뒤에만 signing을 시작한다. 이 값들은 저장소가 임의로 만들 수 없는 외부 release configuration이다.

scratch/brain 실험 코드는 analyzer 대상에서 제외하고, command-line tool의 의도적인 console output만 파일 단위로 명시했다. production·test·tool 대상 analyzer는 0 issue다. UIScene 전환 예정 경고와 기존 `google_mobile_ads`, `share_plus`, `tflite_flutter`의 Swift Package Manager 미지원 경고는 SwiftPM 전환으로 해소했다.

## 계획 대비 구현 상태

| 영역 | 상태 | 확인 결과 |
|---|---|---|
| P1-1 공간 정합성 | 완료 | crop/flip/rotation/expand/perspective와 portrait/local mask 좌표 변환을 공통 spatial renderer로 검증 |
| P1-2 export worker | 완료 | success/error/exit/timeout/cancel terminal contract, 단일 완료, cleanup 후 재실행을 검증 |
| P1-3 correctness/parity | 완료 | 실제 사진 tone/curve/HDR/grain/drama/LUT/local/blur, portrait mask, preview/export isolate, frame/blend/text, JPEG/PNG/TIFF, wide/tall/alpha/EXIF/12MP matrix를 hash·signature로 고정 |
| iOS WebP | 완료 | v1 비지원 제품 결정을 문서화. native capability false면 선택지를 숨기고 JPEG로 정규화해 확장자 위장을 방지 |
| iOS UIScene / SPM | 완료 | implicit engine 등록과 scene manifest 적용, CocoaPods 제거. 광고·공유·LiteRT가 SwiftPM package graph에서 해석되고 simulator runtime 확인 |
| P1-4 `EditorPage` 축소 | 완료 | 본체 408줄. history/runtime/controls/shell/menus/widgets를 책임별 part로 분리하고, 화면 chrome state는 `_EditorUiState`, 실제 편집값과 snapshot 변환은 `EditorEditState`가 소유 |
| `CreateFilterPage` 축소 | 완료 | 본체 967줄. 생성 흐름·상태는 본체에 두고 단계별 선택 UI와 결과/완료 UI를 별도 part로 분리 |
| 도구 연결 단일화 | 완료 | 26개 도구의 catalog, 전 도구 controls/cancel, reset 정책, apply 이력 type을 매트릭스로 검증 |
| container/service 경계 | 완료 | editor transaction을 controller로, Create Filter 파일 분석을 주입 가능한 analyzer로 분리. 프레젠테이션 header navigation은 callback으로 전달 |
| P0 preview 최신성 | 완료 | clock/worker 주입 scheduler가 debounce와 token을 소유하며 늦은 worker 결과를 결정론적으로 폐기 |
| P0 draft/rollback | 완료 | 실제 page 재생성 v3 복원, preview/save 중 생성 취소의 metadata·artifact 보상 정리 검증 |
| startup 실패 격리 | 완료 | first frame 이후 named task를 순차 실행하되 각 실패를 개별 기록하여 locale/orientation/model preload 등 뒤 단계가 계속 실행됨 |
| 접근성 회귀 방지 | 완료 | 편집기·필터 생성 화면의 명시적 button/selected semantics와 320×640, 200% 글자 크기 widget test 추가 |
| iOS integration CI | 완료 | simulator boot 후 `integration_test/` 전체를 iOS build workflow에서 실행 |
| P1-5 손상 저장 복구 | 완료 | 원문 backup, filter index quarantine/rebuild, temp→rename 쓰기, 설정의 복구·원본 보관·삭제 확인 UI와 iOS integration 검증 완료 |
| silent catch 분류 | 완료 | `catch (_)` 및 익명 `catchError` 0건. 의도적 fallback의 중앙 진단/중복 제거는 P2로 남음 |

## 현재 연결 구조 평가

```text
EditorPage
  ├─ editor_page.dart (state / lifecycle)
  ├─ history / runtime / controls
  ├─ shell / menus / widgets
  ├─ EditorToolCatalog / Transaction / Reset / Apply controllers
  ├─ _EditorUiState
  ├─ EditorEditState ──> EditorStateSnapshot
  │                      ├─ EditorHistoryController / EditorDraftStore
  │                      └─ EditorRenderRecipe ──> EditorRenderer
  │                                                ├─ PreviewScheduler ──> isolate
  │                                                └─ export render
  ├─ EditorResourcePreparer ──> mask / blend / frame / text bytes
  └─ EditorMediaExportCoordinator ──> EditorExportService
                                      ├─ temp / WebP / signature / retry
                                      └─ Photos / share / cleanup
```

잘 연결된 부분:

- preview와 export가 같은 `EditorRenderRecipe`와 `EditorRenderer`를 사용한다.
- worker 밖으로 decode/write/exit/timeout 오류가 typed failure로 전달된다.
- 실제 이미지 fixture가 production preview/export 경계를 통과한다.
- filter 파일 저장은 metadata와 index를 atomic rename으로 기록하며 손상 index를 격리 후 재구성한다.
- WebP 지원 여부는 Swift ImageIO → MethodChannel → 설정/내보내기로 한 방향으로 전달된다.
- iOS startup은 first Flutter frame 이후에 renderer fallback, diagnostics, locale, model/ad 초기화를 수행해 native splash가 비동기 초기화를 기다리지 않는다.
- startup 단계는 `StartupTask` 단위로 실패를 격리한다. 앞 단계 하나가 실패해도 방향·system UI·두 모델 preload와 뒤 단계가 건너뛰어지지 않는다.
- editor grid·favorites·history 분류는 같은 `EditorToolCatalog`를 사용하며 26개 production tool의 controls/cancel 연결을 widget matrix로 검증한다.
- reset은 `EditorToolResetController`, apply→history 변환은 `EditorToolApplyController`가 소유하며 26개 도구 전체 계약을 parameterized test로 고정한다.
- preview debounce/token/worker 실행은 `EditorPreviewScheduler`가 소유하고 늦은 결과는 page state를 변경하지 않는다.
- Create Filter의 reference 분석은 page 밖의 주입 가능한 service가 담당하고 run token이 stale 결과를 차단한다.
- export coordinator가 temporary path, worker 호출, native WebP, signature 검증, gallery/share, retry, cleanup을 소유한다.
- renderer는 blend 경로를 다시 읽지 않고 preview/export 모두가 전달한 bytes만 소비한다.
- `EditorResourcePreparer`가 frame·blend bytes, portrait mask와 text raster를 좌표가 명시된 typed resource로 준비한다. `EditorPage`는 preview/live/export 모두에서 그 결과만 전달한다.
- export resource 준비 실패는 typed failure로 coordinator까지 전달되며, 이미 할당된 temporary output은 cleanup한다.

구조적으로 확인한 부분:

- 화면 전용 navigation/tool/export/preview/favorites 상태는 `_EditorUiState`가 소유한다. 실제 편집 field는 `EditorEditState`가 소유하고 snapshot 생성·복원을 한 곳에서 담당하며, 도구 취소 transaction도 개별 backup field 대신 `EditorStateSnapshot` 하나로 되돌린다.
- 거대 state 객체를 억지로 복제하지 않고 동일 library의 책임별 part로 분리해 private 계약과 동작을 보존했다. 이후 각 모듈을 독립 controller로 옮길 때도 경계가 드러난다.
- Create Filter는 생성 orchestration과 프레젠테이션을 분리했고, 큰 글자에서 header/최근 사진 상태가 넘치지 않도록 반응형 배치를 사용한다.
- 완료: `EditOperationPlayer`와 `EditSession`을 제거하고, production history는 `EditorHistoryController`가 snapshot list와 draft 호환 JSON을 직접 소유한다. renderer 계보는 `EditorRenderer` 하나다.
- histogram UI/engine과 depth/multiclass 계열은 production 진입점이 없음을 확인해 제거했다. legacy player 회귀 테스트는 production renderer 계약 또는 직접 engine test로 이관했다.

## 코드 품질 판정

| 항목 | 판정 | 이유 |
|---|---|---|
| 렌더링 correctness | 좋음 | 실제 사진 baseline과 입력/resource matrix가 넓고 preview/export 경계를 통과 |
| export 안정성 | 좋음 | isolate lifecycle과 실패 형태가 명시적이며 timeout/cancel cleanup 검증 |
| 저장 데이터 안전성 | 좋음 | preferences와 filter index 모두 typed recovery state와 비파괴 복구/초기화 선택을 제공하며 settings UI interaction과 iOS integration을 검증했다 |
| 모듈 경계 | 좋음 | editor transaction/reset/apply/preview와 Create Filter reference 분석이 독립 controller/service이며 presentation은 callback 경계를 사용 |
| 도구 연결성 | 좋음 | 단일 catalog와 26개 도구 production widget/reset/apply matrix로 grid/controls/cancel/history 누락을 방지 |
| startup 복원력 | 좋음 | named task별 실패 격리와 실행 순서 테스트로 일부 초기화 실패가 전체 후속 초기화를 막지 않음 |
| 접근성 | 보통 이상 | 핵심 화면 button/selected semantics와 200% 글자 크기 회귀 테스트를 보유. VoiceOver 실기기 탐색은 release gate로 유지 |
| dead code 관리 | 좋음 | unused suppression, legacy renderer/UI/model 계보와 제품 경로 없는 중복 엔진을 제거하고 production graph를 단일화 |
| 플랫폼 codec 정직성 | 좋음 | 미지원 codec을 노출하거나 확장자만 위장하지 않음 |
| 배포 재현성 | 미확인 | dirty tree이며 같은 commit의 CI와 실기기 profile evidence 없음 |

## P1 완료 기록

### 1. dead/legacy 호출 graph 정리

- 완료: `_ToolsPanel`, `_ToolsSubTab`, `_buildLocalSubTabRow`, `_TabBtn`, `_FlipBtn`, 구형 local panel builders와 draft의 `toolsSubTab` 직렬화를 제거했다.
- 완료: `HistogramWidget`/histogram engine과 테스트 전용 depth/multiclass registry·implementations를 제거했다. 이들은 production 진입점이 없었다.
- 완료: legacy player 테스트는 production `EditorRenderer` 계약 또는 직접 engine unit test로 이관했고, player와 `EditSession`을 삭제했다.
- 완료: 세 종류 depth estimator와 multiclass model 상태는 production 진입점이 없음을 확인해 삭제했다.
- 완료: 구형 `EditOps`/`ExportFormat`, 재귀 호환 extension, 중복 LUT predictor native/stub 구현을 제거했다. 편집 상태는 `EditOperation`, AI LUT는 검증된 단일 `LutPredictor` 계약만 사용한다.
- 완료: 제품 경로가 없고 현재 엔진과 중복되던 hue/color-constancy, basis LUT runtime scaffold, placeholder healing, pseudo-RAW noise reduction을 테스트와 함께 제거했다. 노이즈 감소는 production Lab 경로만 유지한다.
- 완료: 테스트만 통과하던 구형 brush/crop/perspective 엔진을 제거하고, brush는 `local_adjust`, crop/perspective는 `EditorSpatialRenderer`의 production 계약과 테스트만 유지한다. 미연결 editor tab preference scaffold도 제거했다.
- 완료: `StyleAnalyzer`의 외부 사용처 없는 legacy CDF helper와 `ErrorLogger` 파일의 사용되지 않는 예외 계층을 제거했다.
- 완료: `EditorPage`의 `unused_element`, `unused_field`, `unused_element_parameter` 억제를 제거했고 editor analyzer warning은 0이다.

완료 조건:

- [x] editor production graph의 unused suppression 0.
- [x] 동일 기능의 production renderer 계보 1개.
- [x] known legacy widget/engine/state 및 미사용 tool payload 0. analyzer와 production graph 검색에서 legacy renderer/session, histogram, depth/multiclass, tools-subtab, 중복 LUT predictor, placeholder healing/RAW 참조가 없다.

### 2. `EditorMediaExportCoordinator` 추출 — 완료

- `EditorPage`에서 설정 로드, 임시 경로, `EditorExportService`, WebP capability/변환, Photos 저장, share, retry, cleanup을 분리했다.
- page는 사용자 선택, 진행 UI, renderer request 준비만 소유한다.
- coordinator test는 publish, WebP 미지원 정규화, OOM retry, native encoding failure cleanup을 고정한다.

완료 조건:

- [x] page에 `File` 기반 export 후처리와 codec 분기 없음.
- [x] save/share/WebP 미지원/변환 실패/cleanup을 coordinator 단위 테스트로 검증.

### 3. state → recipe/draft/history adapter 통합 — 완료

- 완료: `EditorStateSnapshot`이 recipe 생성, history operation, version 3 draft를 같은 immutable 값에서 파생한다. version 2 draft restore는 호환 fallback으로 유지한다.
- 완료: undo history가 비어 초기 상태로 돌아갈 때도 `EditorStateSnapshot.initial`을 거쳐 같은 restore adapter를 사용한다.
- 완료: 도구 진입/취소 transaction은 50여 개 개별 backup field 대신 `EditorStateSnapshot` 하나와 LUT resource snapshot으로 저장·복원한다.
- 완료: render recipe에 속하지 않는 navigation/tool/export/preview/favorites UI field는 `_EditorUiState` container가 소유한다.
- 완료: global/crop/portrait/creative/local-effect 편집 field는 `EditorEditState`가 단독 소유한다. page의 호환 accessor는 기존 widget callback을 유지하지만 별도 상태를 저장하지 않는다.
- 완료: `EditorEditState.toSnapshot/restore`가 crop·portrait future payload·creative·brush/local effect를 포함한 전체 상태군을 round-trip한다.
- blend bytes는 page loader → request/resources로 전달하며 `EditorRenderer`의 sync blend file fallback은 제거했다.
- 완료: `EditorResourcePreparer`가 output geometry, text raster, portrait mask, blend/frame bytes를 준비한다. export geometry는 spatial renderer와 직접 대조하고 crop/rotation text target, mask transform, preview/export frame·blend·text parity, typed failure cleanup을 회귀 테스트로 고정했다.

완료 조건:

- [x] 새 도구 필드는 단일 state/adapter 진입점에서 연결.
- [x] renderer input은 bytes, dimensions, coordinate space를 명시.
- [x] snapshot adapter의 preview recipe/history operation/version 3 draft round-trip 테스트 통과.

### 4. 손상 데이터 사용자 복구 경로

- [x] `PreferencesRecoveryService`가 즐겨찾기와 사용자 보정값 backup을 typed recovery entry로 노출한다.
- [x] 설정에서 복구 시도, 원본 보관 초기화, 확인을 거친 원본 삭제 초기화를 제공한다.
- [x] 성공 복구와 안전 초기화는 원문을 archive로 옮긴 뒤 pending backup을 제거한다. 원문 삭제는 별도 경고·확인 뒤에만 수행한다.
- [x] filter index quarantine도 설정에서 복구 시도, 재구성된 목록 유지(원문 archive), 명시적 원본 삭제로 처리한다. 복구 시에는 현재 재구성된 index를 교체하지 않고 읽을 수 있는 이전 id만 병합한다.

완료 조건:

- [x] 손상 감지 후 자동 파괴 없음.
- [x] preferences의 복구·안전 초기화·원본 삭제 초기화 service test.
- [x] filter index의 병합 복구·원문 보관·원본 삭제 service test.
- [x] 설정 UI의 항목 선택, 복구, 안전 초기화, 파괴적 삭제 확인 interaction test.
- [x] iOS 26.5 simulator에서 설정 복구 UI integration test.

### 5. WebP 제품 결정 — 완료

- v1은 WebP export를 제품 기능으로 제공하지 않는다. JPEG·PNG·TIFF만 지원하며 README와 설정은 iOS WebP를 약속하지 않는다.
- capability bridge는 false일 때 선택지를 숨기고 기존 저장값을 JPEG로 정규화한다. 향후 WebP를 도입하려면 bundled `libwebp`/동등 encoder와 RIFF/WEBP, dimensions, quality, Photos/share 실기기 검증을 추가한다.

## 이후 P2 / release gate

- renderer/file diagnostics를 중앙 sanitizer와 event code/severity/retryability로 통합.
- deprecated Flutter API 정리와 남은 analyzer info 축소.
- 연결 iPhone profile에서 12/24MP export p50/p95, peak RSS, 취소/저메모리/limited PhotoKit 검증.
- Android permission/export/signing 검증.
- clean snapshot에서 unit + integration + analyze를 같은 commit/CI로 재현.

최종 출시 조건:

- [x] P1 1~5 완료 또는 WebP 비지원 제품 결정을 문서화.
- [x] analyzer error/warning/info 0, editor unused suppression 0.
- [ ] 필수 fixture skip 0, iOS/Android 실기기 export 통과.
- [ ] clean checkout CI 재현과 signing/privacy/광고 정책 확정. signed workflow가 누락된 외부 설정을 명시적으로 차단한다.
