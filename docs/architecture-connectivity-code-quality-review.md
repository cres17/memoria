# Memoria 구현 검증 및 남은 구조 작업

> 2026-08-26 로컬 작업 트리 기준. 완료 사실은 짧게 증거만 남기고, 앞으로 수정할 항목을 중심으로 유지한다.

## 결론

- 판정: **내부 beta 가능, production release gate는 아직 미통과**.
- 렌더링 기준 객체, preview/export 경계, 공간 변환, 실패 전달, 손상 데이터 보존은 이전보다 명확하고 테스트 가능하게 분리됐다.
- 가장 큰 구조 부채는 6,038줄짜리 `EditorPage`다. export publish/orchestration, 편집 상태 소유권과 snapshot 변환은 분리됐지만 preview scheduling과 화면 조립은 계속 소유한다.
- iOS 26.5 시뮬레이터의 ImageIO는 WebP destination encoder를 제공하지 않았다. 현재 구현은 이를 정확히 감지해 WebP 선택을 숨기고 저장값을 JPEG로 정규화한다. **가짜 WebP는 방지했지만 실제 WebP export 기능을 제공한 것은 아니다.**

## 검증 기준과 결과

- branch/HEAD: `main` / `395eabc87` + 로컬 변경.
- simulator: `iPhone 17`, iOS 26.5, `4CCB786A-8BA7-40FB-AA91-6B0CCAA25FD1`.
- `flutter test --coverage --reporter compact`: 474 pass. 선택형 로컬 모델 fixture 1건은 기존 조건부 경로로 건너뛴다. (`EditorEditState` 전체 상태군 round-trip과 설정 복구 interaction 포함)
- `flutter analyze`: error 0, warning 0, info 138. 명령 종료 코드는 info 때문에 1이다.
- iOS integration: WebP capability/가짜 `.webp` 방지 계약과 설정의 손상 데이터 복구·삭제 확인 UI가 iOS 26.5 simulator에서 **pass**.
- iOS runtime: iOS 26.5 `iPhone 17` simulator에서 현재 작업 트리의 debug build 설치·실행이 성공했다. Xcode가 직접 만든 `Runner.app`도 simulator에 설치·launch한 뒤 프로세스가 유지되는 것을 확인했다. `runApp` 이전의 GPU texture/storage/locale await는 iOS에서 splash 정체를 만들 수 있어 first frame 이후 초기화로 이관했다.
- iOS UIScene/SPM: `UIApplicationSceneManifest`와 `FlutterImplicitEngineDelegate` 등록으로 UIScene 전환을 완료했다. `SceneDelegate.swift`가 Runner target에서 컴파일되는 것도 확인했다. CocoaPods를 deintegrate하고 `google_mobile_ads 9.1.0`, `share_plus 10.1.4`, `flutter_litert 3.8.0`을 SwiftPM으로 해석했다. `xcodebuild` Runner Debug simulator build와 `flutter build ios --no-codesign --release`가 모두 통과했다.
- GitHub Actions: 최근 실패 run `32918116972`는 SPM 전환 뒤 남은 `pod install --deployment`의 `No Podfile found`, run `32918116967`은 CI에 없는 `ml_pipeline/reports/deployment` 모델을 요구한 테스트 4건이 원인이었다. 세 iOS workflow의 CocoaPods 단계를 제거하고 테스트 모델 경로를 검증된 `assets/models/direct_mvp_color_transfer_fp16.tflite`로 통일했다. 같은 전체 test/unsigned release 명령은 로컬에서 통과했으며 수정 commit의 원격 run은 아직 실행 전이다.
- `git diff --check`: pass.
- 작업 트리가 크고 미커밋 상태라 수정 commit의 clean checkout/원격 CI 재현성은 아직 증명하지 않았다.

분석 info에는 앱 코드의 deprecated API, const/style 항목과 scratch/tool 항목이 섞여 있다. 현재 release blocker는 아니지만 0이라고 표현하면 안 된다. UIScene 전환 예정 경고와 기존 `google_mobile_ads`, `share_plus`, `tflite_flutter`의 Swift Package Manager 미지원 경고는 SwiftPM 전환으로 해소했다.

## 계획 대비 구현 상태

| 영역 | 상태 | 확인 결과 |
|---|---|---|
| P1-1 공간 정합성 | 완료 | crop/flip/rotation/expand/perspective와 portrait/local mask 좌표 변환을 공통 spatial renderer로 검증 |
| P1-2 export worker | 완료 | success/error/exit/timeout/cancel terminal contract, 단일 완료, cleanup 후 재실행을 검증 |
| P1-3 correctness/parity | 완료 | 실제 사진 tone/curve/HDR/grain/drama/LUT/local/blur, portrait mask, preview/export isolate, frame/blend/text, JPEG/PNG/TIFF, wide/tall/alpha/EXIF/12MP matrix를 hash·signature로 고정 |
| iOS WebP | 부분 완료 | native capability 탐지와 안전한 비활성화는 완료. iOS 26.5 ImageIO에서 실제 encoder는 없음 |
| iOS UIScene / SPM | 완료 | implicit engine 등록과 scene manifest 적용, CocoaPods 제거. 광고·공유·LiteRT가 SwiftPM package graph에서 해석되고 simulator runtime 확인 |
| P1-4 `EditorPage` 축소 | 진행 중 | unused suppression·미연결 tool panel·histogram/depth/multiclass 계열과 legacy renderer/session 제거, export/resource 분리. 화면 chrome state는 `_EditorUiState`, 실제 편집값과 snapshot 변환은 `EditorEditState`가 소유 |
| P1-5 손상 저장 복구 | 완료 | 원문 backup, filter index quarantine/rebuild, temp→rename 쓰기, 설정의 복구·원본 보관·삭제 확인 UI와 iOS integration 검증 완료 |
| silent catch 분류 | 완료 | `catch (_)` 및 익명 `catchError` 0건. 의도적 fallback의 중앙 진단/중복 제거는 P2로 남음 |

## 현재 연결 구조 평가

```text
EditorPage
  ├─ _EditorUiState
  ├─ EditorEditState ──> EditorStateSnapshot
  │                      ├─ EditorHistoryController / EditorDraftStore
  │                      └─ EditorRenderRecipe ──> EditorRenderer
  │                                                ├─ preview isolate
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
- export coordinator가 temporary path, worker 호출, native WebP, signature 검증, gallery/share, retry, cleanup을 소유한다.
- renderer는 blend 경로를 다시 읽지 않고 preview/export 모두가 전달한 bytes만 소비한다.
- `EditorResourcePreparer`가 frame·blend bytes, portrait mask와 text raster를 좌표가 명시된 typed resource로 준비한다. `EditorPage`는 preview/live/export 모두에서 그 결과만 전달한다.
- export resource 준비 실패는 typed failure로 coordinator까지 전달되며, 이미 할당된 temporary output은 cleanup한다.

아직 약한 부분:

- 화면 전용 navigation/tool/export/preview/favorites 상태는 `_EditorUiState`가 소유한다. 실제 편집 field는 `EditorEditState`가 소유하고 snapshot 생성·복원을 한 곳에서 담당하며, 도구 취소 transaction도 개별 backup field 대신 `EditorStateSnapshot` 하나로 되돌린다.
- 완료: `EditOperationPlayer`와 `EditSession`을 제거하고, production history는 `EditorHistoryController`가 snapshot list와 draft 호환 JSON을 직접 소유한다. renderer 계보는 `EditorRenderer` 하나다.
- histogram UI/engine과 depth/multiclass 계열은 production 진입점이 없음을 확인해 제거했다. legacy player 회귀 테스트는 production renderer 계약 또는 직접 engine test로 이관했다.

## 코드 품질 판정

| 항목 | 판정 | 이유 |
|---|---|---|
| 렌더링 correctness | 좋음 | 실제 사진 baseline과 입력/resource matrix가 넓고 preview/export 경계를 통과 |
| export 안정성 | 좋음 | isolate lifecycle과 실패 형태가 명시적이며 timeout/cancel cleanup 검증 |
| 저장 데이터 안전성 | 좋음 | preferences와 filter index 모두 typed recovery state와 비파괴 복구/초기화 선택을 제공하며 settings UI interaction과 iOS integration을 검증했다 |
| 모듈 경계 | 보통 이상 | export/publish와 renderer resource I/O는 분리됐지만 page가 state/recipe 변환을 과다 소유 |
| dead code 관리 | 보통 | editor unused suppression은 제거됐으나 legacy renderer/UI/model 계보 정리가 남음 |
| 플랫폼 codec 정직성 | 좋음 | 미지원 codec을 노출하거나 확장자만 위장하지 않음 |
| 배포 재현성 | 미확인 | dirty tree이며 같은 commit의 CI와 실기기 profile evidence 없음 |

## 남은 P1 — 이 순서로 마감

### 1. dead/legacy 호출 graph 정리

- 완료: `_ToolsPanel`, `_ToolsSubTab`, `_buildLocalSubTabRow`, `_TabBtn`, `_FlipBtn`, 구형 local panel builders와 draft의 `toolsSubTab` 직렬화를 제거했다.
- 완료: `HistogramWidget`/histogram engine과 테스트 전용 depth/multiclass registry·implementations를 제거했다. 이들은 production 진입점이 없었다.
- 완료: legacy player 테스트는 production `EditorRenderer` 계약 또는 직접 engine unit test로 이관했고, player와 `EditSession`을 삭제했다.
- 완료: 세 종류 depth estimator와 multiclass model 상태는 production 진입점이 없음을 확인해 삭제했다.
- 완료: `EditorPage`의 `unused_element`, `unused_field`, `unused_element_parameter` 억제를 제거했고 editor analyzer warning은 0이다.

완료 조건:

- [x] editor production graph의 unused suppression 0.
- [x] 동일 기능의 production renderer 계보 1개.
- [ ] 미연결 widget/engine/state 0. 나머지 legacy UI와 snapshot model의 미사용 tool payload를 정리한다.

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

### 5. WebP 제품 결정

- WebP가 필수라면 ImageIO가 아니라 검증된 bundled `libwebp`/동등 encoder를 iOS native에 연결하고 실제 RIFF/WEBP bytes, dimensions, quality, Photos/share를 실기기까지 검증한다.
- 필수가 아니라면 현재처럼 capability false일 때 숨기고 JPEG로 정규화한다. README/설정에서 iOS WebP 지원을 약속하지 않는다.

## 이후 P2 / release gate

- renderer/file diagnostics를 중앙 sanitizer와 event code/severity/retryability로 통합.
- deprecated Flutter API 정리와 남은 analyzer info 축소.
- 연결 iPhone profile에서 12/24MP export p50/p95, peak RSS, 취소/저메모리/limited PhotoKit 검증.
- Android permission/export/signing 검증.
- clean snapshot에서 unit + integration + analyze를 같은 commit/CI로 재현.

최종 출시 조건:

- [ ] P1 1~5 완료 또는 WebP 비지원 제품 결정을 문서화.
- [ ] analyzer error/warning 0, editor unused suppression 0.
- [ ] 필수 fixture skip 0, iOS/Android 실기기 export 통과.
- [ ] clean checkout CI 재현과 signing/privacy/광고 정책 확정.
