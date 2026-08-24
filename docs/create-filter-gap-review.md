# 사용자 필터 생성 기능 재검토 및 완성 계획

- 작성일: 2026-08-19
- 대상: `CreateFilterPage`, 최근 사진 선택, Style/Before-After 생성기, 생성 LUT 저장·미리보기·재적용
- 관련 기준:
  - [사진 편집기 전체 기능 화이트박스 검증 계획](editor-whitebox-validation-plan.md)
  - [사진 편집기·필터 생성 복구 계획](editor-filter-repair-plan.md)
  - [온디바이스 참조 룩 설계](on-device-reference-look-design.md)
  - [모델 학습 진행 기록](../ml_pipeline/TRAINING_PROGRESS.md)

## 1. 최종 판단

현재 구현은 **single-reference Direct MVP가 실제 앱 worker 경로까지 연결된 기능 검증 단계**다.

다음 항목은 구현되어 있다.

- PhotoKit에서 최근 사진 최대 30장을 읽어 실제 이미지로 표시한다.
- Style mode에서 1~5장, Pair mode에서 Before/After 사진을 받을 수 있다.
- 생성 작업을 isolate에서 실행하고 단계별 progress를 표시한다.
- 생성 LUT의 dimension, finite 값, clipping, 인접 변화, 중성축 단조성, primary chroma를 검사한다.
- 위험한 LUT는 identity 방향으로 강도를 낮추거나 identity로 fallback한다.
- 생성 완료 시 동일 source 사진의 Before와 새 LUT가 적용된 After를 표시한다.
- LUT, recipe, thumbnail을 custom preset으로 저장해 편집기에서 다시 사용할 수 있다.

그러나 프로젝트가 목표로 한 아래 수준에는 도달하지 못했다.

> 참조 이미지의 장면이나 피사체를 복사하지 않고 색감·톤 규칙을 Style Code로 추출하며, 참조 이미지에 없던 색까지 포함하는 전체 RGB Color Cube의 새로운 LUT를 생성한다.

Direct MVP 연결 문제는 해소됐다. 현재 완성 판정을 막는 가장 큰 이유는 다중 참조가 여전히 algorithmic fallback이고, 실제 사용자 사진에서 scene invariance·skin·unseen hue·blind preference 및 모바일 성능 gate가 검증되지 않았기 때문이다.

따라서 현재 기능을 **필터 생성 완성**, **AI 스타일 학습 완성**, **배포 준비 완료**로 판정하면 안 된다.

## 2. 요구 수준과 현재 상태

| 영역 | 요구 수준 | 현재 상태 | 판정 |
| --- | --- | --- | --- |
| 최근 사진 | 실제 최신 사진, thumbnail, pagination, 권한·빈 상태·cloud 상태 구분 | 176px thumbnail·asset ID, 실제 30장 및 추가 page, full/limited/denied/empty/unavailable/error 구현. 선택 시에만 원본 요청 | 구현, 실기기 검증 필요 |
| 선택 UX | 1/3/5장 선택 순서와 최대 수 표시 | 최대 5장 제한과 선택 순서 badge, 독립 Before/After 슬롯·해제 구현 | 구현됨 |
| Style 생성 | 장면 불변 Style Code → 새로운 전체 RGB LUT | 1장은 Direct MVP, 2~5장은 algorithmic fusion | 단일 참조 연결, 품질 승인 전 |
| 학습 모델 | 검증된 Direct MVP를 앱에서 실행 | 35MB fp16 후보를 app asset으로 포함, SHA 검증 설치 후 worker neural 경로 실행 | 구현됨 |
| 다중 참조 | 여러 장의 공통 스타일을 학습 모델 기준으로 융합 | algorithmic profile fusion만 사용 | 부분 구현 |
| Pair 생성 | 정렬된 Before/After 편집 차이에서 전역 룩 추출 | affine + residual LUT fitting, 구도·로컬 편집 정렬 없음 | 제한적 구현 |
| LUT 안전성 | 저장 전 finite/range/channel/collapse/inversion gate | 강도 축소 및 identity fallback 구현 | 구현됨 |
| 완료 미리보기 | 동일 사진의 실제 Before/After | 실제 파일과 LUT 적용 결과 사용 | 구현됨 |
| 완료 transaction | preview·검증 성공 후에만 preset 저장 | preview 파일 생성·존재 검증 후 저장하며 실패 시 index/LUT/preview rollback | 구현됨 |
| 재적용 | 생성 직후와 reload 후 bytes/output 동일 | repository/recipe 단위 테스트 일부만 존재 | 미검증 |
| 오류·취소 | isolate 오류/timeout/cancel 시 미저장·정리·재시도 | result/error/exit 수신, 45초 timeout, 사용자 취소, 실행 중 새 artifact 정리 구현 | 구현됨 |
| 성능 | 1장 p95 1초, 5장 p95 3초, main frame p95 16ms | desktop 후보 측정만 존재 | 실기기 미검증 |
| 품질 | unseen scene/LUT, 피부, 비관찰 hue, blind 평가 통과 | offline family holdout만 일부 통과 | 제품 품질 미확정 |

## 3. 핵심 기술 간극

### 3.1 학습 모델이 앱에서 사용되지 않음 — P0

`lib/ai/ai_manager.dart`의 `kModelColorTransfer`에는 2026-08-19 기준 release candidate의 model ID/version/SHA-256/byte size와 bundled asset path를 고정했다. `assets/models/direct_mvp_color_transfer_fp16.tflite`를 포함하며 첫 사용 시 documents directory에 임시 파일로 기록하고 크기·SHA 검증 후 rename한다.

`generateLutFromStyle()`은 다음 조건을 모두 만족할 때만 neural predictor를 사용한다.

1. 참조 사진이 정확히 한 장이다.
2. `AiManager.colorTransferReady == true`다.

`IsolateCreateFilterGenerator`는 main isolate에서 번들 모델을 준비한 후 검증된 절대 경로를 worker isolate에 전달한다. 따라서 isolate별 singleton 상태가 공유되지 않아 neural 경로가 비활성화되던 문제를 피한다. single reference는 Direct MVP neural 경로를 사용하고, 설치·추론 실패는 명시적인 fallback reason과 함께 algorithmic 경로로 전환한다. 참조 사진 2~5장은 아직 `multi_reference_neural_unsupported` fallback을 사용한다.

영향:

- 사용자가 보는 “필터 생성”이 학습된 Direct MVP의 품질과 같지 않다.
- offline 모델 평가 결과가 현재 앱 품질을 증명하지 않는다.
- 다중 참조 UX와 모델 입력 계약이 서로 연결되지 않았다.

완료 조건:

- release candidate TFLite의 app asset 전략을 적용했다.
- SHA-256, byte size, model ID/version, input/output contract를 registry에 기록했다.
- single reference에서 실제 Direct MVP 경로가 실행됐다는 recipe evidence를 테스트한다.
- model load/inference 실패 시 사용자에게 fallback 여부를 명확히 알린다.
- 다중 참조를 model latent/LUT fusion으로 처리하거나, neural은 1장만 지원한다고 UX 계약을 명확히 제한한다.

### 3.2 현재 algorithmic path는 장면과 스타일을 완전히 분리하지 못함 — P0

현재 algorithmic generator는 참조 사진의 channel histogram, Lab zone cast, tone 분포와 palette 통계를 고정된 neutral distribution과 비교해 LUT를 만든다.

이 방식은 안전하고 빠른 fallback으로는 유효하지만, 한 장의 완성 사진만 보고 아래 두 요소를 완전히 분리할 수 없다.

- 원래 장면에 존재하던 하늘·식물·피부·조명 색
- 후보가 추출해야 하는 편집 스타일 색

따라서 특정 장면의 dominant color가 전체 LUT의 스타일로 잘못 일반화될 수 있다. 동일 스타일이 적용된 서로 다른 장면에서 동일 LUT를 생성한다는 제품 핵심 계약도 앱 경로에서 검증되지 않았다.

완료 조건:

- 같은 target LUT가 적용된 서로 다른 장면에서 생성 LUT 간 거리와 output 차이를 측정한다.
- 비관찰 hue cube 영역과 피부색 fixture를 별도로 평가한다.
- algorithmic fallback과 Direct MVP를 동일 reference/unseen scene fixture에서 비교한다.
- scene invariance와 blind preference gate를 통과한 경로만 기본 생성기로 채택한다.

### 3.3 Pair mode는 실제 편집 쌍의 오정렬에 취약함 — P1

Pair mode는 같은 좌표의 Before/After pixel을 대응시켜 affine transform과 residual LUT를 fitting한다. 크기가 다르면 resize하지만 geometric alignment, crop matching, local-edit mask, subject movement 제거는 하지 않는다.

영향:

- 다른 crop 또는 움직이는 피사체가 색 변환 sample로 잘못 들어간다.
- 하늘만 어둡게 하는 등의 local edit가 전체 색 LUT로 일반화될 수 있다.
- 합성 affine pair 테스트 통과만으로 실제 사용자 pair 품질을 보장하지 못한다.

완료 조건:

- identity pair의 mean output diff가 `≤ 1/255`다.
- known global color mapping pair가 oracle LUT와 일치한다.
- crop/translation/subject motion/local edit fixture에서 confidence가 낮아지거나 생성 거부·softening된다.
- pair fit confidence와 fallback reason이 성공 화면에 이해 가능한 형태로 표시된다.

## 4. UX 및 안정성 간극

### 4.1 최근 사진 목록 — P1

현재 구현(2026-08-19 보강 후):

- PhotoKit의 All album에서 최근순 30개씩 page를 요청한다.
- 각 asset의 176px JPEG thumbnail만 먼저 요청하고 `Image.memory`로 표시한다.
- 원본 file path는 사용자가 해당 asset을 선택할 때만 요청한다.
- full/limited/denied/empty/error 상태를 구분한다.
- 제한 접근 안내, 오류 재시도, 추가 로드 버튼, 선택 순서 badge를 표시한다.

부족한 점:

- 자동 infinite scroll 대신 명시적 추가 로드 버튼을 사용한다.
- thumbnail 전체 실패는 unavailable 상태, 일부 실패는 누락 수로 표시한다. 원본 선택 실패는 iCloud 상태 안내를 표시한다.
- 실제 PhotoKit/iCloud 환경에서 unavailable 판단과 복구 동작을 아직 계측하지 않았다.

완료 조건:

- 첫 화면은 최근순 30개 thumbnail을 사용한다.
- scroll 끝에서 다음 page를 요청한다.
- 선택 순서를 `1…5` badge로 표시한다.
- full/limited/denied/empty/cloud-only/error 상태별 문구와 재시도 동작을 제공한다.
- main isolate의 원본 이미지 일괄 decode를 금지한다.

### 4.2 생성·저장 transaction — P0

기존 순서는 다음과 같았다.

```text
LUT 생성
→ preset repository 저장
→ sample preview 생성
→ 성공 또는 preview 실패 sheet
```

2026-08-19 구현에서 이 순서를 preview 선검증 transaction으로 교체했다. preview decode/파일 검증 또는 repository 저장이 실패하면 preset index, 생성 LUT directory, 임시 preview를 rollback한다.

수정 목표 순서:

```text
입력 검증
→ LUT 생성
→ safety 검사
→ sample preview 생성·decode 검증
→ 임시 LUT/preview round-trip 검증
→ preset 원자적 저장
→ 성공 sheet
```

중간 단계 실패 시 임시 filter directory와 preview 파일을 정리하고 repository index를 변경하지 않는다.

### 4.3 isolate 실패와 취소 — P0

2026-08-19 구현에서 result/error/exit를 수신하는 worker runner, 45초 timeout, 명시적 cancel을 추가했다. 실패 시 실행 시작 전에 없던 filter directory만 정리해 기존 preset을 보존한다.

완료 조건:

- `onError`, `onExit`, result port를 분리한다.
- timeout을 둔다.
- 생성 화면에 취소 버튼을 제공한다.
- cancel/error/timeout에서 isolate, receive ports, temporary files를 정리한다.
- retry 시 이전 message나 partial artifact가 새 결과를 오염시키지 않는다.

### 4.4 완료 화면 — P1

개선된 점:

- Before와 After가 회색 placeholder가 아니라 실제 사진이다.
- After는 동일 source에 생성 LUT를 적용해 만든 파일이다.
- preview 실패는 성공 화면과 분리한다.

남은 점:

- intensity를 0~1로 조절하며 비교할 수 없다.
- “바로 편집”은 현재 preview source를 여는 것이 아니라 새 사진 picker를 다시 연다.
- 생성 결과의 모델 종류, confidence, safety strength 축소 여부가 충분히 표시되지 않는다.
- 성공 sheet 종료 시 preview 임시 파일을 정리한다. 해당 정리는 여러 번 호출해도 안전하다.

완료 조건:

- Before/After slider 또는 intensity slider를 제공한다.
- `0`은 source, `1`은 full generated look로 정확히 동작한다.
- 현재 선택 사진으로 편집기를 바로 열거나 “현재 사진 / 다른 사진” 선택을 명확히 제공한다.
- low confidence, excluded reference, safety attenuation, identity fallback을 사용자에게 숨기지 않는다.
- sheet 종료와 preset 삭제 시 관련 임시 preview를 정리한다.

## 5. 현재 모델 후보 평가

현재 release candidate는 다음 artifact다.

- `ml_pipeline/reports/deployment/direct_mvp_family_holdout_smooth_010_001_fp16.tflite`
- 크기: 약 35MB
- input: float32 NCHW `[1, 3, 256, 256]`
- output: float32 `[1, 17, 17, 17, 3]`
- 앱 wrapper에서 65³ R-fastest LUT로 upsample

Family holdout test 주요 결과:

| 모델 | Sample ΔE2000 | LUT-macro ΔE2000 | 해석 |
| --- | ---: | ---: | --- |
| Direct MVP selected | 12.9299 | 14.0013 | 현재 학습 후보 중 기본 선택 |
| Top-3 interpolation | 13.7310 | 14.7797 | MVP보다 낮은 성능 |
| V2 PCA family-train | 16.4311 | 17.1117 | legacy baseline |
| Retrieval | 별도 report 참조 | 16.4629 | 검색 baseline |
| Identity | 큰 오차 | 28.9015 | 안전 기준선 |

Direct MVP는 family holdout에서 interpolation과 V2보다 좋지만 다음 이유로 제품 품질 승인을 내릴 수 없다.

- 앱 worker 경로 실행은 검증됐지만 실제 사용자 reference 품질 승인은 아직 없다.
- test monotonicity luminance violation ratio가 약 `2.52%`다.
- 실제 사용자 reference에 대한 blind preference test가 없다.
- 피부색, 장면 불변성, camera/device domain shift 검증이 미완료다.
- iOS/Android cold/warm latency와 peak memory가 없다.
- v1 전달은 app bundle로 정했다. 이후 모델 업데이트·delta 전달 정책은 아직 없다.

Desktop 검증:

- TFLite XNNPACK 2-thread invoke 평균 약 `3.27ms`, p95 약 `3.41ms`.
- Flutter wrapper 전체는 최근 재실행에서 약 `600ms`였다.
- desktop 수치는 모바일 성능 주장으로 사용할 수 없다.

## 6. 테스트 현황

2026-08-19 재실행 결과:

- `test/engine/personal_filter_core_test.dart`
- `test/whitebox_lut_core_test.dart`
- `test/filter_recipe_test.dart`
- `test/direct_mvp_tflite_candidate_test.dart`
- 총 39개 테스트 통과

이 테스트들이 증명하는 범위:

- LUT axis/interpolation과 identity 동작
- LUT safety 검사와 strength attenuation
- malformed/collapsed LUT identity fallback
- reference fusion outlier 처리
- synthetic affine Before/After fitting
- recipe 직렬화
- TFLite candidate의 앱 predictor shape/range contract

증명하지 못하는 범위:

- PhotoKit full/limited/denied/empty/cloud-only UX
- 실제 최근 사진 정렬·pagination·thumbnail memory
- CreateFilterPage 전체 사용자 흐름
- 실제 성공 sheet golden
- generate → save → reload → editor apply 결과 동일성
- isolate crash/timeout/cancel rollback
- 사용자 reference의 장면 불변성 및 정성 품질

새로 추가되어 통과한 target:

- `test/features/create_filter/create_filter_flow_test.dart`
- `test/features/create_filter/recent_photos_test.dart`
- `test/features/create_filter/create_filter_services_test.dart`

아직 없는 필수 target:

- `test/golden/custom_filter_creation_golden_test.dart`
- `integration_test/custom_filter_roundtrip_test.dart`

## 7. 구현 우선순위

### Phase A — 생성 transaction과 오류 안전성

1. generator, PhotoKit source, repository, preview renderer를 주입 가능한 interface로 분리한다.
2. isolate error/exit/timeout/cancel을 구현한다.
3. preview와 round-trip 검증 전 preset 저장을 금지한다.
4. 실패 시 temporary directory와 repository 변경을 rollback한다.
5. `CF-14`, `CF-16` 테스트를 먼저 추가한다.

완료 판정:

- worker crash, decode error, save error, preview error, 사용자 cancel 모두 preset을 남기지 않는다.
- 재시도 후 하나의 정상 preset만 생성된다.

### Phase B — 최근 사진과 선택 UX

1. PhotoKit asset ID와 thumbnail data를 사용하는 data source를 만든다.
2. permission/empty/cloud/error 상태 model을 분리한다.
3. recent-first 30개와 pagination을 구현한다.
4. 선택 순서와 최대 5장을 표시한다.
5. Style/Pair 선택 UI를 독립된 slot으로 만든다.

완료 판정:

- `CF-01~05`가 simulator fixture와 iOS 권한 상태에서 통과한다.
- 회색 placeholder만 표시되는 정상 성공 상태가 없다.

### Phase C — Direct MVP 앱 연결

1. TFLite release candidate의 SHA-256과 model metadata를 고정한다.
2. asset bundle 또는 remote download 전략을 선택한다.
3. neural/fallback 실행 경로를 recipe에 정확히 기록한다.
4. single-reference E2E를 먼저 완성한다.
5. multi-reference latent/LUT fusion을 설계하거나 UX를 single-reference로 제한한다.
6. simulator 및 iOS/Android에서 shape, axis, parity, cold/warm latency, memory를 측정한다.

완료 판정:

- 사용자 생성 preset의 recipe가 Direct MVP model ID/version을 가진다.
- 앱에서 생성한 LUT checksum이 동일 입력의 reference inference와 일치한다.
- 실패 시 fallback 사실과 품질 제한을 사용자에게 표시한다.

### Phase D — 품질 및 round-trip 검증

1. identity, known mapping, inconsistent reference fixture를 만든다.
2. same-style/different-scene fixture를 만든다.
3. unseen hue와 피부색 fixture를 추가한다.
4. algorithmic, Direct MVP, interpolation을 blind 비교한다.
5. 생성 직후, 저장 후 reload, 편집 preview, export 결과를 checksum/metric으로 비교한다.

완료 판정:

- `CF-06~13`, `CF-15`가 통과한다.
- 동일 스타일의 다른 장면에서 LUT가 일관된다.
- 비관찰 hue와 피부색에서 사전 합의한 품질 gate를 통과한다.
- 실제 사용자 blind test에서 기본 방식이 baseline보다 우수하다.

## 8. CF-01~16 완료표

| ID | 항목 | 현재 | 다음 evidence |
| --- | --- | --- | --- |
| CF-01 | full/limited/denied 권한 | widget 상태/재시도 구현·통과 | 실제 iOS permission integration test |
| CF-02 | recent-first 실제 30장 | thumbnail/asset ID/pagination widget 통과 | 실제 PhotoKit date/order + simulator memory |
| CF-03 | cloud/missing/corrupt | unavailable 및 원본 resolve 실패 widget 통과 | 실제 iCloud/corrupt integration test |
| CF-04 | 1/3/5장 선택·순서 | 순서 badge widget test 통과 | 1/3/5 collage/input ID exact match test |
| CF-05 | Style/Pair 계약 분리 | 독립 Before/After 선택·해제 widget 통과 | picker 대상 슬롯 integration test |
| CF-06 | identity pair | 부분 | mean diff `≤1/255` output test |
| CF-07 | known mapping | 부분 | oracle cube/output comparison |
| CF-08 | inconsistent references | 엔진 일부 | UI guidance 연동 test |
| CF-09 | LUT validation | 엔진 구현 | 저장 차단 integration test |
| CF-10 | 실제 Before/After | 구현 | golden + decode assertion |
| CF-11 | intensity 0/1 | 엔진 구현 | 완료 화면/편집 round-trip test |
| CF-12 | save/reload/apply | neural generate→save→reload→apply SHA 동일 test 통과 | simulator export integration test |
| CF-13 | duplicate/rename/delete | 미검증 | repository/session fallback test |
| CF-14 | cancel/error/save failure | unit/widget 6개 경로 통과 | timeout·재시도 integration test |
| CF-15 | 성능 | desktop 일부 | iOS/Android p50/p95/RSS report |
| CF-16 | privacy cleanup | preview/worker artifact cleanup unit 통과 | source lifecycle integration test |

## 9. 배포 승인 조건

아래 조건을 모두 만족하기 전에는 사용자 필터 생성을 완성 또는 배포 준비 완료로 표시하지 않는다.

- [x] 기본 single-reference Style 생성 경로가 Direct MVP와 일치한다.
- [x] 모델 ID, version, SHA-256, input/output, LUT axis가 고정됐다.
- [x] 생성 실패·취소·preview 실패가 preset과 임시 파일을 남기지 않는다.
- [x] 실제 최근 사진 thumbnail과 권한/빈 상태 UX가 구현됐다.
- [x] 성공 화면에 실제 동일 사진의 Before/After가 표시된다.
- [ ] 저장·reload·편집·export 결과가 허용 오차 안에서 동일하다.
- [ ] `CF-01~16`이 모두 pass evidence를 가진다.
- [ ] iOS/Android cold/warm latency와 peak memory가 목표를 통과한다.
- [ ] same-style/different-scene, unseen hue, skin fixture를 통과한다.
- [ ] blind preference에서 선택된 생성기가 baseline보다 우수하다.

## 10. 2026-08-19 구현 결과

이번 구현에서 완료한 범위:

- generator, recent photo source, repository, preview renderer를 주입 가능한 경계로 분리했다.
- isolate worker error/exit/timeout/cancel과 partial artifact 정리를 구현했다.
- preview 생성·존재 검증 후에만 preset을 저장하는 transaction을 적용했다.
- preview/save/cancel/worker crash에서 preset과 신규 artifact를 남기지 않는 테스트를 추가했다.
- 최근 사진 full/limited/denied/empty/unavailable/error 상태, 재시도, 선택 순서 badge, page 추가 로드를 구현했다.
- 176px PhotoKit thumbnail과 asset ID를 사용하며, 선택된 asset만 원본 경로를 지연 해석한다.
- Before/After를 독립 슬롯으로 분리하고 각각 선택·교체·해제할 수 있게 했다.
- 성공 sheet 종료 시 임시 preview를 반복 호출에 안전하게 정리한다.
- Direct MVP를 app asset에 포함하고 정확한 size/SHA-256을 통과한 파일만 설치한다.
- 검증된 모델 경로를 worker isolate에 전달해 실제 화면 생성이 neural 경로를 사용하게 했다.
- neural 생성→저장→새 repository reload→재적용 PNG SHA가 동일한 round-trip을 추가했다.

검증 결과:

```text
flutter analyze (변경 핵심 파일 + 신규 테스트): No issues found
flutter test (신규 생성 흐름 + 기존 LUT/recipe/Direct MVP): 56 passed
Direct MVP Flutter wrapper 참고 측정: 479ms (desktop 최종 회귀 실행, 모바일 성능 주장 아님)
iOS 26.5 simulator debug build: success
iPhone 17 Pro simulator install/launch: success (PID 확인)
Runner.app 내 model size/SHA-256: registry와 일치
git diff --check: pass
```

Phase 판정:

- Phase A: 완료. 실제 timeout 재시도 E2E는 integration 단계에서 추가한다.
- Phase B: 코드 및 widget fixture 완료. 실제 iOS limited/iCloud 상태와 메모리 검증이 남았다.
- Phase C: app asset 및 worker neural 경로 연결 완료. iOS simulator build/install/launch도 통과했다. 모바일 latency/RSS 계측은 남았다.
- Phase D: CF-12 round-trip 자동화 완료. scene/skin/unseen hue/blind 품질 검증은 남았다.

## 11. 권장 다음 작업

다음 작업은 **Phase D 품질 fixture와 모바일 성능 계측**이다. 앱 경로 연결 자체는 완료됐으며, 이제 scene invariance·skin·unseen hue와 cold/warm latency/RSS를 수치로 승인해야 한다.

권장 실행 순서:

```text
same-style/different-scene + skin/unseen hue fixture
→ iOS/Android cold/warm latency·memory
→ blind 품질 비교
```
