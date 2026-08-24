# Memoria 편집 UX·미디어·내보내기 복구 계획

- 작성일: 2026-08-20
- 상태: 기능 구현·자동 검증·iOS 시뮬레이터 검증 완료 / 실기기 Photos·share 최종 확인 대기
- 범위: 편집기 상단 액션, 크롭, 확장, 프레임, 텍스트, 드라마/HDR, 효과 미리보기, 필터 제작 사진 선택, 내보내기 설정/인코딩, AI 모델 초기화
- 관련 기준 문서: `docs/editor-whitebox-validation-plan.md`, `docs/create-filter-gap-review.md`

## 1. 목표

### 진행 기록 (2026-08-20)

- 상단 고대비 액션, 크롭 preset 최대 영역 refresh, 스마트 확장 신규 노출 제거, 필터 제작 사진 선택 surface, 내보내기 형식·품질 계약, 기본 AI preload를 구현했다.
- 텍스트는 입력 즉시 live overlay로 표시하며 drag / pinch-zoom / rotation 상태를 history·draft·preview·export·live slider 경로에 연결했다.
- RGB 프레임 PNG에서 alpha write가 무시되던 결함을 수정했다. 13개 출시 프레임을 실제 RGBA overlay asset으로 변환하고 preview/export/replay가 동일 helper를 사용하도록 통일했다.
- HDR을 luminance 중심 tone mapping으로 교체하고 highlight·alpha·shadow-noise gate를 추가했다. 드라마/HDR 선택 카드는 실제 사진 proxy 미리보기를 비동기로 cache한다.
- iOS의 WebP 설정은 native ImageIO 변환을 거쳐 실제 WebP가 생성될 때만 완료된다. 변환 불가 시 오류 처리하여 잘못된 확장자 파일을 만들지 않는다.
- 그레인·아웃포커스·렌즈 흐림·피부 보정의 small RGBA crash/alpha/mask 계약을 보강했고, 얼굴 분할 모델을 앱 시작 후 자동 준비한다.
- 2026-08-20 검증: Flutter 전체 테스트 468개, 시뮬레이터 화이트박스 3개, 시뮬레이터 성능 시나리오 2개, iOS simulator build/install/launch를 통과했다. 정적 분석은 error/warning 0이며 기존 deprecation/info만 남아 있다.
- 무선 실기기에는 개발 서명·설치·비디버그 앱 실행까지 성공했지만 Local Network 권한이 허용되지 않아 Dart VM service가 연결되지 않았다. Photos 저장·share sheet 포맷/품질과 profile 성능은 권한 허용 또는 USB 연결 후 최종 확인한다.

이번 작업은 보이지 않는 버튼의 색만 바꾸는 수준이 아니다. 사용자가 어떤 사진을 열어도 편집 동작을 즉시 찾을 수 있어야 하며, 화면에서 보인 결과와 내보낸 파일이 같아야 한다.

1. 뒤로가기, 실행 취소, 다시 실행, 적용 전 보기, 적용 버튼이 모든 사진 톤에서 식별된다.
2. 크롭 비율을 바꿀 때 이전의 작은 크롭 박스를 재사용하지 않고, 선택한 비율로 가능한 최대 크기의 박스를 새로 만든다.
3. 품질이 불충분한 스마트 확장 옵션은 신규 UI에서 제거한다.
4. 프레임은 사진 위의 테두리로만 보이고 사진 중앙을 가리지 않는다.
5. 텍스트를 입력하는 즉시 사진 위에 나타나며 위치·크기·색상·글꼴을 수정할 수 있다.
6. 드라마와 HDR 스케이프가 디테일을 파괴하거나 밴딩·헤일로를 만들지 않는다.
7. 필터 제작 화면은 사진 라이브러리를 첫 화면부터 보여주며, 빈 이미지 영역과 이미지 선택 버튼 모두 같은 선택 동작을 수행한다.
8. 내보내기 품질과 포맷 설정이 실제 인코더에 연결되고, 확장자와 파일 내용이 일치한다.
9. 번들 색감 이전 모델은 사용자 다운로드 버튼 없이 자동 준비되고, 설정의 AI 모델 섹션은 제거된다.

## 2. 현재 코드 감사 결과

| 영역 | 현재 상태 | 판정 |
|---|---|---|
| 편집 상단 액션 | `editor_page.dart::_buildTopBar()`가 배경 없는 작은 아이콘을 직접 배치한다. 적용은 초록 체크 아이콘만 있고, 적용 전 보기도 아이콘뿐이다. | 밝거나 복잡한 배경에서 탐색성과 대비가 부족하다. |
| Edit 빈 화면 뒤로가기 | 밝은 빈 화면에서도 단색 아이콘만 사용한다. | 공통 고대비 컴포넌트가 필요하다. |
| 크롭 비율 | `_setCropRatioPreset()`가 새 비율을 현재 crop rect 안에 맞춘다. | 비율 전환을 반복하면 박스가 누적 축소되는 직접 원인이다. |
| 확장 | 기본값과 UI가 `smart`, `black`, `white`를 노출한다. | `smart` 신규 선택을 제거하되 기존 draft 호환 정책이 필요하다. |
| 프레임 | 번들 프레임 대부분이 alpha 없는 JPEG/RGB PNG이다. 현재 고정 5.5% 경계만 남기는 `_extractFrameBorder()`를 사용한다. | 에셋마다 실제 안쪽 개구부가 달라 고정 경계 추출로는 중앙 가림을 보장할 수 없다. |
| 텍스트 | 모델에는 `textX`, `textY`, `textRotation`이 있으나 편집기는 좌표를 0.5/0.82로 고정하고 직접 조작 overlay가 없다. 입력 후 32ms debounce를 거친 전체 preview raster에만 의존한다. | 즉시 표시와 직접 수정이 불가능하고, 흰 사진에서는 기본 흰 글자가 보이지 않을 수 있다. |
| 드라마/HDR | 드라마는 여러 8-bit 변환을 순차 적용한다. HDR은 blur와 Lab 변환 후 강한 local contrast를 적용한다. | 반복 양자화, clipping, halo, 노이즈 증폭 위험이 있다. |
| 효과 미리보기 | 실제 이미지 thumbnail이 아니라 어두운 카드에 아이콘과 글자만 표시한다. | 효과 차이를 선택 전에 판단할 수 없다. |
| 필터 제작 사진 선택 | 최근 사진 strip은 있으나 빈 stage가 정적 frame asset을 사용한다. 보정 레시피의 빈 slot 탭은 active slot만 바꾸고 시스템 picker를 열지 않는다. | 사용자의 사진이 주인공인 선택 UI가 아니며 진입점이 일관되지 않다. |
| 내보내기 품질 | 설정의 품질 행 `onTap`이 `null`이고 표시값은 `JPEG 95%`로 고정이다. | 실제 설정 불가. |
| WebP | `exportFormat == 'webp'`에서 `encodeJpg(... quality: 90)`을 호출한 뒤 `.webp`로 저장한다. | 확장자와 파일 내용이 불일치하는 출시 차단 결함이다. |
| RAW/DNG | `exportFormat == 'raw'`에서 TIFF를 인코딩한 뒤 `.dng`로 저장한다. | 진짜 DNG/센서 RAW가 아니다. 현재 문구의 `100% Meta Preservation`도 사실이 아니다. |
| AI 모델 | 색감 이전 모델은 이미 앱 asset으로 번들된다. 설정에서 수동 설치 버튼을 제공하지만 앱 시작 시 preload하지 않는다. | 네트워크 다운로드가 아니라 번들 asset 설치이므로 자동 준비가 맞다. |

## 3. 제품·기술 결정

### 3.1 상단 액션은 적응형 글래스 버튼으로 통일

사진 평균색에 버튼 색을 계속 바꾸면 미리보기 갱신 중 깜빡임이 생길 수 있다. 따라서 아래 조합을 사용한다.

- 사진의 축소 preview에서 상단 영역 luminance를 한 번 계산해 `lightPhoto`/`darkPhoto` 두 상태만 선택한다.
- 모든 액션에 반투명 반대 톤 surface, 1.5px 이중 대비 테두리, 약한 그림자, backdrop blur를 적용한다.
- 적용 버튼은 체크 아이콘만 두지 않고 `적용` 글자가 있는 filled pill로 만든다.
- 적용 전 보기는 `적용 전` 글자와 눈 아이콘을 함께 표시하며 press-down 동안 active surface로 바뀐다.
- 뒤로가기·실행 취소·다시 실행은 최소 44×44pt hit target을 유지한다.
- disabled undo/redo도 형태는 남기되 opacity와 semantics `disabled` 상태가 명확해야 한다.

공통 컴포넌트 후보:

- `EditorOverlayActionButton`
- `EditorApplyButton`
- `EditorCompareHoldButton`
- `EditorTopActionBar`

### 3.2 RAW에 대한 정직한 정책

편집된 JPEG/HEIC에서 원래 센서 RAW를 복원할 수는 없다. 따라서 다음 중 하나만 출시한다.

- 기본안: 포맷 목록을 `JPEG / PNG / WebP / TIFF`로 수정하고 가짜 RAW/DNG 옵션을 제거한다.
- DNG가 반드시 필요하면: `Processed DNG`로 명확히 표기하고, 네이티브 DNG writer, 색공간, bit depth, metadata 범위를 별도 구현·검증한 뒤에만 노출한다.

본 계획의 1차 구현은 기본안인 TIFF 노출을 사용한다. `.dng` 확장자에 TIFF bytes를 쓰는 현재 동작은 즉시 제거한다.

### 3.3 포맷과 품질의 관계

- JPEG: 70/80/90/95/100 품질 설정을 실제 JPEG encoder에 전달한다.
- WebP: 70/80/90/95/100 품질 설정을 실제 WebP encoder에 전달한다.
- PNG: lossless이므로 화질 slider를 숨기고 압축 속도/파일 크기 설명만 표시한다.
- TIFF: lossless processed image로 표시하고 품질 slider를 숨긴다.
- 포맷 변경이 곧 화질 변경이라는 표현은 사용하지 않는다. 손실 포맷에서만 quality가 유효하다.

## 4. 구현 계획

### Phase 0 — 회귀 fixture와 테스트 seam 준비

수정 전에 아래 fixture를 고정한다.

- 밝은 설경, 어두운 야경, 고대비 패턴: 상단 액션 대비 확인.
- 가로 4:3, 세로 3:4, 정사각형: 크롭 최대 rect 계산.
- 중앙 단색 + 가장자리 색상 frame fixture: layer 순서와 중앙 보존.
- 흰/검/복잡한 배경: 텍스트 가시성.
- highlight ramp, shadow ramp, checker detail, ISO noise: 드라마/HDR 품질.
- JPEG/PNG/WebP/TIFF magic bytes fixture: 내보내기 포맷 검증.

추가 파일 후보:

- `test/features/editor/editor_top_actions_test.dart`
- `test/features/editor/crop_ratio_refresh_test.dart`
- `test/features/editor/frame_panel_test.dart`
- `test/features/editor/text_overlay_panel_test.dart`
- `test/engine/hdr_drama_quality_test.dart`
- `test/features/create_filter/photo_selection_surface_test.dart`
- `test/features/settings/export_settings_test.dart`
- `test/engine/export_format_contract_test.dart`
- `test/ai_manager_bundled_model_test.dart` 보강

### Phase 1 — 편집 상단 액션과 Edit 뒤로가기

대상:

- `lib/features/editor/editor_page.dart`
- `lib/features/editor/widgets/` 아래 공통 top action widget 신설
- `lib/core/theme/app_colors.dart`

작업:

1. `_buildTopBar()`의 naked icon을 공통 적응형 glass action으로 교체한다.
2. 편집 도구 비활성 상태: `뒤로가기 / 실행 취소 / 다시 실행`을 동일한 surface에 정렬한다.
3. 도구 활성 상태: 왼쪽 뒤로가기는 해당 도구 취소, 오른쪽에는 `적용 전` hold 버튼과 `✓ 적용` pill을 둔다.
4. 적용 버튼은 enabled일 때 foam 계열 filled surface + 흰색/짙은색 자동 foreground를 사용하고, press 시 scale 0.96 및 haptic을 적용한다.
5. 사진이 없는 Edit 화면의 뒤로가기도 같은 contrast-safe component를 사용한다.
6. VoiceOver label과 tooltip을 `뒤로가기`, `실행 취소`, `다시 실행`, `적용 전 보기`, `적용`으로 고정한다.

완료 조건:

- WCAG 대비: 아이콘/텍스트 4.5:1 이상, 비텍스트 테두리 3:1 이상.
- 모든 버튼 hit target 44×44pt 이상.
- `적용 전`은 누르는 동안만 원본/도구 진입 전 preview를 표시하고 release/cancel 시 최신 preview로 복귀.
- 뒤로가기는 도구 활성 시 취소, 비활성 시 편집 취소 확인창이라는 기존 transaction 정책을 보존.

### Phase 2 — 크롭 비율 전환을 매번 최대 크기로 리프레시

대상:

- `lib/features/editor/editor_page.dart::_setCropRatioPreset()`
- `lib/features/editor/widgets/crop_overlay_widget.dart`
- `lib/features/editor/widgets/crop_panel.dart`

작업:

1. preset 선택 시 현재 crop rect를 입력으로 쓰지 않는다.
2. 원본 image aspect를 `A = imageWidth / imageHeight`, 선택 비율을 `R`이라고 할 때 최대 normalized rect를 새로 계산한다.
   - `A > R`: `height = 1`, `width = R / A`
   - `A <= R`: `width = 1`, `height = A / R`
3. 계산된 rect를 `(0.5, 0.5)` 중심으로 배치한다.
4. `자유`와 `원본`은 `[0, 0, 1, 1]`에서 다시 시작한다.
5. overlay key를 ratio/version과 연결하거나 `didUpdateWidget`에서 drag state를 초기화해 이전 handle state가 남지 않게 한다.
6. 비율 선택은 crop을 commit하지 않고, 상단 적용을 눌렀을 때만 history에 기록한다.

완료 조건:

- `1:1 → 16:9 → 4:5 → 1:1` 왕복 후 첫 1:1 rect와 좌표 오차 `1e-6` 이내.
- 모든 preset이 image bounds 안에서 해당 비율의 최대 면적을 사용.
- preset 이후에도 사용자가 박스를 이동하고 같은 비율로 확대/축소 가능.
- preview/export crop 경계 오차 1 output pixel 이하.

### Phase 3 — 확장 스마트 옵션 제외

대상:

- `lib/features/editor/editor_page.dart`
- `lib/domain/models/edit_operation.dart`
- `lib/engine/edit_operation_player.dart`

작업:

1. 신규 UI에서 `스마트` ChoiceChip을 제거하고 `블랙`, `화이트`만 제공한다.
2. 신규 session 기본값과 reset값을 `black`으로 변경한다.
3. 기존 저장 draft의 `smart`는 renderer에서 legacy 호환을 유지하되 UI에서 신규 선택할 수 없게 한다.
4. 저장된 legacy draft를 열었을 때 `스마트(이전 편집)` 읽기 전용 안내 또는 자동 `black` 전환 중 하나를 migration test로 고정한다. 기본안은 기존 픽셀 결과 보존을 위해 legacy renderer 유지다.
5. smart 관련 신규 광고/설명 문구와 테스트 기대값을 제거한다.

완료 조건:

- 새 편집에서 직렬화되는 `expandMode`는 `black` 또는 `white`뿐이다.
- 기존 smart draft는 crash 없이 기존 결과를 재생한다.

### Phase 4 — 프레임 layer 및 asset 복구

대상:

- `assets/frames/`
- `lib/features/editor/editor_page.dart::_applyCreativeEffects()`
- `lib/engine/edit_operation_player.dart`
- `pubspec.yaml`

현재 프레임은 alpha가 없는 JPEG가 많으므로 코드에서 임의로 5.5%만 남기는 방식만으로는 부족하다.

작업:

1. 모든 frame asset을 전수 분석해 중앙 개구부와 실제 border를 확인한다.
2. 출시 frame은 투명 중앙을 가진 RGBA PNG/WebP overlay로 변환하고 manifest에 `insetLeft/Top/Right/Bottom`, aspect 정책을 기록한다.
3. 합성 순서를 `사진 → 색/효과 → 프레임 overlay → 텍스트`로 고정한다.
4. preview, export, draft replay가 하나의 frame compositing helper를 공유한다.
5. 프레임의 center alpha가 기준 이상이면 asset test를 실패시킨다. 중앙 60% 영역 alpha p99는 0 또는 명시된 translucent 디자인 한계 이하여야 한다.
6. thumbnail도 실제 overlay를 checker/photo 위에 합성해 사용자가 가림 정도를 선택 전에 볼 수 있게 한다.

완료 조건:

- 모든 출시 frame에서 중앙 사진의 기준 픽셀이 보존된다.
- border는 사진 위에 표시되고 preview/export가 동일하다.
- 1:1, 4:3, 3:4, 16:9, 9:16에서 stretch 정책이 명시되고 왜곡이 없다.

### Phase 5 — 텍스트 즉시 표시와 직접 편집

대상:

- `lib/features/editor/editor_page.dart`
- `lib/features/editor/utils/text_rasterizer.dart`
- `lib/domain/models/edit_operation.dart`
- `lib/engine/edit_operation_player.dart`
- `lib/features/editor/widgets/text_overlay_editor.dart` 신설

작업:

1. 텍스트 도구 활성 중에는 전체 이미지 재렌더를 기다리지 않고 Flutter overlay로 글자를 즉시 표시한다.
2. 입력 첫 글자부터 preview에 나타나게 하고, focus가 열린 동안에도 유지한다.
3. overlay drag로 `textX/textY`, 회전 handle로 `textRotation`, pinch 또는 slider로 `textSize`를 변경한다.
4. 이미 모델에 존재하는 `textX`, `textY`, `textRotation`을 editor state, history, draft, preview, export에 실제 연결한다.
5. 기본 흰색 글자에는 반투명 검정 shadow/selection outline을 표시해 밝은 사진에서도 편집 중 위치를 찾을 수 있게 한다. 최종 shadow 옵션은 별도 사용자 설정이 없으면 export에 강제하지 않는다.
6. keyboard가 control panel을 가리지 않도록 viewInsets에 반응하고, 완료 버튼으로 keyboard를 내릴 수 있게 한다.
7. `TextRasterizer`의 preview/export scale 계약을 통일하고 font fallback을 deterministic하게 만든다.
8. 텍스트는 프레임 위에 합성한다.

완료 조건:

- 입력 후 다음 frame 또는 100ms 이내에 글자가 화면에 나타난다.
- drag한 위치와 export 위치가 normalized 좌표 오차 0.01 이하.
- undo/redo, 취소, 초기화, draft 재시작에서 텍스트 문자열·위치·회전·크기·색·글꼴이 정확히 복원.
- 빈 문자열은 완전 no-op이며 이전 text bitmap cache가 남지 않는다.

### Phase 6 — 드라마·HDR 화질 복구 및 효과 미리보기 강화

대상:

- `lib/engine/artistic_effects.dart`
- `lib/engine/lut_engine.dart`
- `lib/features/editor/editor_page.dart::_EffectsPanel`

엔진 작업:

1. 드라마의 exposure/contrast/clarity/saturation/shadow 연산을 가능한 한 단일 float working pass로 통합해 중간 8-bit 양자화를 줄인다.
2. 밝은 드라마 preset은 highlight roll-off를 적용하고 clipping pixel 비율을 제한한다.
3. HDR은 색 채널 각각의 비율을 증폭하는 대신 luminance 중심 multi-scale local contrast로 변경하고 chroma는 별도로 제한한다.
4. flat 영역에는 detail boost를 감쇠하고 edge-aware threshold로 noise와 halo를 억제한다.
5. alpha를 보존하고 strength 0은 byte-identical no-op으로 유지한다.
6. preview proxy와 full export가 같은 parameter contract를 사용하도록 공통 helper를 둔다.

UI 작업:

1. 효과 chip의 미선택 배경을 더 진한 `oceanDeep/oceanNavy` 계열로 통일한다.
2. 선택 상태는 foam 2px border, glow, check badge로 강조한다.
3. 아이콘만 표시하지 않고 현재 사진의 96~128px proxy에 실제 효과를 렌더한 thumbnail을 cache한다.
4. thumbnail 생성 중에는 짙은 skeleton을 표시하고 스크롤 frame을 막지 않는다.

품질 gate:

- strength 0: max pixel diff 0.
- 밝은 fixture highlight clipping 증가율 0.5%p 이하.
- flat gradient banding: 고유 luminance 단계가 기준 대비 95% 이상 유지.
- edge halo: 기준 edge 주변 overshoot 3/255 이하.
- preview/export downsample SSIM 0.992 이상.
- thumbnail cached switch p95 80ms 이하, 스크롤 frame p95 16ms 이하.

### Phase 7 — 필터 제작 사진 선택 화면 재구성

대상:

- `lib/features/create_filter/create_filter_page.dart`
- `lib/features/create_filter/create_filter_services.dart`
- `lib/core/services/media_permission_service.dart`

무드 스타일:

1. 선택 전 회색/정적 frame placeholder를 제거한다.
2. 접근 허용된 최근 사진을 stage 안의 snapping photo shelf 또는 유동형 mosaic로 즉시 표시한다.
3. stage 중앙에 liquid-glass `이미지 선택` pill을 배치한다.
4. 빈 stage, stage에 표시된 `이미지` 영역, 중앙 `이미지 선택` pill, 하단 선택 action 모두 `_pickReferenceImage()`로 연결한다.
5. 최근 사진 thumbnail 자체를 누르면 즉시 참조 사진에 추가하고 선택 순서 badge를 표시한다.
6. 선택 후 stage는 실제 사진 collage로 전환되며 stage 전체를 탭하면 다시 picker가 열린다.

보정 레시피:

1. BEFORE/AFTER 빈 slot을 누르면 active slot 지정과 동시에 system photo picker를 연다.
2. 두 slot 사이 또는 바로 아래 중앙에 liquid-glass `이미지 선택` pill을 둔다.
3. 중앙 버튼은 현재 active slot에 사진을 넣고, BEFORE 선택 완료 후 AFTER로 자동 이동한다.
4. 최근 사진 strip 선택과 system picker 선택이 같은 state transition을 사용한다.
5. 선택된 slot 재탭은 사진 교체, X 버튼은 해당 slot만 제거한다.

Apple 스타일 세부사항:

- `BackdropFilter` blur, 얇은 흰 highlight border, mint/cream tint, 깊지 않은 shadow 사용.
- 회색 solid placeholder 금지.
- photo access limited/denied/iCloud unavailable 상태는 각각 안내와 picker fallback을 제공.
- `Image.file` decode는 thumbnail/proxy를 우선 사용하고 원본 decode로 스크롤을 막지 않는다.

완료 조건:

- 사진 접근 허용 상태에서 화면 진입 후 최근 사진 첫 행이 500ms 이내 표시.
- 무드 스타일과 보정 레시피 모두 빈 이미지 창과 중앙 버튼으로 system picker 진입 가능.
- 어떤 진입점을 사용해도 palette/style 분석과 필터 생성 입력이 동일하다.
- 5장 제한, 중복 선택, 취소, limited access, iCloud 실패가 기존 데이터 손실 없이 처리된다.

### Phase 8 — 내보내기 설정과 실제 encoder 연결

대상:

- `lib/features/settings/settings_page.dart`
- `lib/features/editor/editor_page.dart`
- `lib/core/l10n/strings.dart`
- 필요 시 `lib/core/services/export_preferences.dart`, `lib/engine/export_encoder.dart` 신설
- 실제 WebP encoder dependency 또는 iOS/Android native encoder

설정 UI:

1. 비활성 `내보내기 품질` 행을 활성화한다.
2. JPEG/WebP 선택 시 quality picker 또는 slider를 열고 70/80/90/95/100 preset을 제공한다.
3. PNG/TIFF 선택 시 품질 행에 `무손실 · 품질 설정 없음`을 표시하고 비활성 이유를 설명한다.
4. 설정은 typed `ExportSettings(format, quality)` 모델로 저장하며 문자열 key를 화면과 worker가 직접 해석하지 않게 한다.

인코더:

1. `ExportEncoder`를 만들어 format별 encoder와 MIME/extension/magic-byte 계약을 한곳에 둔다.
2. JPEG는 실제 quality 값을 `encodeJpg`에 전달한다.
3. PNG는 PNG signature로 저장한다.
4. WebP는 실제 WebP encoder를 사용한다. encoder 확보 전에는 WebP 옵션을 UI에 노출하지 않는다.
5. TIFF는 `.tif/.tiff`로 저장하고 `image/tiff`로 공유한다.
6. 가짜 `.dng` 출력은 제거한다.
7. 공유 및 갤러리 저장 시 파일명, MIME, UTI가 format과 일치하도록 platform channel/API를 검증한다.
8. 실패 시 낮은 해상도로 재시도하더라도 사용자가 지정한 format과 quality는 바꾸지 않는다.

화이트박스 검증:

| ID | 검증 | 통과 조건 |
|---|---|---|
| EX-FMT-01 | JPEG magic bytes | `FF D8 FF`, decoder=JPEG, 확장자 `.jpg`, 설정 quality 반영 |
| EX-FMT-02 | PNG magic bytes | `89 50 4E 47`, alpha 정책과 확장자 일치 |
| EX-FMT-03 | WebP magic bytes | `RIFF....WEBP`, JPEG signature가 절대 나오지 않음 |
| EX-FMT-04 | TIFF magic bytes | `II*` 또는 `MM*`, 확장자 `.tif/.tiff` |
| EX-FMT-05 | quality 70 vs 95 | 동일 입력에서 95가 일반적으로 더 큰 파일이고 품질 metric이 낮아지지 않음 |
| EX-FMT-06 | PNG/TIFF quality | slider 미노출, 저장값이 encoder 결과를 바꾸지 않음 |
| EX-FMT-07 | share sheet | MIME/UTI와 실제 bytes 일치 |
| EX-FMT-08 | preview/export | 선택 format과 무관하게 편집 픽셀 parity 허용치 충족 |

### Phase 9 — AI 모델 자동 준비 및 설정 정리

대상:

- `lib/main.dart` 또는 app bootstrap provider
- `lib/ai/ai_manager.dart`
- `lib/features/settings/settings_page.dart`
- `lib/core/l10n/strings.dart`

작업:

1. 첫 frame 이후 `AiManager.instance.preload(kModelColorTransfer)`를 non-blocking 실행한다.
2. 색감 이전 모델은 이미 bundle asset이므로 네트워크를 호출하지 않고 documents cache에 원자적으로 설치·SHA 검증한다.
3. 첫 preload와 필터 생성의 `require()`가 동시에 호출돼도 `_inFlight`로 한 번만 설치되게 유지한다.
4. 실패해도 앱 시작을 막지 않고 필터 생성 진입 시 재시도 및 명확한 오류를 제공한다.
5. 설정 화면의 `AI 모델` section과 `_AiModelRow`, 관련 listener/state를 제거한다.
6. 미사용 localization key를 제거하거나 향후 내부 진단용 key와 분리한다.
7. debug dev panel에는 모델 버전/SHA/path/status를 남겨 화이트박스 확인이 가능하게 한다.

완료 조건:

- fresh install 후 설정 조작 없이 color transfer model이 ready가 된다.
- 번들 모델 설치 중 네트워크 요청 0회.
- SHA/크기 불일치 시 corrupt file 삭제 후 재설치.
- release 설정 화면에 AI 모델 다운로드 UI가 없다.

## 5. 통합 테스트 시나리오

| ID | 시나리오 | 기대 결과 |
|---|---|---|
| UX-01 | 밝은/어두운/고대비 사진에서 상단 확인 | 모든 action 경계와 아이콘/글자 식별 가능 |
| UX-02 | undo → redo → 새 편집 | history cursor와 버튼 enabled 상태 정확 |
| UX-03 | 적용 전 hold 중 손가락을 영역 밖으로 이동 | 원본 상태 고착 없이 최신 preview 복귀 |
| CR-01 | 모든 crop preset 순차 선택 | 매번 full bounds 기준 최대 rect로 refresh |
| CR-02 | preset resize 후 다른 preset, 다시 원래 preset | 누적 축소 없음 |
| EX-01 | 신규 확장 도구 진입 | smart 미노출, black 기본 |
| FR-01 | 모든 frame asset 순회 | 중앙 사진 가림 없음, border가 위에 표시 |
| TX-01 | 한글/영문/이모지 입력 | 다음 frame에 overlay 표시, 지원 불가 glyph fallback 명확 |
| TX-02 | drag/resize/rotate 후 export | 위치·크기·회전 parity 충족 |
| HD-01 | 밝은 드라마 0→100 | highlight detail 유지, clipping gate 통과 |
| HD-02 | HDR 0→100 on noisy shadow | noise 폭증/halo 없이 local contrast 증가 |
| CF-01 | 무드 스타일 빈 stage 탭 | system picker 열림 |
| CF-02 | 보정 레시피 BEFORE/AFTER 빈 slot 탭 | 해당 slot 대상 picker 열림 |
| CF-03 | recent photo와 picker를 섞어 선택 | 동일 selection order와 분석 결과 |
| SET-01 | format별 설정 전환 | quality 행의 활성/설명 상태가 format과 일치 |
| OUT-01 | JPEG/PNG/WebP/TIFF 각각 export/share | extension, MIME/UTI, magic bytes, decoder 모두 일치 |
| AI-01 | fresh install offline | 번들 color model 자동 설치 성공 |
| AI-02 | model install 중 필터 제작 진입 | 중복 설치 없이 await 후 정상 생성 |

## 6. 실행 순서와 우선순위

1. **P0-A:** 가짜 WebP/DNG 차단 및 export contract test.
2. **P0-B:** 상단 적용/뒤로가기/undo/redo/적용 전 버튼 가시성.
3. **P0-C:** 크롭 누적 축소 수정.
4. **P0-D:** 프레임 중앙 가림과 텍스트 미표시 수정.
5. **P1-A:** 필터 제작 사진 선택 UI 재구성.
6. **P1-B:** 드라마/HDR 품질 개선과 실제 thumbnail preview.
7. **P1-C:** export 품질 설정 UI와 실제 WebP/TIFF encoder 완성.
8. **P1-D:** AI 모델 자동 preload와 설정 섹션 제거.
9. **P2:** 접근성, localization, 성능, 전체 integration/golden/실기기 QA.

각 단계는 구현 → unit/widget test → golden/parity test → iOS simulator build 순으로 닫는다. 이미지 엔진·텍스트·프레임·내보내기 단계는 마지막에 실기기 profile-mode 성능과 실제 Photos/share sheet 확인을 추가한다.

## 7. 수정 파일 예상 목록

```text
lib/
  ai/ai_manager.dart
  core/l10n/strings.dart
  core/services/export_preferences.dart          # 신규 후보
  engine/artistic_effects.dart
  engine/edit_operation_player.dart
  engine/export_encoder.dart                     # 신규 후보
  engine/lut_engine.dart
  features/create_filter/create_filter_page.dart
  features/editor/editor_page.dart
  features/editor/utils/text_rasterizer.dart
  features/editor/widgets/crop_overlay_widget.dart
  features/editor/widgets/crop_panel.dart
  features/editor/widgets/editor_top_action_bar.dart # 신규 후보
  features/editor/widgets/text_overlay_editor.dart   # 신규 후보
  features/settings/settings_page.dart
assets/frames/
pubspec.yaml
test/
integration_test/
```

## 8. 최종 Definition of Done

- [x] 어떤 사진에서도 뒤로가기, undo, redo, 적용 전, 적용 버튼이 선명하다.
- [x] 도구 적용/취소/history transaction이 기존 정책대로 동작한다.
- [x] crop preset 전환을 반복해도 crop rect가 누적 축소되지 않는다.
- [x] 신규 UI에서 스마트 확장이 보이지 않는다.
- [x] 모든 출시 frame이 중앙 사진을 보존한다.
- [x] 텍스트 입력 즉시 표시, 직접 이동/크기/회전 수정, export parity가 된다.
- [x] 드라마/HDR 품질 gate와 preview/export parity를 통과한다.
- [x] 효과 선택 카드가 진한 배경과 실제 thumbnail로 식별된다.
- [x] 필터 제작의 모든 빈 stage/slot과 중앙 버튼이 picker를 연다.
- [x] 최근 사진이 허용 범위 내에서 유동형 UI로 즉시 보인다.
- [x] 내보내기 quality가 실제 JPEG/WebP encoder에 전달된다.
- [x] 확장자, MIME/UTI, magic bytes, 실제 decoder format이 모두 일치한다.
- [x] `.webp` 안의 JPEG와 `.dng` 안의 TIFF 같은 위장 파일이 존재하지 않는다.
- [x] 번들 색감 이전 모델과 얼굴 분할 모델이 자동 준비되며 설정의 AI 모델 칸이 제거된다.
- [x] 관련 unit/widget/golden/integration test, 정적 분석 error/warning gate, iOS simulator build가 통과한다.
- [ ] 실제 iPhone에서 Photos 저장과 share sheet의 파일 형식/품질/성능을 확인한다.
