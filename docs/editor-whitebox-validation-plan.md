# 사진 편집기 전체 기능 화이트박스 검증 계획

- 작성일: 2026-08-18
- 상태: 실행 전 검증 명세
- 관련 구현 계획: [editor-filter-repair-plan.md](editor-filter-repair-plan.md)
- 기능 기준: [feature-checklists/README.md](feature-checklists/README.md)
- 대상: 편집기 UI 상태, 이미지 엔진, preview/export, 저장·복원, 오류 복구, 성능, 사용자 필터 생성

## 1. 검토 결론

기존 `editor-filter-repair-plan.md`는 사용자가 보고한 문제와 주요 완료 조건은 포함하지만, 모든 편집 기능을 하나씩 검증하고 성능까지 완료 판정하기에는 부족하다.

2026-08-18 현재 저장소 감사 결과:

- 기능 체크리스트가 참조하는 Dart 테스트 파일은 중복 제거 기준 84개다.
- 현재 존재하는 테스트 파일은 46개이고, 계획만 있고 아직 없는 파일은 38개다.
- 모든 기능 체크리스트가 성능 측정에 `tool/perf_gate.dart`를 참조하지만 실제 파일은 없다.
- 기존 테스트 상당수는 작은 synthetic image의 단일 엔진 함수 또는 numeric signature만 확인한다.
- 적용(✓)·취소·초기화 transaction, stale async preview, 실제 preview/export 합성 순서, 실기기 p95 latency/RSS는 충분히 자동 검증되지 않는다.
- 프레임, 텍스트, 선택 보정, 아웃포커스/렌즈 흐림, glow, light leak, halation, HDR/drama, RAW, 필터 생성의 widget/golden/performance target이 다수 없다.

따라서 **현재 테스트가 통과한다는 사실만으로 전체 편집기의 정상 작동과 성능을 승인하면 안 된다.** 이 문서의 필수 test target과 정량 gate를 구현하고 실제 결과 artifact를 남긴 뒤 승인한다.

## 2. 검증 목표와 원칙

### 2.1 검증할 질문

각 기능은 아래 질문에 모두 답해야 한다.

1. 중립값이 원본을 바꾸지 않는가?
2. 최소·중간·최대의 유효 값이 실제로 의도한 방향의 변화를 만드는가?
3. 다른 영역·색상·레이어에 원치 않는 변화가 새지 않는가?
4. 적용, 취소, 초기화, undo, redo, draft 복원이 정확한가?
5. preview와 export가 같은 파라미터·좌표·mask·layer order를 사용하는가?
6. 파일·asset·model·permission이 없거나 입력이 손상돼도 crash하지 않는가?
7. 빠른 연속 입력에서 오래된 비동기 결과가 최신 상태를 덮지 않는가?
8. 정해진 latency, frame time, memory budget을 충족하는가?
9. 작은 화면, 회전 화면, 접근성 모드에서도 조작 가능한가?
10. 다른 편집과 조합했을 때 순서와 결과가 결정적인가?

### 2.2 테스트 계층

| 계층 | 목적 | 실행 환경 | 필수 증거 |
| --- | --- | --- | --- |
| L0 모델/계약 | 범위, 기본값, JSON, cache key, schema | host unit test | assertion log |
| L1 엔진 | 픽셀 수학, mask, geometry, blend, 오류 fallback | host unit test | metric JSON + 실패 diff |
| L2 Widget/상태 | 터치, slider, ✓/취소/reset, semantics | Flutter widget test | test log + 필요한 golden |
| L3 통합 | UI state → preview → export → reload | integration test | preview/export image와 parity JSON |
| L4 성능 | frame, first preview, export, RSS, cancellation | profile-mode 실기기 | device별 benchmark JSON |
| L5 시각 QA | ML 경계, halo, banding, 텍스트/font, frame asset 전수 | 기준 실기기 | 체크리스트 + 캡처 |

L0~L3를 simulator/host에서 통과해도 L4 실기기 성능을 대신할 수 없다. L5는 정량화하기 어려운 시각 결함을 보완하지만 L0~L4를 대체하지 않는다.

## 3. 전체 기능 인벤토리

아래 항목을 모두 추적한다. 현재 UI에 숨겨진 기능도 구현이 존재하거나 체크리스트에 포함돼 있으면 `숨김/실험/출시` 상태를 검증한다.

| 영역 | 기능/파라미터 | 상태 확인 대상 |
| --- | --- | --- |
| 편집기 공통 | 도구 진입, ✓, 취소, reset, 원본 보기, back, undo/redo, draft | UI state/history |
| 필터 | 기본/custom LUT, intensity, favorite, cache | LUT/UI/repository |
| 기본 보정 | exposure, contrast, saturation, temperature, tint, highlights, shadows, ambiance | GPU/CPU pipeline |
| 톤 보정 | tonal shadows/midtones/highlights, B&W channel mix | color pipeline |
| 디테일 | sharpen, structure, clarity | detail engine |
| 커브 | luminance, RGB, R, G, B | curve LUT |
| 화이트밸런스 | preset, temperature, tint | white balance |
| HSL | 8 bands × hue/saturation/luminance | HSL engine |
| 스플릿 톤 | shadow/highlight hue/sat, balance | split tone |
| 크롭 | free/original/ratio, resize, move | crop UI/engine |
| 회전/반전 | straighten, 90°, horizontal, vertical | geometry |
| 원근 | horizontal/vertical 또는 homography | geometry |
| 확장 | top/bottom/left/right, smart/black/white | expand/inpaint |
| 부분 보정 | point, radius, feather, local B/C/S | local mask |
| 브러시 | dodge, burn, size, hardness, strength, clear | brush mask |
| 아웃포커스 | tilt center, band width, max blur | focus mask/blur |
| 렌즈 흐림 | focus depth/center, radius, feather | depth/radial blur |
| 비네팅 | strength, feather/center 지원 범위 | vignette |
| 그레인 | strength, size, seed, mono/color 지원 범위 | grain |
| 노이즈 제거 | luminance, colour, detail preservation | denoise |
| 글로우 | strength, saturation/threshold, warmth/softness | glow |
| 인물 | smoothing, spotlight, skin tone, bokeh, head pose 지원 범위 | segment/depth |
| 이중 노출 | image, blend mode, opacity, fit | blend |
| 프레임 | none + 모든 asset, fit, z-order | layer composite |
| 텍스트 | string, font, size, color, position, rotation/opacity/align 지원 범위 | raster/composite |
| 광학 유출 | strength, angle/position, warmth/tint, seed/texture 지원 범위 | overlay |
| 헐레이션 | strength, threshold, spread, warmth/tint | highlight mask |
| 드라마 | style preset, strength | local contrast |
| HDR 스케이프 | strength, saturation | HDR |
| 힐링 | stroke, radius, fill algorithm | inpainting |
| RAW 현상 | detection, decode, WB/exposure/noise | RAW pipeline |
| 히스토그램 | RGB/luma bins, refresh, no editor blocking | histogram |
| 필터 생성 | recent photos, style/pair mode, LUT fit, preview, save/reload | create-filter flow |
| 탭/즐겨찾기 | 4 tabs, all tools, edit tabs, favorite tools | preferences/UI |
| 내보내기 | format, resolution, progress, cancel, permission/share | export pipeline |

## 4. 공통 fixture와 측정 도구

### 4.1 Deterministic synthetic fixture

테스트 코드에서 생성하고 seed를 고정한다.

| Fixture ID | 내용 | 주 검증 기능 |
| --- | --- | --- |
| FX-01 | 1×1 black/white/mid-gray/R/G/B/C/M/Y | channel math, clamp, no-op |
| FX-02 | 256-step grayscale gradient | exposure, curves, banding, tone masks |
| FX-03 | hue wheel + 8 HSL band patch | HSL, saturation, WB, split tone |
| FX-04 | 비대칭 4분면 + 방향 문자 | crop, rotate, flip, perspective, export orientation |
| FX-05 | 1px/4px checkerboard | blur, sharpen, resampling, focus |
| FX-06 | black-white hard edge | halo, overshoot, feather, sharpening |
| FX-07 | flat gray + seeded luma/chroma noise | denoise, grain |
| FX-08 | dark/mid/highlight 3-zone ramp | highlights, shadows, glow, halation, HDR |
| FX-09 | 두 색 영역 + 중앙 경계 | selective color leakage, brush mask |
| FX-10 | alpha frame with known center/border colors | frame z-order and alpha |
| FX-11 | deterministic second image patterns | all blend modes |
| FX-12 | synthetic subject mask/depth map with hair-like thin structures | portrait, bokeh, lens blur |
| FX-13 | blemish on repeatable texture | healing/inpainting |
| FX-14 | valid identity LUT, axis LUT, constant LUT, corrupt/truncated/NaN LUT | filter safety |
| FX-15 | short/long/Korean/English/emoji/multiline text set | text rasterization |
| FX-16 | EXIF 1/3/6/8 orientation images | import, rotation, crop |
| FX-17 | tiny 1×1/2×2 and odd 17×13 images | boundary safety |
| FX-18 | 48MP-equivalent generated/fixture image | memory/export stress |

### 4.2 Approved real-image fixture

- portrait: 1인, 다인, 안경, 수염, 곱슬/잔머리, 어두운 피부/밝은 피부, 얼굴 없음.
- landscape: 하늘/나뭇잎/수평선/역광.
- low-light: luma/chroma noise와 작은 광원.
- high-key: 흰 옷, 구름, 밝은 피부, 이미 clipping된 highlight.
- architecture: 직선/격자/반복 무늬.
- text/screenshot: 날카로운 edge와 넓은 단색 영역.
- frame aspect: 1:1, 4:3, 3:4, 16:9, 9:16.
- RAW: 지원 카메라별 최소 1개 DNG/RAW와 손상 파일 1개.

원본, 라이선스, 기대 결과, mask/depth annotation, checksum을 `test/fixtures/manifest.json`에 기록한다. 사람 얼굴 fixture는 저장소 정책상 허용된 자산만 사용한다.

### 4.3 공통 metric

| Metric | 정의/용도 |
| --- | --- |
| mean absolute diff / max / p99 | no-op, golden, leakage |
| SSIM / PSNR | preview/export 및 품질 보존 |
| ΔE2000 | 색상·WB·HSL·filter 색 차이 |
| clipping ratio | RGB 0/255 pixel 비율 변화 |
| edge energy/MTF proxy | sharpen, blur, denoise, bokeh |
| halo overshoot | hard edge 주변 최대 초과/미달 |
| flat-region variance | grain/denoise |
| mask inside/outside diff | selective, brush, portrait |
| energy centroid | light leak 방향 |
| bounding box delta | crop, frame, text, geometry |
| time-to-first-preview | tap/drag 후 최신 결과 표시 시간 |
| frame build+raster p50/p95/p99 | 직접 조작 부드러움 |
| RSS/heap/GPU texture delta | memory 누수와 cache budget |

### 4.4 공통 허용치

- deterministic golden: mean diff ≤ 1.5/255, p99 ≤ 8/255, SSIM ≥ 0.995.
- preview/export parity: downsample 후 mean diff ≤ 2/255, p99 ≤ 10/255, SSIM ≥ 0.992.
- neutral no-op: mean diff ≤ 0.25/255, max diff ≤ 2/255.
- non-zero 작동 gate: 의도 영역 mean diff ≥ 0.5/255. 기능별 방향 metric도 함께 만족해야 한다.
- GPU drag: p95 frame ≤ 16ms.
- 일반 CPU preview: debounce 후 p95 ≤ 80ms.
- detail/glow/text 등 지정 기능은 기능별 budget을 우선한다.
- ML/healing/HDR/denoise: 첫 reduced preview p95 ≤ 250ms. 모델 최초 load는 별도 budget을 사용한다.
- preview RSS delta ≤ 128MB, export RSS delta ≤ 512MB. 그레인 cache는 32MB 이하.

## 5. 모든 도구에 강제하는 공통 테스트 매트릭스

아래 12개 case를 **모든 출시 상태 도구**에 parameterized test로 적용한다. 기능별 표는 여기에 더해지는 고유 검증이다.

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| CM-01 | neutral/default | 공통 no-op 허용치 충족 |
| CM-02 | min/mid/max 및 ± 방향 | non-zero gate와 기능별 방향성 충족, NaN/overflow 없음 |
| CM-03 | reset | 현재 도구만 중립화, 이전 확정 operation 유지 |
| CM-04 | back/cancel | snapshot, 픽셀, history count가 진입 전과 동일 |
| CM-05 | ✓ apply | history가 정확히 1 증가하고 도구가 닫힘 |
| CM-06 | undo/redo | 픽셀 hash와 모든 UI 값이 왕복 복원 |
| CM-07 | JSON/draft/restart | schema round-trip과 cache key가 일치 |
| CM-08 | preview/export | 공통 parity 허용치 또는 기능별 허용치 충족 |
| CM-09 | rapid update | 마지막 입력만 반영, stale result 폐기, dispose 후 callback 없음 |
| CM-10 | missing/corrupt input | crash 없이 no-op/복구 UI, 잘못된 성공 표시 없음 |
| CM-11 | accessibility/layout | 44px hit target, semantics, 한/영 320px/landscape overflow 없음 |
| CM-12 | performance/memory | 기능별 p95/RSS gate 충족, 반복 진입 후 자원 증가가 bounded |

## 6. 편집기 공통 상태·내비게이션

| ID | 조작/내부 관찰 | 합격 조건 |
| --- | --- | --- |
| ED-01 | 각 도구 진입 시 backup state capture | 도구가 소유한 모든 필드가 빠짐없이 snapshot에 포함됨 |
| ED-02 | 값 변경 후 왼쪽 back/시스템 back/제스처 | 활성 도구만 취소, editor route 유지, history 불변 |
| ED-03 | dirty editor에서 back | 폐기 확인창 표시; 계속 편집/나가기 분기 정확 |
| ED-04 | clean editor에서 back | 불필요한 확인 없이 route pop |
| ED-05 | 원본 보기 press-down/release/cancel gesture | 누르는 동안만 source, release 후 최신 preview 복원 |
| ED-06 | reset 후 cancel, reset 후 ✓ | cancel은 진입 전 복구, ✓는 중립 상태 확정 |
| ED-07 | A 도구 임시 편집 중 B 도구 선택 | A가 자동 commit되지 않고 명시한 취소 정책 적용 |
| ED-08 | 100회 slider update + tool close | 마지막 값만 보이고 setState-after-dispose/late callback 없음 |
| ED-09 | history 100개 경계/branch undo 후 새 edit | cursor와 redo branch 정책이 일관되고 사용자 작업 손실 없음 |
| ED-10 | draft 저장 중 앱 pause/resume/restart | committed state만 복원하거나 명시한 temporary 정책과 일치 |
| ED-11 | 빈 이미지/깨진 이미지/권한 취소 | editor가 crash하지 않고 복구 action 제공 |
| ED-12 | 모든 도구 action 위치 | 원본/✓ 상단 오른쪽, reset 하단 오른쪽, semantics 존재 |

필수 신규 target:

- `test/features/editor/editor_tool_transaction_test.dart`
- `test/features/editor/editor_back_navigation_test.dart`
- `test/features/editor/editor_async_race_test.dart`
- `integration_test/editor_draft_restore_test.dart`

## 7. 색상·톤·필터 기능

### 7.1 필터와 LUT

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| FT-01 | identity/constant/axis LUT의 8 cube corner와 interpolation | R-fastest axis, RGB channel, trilinear 결과가 oracle과 일치 |
| FT-02 | intensity 0/0.5/1 | 0=source, 1=full LUT, 0.5=정의한 color space의 중간값 |
| FT-03 | 카드 선택 → cancel/✓ | 선택만으로 history 불변, cancel 복구, ✓ 1회 commit |
| FT-04 | 빠르게 20개 필터 탭 | 마지막 preset/LUT만 표시, 이전 request 폐기 |
| FT-05 | corrupt/truncated/wrong-dimension LUT | 원본/params-only fallback, crash와 inverted output 없음 |
| FT-06 | cold/cached switch와 LRU eviction | cold ≤150ms, cached ≤50ms, cache가 bounded |
| FT-07 | favorite/custom rename/delete/missing path | ID 안정성, session fallback, strip state 정상 |
| FT-08 | preview/export/reload | 동일 LUT checksum/intensity, parity gate 충족 |

### 7.2 기본 보정·톤·B&W

| ID | 파라미터 | 고유 기대 결과 |
| --- | --- | --- |
| GA-01 | exposure -2/-1/0/+1/+2 | 중간 회색 luminance가 EV 방향으로 단조 변화, clamp만 허용 |
| GA-02 | contrast -100/0/+100 | pivot mid-gray 보존, dark/bright가 반대 방향으로 벌어짐/수축 |
| GA-03 | saturation -100/0/+100 | -100 RGB 채널 수렴, neutral은 전 범위에서 neutral 유지 |
| GA-04 | temperature/tint ± | warm은 R↑ B↓, tint의 축 정의와 일치, clipping 증가 제한 |
| GA-05 | highlights/shadows ± | FX-08의 목표 zone이 비목표 zone보다 크게 변함 |
| GA-06 | ambiance | 단순 contrast와 pixel signature가 달라야 하며 local tone 방향 일치 |
| GA-07 | tonal shadow/mid/high 각각 ± | 목표 luminance zone isolation과 feather 연속성 충족 |
| GA-08 | B&W toggle + R/G/B/Y mix | RGB가 gray로 수렴하고 각 source patch 기여 방향이 맞음 |
| GA-09 | 모든 slider 조합과 operation order | LUT/curve/HSL과 순서 hash가 문서화된 oracle과 일치 |
| GA-10 | 100 rapid slider events | GPU p95 16ms 또는 CPU p95 80ms, commit은 ✓에서 1회 |

### 7.3 화이트밸런스

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| WB-01 | 각 preset | preset이 정확한 temperature/tint 값으로 매핑 |
| WB-02 | neutral gray + temperature/tint | 정의하지 않은 색 축 오염이 제한되고 값이 단조 변화 |
| WB-03 | saturated primaries/highlights | NaN, hue wrap, 과도한 clipping 없음 |
| WB-04 | preset 후 수동 조절/reset/cancel | UI 값, params, preview가 같은 state를 가리킴 |

### 7.4 커브

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| CV-01 | identity/0점/1점/2점/다점 LUT bake | 길이·endpoint·oracle interpolation 일치, NaN 없음 |
| CV-02 | point add/drag/cross/delete | x order와 bounds 유지, invalid curve 생성 불가 |
| CV-03 | Luma/RGB/R/G/B isolation | 선택 channel만 의도대로 변하고 alpha 보존 |
| CV-04 | S-curve/matte/extreme curve gradient | 단조성 정책, clipping, banding gate 충족 |
| CV-05 | continuous drag | LUT bake p95 ≤8ms, frame p95 ≤16ms, 변경 없으면 texture rebuild 없음 |
| CV-06 | preview/export/draft | 같은 baked LUT hash 또는 같은 serialized points 사용 |

### 7.5 HSL

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| HS-01 | 8 band × H/S/L × min/mid/max | 해당 band 변화가 최대이고 비인접 band leakage 제한 |
| HS-02 | red 359°/0°/1° | wrap 경계가 연속적이며 abrupt jump 없음 |
| HS-03 | 인접 band feather | 경계 p99 jump ≤4/255 |
| HS-04 | true gray/near gray | hue-only는 gray 보존, saturation speckle 없음 |
| HS-05 | orange/skin fixture에서 unrelated blue edit | skin ΔE가 허용 범위 안 |
| HS-06 | band reset/all reset/old schema | 선택 band와 전체 reset 구분, 누락 band는 zero |

### 7.6 스플릿 톤

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| ST-01 | shadow/highlight saturation 0 | hue/balance 값과 무관하게 no-op |
| ST-02 | shadow tone | dark zone 변화가 highlight보다 큼 |
| ST-03 | highlight tone | highlight 변화가 dark보다 큼, white clipping 제한 |
| ST-04 | balance -100/0/100 ramp | crossover가 단조 이동하고 hard boundary 없음 |
| ST-05 | LUT+curve+global stack | operation order와 preview/export parity 충족 |

## 8. 디테일·질감·노이즈

### 8.1 세부 정보

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| DT-01 | sharpen/structure/clarity 각각 0/50/100 | 세 효과의 signature가 서로 다르고 non-zero gate 충족 |
| DT-02 | hard edge | halo overshoot p99 ≤6/255 |
| DT-03 | flat noisy region | edge 증가는 허용하되 noise 증폭이 정한 상한 이하 |
| DT-04 | portrait skin/hair | 피부 보호 시 skin noise 증가 제한, hair edge 유지 |
| DT-05 | rapid drag/export | preview p95 ≤120ms, main frame >24ms 없음, export off UI thread |

### 8.2 그레인

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| GR-01 | strength 0/25/50/100 | 0 no-op, flat variance가 단조 증가 |
| GR-02 | same/different seed | same seed byte-identical, different seed pattern difference |
| GR-03 | size/roughness/mono-color 지원 값 | spatial frequency/channel correlation이 정의와 일치 |
| GR-04 | preview/export resolution | downsample 후 grain scale과 parity gate 충족 |
| GR-05 | undo/reload/cache | pattern이 바뀌지 않고 cache RSS ≤32MB |

### 8.3 노이즈 제거

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| NR-01 | luma/chroma strength 각각 | 목표 noise variance가 줄고 비목표 channel 오염 제한 |
| NR-02 | detail preservation 0/50/100 | edge contrast loss ≤8%, 값 증가 시 원본 edge에 가까워짐 |
| NR-03 | flat color | 평균 color shift ≤2/255 |
| NR-04 | tiny/huge/corrupt input | crash/OOM 없이 no-op 또는 오류 처리 |
| NR-05 | cancellation/performance | first preview ≤250ms, debounce ≤100ms, main frame p95 ≤16ms |

## 9. 기하 변환

### 9.1 크롭

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| CR-01 | 모든 ratio preset | ratio 오차 epsilon 이하, 선택만으로 commit 없음 |
| CR-02 | 고정 ratio corner drag | 비율 유지하며 min~max resize 가능 |
| CR-03 | edge/corner/free drag | 해당 edge만 변화, bounds/min-size clamp |
| CR-04 | box move | size/ratio 유지, 사진 bounds 밖 이동 불가 |
| CR-05 | ratio 전환 | 현재 중심 최대 보존, 즉시 apply 없음 |
| CR-06 | transformed image에서 crop | rotation/flip/perspective와 좌표 계약 일치 |
| CR-07 | 320px/landscape hit test | handle hit target ≥44px, overlay 가시성 유지 |
| CR-08 | export | edge별 좌표 오차 ≤1 output pixel, drag p95 ≤16ms |

### 9.2 회전·반전

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| RF-01 | H/V flip과 두 번 flip | FX-04 방향 oracle 일치, 두 번은 no-op |
| RF-02 | 90/180/270/360 | dimension/orientation/pixel mapping 일치 |
| RF-03 | straighten -45/0/+45 | 중심 안정, fill 정책 일관, 0 no-op |
| RF-04 | EXIF 1/3/6/8 | normalize 후 이중 회전 없음 |
| RF-05 | rapid alternating flip | 탭 response p95 ≤50ms, 마지막 flags만 반영 |
| RF-06 | crop과 조합 | transform order에 따른 preview/export 위치 일치 |

### 9.3 원근

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| PS-01 | H/V 0, ±중간, ±최대 | 0 no-op, 직선이 정의한 transform과 일치 |
| PS-02 | extreme/degenerate denominator | NaN/crash 없음, bounds/fill deterministic |
| PS-03 | synthetic grid | export alignment 오차 ≤1.5px, SSIM ≥0.995 |
| PS-04 | shear/homography UI 정직성 | 실제 알고리즘과 UI 명칭/설명이 일치 |
| PS-05 | interactive drag | matrix preview p95 ≤16ms |

### 9.4 캔버스 확장

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| EX-01 | 각 edge 0/25/50% 단독/조합 | output dimension과 source offset 정확 |
| EX-02 | black/white fill | 확장 영역 pixel이 정확한 fill color |
| EX-03 | smart fill | seed/version 고정 시 deterministic, seam 품질 golden 충족 |
| EX-04 | reset/cancel/export | 모든 edge 0 no-op, preview/export dimension 일치 |
| EX-05 | performance | simple ≤50ms, smart first preview ≤250ms, UI non-blocking |

## 10. 영역·마스크 기반 기능

### 10.1 부분 보정

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| SE-01 | tap/add/move/delete/duplicate point | normalized 좌표와 선택 state 정확 |
| SE-02 | radius/feather min/mid/max | mask extent 단조 변화, edge p99 jump ≤6/255 |
| SE-03 | two-color fixture colorAuto | 선택 색 영역 inside diff ≥0.5/255, 반대 영역 leakage 제한 |
| SE-04 | brightness/contrast/saturation 각각 ± | mask 내부에서 각 조정의 방향 metric 충족 |
| SE-05 | multiple overlap points | 정한 합성 규칙과 일치, overflow/clamp 없음 |
| SE-06 | point 없음/zero params | no-op이고 dead slider를 정직하게 비활성화/안내 |
| SE-07 | zoom/crop/rotate/export | point가 같은 image-space 위치에 유지 |
| SE-08 | move/radius performance | preview p95 ≤80ms |

### 10.2 브러시·닷지/번

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| BR-01 | touch path sampling | stroke overlay p95 ≤16ms, path 누락/점프 없음 |
| BR-02 | size/hardness/strength | mask radius, feather, opacity가 단조 변화 |
| BR-03 | dodge/burn | mask 안 luminance가 각각 증가/감소, 밖은 no-op |
| BR-04 | eraser/clear/undo-last | mask subtraction과 stroke state가 deterministic |
| BR-05 | zoom/pan/crop/rotate | overlay와 export mask 좌표가 일치 |
| BR-06 | 100 strokes | replay ≤250ms, RSS delta ≤128MB, flatten 후 결과 유지 |

### 10.3 아웃포커스·렌즈 흐림

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| BF-01 | tilt center/band/radius | focus band는 선명, 바깥 edge energy 감소 |
| BF-02 | linear/elliptical 또는 제공 mode | mask geometry가 UI overlay와 일치 |
| BF-03 | lens center/depth/radius/feather | blur가 distance/depth에 따라 단조 증가 |
| BF-04 | radius 0/invalid mask/wrong size | no-op이며 crash 없음 |
| BF-05 | portrait subject mask | subject/hair edge 보존, background만 blur |
| BF-06 | missing model/depth | 전역 blur로 fallback하지 않고 no-op+안내 |
| BF-07 | rapid drag | first reduced preview ≤250ms, stale result 폐기 |
| BF-08 | preview/export | normalized mask/depth resize와 blur scale 일치 |

### 10.4 인물

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| PT-01 | no face/model missing/invalid mask | 전체 화면 보정 없이 no-op, crash 없음 |
| PT-02 | smoothing 0/25/50/100 | skin texture noise 단조 감소, eye/hair edge 보호 |
| PT-03 | spotlight | mask 내부 luminance 변화가 외부보다 크고 clipping 제한 |
| PT-04 | 모든 skin tone + strength | skin mask 안 hue 방향 일치, 밖 leakage 제한 |
| PT-05 | bokeh depth 0/중간/최대 | 먼 배경 blur 증가, face/hair 보존 |
| PT-06 | head yaw/pitch 지원 시 | mask 안 warp, 배경 보존, invalid geometry 없음 |
| PT-07 | 다인/부분 얼굴/안경/머리카락 | 승인 mask fixture별 edge quality gate 충족 |
| PT-08 | mask cache/geometry change | slider 때 ML 재실행 없음, crop/rotate 후 cache invalidation |
| PT-09 | performance | cached slider ≤80ms, first model ≤1500ms 또는 non-blocking unavailable |

### 10.5 힐링

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| HE-01 | empty/invalid mask | no-op, crash 없음 |
| HE-02 | blemish texture fixture | mask 안 mean diff ≥0.5/255, blemish error 감소 |
| HE-03 | unmasked area | 픽셀 보존 또는 정의한 seam tolerance 충족 |
| HE-04 | edge/texture cases | blur smear 없이 승인 golden SSIM ≥0.985 |
| HE-05 | stroke undo/reset/reload | stroke와 algorithm version 복원 |
| HE-06 | performance | mask feedback ≤16ms, small heal preview ≤250ms, fill isolate 실행 |

## 11. 광학·아티스틱 효과

### 11.1 비네팅

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| VG-01 | strength 0/중간/최대 | 0 no-op, corner 변화가 center보다 큼 |
| VG-02 | center/feather/inner brightness 지원 시 | energy center와 falloff가 UI 값과 일치 |
| VG-03 | bright/dark vignette 지원 범위 | 방향성, clamp, banding 없음 |
| VG-04 | performance/parity | GPU drag ≤16ms, export parity gate 충족 |

### 11.2 글로우

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| GL-01 | strength 0/중간/최대 | highlight 주변 bloom 증가, shadow 오염 제한 |
| GL-02 | threshold/softness 지원 시 | mask/spread가 단조 변화하고 hard boundary 없음 |
| GL-03 | saturation/warmth | bloom color만 의도 방향으로 변화 |
| GL-04 | high-key image | default clipping 증가 ≤1%p, muddy detail 제한 |
| GL-05 | performance/parity | preview ≤120ms, main frame ≤16ms, export radius 의도 일치 |

### 11.3 광학 유출

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| LL-01 | strength 0/25/50/100 | 0 no-op, energy가 단조 증가 |
| LL-02 | angle 0/90/180/270 | energy centroid가 기대 방향으로 이동 |
| LL-03 | warmth/tint/texture | 색 방향과 선택 asset이 실제 output에 반영 |
| LL-04 | same seed/reload | random variant가 deterministic |
| LL-05 | missing texture | no-op+안내, crash/회색 overlay 없음 |
| LL-06 | switch/drag perf | transform ≤16ms, cached texture ≤50ms, cold ≤150ms |

### 11.4 헐레이션

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| HL-01 | strength 0 | no-op |
| HL-02 | threshold 양쪽 | threshold 아래 contamination mean ≤1/255 |
| HL-03 | spread min/mid/max | highlight 주변 radius가 단조 증가 |
| HL-04 | warmth/tint | bloom 색만 의도 방향으로 변화 |
| HL-05 | scale/parity/perf | 해상도 보정, preview ≤120ms, main frame ≤16ms |

### 11.5 드라마·HDR 스케이프

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| HD-01 | drama 각 style × 0/25/50/100 | 0 no-op, 각 style signature가 구별되고 deterministic |
| HD-02 | HDR strength/saturation | local contrast와 saturation 방향 metric 충족 |
| HD-03 | hard edge | halo overshoot p99 ≤8/255 |
| HD-04 | high-key gradient | clipping 증가 제한, 새 band/posterization 없음 |
| HD-05 | low-light | block noise/색 speckle의 과도한 증폭 없음 |
| HD-06 | rapid changes/export | first preview ≤250ms, UI frame ≤16ms, progress/cancel 제공 |

## 12. 레이어·창작 기능

### 12.1 이중 노출

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| DE-01 | 모든 blend mode의 known pixels | blend formula oracle와 rounding tolerance 내 일치 |
| DE-02 | opacity 0/0.5/1 | 0 source, 1 full blend, 중간값 monotonic |
| DE-03 | aspect/fit/crop | preview/export가 같은 mapping 사용 |
| DE-04 | missing/deleted/corrupt second image | no-op/복구 UI, crash 없음 |
| DE-05 | cache/performance | opacity cached ≤50ms, mode change ≤80ms, cache bounded |

### 12.2 프레임

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| FR-01 | none | no-op |
| FR-02 | 모든 frame asset 순회 | decode 성공, thumbnail/selection 일치 |
| FR-03 | FX-10 layer test | 중앙 사진 pixel 보존, border만 frame이 위에 합성 |
| FR-04 | 5개 aspect ratio | stretch/fit/crop 정책과 alignment 일치 |
| FR-05 | alpha/JPG asset audit | 중앙을 가리는 불투명 asset은 실패 처리 또는 mask 적용 |
| FR-06 | missing asset | none fallback, crash 없음 |
| FR-07 | cold/cached/parity | cold ≤150ms, cached ≤50ms, export parity 충족 |

### 12.3 텍스트

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| TX-01 | empty/space-only | no-op |
| TX-02 | 한글/영문/숫자/emoji/multiline | glyph 누락 없이 표시하거나 명시적 fallback |
| TX-03 | 모든 bundled/preset font | preview/export font 선택 일치, missing font deterministic |
| TX-04 | size/color/opacity/align 지원 값 | raster bounds와 색/alpha가 parameter에 맞음 |
| TX-05 | position/rotation/edge clamp 지원 값 | image-space 좌표와 canvas 위치 일치 |
| TX-06 | long text/IME/composition/delete | UI overflow/crash/stale text 없음 |
| TX-07 | frame과 조합 | 명시한 z-order대로 text 가시성 유지 |
| TX-08 | performance/parity | key debounce 후 ≤120ms, transform drag ≤16ms, bbox delta ≤2px |

## 13. RAW·히스토그램·내보내기

### 13.1 RAW 현상

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| RW-01 | JPEG/PNG 입력 | RAW UI 숨김/비활성, dead control 없음 |
| RW-02 | 지원 RAW/DNG | 실제 decoder와 profile 경로 사용, placeholder no-op 아님 |
| RW-03 | exposure/WB/tint/highlight/shadow/noise | 각 방향 metric과 non-zero gate 충족 |
| RW-04 | corrupt/unsupported camera RAW | editor crash 없이 오류/대안 제공 |
| RW-05 | preview/export/order | downsample/full decode color intent와 global adjust 이전 순서 일치 |
| RW-06 | performance | detection ≤50ms, first preview ≤1500ms, main frame ≤16ms |

### 13.2 히스토그램

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| HG-01 | black/white/R/G/B fixture | 각 bin count와 luminance weighting oracle 일치 |
| HG-02 | preview 변경/undo/original compare | 표시 대상 이미지와 histogram state 동기화 |
| HG-03 | corrupt/tiny/alpha input | bounds 오류 없이 합리적 count |
| HG-04 | 100 preview updates | 계산 debounce/cancel, editor interaction block 없음 |

### 13.3 내보내기

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| EP-01 | 각 단일 operation export | CM-08 parity 충족 |
| EP-02 | full stack order | geometry → color/effects → local/creative의 명시된 순서와 일치 |
| EP-03 | JPEG/PNG/지원 format·quality | dimension, metadata/orientation, alpha 정책 정확 |
| EP-04 | 48MP/low-memory | UI isolate 미차단, OOM 없이 bounded memory 또는 안전한 실패 |
| EP-05 | progress/cancel | >1s 작업 progress ≤500ms 간격, cancel 후 partial file 정리 |
| EP-06 | storage/share permission denial | recoverable 오류, 성공으로 오표시하지 않음 |
| EP-07 | second export/retry | 이전 임시 state/파일이 새 결과를 오염하지 않음 |

## 14. 사용자 필터 생성

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| CF-01 | full/limited/denied photo permission | 허용 범위와 picker 정책 일치, crash 없음 |
| CF-02 | recent photo query | 실제 최신 30개가 recent-first로 표시, 회색 placeholder만 남지 않음 |
| CF-03 | cloud-only/missing/corrupt asset | loading/error/retry가 구분되고 잘못된 선택 없음 |
| CF-04 | 1/3/5장 선택·해제·순서 | collage와 generator input ID/path가 정확히 일치 |
| CF-05 | style mode와 before/after pair mode | 입력 contract와 UI가 명확히 분리 |
| CF-06 | identity pair | output이 identity-like, mean diff ≤1/255 |
| CF-07 | known color mapping pair | LUT axis/range/channel/interpolation이 oracle와 일치 |
| CF-08 | inconsistent references | outlier/softening diagnostics와 UI 안내 일치 |
| CF-09 | generated LUT validation | finite, dimension, range, channel, collapse/inversion gate 통과 전만 저장 |
| CF-10 | success preview | Before=실제 선택 사진, After=동일 사진+생성 LUT; 회색 성공 화면 금지 |
| CF-11 | intensity 0/1 | 0 source, 1 generated look |
| CF-12 | save/reload/apply | LUT checksum, recipe, preset ID, thumbnail, output이 동일 |
| CF-13 | duplicate name/rename/delete | repository index와 기존 session fallback 정확 |
| CF-14 | cancel/isolate error/save failure | preset 미저장, port/temp 정리, retry 가능 |
| CF-15 | performance | small fit p95 ≤1500ms, main frame p95 ≤16ms, progress 표시 |
| CF-16 | privacy cleanup | 명시 저장하지 않은 source/reference와 temp preview 삭제 |

필수 신규 target:

- `test/features/create_filter/create_filter_flow_test.dart`
- `test/features/create_filter/recent_photos_test.dart`
- `test/golden/custom_filter_creation_golden_test.dart`
- `integration_test/custom_filter_roundtrip_test.dart`

## 15. 탭·즐겨찾기·접근성

| ID | 검증 | 합격 조건 |
| --- | --- | --- |
| UI-01 | 기본/저장 tab 목록 | 정확히 4개, 순서 보존, 중복/unknown 복구 |
| UI-02 | all-tools와 hidden active tool | 모든 출시 도구 접근 가능, active 표시 정확 |
| UI-03 | tab edit 3/4/5개 선택 시도 | 정확히 4개만 저장 가능 |
| UI-04 | favorite filter/tool add/remove/restart | ID와 순서가 안정적으로 복원 |
| UI-05 | 320×640/640×320/tablet/text scale 200% | overflow와 잘린 action 없음 |
| UI-06 | semantics traversal | 모든 icon/slider/tab에 label/value/selected/action 존재 |
| UI-07 | sheet/tab performance | open/switch ≤50ms, save ≤100ms, 이미지 재렌더 불필요 |

## 16. 조합·순서·회귀 테스트

단일 기능 통과 후 아래 stack을 고정 fixture로 검증한다.

| ID | Stack | 검증 |
| --- | --- | --- |
| IN-01 | crop → rotate/flip → perspective | geometry 좌표와 export parity |
| IN-02 | WB → global → curves → HSL → LUT | 색 pipeline 순서와 clamp |
| IN-03 | denoise → details → grain | noise/detail/grain 의도와 순서 |
| IN-04 | selective + brush + portrait mask | 각 mask 좌표와 leakage |
| IN-05 | glow + halation + light leak + vignette | highlight/overlay clipping과 z-order |
| IN-06 | double exposure → frame → text | 사진/프레임/텍스트 layer order |
| IN-07 | full 12-operation stack | blank output, NaN, stale state, export parity |
| IN-08 | full stack undo-all/redo-all/restart | 각 단계 pixel hash와 UI 값 복원 |
| IN-09 | source image 교체 | 이전 image cache/mask/LUT preview가 새 이미지에 섞이지 않음 |
| IN-10 | repeated editor open/close 20회 | stream/isolate/GPU texture/file handle 누수 없음 |

## 17. 성능 검증 설계

### 17.1 현재 blocker

`tool/perf_gate.dart`가 없으므로 체크리스트의 성능 명령은 현재 실행 불가능하다. 아래를 먼저 구현한다.

- `tool/perf_gate.dart`: benchmark JSON 수집·threshold 비교·exit code 반환.
- `integration_test/editor_performance_test.dart`: profile-mode gesture/preview/export 측정.
- `tool/perf_baseline.json`: device class, OS, app commit, fixture checksum, metric별 threshold와 baseline.
- `build/perf/editor_perf_<device>_<commit>.json`: raw samples, p50/p95/p99, RSS, 실패 항목.

### 17.2 측정 규칙

- debug mode 숫자는 승인 근거로 사용하지 않는다. profile/release mode 실기기에서 측정한다.
- warm-up 5회 후 최소 30회, slider/gesture는 100 update sequence를 10회 반복한다.
- cold와 warm cache를 분리한다.
- 평균만 보고하지 않고 p50/p95/p99와 raw sample 수를 남긴다.
- 같은 기기에서 기준 commit 대비 regression도 기록한다. 절대 gate와 regression gate를 모두 통과해야 한다.
- thermal state, battery/charging, OS, device model, available memory를 report에 기록한다.
- 이미지 처리 시간이 빨라도 main isolate frame이 budget을 넘으면 실패다.

### 17.3 기능군별 budget

| 기능군 | Gate |
| --- | --- |
| crop/rotate/curve/overlay transform/GPU slider | frame p95 ≤16ms |
| filter cached/cold | visual update p95 ≤50/150ms |
| CPU color/selective | latest preview p95 ≤80ms |
| details/glow/text debounce | p95 ≤120ms |
| denoise/HDR/heal/blur | first reduced preview p95 ≤250ms |
| portrait model first/cached | ≤1500ms / ≤80ms 또는 non-blocking unavailable |
| RAW first preview | ≤1500ms 또는 non-blocking unsupported |
| filter fit | ≤1500ms small preview, UI frame p95 ≤16ms |
| export >1s | progress interval ≤500ms, cancel 가능 |
| memory | preview ≤128MB, export ≤512MB, feature-specific stricter budget 우선 |

## 18. 자동화 target 감사와 추가 계획

### 18.1 현재 없는 체크리스트 필수 target

기존 체크리스트가 요구하지만 현재 파일이 없는 target은 정확히 38개다.

- 엔진 9개: `blend_modes_test.dart`, `expand_engine_test.dart`, `glow_engine_test.dart`, `halation_engine_test.dart`, `hdr_drama_engine_test.dart`, `light_leak_engine_test.dart`, `raw_develop_engine_test.dart`, `selective_engine_test.dart`, `vignette_engine_test.dart`.
- Widget 15개: `create_filter_flow_test.dart`, `double_exposure_panel_test.dart`, `editor_tabs_layout_test.dart`, `expand_panel_test.dart`, `frame_panel_test.dart`, `glow_panel_test.dart`, `halation_panel_test.dart`, `hdr_panel_test.dart`, `healing_panel_test.dart`, `light_leak_panel_test.dart`, `portrait_panel_test.dart`, `raw_develop_panel_test.dart`, `selective_panel_test.dart`, `text_overlay_panel_test.dart`, `vignette_panel_test.dart`.
- Golden 14개: `custom_filter_creation_golden_test.dart`, `double_exposure_golden_test.dart`, `expand_golden_test.dart`, `frames_golden_test.dart`, `glow_golden_test.dart`, `halation_golden_test.dart`, `hdr_drama_golden_test.dart`, `healing_golden_test.dart`, `light_leak_golden_test.dart`, `portrait_golden_test.dart`, `raw_develop_golden_test.dart`, `selective_golden_test.dart`, `text_overlay_golden_test.dart`, `vignette_golden_test.dart`.
- 성능: `tool/perf_gate.dart` 전체.

기존 파일이 존재하더라도 이름만으로 완료 처리하지 않는다. 이 문서의 test ID가 assertion으로 연결됐는지 traceability table로 확인한다.

### 18.2 권장 디렉터리

```text
test/
  fixtures/
    manifest.json
  support/
    image_fixtures.dart
    image_metrics.dart
    render_harness.dart
    fake_segmenter.dart
    fake_media_library.dart
    test_clock.dart
  engine/
  features/editor/
  features/create_filter/
  golden/
integration_test/
  editor_preview_export_test.dart
  editor_performance_test.dart
  editor_draft_restore_test.dart
tool/
  perf_gate.dart
build/test-results/editor/
```

## 19. 실행 순서

### Wave 0: Harness

- deterministic fixture generator와 image metric 구현.
- preview/export render harness와 fake model/media/file failure 주입 구현.
- performance runner와 result schema 구현.

### Wave 1: 출시 차단 기능

- 공통 transaction/back/reset.
- 크롭, 반전, 필터 apply/cancel.
- 부분 보정, 아웃포커스/렌즈 흐림.
- 그레인, 텍스트, 프레임.

### Wave 2: 색상·기하·로컬 도구 전수

- global/WB/curves/HSL/split/details/noise.
- perspective/expand/selective/brush.
- 단일 기능 preview/export/undo/draft.

### Wave 3: ML·아티스틱·창작

- portrait, healing, RAW.
- glow, vignette, light leak, halation, drama/HDR.
- double exposure, full layer order.

### Wave 4: 필터 생성·통합·실기기

- recent photos와 생성 LUT 전 과정.
- full stack, export, restart, low-memory/error injection.
- iOS/Android 기준 실기기 profile benchmark와 L5 시각 QA.

한 Wave의 P0 실패가 남아 있으면 다음 Wave 완료를 선언하지 않는다.

## 20. 결과 기록 형식

각 실행은 다음 정보를 JSON/JUnit과 Markdown summary로 남긴다.

- app commit, dirty status, device/OS/build mode.
- fixture ID/checksum과 seed.
- test ID, 입력 parameter, engine path(GPU/CPU/isolate/model/fallback).
- output metric, threshold, pass/fail.
- preview/export file checksum과 diff image path.
- latency raw samples, p50/p95/p99, RSS delta.
- 실패 stack trace, 재현 명령, 최초 실패 pixel/영역.
- skip이면 이유와 release 영향. `미구현` 또는 `환경 없음`을 pass로 바꾸지 않는다.

권장 summary 열:

| Test ID | Feature | L0 | L1 | L2 | L3 | L4 | L5 | Blocker | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 21. 완료 판정과 release blocker

기능 하나를 완료로 표시하려면:

1. CM-01~CM-12가 모두 통과한다.
2. 해당 기능의 고유 test ID가 모두 자동화되거나, L5 전용 항목은 승인 증거가 있다.
3. neutral/no-op과 non-zero 작동 gate를 모두 만족한다.
4. preview/export, undo/redo, draft/restart가 일치한다.
5. 오류 주입과 빠른 연속 입력에서 crash/stale overwrite가 없다.
6. profile-mode 실기기 성능과 memory gate를 만족한다.
7. test result artifact가 commit과 fixture checksum에 연결된다.

다음 중 하나라도 있으면 앱 release blocker다.

- 노출된 도구가 non-zero에서 원본을 그대로 반환한다.
- 영역 보정이 전역 보정으로 작동하거나 mask 밖을 크게 바꾼다.
- missing asset/model/file이 editor를 crash시킨다.
- ✓ 전 변경이 확정되거나 cancel/reset/undo가 사용자 작업을 잃게 한다.
- preview와 export가 허용치 밖으로 다르다.
- main UI가 common edit 중 멈추거나 p95 gate를 넘는다.
- `skip`, 회색 placeholder, fallback no-op을 성공으로 보고한다.
- 성능 harness 없이 체감만으로 “빠름”을 승인한다.

## 22. 최종 검토 체크리스트

- [ ] 3장의 전체 기능 인벤토리 항목마다 owner와 test target이 연결됐다.
- [ ] 모든 출시 도구에 CM-01~CM-12가 parameterized 적용됐다.
- [ ] 각 기능 고유 test ID가 실제 test name 또는 traceability manifest에 연결됐다.
- [ ] 38개 missing target이 구현됐거나 제품에서 기능을 숨긴 명확한 결정이 기록됐다.
- [ ] `tool/perf_gate.dart`와 실기기 profile benchmark가 실행 가능하다.
- [ ] 모든 frame asset, font, LUT, model fallback을 전수 검사했다.
- [ ] iOS/Android, 작은 화면/landscape, low-memory, offline/no-model을 검사했다.
- [ ] preview/export diff, performance JSON, L5 캡처가 같은 commit에 묶였다.
- [ ] P0 실패와 skip이 0개다.
- [ ] 기존 feature checklist의 `[x]`를 실제 최신 증거로 재검증했다.

이 체크리스트가 완료되기 전에는 “각 기능이 하나도 빠짐없이 정상 작동하고 의도한 성능을 낸다”고 결론 내리지 않는다.
