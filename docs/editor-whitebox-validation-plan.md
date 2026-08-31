# Memoria 화이트박스 검증 계획

> 기준일: 2026-08-26
>
> 대상: 현재 production graph에 연결된 편집기, 필터 생성, 저장·복구, iOS export
>
> 상태: L0~L3 자동 검증 운영 중. L4 실기기 profile과 L5 VoiceOver·시각 QA는 출시 gate.

## 1. 승인 기준

화이트박스 승인은 화면이 열린다는 사실이 아니라 다음 연결을 모두 증명해야 한다.

1. 사용자 입력이 단 하나의 상태 소유자에게 전달된다.
2. 임시 도구 상태는 적용·취소 중 정확히 한 경로로 종료된다.
3. 같은 snapshot이 history, draft, preview recipe, export recipe의 기준이 된다.
4. preview와 export가 같은 renderer와 resource 계약을 사용한다.
5. 비동기 작업은 최신 요청만 UI와 저장소를 변경한다.
6. 실패·취소·timeout 후 임시 파일, isolate, 진행 UI가 정리된다.
7. 도구 카탈로그에 노출된 모든 도구가 controls, reset, history 분류와 연결된다.
8. 200% 글자 크기와 semantics tree에서도 핵심 흐름을 조작할 수 있다.

코드 승인과 스토어 출시는 구분한다. host/simulator 검증이 통과해도 signed clean CI, 실제 iPhone profile 성능, VoiceOver 수동 탐색이 없으면 스토어 출시를 승인하지 않는다.

## 2. 현재 연결 구조

```text
EditorPage container
  ├─ EditorToolCatalog ──> grid / favorites / history classification
  ├─ EditorToolTransactionController ──> begin / cancel / complete
  ├─ EditorEditState ──> EditorStateSnapshot
  │                       ├─ EditorHistoryController
  │                       ├─ EditorDraftStore
  │                       └─ EditorRenderRecipe
  ├─ preview scheduler ──> EditorRenderer
  ├─ EditorResourcePreparer ──> mask / frame / blend / text bytes
  └─ EditorMediaExportCoordinator ──> EditorExportService isolate

CreateFilterPage container
  ├─ RecentPhotoSource
  ├─ CreateFilterReferenceAnalyzer ──> palette / tags
  ├─ CreateFilterGenerator isolate ──> LUT / recipe / fit report
  ├─ CreateFilterCommitTransaction ──> preview / repository / rollback
  └─ stateless stage/result components ──> callbacks only
```

의존 방향은 page container → controller/service → domain/engine이다. renderer, repository, generator는 widget을 참조하지 않는다. 프레젠테이션 컴포넌트는 상태를 직접 저장하거나 repository를 호출하지 않고 값과 callback을 받는다.

## 3. 컨테이너·컴포넌트 평가

| 영역 | 판정 | 근거 | 남은 제한 |
|---|---|---|---|
| Editor 상태 소유권 | 좋음 | 실제 편집값은 `EditorEditState`, 임시 화면값은 `_EditorUiState`, 도구 수명은 transaction controller가 소유 | page에 호환 accessor가 많아 필드 추가 시 adapter test가 필수 |
| Editor 컴포넌트 | 보통 이상 | panel·overlay·button은 callback 기반 widget, shell/menu/control은 책임별 part | shell/control은 같은 library의 State extension이므로 완전한 독립 presenter는 아님 |
| Editor 도구 연결 | 좋음 | 26개 도구의 단일 catalog, controls/cancel 및 reset/apply 계약 매트릭스 | 도구별 픽셀 oracle은 P2에서 확대 |
| preview/export 경계 | 좋음 | 같은 snapshot→recipe→renderer, 주입 가능한 preview scheduler, resource preparer와 export coordinator 분리 | 실기기 profile 수치는 P1 release gate |
| Create Filter container | 좋음 | generator/source/repository/preview/reference analyzer 모두 주입 가능 | picker·permission·navigation은 플랫폼 container 책임으로 page에 남음 |
| Create Filter 컴포넌트 | 좋음 | stage/result/control이 stateless + callback 구조, header navigation도 callback으로 전달 | success sheet의 route 결과 해석은 container가 담당 |
| 비동기 최신성 | 좋음 | preview scheduler와 preset/generation/reference-analysis run token 보유 | 플랫폼 background 전환은 P1에서 검증 |

현재 구조는 “파일만 나눈 거대 위젯” 단계에서는 벗어났다. `EditorToolResetController`, `EditorToolApplyController`, `EditorPreviewScheduler`는 page library 밖의 공개 계약으로 분리됐다. 남은 `part` 파일은 같은 Dart library이므로 새 상태군을 추가할 때도 controller/service 경계를 먼저 만든다.

## 4. 테스트 계층

| 계층 | 목적 | 실행 위치 | 필수 증거 |
|---|---|---|---|
| L0 계약 | schema, 기본값, catalog, transaction, cache key | host unit | assertion |
| L1 엔진 | 픽셀 수학, geometry, mask, LUT, codec | host unit/golden | hash·metric·golden |
| L2 container/widget | 입력, reset/apply/cancel, semantics, stale result | Flutter widget | UI state와 callback assertion |
| L3 앱 통합 | 실제 page→renderer/export/recovery | iOS simulator CI | integration log/reportData |
| L4 성능 | frame p95, first preview, export, cancel, RSS | 실제 iPhone profile | benchmark JSON |
| L5 사용성 | VoiceOver 순서, halo/banding, 긴 문구 | 기준 실기기 | 체크리스트와 캡처 |

## 5. 현재 자동화된 핵심 계약

### 5.1 연결·컨테이너

| ID | 테스트 | 합격 조건 | 구현 |
|---|---|---|---|
| WB-ARC-01 | 도구 catalog | 26개 ID가 고유하고 모두 history type 보유 | `editor_tool_connectivity_test.dart` |
| WB-ARC-02 | 전 도구 화면 연결 | catalog의 모든 도구가 production controls와 apply/reset을 노출하고 cancel 가능 | `editor_tool_connectivity_test.dart` |
| WB-ARC-03 | 도구 transaction | begin 후 cancel은 진입 snapshot/LUT 복원, complete는 backup 폐기, 중첩 begin 거부 | `editor_tool_transaction_controller_test.dart` |
| WB-ARC-04 | 편집 상태 adapter | 전체 상태군 snapshot round-trip과 initial restore | `editor_edit_state_test.dart`, `editor_state_adapter_test.dart` |
| WB-ARC-05 | history | apply/undo/redo/branch/max history | `editor_history_controller_test.dart` |
| WB-ARC-06 | startup | 한 단계 실패 후 뒤 task 실행, 선언 순서 보존 | `app_startup_test.dart` |
| WB-TOOL-RESET-* | 도구 초기화 | 26개 도구 non-neutral→neutral 정책 | `editor_tool_reset_controller_test.dart` |
| WB-TOOL-APPLY-* | 도구 적용 | 26개 도구와 filter가 이력 1건·정확한 type 기록 | `editor_tool_apply_controller_test.dart` |
| WB-ASYNC-01 | preview 최신성 | 주입 clock debounce와 늦은 worker 결과 폐기 | `editor_preview_scheduler_test.dart` |

### 5.2 렌더·내보내기

| ID | 테스트 | 합격 조건 | 구현 |
|---|---|---|---|
| WB-REN-01 | recipe 변환 | snapshot과 renderer input의 모든 상태군 일치 | `editor_render_recipe_test.dart` |
| WB-REN-02 | 공간 변환 | crop/rotate/flip/perspective와 mask 좌표 일치 | `editor_spatial_renderer_test.dart` |
| WB-REN-03 | resource 준비 | frame/blend/text/portrait bytes와 좌표 명시, 실패 typed | `editor_resource_preparer_test.dart` |
| WB-REN-04 | preview/export parity | 실제 fixture와 input matrix가 같은 renderer 계약 통과 | renderer golden/parity/input-matrix tests |
| WB-EXP-01 | worker 수명 | success/error/exit/timeout/cancel 단일 terminal event | `editor_export_service_test.dart` |
| WB-EXP-02 | publish/cleanup | WebP fallback, retry, Photos/share, temporary cleanup | `editor_media_export_coordinator_test.dart` |
| WB-EXP-03 | 기기 취소 | 진행률 표시 후 취소, 완료 UI와 파일 저장 없음 | `editor_performance_test.dart` |

### 5.3 Create Filter

| ID | 테스트 | 합격 조건 | 구현 |
|---|---|---|---|
| WB-CF-01 | source 상태 | ready/limited/denied/empty/error/paging UI | `recent_photos_test.dart` |
| WB-CF-02 | 최신 분석 우선 | 늦게 끝난 이전 palette/tag 분석이 최신 선택을 덮지 않음 | `create_filter_flow_test.dart` |
| WB-CF-03 | generator 수명 | progress/cancel/timeout/worker exit 구분 | `create_filter_services_test.dart` |
| WB-CF-04 | commit 원자성 | preview 성공 후에만 저장, 실패/취소 시 디렉터리 rollback | services/roundtrip tests |
| WB-CF-05 | 생성 round-trip | neural 생성→저장→reload→apply byte 안정성 | `custom_filter_roundtrip_test.dart` |
| WB-CF-ROLLBACK-01 | commit 취소 | preview 중·repository 저장 중 취소 모두 metadata/file 0 | `create_filter_services_test.dart` |

### 5.4 접근성·기기 통합

| ID | 테스트 | 합격 조건 | 구현 |
|---|---|---|---|
| WB-A11Y-01 | 큰 글자 | 320×640, 200% text scale에서 핵심 화면 overflow/exception 없음 | `page_accessibility_test.dart` |
| WB-A11Y-02 | semantics | back/select/mode button과 selected state 노출 | `page_accessibility_test.dart` |
| WB-GEST-01 | focus overlay | 한 손가락 이동과 pinch가 단일 scale recognizer에서 assertion 없이 동작 | `focus_overlay_widget_test.dart` |
| WB-IOS-01 | Editor transaction | reset/apply/back/crop production page 동작 | `editor_whitebox_device_test.dart` |
| WB-IOS-02 | 플랫폼 계약 | WebP capability false일 때 가짜 WebP 미발행 | `ios_native_webp_test.dart` |
| WB-IOS-03 | 저장 복구 | settings에서 복구/보관/삭제 흐름 실행 | `settings_recovery_ui_test.dart` |
| WB-DRAFT-01 | 실제 page 복원 | `EditorPage` 폐기·재생성 후 v3 snapshot/history 복원 | `editor_whitebox_device_test.dart` |

## 6. 다음 화이트박스 확장 순서

### P0 — 완료

1. [x] `WB-TOOL-RESET-*`: 26개 도구의 non-neutral→reset→neutral 정책을 parameterized 검증한다.
2. [x] `WB-TOOL-APPLY-*`: 26개 도구와 filter의 apply가 history를 정확히 1개 늘리고 올바른 `EditToolType`을 기록한다.
3. [x] `WB-ASYNC-01`: clock/worker 주입 가능 scheduler와 오래된 render 결과 폐기를 deterministic 검증한다.
4. [x] `WB-DRAFT-01`: 실제 `EditorPage` 폐기·재생성 후 version 3 draft 복원을 iOS simulator에서 검증한다.
5. [x] `WB-CF-ROLLBACK-01`: commit 직전 및 repository write 중 취소, preview/repository 실패 후 파일·metadata 잔존 0을 fault-injection으로 검증한다.

검증 결과: analyzer 0, unit/widget 502 pass(선택형 로컬 fixture 1건 조건부 skip), iPhone 17 / iOS 26.5 simulator integration 8 pass.

### P1 — signed candidate에서 검증

1. 실제 iPhone profile mode에서 12MP·24MP JPEG/PNG/TIFF export를 각각 5회 실행한다.
2. preview frame build+raster p50/p95/p99, first preview, export duration, peak RSS를 JSON으로 저장한다.
3. background/foreground, 메모리 경고, limited Photos, share 취소를 반복한다.
4. VoiceOver로 HOME→Editor→도구→적용→내보내기와 Create→생성 완료 순서를 탐색한다.
5. 200%·300% 글자 크기, 한국어·영어, iPhone SE급 폭과 landscape에서 hit target/overflow를 확인한다.

### P2 — 시각 품질 승인

1. portrait hair/안경/다인/얼굴 없음 mask 경계와 halo를 기준 사진으로 비교한다.
2. gradient의 curve/HSL/glow/halation banding, hard edge의 sharpen halo를 검사한다.
3. frame/text/blend z-order와 alpha, EXIF 1/3/6/8 방향을 캡처한다.
4. custom LUT의 saturated primary, skin tone, low-light clipping을 비교한다.

## 7. 공통 fixture와 정량 gate

| fixture | 목적 |
|---|---|
| 1×1 primary/gray | clamp, channel, neutral no-op |
| 256 gray gradient | curve, exposure, banding |
| hue wheel + 8 patches | HSL, saturation, WB |
| 비대칭 사분면 | crop, rotate, flip, perspective |
| checker/hard edge | blur, sharpen, halo |
| seeded noisy gray | denoise, grain 결정성 |
| alpha frame + second image | frame/blend 순서 |
| EXIF 1/3/6/8 | import/export 방향 |
| 12MP/24MP synthetic | memory와 export 성능 |

- neutral no-op: mean absolute diff ≤ 0.25/255, max ≤ 2/255.
- preview/export parity: downsample 후 mean diff ≤ 2/255, p99 ≤ 10/255, SSIM ≥ 0.992.
- deterministic golden: mean diff ≤ 1.5/255, SSIM ≥ 0.995.
- 실제 iPhone steady-state frame: build+raster p95 ≤ 16ms.
- 일반 preview: debounce 이후 최신 결과 p95 ≤ 80ms; ML/고비용 효과 p95 ≤ 250ms.
- export cancel: 요청 후 UI 종료 p95 ≤ 500ms, 임시 파일 0.
- 메모리 budget: preview RSS 증가 ≤ 128MB, export peak 증가 ≤ 512MB.

## 8. CI 실행과 증거

```bash
flutter analyze --no-fatal-infos
flutter test --coverage --reporter compact
flutter test integration_test --device-id <ios-simulator-id> --reporter compact
flutter drive --profile \
  --driver test_driver/editor_performance_driver.dart \
  --target integration_test/editor_performance_test.dart \
  --device-id <physical-ios-device-id> --publish-port
```

CI는 analyze, 전체 unit/widget, iOS simulator integration을 같은 commit에서 실행한다. L4 결과에는 commit SHA, 기기 모델, OS, build mode, fixture checksum, p50/p95/p99, peak RSS를 기록한다. 수동 L5 결과에는 화면 녹화 또는 캡처와 통과한 언어·접근성 설정을 남긴다.

## 9. 최종 판정 규칙

- **코드 release candidate**: L0~L3 전부 통과, analyzer 0, 필수 fixture skip 0.
- **성능 candidate**: L4 budget 전부 통과하고 반복 실행의 편차 원인이 설명됨.
- **스토어 candidate**: L5 VoiceOver·시각 QA, signing, privacy/광고 설정, 실제 Photos/share까지 통과.
- 실패를 skip·허용치 완화·기능명 변경으로 숨기지 않는다. 제품 경로가 없는 기능은 테스트를 유지하지 않고 catalog와 문서에서 제거한다.
