# Conditional 3D LUT Generation Training Progress

| 항목 | 현재 상태 |
|---|---|
| 프로젝트 상태 | axis-v2 G0~G3는 통과했지만 3-seed validation에서 interpolation 대비 LUT-macro paired CI가 모두 0을 포함해 G4 실패. test·배포 승격을 중단했다. |
| 최근 수정일 | 2026-08-28 |
| 현재 진행 Phase | G4 실패 후 원인 진단 단계; G5/G6 미진입 |
| 현재 핵심 문제 | 세 seed 모두 sample 평균은 개선됐지만 미관측 LUT 10개의 macro 우위를 통계적으로 확정하지 못했다. 참조 이미지 정보량·합성 domain gap·source 품질을 분리해야 한다. |
| 다음 우선 작업 | 추가 epoch/seed 없이 validation의 LUT별 실패를 source group·참조 색역·LUT 식별 가능성으로 진단한다. test 702건은 계속 봉인한다. |

> 참조 이미지에서 관찰된 색감과 톤의 규칙을 Style Latent로 추출하고, 해당 규칙을 이용해 참조 이미지에 나타나지 않은 색상까지 포함하는 전체 RGB 색 공간의 새로운 3D LUT를 생성한다.

---

## 1. 프로젝트 개요

### 1.1 해결하려는 문제

인스타그램·블로그 등에 게시된 최종 보정 이미지는 실제 장면, 조명, 카메라 색 처리,
HDR, 개인 전역 보정, 로컬 보정이 합쳐진 결과다. 본 프로젝트는 이 최종 이미지에서
재사용 가능한 전역 색감과 톤의 규칙을 Style Code로 추출하고, 이미지에 실제로
등장하지 않은 색상까지 포함하는 전체 RGB 변환을 생성한다.

### 1.2 기존 방식과의 차이

| 구분 | 기존 V3 PCA 가중치 예측 | 현재 조건부 LUT 생성 |
|---|---|---|
| 목적 | 고정된 mean LUT와 PCA residual basis의 계수 예측 | 참조 이미지의 스타일 규칙으로 새로운 전체 3D LUT 생성 |
| 출력 공간 | 17³ mean LUT + 12개 PCA basis, bounded coefficient `[-2, 2]` | MVP: 저해상도 3D LUT. 확장: Tone Curve + Palette + Hue Anchor + Base LUT + Residual LUT |
| 비관찰 색상 | PCA 학습 공간 안에서 간접적으로만 결정 | 전체 Color Cube 정답과 비관찰 Hue Loss로 명시적으로 학습 |
| 장면 불변성 | 동일 LUT가 적용된 여러 장면의 Style Code 일관성을 직접 학습하지 않음 | 동일 LUT·서로 다른 장면의 Style Consistency를 핵심 학습 목표로 사용 |
| 의미 정보 | 전역 MobileNet feature 중심 | 인물·피부·풍경·하늘·식물 등 Semantic Code로 확장 |
| 신뢰도 | Hue별 confidence 없음 | 비관찰 Hue confidence와 Identity Mixing으로 확장 |
| 현재 상태 | V2 checkpoint 존재, V3 최종 checkpoint 미생성 | bounded 17³ MVP skeleton과 1-batch smoke 완료, 일반화 성능 미측정 |

현재 모델은 LUT 검색기, LUT ID 분류기, 기존 LUT 복원기 또는 단순 PCA 계수 예측기로
정의하지 않는다. 학습 LUT는 전체 색 공간의 변환 규칙을 가르치는 정답으로 사용한다.

### 1.3 핵심 개념

```text
참조 이미지
→ Style Encoder
→ Style Code
→ 저해상도 3D LUT 생성
→ 전체 RGB Color Cube 변환
→ 정답 LUT의 Color Cube 출력과 비교
→ LUT 파일 출력
```

같은 LUT가 적용된 서로 다른 장면에서 유사한 Style Code가 나오도록 학습한다.
참조 이미지에 존재하지 않는 색상은 학습된 Style Prior, 인접 Hue 관계, Identity LUT,
Palette Code, Semantic Code와 생성 모드를 이용해 완성한다.

### 1.4 최종 산출물

- [ ] 학습 가능한 조건부 3D LUT 생성 모델
- [ ] 전체 Color Cube 정답을 포함하는 데이터 manifest
- [ ] 학습·검증·테스트 split manifest
- [ ] Style Encoder checkpoint
- [ ] Style Decoder checkpoint
- [ ] 전체 RGB Color Cube 평가 report
- [ ] 비관찰 Hue 평가 report
- [ ] LUT 안정성 및 피부색 평가 report
- [ ] Hue Confidence calibration report
- [ ] Faithful·Balanced·Creative 생성 모드
- [ ] 앱 또는 서버에서 사용할 최종 LUT 파일
- [ ] 재현 가능한 experiment config와 실행 로그

### 1.5 성공 판단 원칙

- 이미지에 보이는 색상의 재현 성능만으로 성공을 판정하지 않는다.
- 전체 RGB Color Cube와 비관찰 Hue 영역을 독립적으로 평가한다.
- 동일 LUT가 적용된 서로 다른 장면에서 Style Code가 일관되어야 한다.
- Hue별 변환은 연속적이어야 하며 LUT 밴딩·불연속이 없어야 한다.
- Monotonicity, Out-of-Gamut, 피부색 안정성을 독립 지표로 관리한다.
- Confidence Score가 실제 오차와 유의미한 상관관계를 가져야 한다.
- 목표 수치는 baseline 측정 후 확정하며 현재는 임의로 설정하지 않는다.

---

## 2. 핵심 가설

| ID | 가설 | 검증 방법 | 필요한 데이터 | 성공 기준 | 현재 상태 |
|---|---|---|---|---|---|
| H1 | 동일한 LUT가 적용된 서로 다른 장면에서는 유사한 Style Code가 추출된다. | LUT별 장면 쌍의 latent 거리와 다른 LUT 간 거리를 비교 | 동일 LUT·다중 장면 triplet | 동일 LUT 내부 거리가 다른 LUT 간 거리보다 작음. 목표값 결정 필요 | 실험 필요 |
| H2 | 이미지에 존재하지 않는 Hue 변환도 Style Prior로 추론할 수 있다. | 참조 Hue mask를 만든 뒤 비관찰 Hue의 Color Cube Error만 별도 측정 | Hue coverage가 다른 참조 이미지와 정답 LUT cube | Identity 및 retrieval baseline보다 비관찰 Hue Error 개선. 목표값 결정 필요 | 실험 필요 |
| H3 | Full Color Cube Loss가 이미지 픽셀 Loss만 사용할 때보다 비관찰 색상 일반화를 개선한다. | `L_image` 단독과 `L_image + L_cube` ablation 비교 | 동일 데이터와 고정 split | 비관찰 Hue Error 개선, 관찰 Hue 성능의 허용 가능한 유지. 허용 범위 결정 필요 | 실험 필요 |
| H4 | 구조화된 Base LUT와 Residual LUT 분리가 직접 LUT 생성보다 안정적이다. | 직접 저해상도 LUT와 계층형 decoder 비교 | 동일 Color Cube 정답 | Smoothness·Monotonicity·Out-of-Gamut 개선. 목표값 결정 필요 | MVP 이후 실험 필요 |
| H5 | Tone Curve·Palette·Hue Anchor의 curriculum이 end-to-end 초기 학습보다 수렴과 해석 가능성을 개선한다. | 동일 budget에서 curriculum 유무 비교 | 단계별 supervision이 가능한 LUT 분석값 | validation cube error와 안정성 개선. 목표값 결정 필요 | 실험 필요 |
| H6 | Semantic Code와 피부 마스크가 풍경 스타일을 유지하면서 피부색 왜곡을 줄인다. | 인물 test set에서 semantic module 유무 비교 | 피부 마스크와 인물/비인물 split | Skin Tone Error 감소, 비피부 style error의 허용 가능한 유지 | 데이터 준비 필요 |
| H7 | Hue Confidence 기반 Identity Mixing이 불확실한 Hue의 극단적 왜곡을 줄인다. | confidence module 전후의 calibration, OOG, 비관찰 Hue tail error 비교 | Hue coverage label과 cube error target | confidence-error 상관 개선 및 tail error 감소. 목표값 결정 필요 | MVP 이후 실험 필요 |
| H8 | 여러 LUT와 장면으로 학습한 생성 모델은 동일 LUT가 없는 참조에서도 색상 관계를 조합할 수 있다. | LUT-family holdout test와 retrieval baseline 비교 | LUT family 기준 완전 holdout test | unseen family에서 retrieval/interpolation보다 cube error 개선 | LUT family 정의 필요 |

---

## 3. 전체 개발 로드맵

### Phase 0. 문제 정의 및 기준 모델 설정

**작업 목적**

기존 V3와 새 조건부 생성 문제를 분리하고, 모든 후속 실험이 공유할 split·baseline·평가
계약을 확정한다.

**구현 내용**

- [x] 조건부 생성 모델의 최종 목적 정의
- [x] 기존 V3 PCA 방식과 새 생성 방식의 차이 문서화
- [x] 기존 V2/V3 artifact 존재 여부 확인
- [x] V2 basis와 현재 LUT holdout split contract 확인
- [x] 기존 dataset의 조건부 생성 학습 적합성 감사 (`DATA-AUDIT-001`)
- [x] LUT holdout과 image holdout의 이중 평가 split 생성 (`SPLIT-CONTRACT-001`)
- [x] Identity LUT baseline 측정
- [x] LUT Retrieval baseline 구현 및 측정 (`RETRIEVAL-BASELINE-001`)
- [x] LUT Retrieval + Interpolation baseline 구현 및 측정 (`RETRIEVAL-BASELINE-001`)
- [x] 기존 PCA baseline을 공통 Color Cube 평가기로 재평가
- [x] 관찰·비관찰 Cube와 LUT 안정성 metric을 포함한 공통 evaluator 구현 (`EVAL-CORE-001`)
- [x] raw LUT와 clamp된 sRGB renderer의 target/safety 계약 감사 (`LUT-OOG-AUDIT-001`)
- [ ] train/validation/test 및 LUT-family holdout 계약 확정

**입력 데이터**

- 기존 `data/dataset/neutral`, `graded`, `luts`
- 기존 3,000개 manifest record
- 기존 V2 checkpoint와 validation report
- 기존 V3 sweep artifact

**사용 모듈**

- 현재: `2_generate_dataset.py`, `11_train_basis_v2.py`, `12_train_basis_v3.py`
- 신규 baseline runner: 미정
- 신규 공통 evaluator: 미정

**사용 Loss**

- 학습 없음
- baseline별 평가에 Full Color Cube Error 사용 예정

**평가 지표**

- 전체 Color Cube RGB MAE/MSE/ΔE2000
- Hue·Saturation·Value 구간별 Error
- 비관찰 Hue Error
- LUT Smoothness, Monotonicity, Out-of-Gamut
- Style Code 일관성은 encoder 구현 후 측정

**완료 조건**

- 모든 baseline이 동일한 test split과 동일 Color Cube evaluator를 사용한다.
- Identity, retrieval, interpolation, PCA 결과가 재현 가능한 JSON으로 저장된다.
- 새 모델의 개선 여부를 판정할 최소 지표와 split이 확정된다.

**발생 가능한 문제**

- 기존 V2 report의 small-LUT RMSE와 새 Color Cube 지표 정의가 다르다.
- V3 sweep artifact가 중단 실행에 의해 덮어써져 완전한 결과가 남아 있지 않다.
- 엄격하게 source LUT와 source image를 함께 격리하면 전 데이터가 하나의 컴포넌트가 된다.

**다음 단계 진입 조건**

Phase 0 baseline report가 두 split 계약에서 저장되고, 각 지표가 어느 일반화를 측정하는지
명시되면 Phase 1의 Color Cube target 구축으로 진입한다.

### Phase 1. 데이터 파이프라인 구축

**작업 목적**

동일 LUT가 적용된 여러 장면, 전체 RGB Color Cube 정답, Hue coverage와 의미 정보를
재현 가능하게 생성한다.

**구현 내용**

- [x] 기존 neutral/graded/LUT triplet 3,000개 생성
- [x] 기존 manifest에 `sourceImage`, `sourceLut`, `inputDomain`, `samplingGroup`, `samplingMode` 기록
- [x] Canon LUT를 `sRGB → CLog → Canon LUT`로 합성해 sRGB 입력용 정답으로 저장
- [x] 파일 존재, manifest 계약, 65³ float16 LUT byte size, 정확한 중복 file hash 감사
- [x] LUT holdout과 image holdout JSONL split manifest 생성
- [ ] 동일 LUT 다중 장면 pair/group index 생성
- [ ] LUT 정규화 및 중복 탐지
- [ ] LUT-family label 또는 자동 군집 정의
- [ ] RGB Color Cube 생성기 구현
- [ ] 정답 LUT의 Full Cube 출력 캐싱
- [x] 참조 이미지별 HSV Hue·Saturation·Value Coverage mask 생성 (`HUE-MASK-001`)
- [ ] 인물·피부·하늘·식물·배경 Semantic Mask 생성
- [ ] 장면 종류 metadata 생성
- [ ] LUT 적용 강도 augmentation 설계
- [ ] 촬영 기기·카메라 처리 domain augmentation 설계
- [ ] 최종 모델 선택용 split 정책 확정
- [x] source LUT/source image 기반 누수와 연결 컴포넌트 검사
- [ ] perceptual duplicate 기반 장면 누수 검사
- [ ] dataset version과 checksum 저장

**입력 데이터**

- 기존 neutral 이미지
- crawled/app/Canon LUT
- 기존 neutral/graded/LUT triplet
- Semantic Mask용 원본 이미지
- 촬영 기기 metadata: 검토 필요

**사용 모듈**

- 기존 `2_generate_dataset.py`
- Color Cube builder: 미정
- LUT normalizer/deduplicator: 미정
- Semantic Mask generator: 미정
- Split auditor: 미정

**사용 Loss**

- 학습 없음
- 데이터 생성 검증에 LUT 적용 오차와 round-trip 검사를 사용

**평가 지표**

- LUT별 장면 수
- source group 및 LUT family 분포
- Hue Coverage 분포
- 피부 포함 이미지 비율
- 저조도·고조도 비율
- 중복 LUT 및 유사 이미지 비율
- LUT 적용 결과와 cached cube의 일치 오차

**완료 조건**

- 각 sample이 원본, 보정본, LUT, cube target, 관찰 Hue mask, split ID를 참조할 수 있다.
- LUT holdout과 image holdout이 각각 보장하는 일반화 범위를 report에 명시한다.
- 최소 LUT별 장면 수와 test holdout 정책이 확정된다.
- dataset audit가 오류 없이 통과하고 versioned manifest가 저장된다.

**발생 가능한 문제**

- crawled LUT의 품질·도메인·채널 순서가 불균일할 수 있다.
- 앱/Canon/crawled 그룹 균형이 스타일 다양성을 보장하지 않는다.
- source LUT와 source image를 동시에 격리하는 엄격 split은 현재 데이터 그래프에서 불가능하다.
- 최종 게시 이미지의 카메라 기본 보정과 합성 데이터 사이에 domain gap이 생길 수 있다.
- 자동 Semantic Mask의 오류가 skin loss를 오염시킬 수 있다.

**다음 단계 진입 조건**

MVP 학습용 versioned dataset과 공통 test set이 준비되고, Full Cube target 및 관찰/비관찰
Hue mask가 검증되면 Phase 2로 진입한다.

### Phase 2. LUT 표현 방식 결정

**작업 목적**

MVP 출력 표현을 먼저 확정하고, 이후 계층형 decoder가 직접 LUT 생성보다 실제로
유리한지 공통 지표로 비교한다.

**비교 대상**

| 표현 방식 | 장점 | 단점 | 현재 판단 |
|---|---|---|---|
| 직접 고해상도 3D LUT 예측 | 표현력이 높고 단순한 정답 계약 | 출력 차원과 메모리 비용이 큼, 불연속 위험 | MVP 제외, 비교 실험 필요 |
| PCA coefficient 예측 | 출력이 작고 기존 artifact 재사용 가능 | 학습 PCA 공간 밖 스타일 생성과 비관찰 Hue 명시 학습에 제한 | legacy baseline으로 유지 |
| 저해상도 LUT 생성 후 업샘플링 | MVP가 단순하고 전체 cube supervision 가능 | 업샘플링과 smoothness 관리 필요 | MVP 채택 |
| Tone Curve + Palette + Anchor + Residual | 해석 가능성과 안정성, 제어 가능성 | 단계별 target과 복잡한 curriculum 필요 | MVP 이후 우선 확장 |
| Basis LUT 혼합 | 계산량이 작고 안전 제약 적용이 쉬움 | basis coverage 밖 생성 제한 | baseline 후보 |
| Neural Field 연속 LUT | 임의 해상도와 연속 표현 가능 | 추론 비용 및 모바일 배포 검증 필요 | 검토 필요 |

**구현 내용**

- [x] MVP 학습용 Color Cube 해상도 17³으로 설정 (`MVP-SKELETON-001`, 최종 해상도는 미정)
- [x] MVP 저해상도 LUT 해상도 17³으로 설정 (`MVP-SKELETON-001`)
- [x] differentiable trilinear LUT 적용기 구현 (`MVP-SKELETON-001`)
- [ ] LUT 업샘플링 방식 구현 및 비교
- [ ] LUT binary export 계약 결정
- [ ] 직접 LUT/PCA/basis/neural field 공통 adapter 설계

**입력 데이터**

- Phase 1의 Full Cube target
- 관찰/비관찰 Hue mask
- 기존 V2 PCA artifact

**사용 모듈**

- Low-resolution LUT decoder: `20_train_conditional_lut_mvp.py`의 bounded direct 17³ decoder
- Differentiable LUT renderer: `20_train_conditional_lut_mvp.py`의 PyTorch 3D `grid_sample`
- LUT exporter: MVP 17³ float16 smoke export 구현, 앱용 최종 exporter는 신규 구현 필요

**사용 Loss**

- Full Color Cube Loss
- LUT Smoothness Loss
- Monotonicity Loss
- Out-of-Gamut Penalty
- Identity Regularization Loss

**평가 지표**

- 전체/비관찰 Hue Color Cube Error
- 메모리 사용량과 추론 시간
- Smoothness, Hue Continuity, Monotonicity
- Out-of-Gamut 비율
- 업샘플링 전후 오차

**완료 조건**

- 저해상도 LUT가 학습부터 export·reload까지 동일 결과를 낸다.
- 공통 evaluator로 표현 방식별 정확도·안정성·비용이 비교된다.
- MVP 표현과 후속 계층형 표현의 진입 기준이 기록된다.

**발생 가능한 문제**

- 낮은 해상도에서 hue 경계와 포화색 표현이 손실될 수 있다.
- 높은 해상도에서는 CPU/GPU 메모리와 학습 시간이 과도해질 수 있다.
- RGB grid에서 저채도 영역이 과대표현될 수 있다.

**다음 단계 진입 조건**

저해상도 LUT representation의 end-to-end gradient, export round-trip, cube metric smoke test가
통과하면 Phase 3으로 진입한다.

### Phase 3. Style Encoder 개발

**작업 목적**

참조 이미지의 장면 내용보다 반복되는 색감과 톤 규칙을 우선하는 Style Code를 생성한다.

**구현 내용**

- [ ] Backbone 후보 선정 및 비교
- [ ] Global Feature 추출
- [ ] MVP 단일 Style Code Head 구현
- [ ] Tone Code Head 구현
- [ ] Palette Code Head 구현
- [ ] Chroma Code Head 구현
- [ ] Semantic Code Head 구현
- [ ] 동일 LUT 다중 장면 batch sampler 구현
- [ ] Scene Invariance 학습
- [ ] Style Consistency 학습
- [ ] 다른 LUT 간 latent separation 평가

**입력 데이터**

- 같은 LUT가 적용된 서로 다른 neutral image group
- LUT ID 또는 style group ID
- 참조 이미지 Hue Coverage
- Phase 1 Semantic Mask와 장면 label

**사용 모듈**

- Style Encoder backbone: 미정
- Tone/Palette/Chroma/Semantic head: MVP 이후 순차 구현
- Pair/group sampler: 미정

**사용 Loss**

- Style Consistency Loss
- Full Color Cube Loss의 decoder 역전파
- Perceptual Loss
- Semantic Consistency Loss
- 필요 시 contrastive/triplet loss: 검토 필요

**평가 지표**

- 동일 LUT·다른 장면 Style Code 거리
- 다른 LUT 간 Style Code 분리도
- 장면 종류별 latent drift
- LUT-family holdout cube error
- 참조 Hue Coverage 변화에 대한 latent 안정성

**완료 조건**

- 동일 LUT 내부 Style Code가 장면 변화에도 안정적이다.
- 서로 다른 LUT가 무의미하게 같은 latent로 붕괴하지 않는다.
- Style Code로 생성한 LUT가 Identity와 legacy baseline을 개선한다.
- 성공 임계값은 Phase 0 baseline 이후 결정한다.

**발생 가능한 문제**

- encoder가 LUT보다 하늘·피부·야간 등 장면 분류 단서를 우선할 수 있다.
- camera/HDR 처리 차이가 개인 스타일로 인코딩될 수 있다.
- latent collapse 또는 LUT ID 암기가 발생할 수 있다.

**다음 단계 진입 조건**

MVP encoder-decoder가 고정 test set에서 전체 cube와 비관찰 Hue baseline을 개선하고,
Style Consistency가 측정 가능해지면 Phase 4의 계층형 decoder 확장으로 진입한다.

### Phase 4. Style Decoder 개발

**작업 목적**

Style Code에서 해석 가능하고 부드러운 전체 RGB 변환을 계층적으로 생성한다.

**구현 내용**

- [ ] Tone Curve Decoder
- [ ] Shadow·Midtone·Highlight Palette Decoder
- [ ] Hue Anchor Decoder
- [ ] Base LUT Decoder
- [ ] Residual LUT Decoder
- [ ] Tone/Palette/Anchor/Base/Residual 결합 모듈
- [ ] LUT 해상도 업샘플링
- [ ] Differentiable LUT 적용 모듈 연결
- [ ] Residual 크기 제한
- [ ] 각 중간 출력의 report·visualization 저장

**입력 데이터**

- Style Code
- Full Color Cube와 정답 LUT 출력
- LUT로부터 추출한 tone/palette/anchor supervision: 생성 방식 미정
- Semantic Code와 Hue Coverage

**사용 모듈**

- Tone Curve Decoder
- Palette Decoder
- Hue Anchor Transform
- Base LUT Decoder
- Residual LUT Decoder
- LUT Composer

**사용 Loss**

- Tone Curve Loss
- Palette Loss
- Hue Anchor Loss
- Full Color Cube Loss
- LUT Smoothness/Monotonicity Loss
- Residual Magnitude Regularization

**평가 지표**

- 모듈별 target error
- 전체/비관찰 Hue Color Cube Error
- Hue Continuity
- LUT Smoothness, Monotonicity, Out-of-Gamut
- Residual이 전체 변환에서 차지하는 크기

**완료 조건**

- Base LUT만으로 안전하고 연속적인 기본 변환이 생성된다.
- Residual LUT가 미세 오차를 줄이되 구조 전체를 대신하지 않는다.
- 계층형 decoder가 직접 저해상도 LUT MVP보다 하나 이상의 핵심 지표를 개선하고
  나머지 지표를 허용 범위 안에 유지한다.

**발생 가능한 문제**

- Residual LUT가 Base LUT를 우회해 모든 변환을 담당할 수 있다.
- 중간 target 추출 오차가 전체 모델의 상한을 제한할 수 있다.
- Tone Curve와 LUT가 중복 기능을 학습할 수 있다.

**다음 단계 진입 조건**

각 decoder 출력이 독립적으로 검증되고, LUT 결합 후 gradient·export·안정성 test가 통과하면
Phase 5의 전체 loss tuning으로 진입한다.

### Phase 5. Loss Function 설계

**작업 목적**

이미지 복원, 전체 색 공간 정확도, 장면 불변성, LUT 안정성, 피부 안전성과 confidence
calibration을 서로 구분해 최적화한다.

**Loss 정의**

| Loss | 목적 | 적용 단계 | 현재 상태 |
|---|---|---|---|
| Image Reconstruction Loss | 생성 LUT를 원본에 적용한 결과와 정답 보정 이미지를 비교 | MVP부터 | Smooth L1 interface 구현, 일반화 실험 필요 |
| Full Color Cube Loss | 참조 이미지에 없는 색까지 정답 LUT의 전체 RGB 변환과 비교 | MVP 핵심 | 17³ Smooth L1 interface 구현, 일반화 실험 필요 |
| Style Consistency Loss | 동일 LUT·다른 장면의 Style Code를 가깝게 유지 | MVP부터 | 구현 필요 |
| Tone Curve Loss | 대비, 블랙, 화이트, 감마, 롤오프 target 비교 | Tone 단계 | target 정의 필요 |
| Palette Loss | Shadow·Midtone·Highlight 대표 색과 관계 비교 | Palette 단계 | target 정의 필요 |
| Hue Anchor Loss | Hue별 채도와 색상 이동 anchor 비교 | Anchor 단계 | target 정의 필요 |
| LUT Smoothness Loss | 인접 RGB grid의 급격한 변화를 억제 | MVP부터 | 2차 finite difference interface 구현, weight 검증 필요 |
| Identity Regularization Loss | 근거가 부족한 색의 과도한 이동 억제 | MVP부터 | 구현 필요 |
| Monotonicity Loss | 밝기 또는 채널 순서 역전 억제 | MVP부터 | 정의 검토 필요 |
| Exposure Preservation Loss | 스타일과 무관한 전역 노출 붕괴 억제 | Tone 단계 | 정의 검토 필요 |
| Skin Tone Preservation Loss | 피부색의 비정상 이동 억제 | Semantic 단계 | mask 필요 |
| Out-of-Gamut Penalty | 유효 색역 밖 출력과 clipping 억제 | MVP부터 | bounded decoder로 raw OOG 0 보장, 별도 penalty 실험 필요 |
| Residual Magnitude Regularization | Residual LUT 과의존 방지 | Residual 단계 | 구현 필요 |
| Confidence Calibration Loss | Hue Confidence가 실제 오차를 반영하도록 학습 | Confidence 단계 | target 정의 필요 |
| Perceptual Loss | 적용 이미지의 지각적 구조와 스타일 비교 | MVP 이후 | 실험 필요 |
| Semantic Consistency Loss | 인물·하늘·식물 등 영역별 안전성과 스타일 규칙 유지 | Semantic 단계 | mask 필요 |

**기본 전체 손실식**

```text
L_total =
λ_image × L_image
+ λ_cube × L_cube
+ λ_style × L_style
+ λ_tone × L_tone
+ λ_palette × L_palette
+ λ_anchor × L_anchor
+ λ_smooth × L_smooth
+ λ_identity × L_identity
+ λ_monotonicity × L_monotonicity
+ λ_exposure × L_exposure
+ λ_skin × L_skin
+ λ_oog × L_oog
+ λ_residual × L_residual
+ λ_confidence × L_confidence
+ λ_perceptual × L_perceptual
+ λ_semantic × L_semantic
```

모든 `λ` 값은 **미정**이며 baseline과 gradient scale 측정 후 실험으로 결정한다.

**입력 데이터**

- 원본/보정 이미지
- Full Color Cube와 정답 LUT cube output
- 동일 LUT 다중 장면 group
- tone/palette/anchor target
- Semantic Mask와 Hue Coverage

**사용 모듈**

- Loss registry와 config loader: 미정
- metric/loss 공통 color conversion 모듈: 미정

**평가 지표**

- Loss별 train/validation curve
- gradient norm 및 loss scale
- 전체/비관찰 Hue Error
- 이미지·LUT 안정성·Style Consistency·confidence calibration 지표

**완료 조건**

- 각 Loss를 독립적으로 enable/disable할 수 있다.
- Loss weight와 정의가 experiment config에 저장된다.
- NaN, gradient 폭주, 한 Loss의 독점 현상을 검출한다.
- ablation으로 각 Loss의 기여가 검증된다.

**발생 가능한 문제**

- Full Cube Loss와 Image Loss의 scale 차이가 클 수 있다.
- Smoothness/Identity가 강하면 평균적이고 약한 LUT로 수축할 수 있다.
- 생성 정확도와 피부 안전성 사이에 trade-off가 생길 수 있다.

**다음 단계 진입 조건**

MVP loss 조합이 안정적으로 수렴하고, weight 변경의 효과를 공통 validation report로
비교할 수 있으면 Phase 6 curriculum을 진행한다.

### Phase 6. 단계별 학습 전략

**작업 목적**

복잡한 전체 모델을 한 번에 학습하지 않고, 해석 가능한 변환부터 순차적으로 학습해
각 모듈의 역할과 실패 원인을 분리한다.

#### Stage 6.1 Tone Curve

- [ ] 학습 대상: Style Encoder의 MVP feature와 Tone Curve Decoder
- [ ] Freeze 모듈: Palette, Hue Anchor, Base/Residual LUT, Semantic, Confidence
- [ ] 사용 Loss: Tone Curve, Image Reconstruction, Exposure Preservation, Monotonicity
- [ ] 입력 데이터: 원본/보정 이미지와 LUT에서 추출한 tone target
- [ ] 검증 지표: tone parameter error, luminance curve error, monotonicity
- [ ] 다음 단계 진입 조건: tone target 생성과 validation curve 재현, 목표값 결정 필요

#### Stage 6.2 Palette + Tone Curve

- [ ] 학습 대상: Palette Decoder 추가
- [ ] Freeze 모듈: Hue Anchor, Base/Residual LUT, Semantic, Confidence
- [ ] 사용 Loss: Tone Curve, Palette, Image Reconstruction, Identity
- [ ] 입력 데이터: shadow/midtone/highlight palette target
- [ ] 검증 지표: palette color error, 밝기 구간별 ΔE, 이미지 clipping
- [ ] 다음 단계 진입 조건: Palette가 Tone 성능을 붕괴시키지 않고 색 오차 개선

#### Stage 6.3 Hue Anchor Transform

- [ ] 학습 대상: Hue Anchor Decoder 추가
- [ ] Freeze 모듈: Base/Residual LUT, Semantic, Confidence
- [ ] 사용 Loss: Hue Anchor, Full Cube, Hue Continuity, Identity
- [ ] 입력 데이터: Hue별 정답 색 이동과 채도 변화
- [ ] 검증 지표: Hue별 Error, 비관찰 Hue Error, Hue Continuity
- [ ] 다음 단계 진입 조건: 비관찰 Hue baseline 개선 및 Hue 불연속 허용 기준 통과

#### Stage 6.4 저해상도 Base LUT

- [ ] 학습 대상: Base LUT Decoder
- [ ] Freeze 모듈: Residual LUT, Semantic, Confidence
- [ ] 사용 Loss: Full Cube, Image, Smoothness, Monotonicity, OOG, Identity
- [ ] 입력 데이터: Full Cube target과 원본/보정 이미지
- [ ] 검증 지표: 전체/비관찰 cube error, smoothness, monotonicity, OOG
- [ ] 다음 단계 진입 조건: MVP export와 round-trip smoke test 통과

#### Stage 6.5 Residual LUT

- [ ] 학습 대상: Residual LUT Decoder 추가
- [ ] Freeze 모듈: 초기에는 encoder와 Base LUT freeze, 이후 일부 unfreeze 검토
- [ ] 사용 Loss: Full Cube, Image, Smoothness, Residual Magnitude
- [ ] 입력 데이터: Base LUT 잔차 target
- [ ] 검증 지표: residual 전후 cube error, residual norm, LUT stability
- [ ] 다음 단계 진입 조건: residual이 오차를 줄이고 크기 제한을 준수

#### Stage 6.6 Full Color Cube Loss 강화

- [ ] 학습 대상: Encoder + Base/Residual LUT
- [ ] Freeze 모듈: Semantic, Confidence
- [ ] 사용 Loss: Full Cube 중심, Image, Style, Smoothness, Identity
- [ ] 입력 데이터: Full Cube와 관찰/비관찰 Hue mask
- [ ] 검증 지표: 비관찰 Hue Error와 관찰/비관찰 성능 차이
- [ ] 다음 단계 진입 조건: 이미지 성능만 개선되고 cube 성능이 악화되는 현상 제거

#### Stage 6.7 Semantic Code

- [ ] 학습 대상: Semantic Code Head와 semantic conditioning
- [ ] Freeze 모듈: 초기 decoder freeze 후 joint tuning
- [ ] 사용 Loss: Semantic Consistency, Skin Tone Preservation, Full Cube, Image
- [ ] 입력 데이터: 인물·피부·하늘·식물·배경 mask와 scene label
- [ ] 검증 지표: 피부색 안정성, 장면별 cube error, 비피부 style 유지
- [ ] 다음 단계 진입 조건: 피부 오류 개선 및 풍경 성능 허용 범위 유지

#### Stage 6.8 Hue Confidence Module

- [ ] 학습 대상: Hue Confidence Head와 Identity Mixing
- [ ] Freeze 모듈: 초기 encoder/decoder freeze 후 calibration tuning
- [ ] 사용 Loss: Confidence Calibration, Full Cube, Identity, OOG
- [ ] 입력 데이터: Hue Coverage와 Hue별 실제 cube error
- [ ] 검증 지표: confidence-error 상관, calibration error, tail error
- [ ] 다음 단계 진입 조건: confidence가 실제 오류를 예측하고 mixing으로 tail error 감소

#### Stage 6.9 Faithful·Balanced·Creative 모드

- [ ] 학습 대상: mode conditioning과 latent sampling
- [ ] Freeze 모듈: 안정적인 base model부터 시작, 범위 미정
- [ ] 사용 Loss: 모드별 Identity/Prior/Full Cube/Style Loss
- [ ] 입력 데이터: LUT 강도와 mode target 정책
- [ ] 검증 지표: 모드별 cube error, OOG, identity distance, 사용자 정성 평가
- [ ] 다음 단계 진입 조건: 세 모드 차이가 분명하고 안전 기준을 모두 통과

#### Stage 6.10 End-to-End Fine-tuning

- [ ] 학습 대상: 전체 모델
- [ ] Freeze 모듈: 없음 또는 backbone 일부. 실험 필요
- [ ] 사용 Loss: 검증된 전체 Loss 조합
- [ ] 입력 데이터: 전체 train dataset과 고정 validation/test
- [ ] 검증 지표: 모든 정량·정성 성공 기준
- [ ] 다음 단계 진입 조건: 최종 test report, export, 실제 사진 blind review 완료

**발생 가능한 공통 문제**

- 앞 단계에서 학습한 해석 가능한 모듈이 joint tuning 중 붕괴할 수 있다.
- 후속 모듈이 이전 모듈의 역할을 우회할 수 있다.
- CPU 환경에서는 전체 curriculum 반복 비용이 과도할 수 있다.

---

## 4. 데이터셋 설계

| 항목 | 설명 | 현재 상태 | 확인 사항 |
|---|---|---|---|
| 원본 이미지 | 다양한 장면과 색상 분포 | 기존 neutral 이미지 존재, 조건부 생성 적합성 검토 필요 | 라이선스, 장면·기기 다양성 |
| LUT | 실제 색보정 LUT | crawled/app/Canon 사용 중 | 중복, 품질, 채널 순서, 입력 도메인 |
| 동일 LUT 다중 장면 | 장면 불변 Style 학습 | 기존 dataset에서 구성 가능, group index 미구현 | LUT별 최소 장면 수 결정 |
| Color Cube | 전체 RGB 공간 학습·평가 | 미구현 | Grid 해상도 결정 |
| Semantic Mask | 인물·하늘·식물 등 | 미정 | 자동 생성 모델과 mask 품질 |
| 생성 강도 | LUT 적용 강도 | 미구현 | 연속값 또는 단계값 |
| Hue Coverage | 참조 이미지에서 관찰되는 Hue | 참조별 17³ Cube mask 생성 완료 | threshold calibration과 perceptual color-space 비교 |
| Camera Domain | 카메라 기본 처리·HDR 차이 | metadata 미정 | domain augmentation 및 test 구성 |

### 4.1 현재 확인된 데이터

- [x] manifest record 총 3,000개 존재
- [x] source group: crawled 1,000 / app 1,000 / canon 1,000
- [x] `neutral`, `graded`, `luts` 디렉터리 존재
- [x] manifest에 원본 이미지 이름과 source LUT 기록
- [x] Canon sample의 `inputDomain`은 `srgb_composed`
- [x] 모든 sample의 neutral/graded/LUT 파일 존재와 65³ float16 LUT byte size 검증
- [x] neutral/LUT exact file hash와 LUT별 다중 장면 통계 생성
- [x] LUT holdout 및 image holdout test split 생성
- [ ] LUT family holdout 생성
- [x] 참조별 Hue Coverage mask 생성

### 4.2 DATA-AUDIT-001 결과

| 항목 | 결과 |
|---|---|
| 실행일 | 2026-07-28 |
| 감사 스크립트 | `14_audit_conditional_dataset.py` |
| 대상 | 3,000개 manifest record와 해당 neutral/graded/LUT file |
| Manifest/계약 오류 | 0 |
| 누락 file | 0 |
| 잘못된 LUT byte size | 0 |
| 중복 sample ID | 0 |
| 고유 source LUT | 119 |
| 고유 source image | 515 |
| LUT 구성 | crawled 7 / app 30 / canon 82 |
| LUT당 sample 수 | crawled 142~143 / app 33~34 / canon 12~13 |
| 전역 HSV Hue Coverage | 24개 bin 모두 관찰됨 |
| 참조별 관찰 Hue bin | 최소 0 / 평균 16.655 / 최대 24 |

전역 Hue histogram은 존재하지만, 이는 개별 참조 이미지에 없는 색을 판정하지 않는다.
비관찰 Hue 평가는 참조별 mask 구현 후에만 시작할 수 있다.

### 4.3 SPLIT-CONTRACT-001 결과

| 계약 | 목적 | 격리 보장 | 알려진 누수 | Split 규모 |
|---|---|---|---|---|
| LUT holdout | unseen LUT style 일반화 | source LUT 0건 교차 | source image 396개 교차 | train 2,316 / validation 343 / test 341 |
| Image holdout | unseen scene content 일반화 | source image 0건 교차 | source LUT 114개 교차 | train 2,421 / validation 280 / test 299 |

엄격하게 source LUT와 source image를 함께 격리하는 bipartite graph는 component 1개이며,
그 component가 3,000개 sample, 119개 LUT, 515개 source image 전체를 포함한다.
따라서 현 데이터만으로 두 일반화를 동시에 엄격히 측정하는 non-empty split은 만들 수 없다.

### 4.4 HUE-MASK-001 결과

| 항목 | 결과 |
|---|---|
| 실행일 | 2026-07-28 |
| 구현 | `16_build_reference_hue_masks.py` |
| 입력 | 3,000개 graded reference 이미지 |
| 출력 | reference별 17³ observed/unobserved Cube mask |
| Hue·Saturation·Value bins | 24 / 4 / 3 |
| 최소 채도·명도 | 0.05 / 0.03 |
| 관찰 cell 최소 pixel 수 | 32 |
| Mask 수 | 3,000 |
| Reference당 Cube point | 4,913 |
| 관찰 Cube 비율 | 최소 0.001221 / 평균 0.095874 / 최대 0.560757 |
| Empty/Fully observed mask | 0 / 0 |

이 mask는 고정 coverage signal이며 학습된 confidence가 아니다. 설정값은 첫 구현값으로
기록하며, Color Cube evaluator와 실제 오차의 상관 분석 전에는 최종 threshold로 확정하지 않는다.

### 4.5 분리 기준

- LUT 기준: LUT holdout 평가에서는 동일 source LUT를 train/validation/test에 동시에 포함하지 않는다.
- LUT family 기준: 유사 LUT 또는 같은 family가 test와 train에 나뉘어 누수되지 않도록
  family holdout을 별도로 구성한다.
- 장면 기준: image holdout 평가에서는 같은 원본 이미지가 split 사이에 섞이지 않는다.
- 촬영 기기 기준: metadata가 확보되면 device holdout test를 구성한다. 현재 `검토 필요`.
- 개인/연속 촬영 기준: 동일 촬영 세션의 유사 이미지는 같은 split에 둔다.
- LUT 강도 variant는 원본 LUT와 같은 split에 둔다.

### 4.6 품질 관리

- [ ] perceptual hash를 이용한 유사 이미지 중복 제거
- [ ] Color Cube output 거리와 파일 hash를 이용한 LUT 중복 탐지
- [ ] NaN, clipping, channel ordering, domain 오류 LUT 제거
- [ ] 극단적인 LUT 제거 기준 결정
- [ ] 피부색 포함 데이터 비율 측정 및 목표 결정
- [ ] 저조도·고조도 데이터 비율 측정 및 목표 결정
- [x] 전체 graded reference의 HSV Hue Coverage histogram 생성
- [ ] 저채도·고채도·경계색 coverage 측정

---

## 5. Color Cube 설계

### 5.1 해상도 후보

| Grid | 용도 후보 | 장점 | 비용·위험 | 상태 |
|---|---|---|---|---|
| 17³ | MVP 학습 및 빠른 전체 평가 | 4,913 points로 CPU에서도 비교적 가벼움 | 세밀한 hue transition 손실 가능 | 우선 후보, 실험 필요 |
| 33³ | 중간 해상도 학습·평가 | 35,937 points로 표현력과 비용 균형 | batch 전체 평가 비용 증가 | 검토 필요 |
| 65³ | 최종 LUT 및 정밀 평가 | 274,625 points로 앱 LUT와 직접 비교 가능 | 학습 시 메모리·시간 부담 | 출력/최종 평가 후보 |

- 학습용 Grid와 출력용 LUT 해상도는 같을 필요가 없다.
- MVP는 저해상도 LUT를 생성하고 검증된 interpolation으로 출력 해상도를 높인다.
- 최종 출력 해상도: `미정`.

### 5.2 Full Grid와 Random Sampling

| 방식 | 장점 | 단점 | 사용 계획 |
|---|---|---|---|
| Full Grid | 전체 색 공간을 빠짐없이 평가, 재현성 높음 | 고해상도에서 계산량 큼 | validation/test 필수 |
| Random RGB Sampling | 학습 비용 절감 | 저채도·경계 Hue 편향 가능 | train 후보 |
| Hue·Saturation·Value 균형 샘플링 | Hue별 coverage 균형 | RGB interpolation 좌표 변환 필요 | train 후보 |
| Boundary Sampling | RGB cube 경계와 포화색 검증 강화 | 자연 이미지 분포와 차이 | OOG·clipping 보강 |

### 5.3 샘플링 요구사항

- [ ] 저채도 RGB grid의 과대표현을 보정한다.
- [ ] Hue별 sample 수를 기록한다.
- [ ] Saturation과 Value 구간별 sample 수를 기록한다.
- [ ] RGB cube 모서리와 경계 영역을 별도 샘플링한다.
- [ ] 관찰 Hue와 비관찰 Hue mask를 cube point에 연결한다.
- [ ] 정답과 예측 LUT의 output을 공통 색공간에서 비교한다.
- [ ] Out-of-Gamut 값의 clamp 전후를 모두 기록한다.

### 5.4 Out-of-Gamut 처리

- [x] 데이터 renderer 계약: 정확도 target은 LUT interpolation 후 채널별 `[0, 1]` clamp한 sRGB output이다.
- [x] 안전성 계약: raw LUT node와 raw 17³ cube render의 OOG 비율·이탈 크기는 정확도와 별도로 기록한다.
- [x] MVP export 계약: decoder output은 채널별 `[0, 1]` 범위로 제한한다. target의 의도된 clipping을 생성 LUT의 raw OOG로 재현시키지 않는다.
- [ ] 학습 중 raw output의 색역 이탈 크기와 비율을 기록한다. MVP bounded decoder에서는 0이어야 한다.
- [ ] crawled 강한 look LUT의 clamp 영향을 별도 태그/가중치로 사용할지 실험한다.
- export format과 앱 적용 시 clamp 정책은 앱 LUT contract 확인 후 결정한다.
- RGB 외 perceptual color space에서의 gamut 평가 방식은 `검토 필요`.

---

## 6. 평가 지표

### 6.1 LUT 정확도

- 전체 RGB Color Cube RGB MAE
- 전체 RGB Color Cube RGB MSE/RMSE
- 전체 Color Cube ΔE2000
- Hue별 Color Cube Error
- Saturation 구간별 Error
- 밝기 구간별 Error
- LUT-family holdout Error

### 6.2 이미지 품질

- PSNR
- SSIM
- LPIPS
- 이미지 ΔE2000
- 색상 왜곡 및 clipping 비율
- 밴딩 검출
- 피부색 변화

### 6.3 LUT 품질

- LUT Smoothness
- 인접 Grid 차이와 최대 jump
- Monotonicity 위반 비율
- Out-of-Gamut 비율과 이탈 크기
- Identity LUT와의 거리
- Residual LUT 크기
- Hue별 변환 연속성(Hue Continuity)

### 6.4 스타일 일관성

- 동일 LUT·다른 장면의 Style Code 거리
- 다른 LUT 간 Style Code 분리도
- 참조 이미지와 적용 결과 이미지의 스타일 유사도
- 장면 내용 변화에 대한 Style Code 안정성
- 카메라·노출·화이트밸런스 변화에 대한 Style Code 안정성

### 6.5 보이지 않은 색상 생성 성능

- 참조 이미지에 없는 Hue 구간의 Color Cube Error
- 관찰 Hue와 비관찰 Hue Error 차이
- 비관찰 Hue 중 worst-k Error
- Hue별 변환 연속성
- Identity Mixing 적용 전후 Error
- Faithful·Balanced·Creative 모드별 비관찰 Hue 안정성

### 6.6 Confidence 평가

- Hue Confidence Score와 실제 Hue별 Error의 Pearson/Spearman 상관관계
- confidence bin별 실제 Error
- calibration error
- 낮은 confidence 영역의 Identity Mixing 전후 Error
- confidence가 높은데 오차도 높은 false-confidence 비율

### 6.7 피부색 안정성

- skin mask 내부 ΔE2000
- skin hue angle 변화
- skin lightness/chroma 변화
- 피부 Out-of-Gamut 및 clipping 비율
- 인물/풍경 모델 또는 모드별 피부 안정성 비교

모든 지표의 목표값은 Phase 0 baseline 측정 후 결정한다.

---

## 7. Baseline 실험 및 실패 기록

### 7.1 Baseline 현황

| 실험 ID | 모델 | 주요 설정 | 결과 | 문제점 | 다음 조치 |
|---|---|---|---|---|---|
| BASE-IDENTITY-001 | Identity LUT | 공통 Color Cube split 미정 | 실험 필요 | baseline evaluator 미구현 | Phase 0에서 우선 측정 |
| BASE-RETRIEVAL-001 | LUT Retrieval | encoder/거리 함수 미정 | 실험 필요 | 구현 없음 | retrieval baseline 구현 |
| BASE-INTERP-001 | LUT Retrieval + Interpolation | 이웃 수와 가중치 미정 | 실험 필요 | 구현 없음 | retrieval 이후 구현 |
| LEGACY-DIRECT-001 | 직접 3D LUT 회귀 | 기존 `3_train.py` | 기존 세션 기록 Val ΔE 약 14.12, 재검증 필요 | 목표 ΔE 2.0 미달, 현재 생성 문제의 cube/비관찰 Hue 지표 없음 | 공통 evaluator로 재평가 |
| LEGACY-PCA-V2-001 | PCA Coefficient Regression | 17³ mean + 12 bases, coefficient `[-2,2]` | checkpoint `val_loss=6.237476`; report overall small-LUT RMSE `1.198659` | crawled holdout가 전체 오류를 지배, 생성식·비관찰 Hue 평가 없음 | legacy PCA baseline으로 공통 test 평가 |
| LEGACY-PCA-V3-001 | V3 group-weight sweep | V2 basis + group/reconstruction weight 탐색 | 현재 저장 sweep은 1 trial뿐이며 최종 V3 checkpoint 없음 | 완료 sweep으로 판정 불가, metric 계약과 artifact 보존 문제 | 실패 기록 보존, 새 생성 모델 baseline과 혼동 금지 |
| DATA-AUDIT-001 | Conditional dataset audit | 전체 3,000개 triplet, 24 HSV hue bins, saturation 0.05 | 무결성 오류 0, source LUT 119개, source image 515개 | per-reference hue mask는 없음 | split contract와 hue mask 구현 |
| SPLIT-CONTRACT-001 | Dual evaluation split | seed 20260728, validation/test ratio 각 0.10 | LUT/image holdout JSONL 생성 | 두 값을 동시에 격리하는 strict split 불가 | 두 계약별 baseline을 분리 보고 |
| HUE-MASK-001 | Reference Hue Coverage Mask | 17³ Cube, HSV 24×4×3, min cell pixels 32 | 3,000개 binary mask 생성, 평균 관찰 Cube 비율 0.095874 | threshold calibration 미완료 | 공통 evaluator에서 observed/unobserved error 측정 |
| EVAL-CORE-001 | Common Color Cube Evaluator | 17³ Cube, CIEDE2000, observed/unobserved mask | identity self-test 통과, 실제 LUT 1건 CLI smoke 통과 | raw OOG와 rendered clamp 계약 차이 확인 | 전체 LUT OOG audit와 baseline 실행 |
| BASELINE-DUAL-001 | Identity + V2 PCA | LUT/image holdout validation+test, 17³ Cube | V2가 Identity 대비 두 계약 모두 ΔE2000 개선 | V2 raw OOG와 비관찰 Hue 오차가 큼 | OOG target audit 후 MVP 구현 |
| LUT-OOG-AUDIT-001 | Source LUT Rendering Contract Audit | 119 unique LUT, raw node/raw 17³ render/clamp effect | app 30개와 Canon 82개는 raw OOG 0, crawled 7개 중 4개만 OOG | crawled 강한 look은 clamp 전후 차이가 큼 | bounded MVP decoder와 clamp된 target accuracy 계약 적용 |
| MVP-SKELETON-001 | Bounded Direct Low-resolution Conditional LUT | Style Encoder + 128-d Style Code + 17³ decoder + full cube/image/smoothness interfaces | actual 2-sample 4-step smoke, loss `0.130816 → 0.025588`, bounded export/reload 통과 | 동일 LUT 다중 장면 consistency 및 held-out 일반화 미측정 | Style Consistency smoke와 controlled validation training |
| STYLE-CONSISTENCY-SMOKE-001 | Pairwise Hinge Style Consistency | 2 LUT × 2 scene, positive intra distance + negative margin | total은 감소했으나 final negative separation penalty `0.099998` | final Style Code collapse | objective 교체 |
| STYLE-CONSISTENCY-SMOKE-002 | Supervised-contrastive Style Consistency | 8 steps, learning rate `0.005` | steps 2~5에는 분리됐으나 step 6부터 불안정 | optimizer step 이후 collapse | lower learning rate와 per-step monitor |
| STYLE-CONSISTENCY-SMOKE-003 | Supervised-contrastive Style Consistency | 8 steps, learning rate `0.001` | steps 2~8 pre-update에는 분리됐지만 final state collapse | saturated contrastive objective 뒤 update instability | checkpoint/early-stop guard 필요 |
| STYLE-CONSISTENCY-SMOKE-004 | Supervised-contrastive Style Consistency | 7 steps, learning rate `0.001` | final state에서도 collapse, report 보존 | short run 자체의 update 안정성 미확보 | controlled training 금지, loss redesign |
| STYLE-CONSISTENCY-SMOKE-005 | Encoder/Decoder LR 분리 | decoder `0.001`, encoder `0.0001`, 8 steps | final eval collapse 지속 | train/eval BatchNorm 통계 불일치 | encoder BatchNorm freeze |
| STYLE-CONSISTENCY-SMOKE-006 | Frozen-BN Supervised Contrastive | decoder `0.001`, encoder `0.0001`, 8 steps | total `0.337308 → 0.085695`, final positive/negative cosine `0.909795/0.465582` | 4-sample overfit이며 validation 미측정 | controlled validation + monitor |
| RETRIEVAL-BASELINE-001 | HSV/RGB LUT Retrieval + top-3 Interpolation | train LUT candidate only, LUT/image holdout validation+test | image holdout retrieval ΔE `10.205129`, LUT holdout interpolation ΔE `15.224448` | unseen LUT에서 V2 PCA를 이기지 못함 | generation MVP와 동일 report 비교 |
| MVP-TRAIN-001 | Bounded MVP Controlled Run | LUT holdout train, 1 epoch, frozen BN + paired Style Consistency | validation ΔE `23.752600`, raw OOG `0.0` | V2/retrieval보다 낮지 않음 | learning/capacity/loss ablation 필요 |
| MVP-BOTTLENECK-ANALYSIS-001 | Checkpoint collapse diagnosis | MVP-TRAIN-001 checkpoint, LUT-holdout validation 343 samples, train unique-LUT mean comparison | prediction variance retention `0.002260`; prediction→mean node RMSE `0.145191` vs target→mean `0.227481` | output diversity is severely compressed; predicted grid is rougher than target | measure decoder-logit/residual scale and test a representation/initialization ablation before any broad sweep |
| MVP-INSTRUMENTED-CONTROL-001 | Direct decoder instrumented control | MVP-TRAIN-001과 같은 1 epoch/seed/budget, first batch loss-gradient/residual diagnostics | initial cube/image→encoder gradient `0`; decoder residual logits `0`; validation ΔE `23.752600`, variance retention `0.002260` | zero-initialized residual head initially disconnects cube/image gradients from encoder; control remains collapsed | bounded residual-amplitude decoder with non-zero small head initialization as a single controlled ablation |
| MVP-BOUNDED-RESIDUAL-001 | Bounded residual-amplitude decoder | control과 동일 seed/budget; `identity + 0.25*tanh(residual)` and head std `1e-3` | initial cube/image→encoder gradient becomes non-zero, but validation ΔE `25.005270`, variance retention `0.000023` | first-step gradient connection alone does not prevent collapse and harms accuracy | preserve failure; inspect training dynamics before changing another representation or loss |
| MVP-DYNAMICS-COMPARISON-001 | Read-only checkpoint dynamics comparison | control/ablation checkpoint 343 validation samples, Style Code/residual-logit/output variance | Style Code variance is similar, but ablation residual-logit variance `0.000916` vs control `0.003107` | decoder attenuates latent differences; this is not evidence of encoder collapse | do not add another decoder sweep before a trajectory-capable instrumented run |
| LUT-FAMILY-HOLDOUT-001 | LUT-output family holdout | clamped 17³ output RMSE connected components, threshold `0.08`, group-stratified family split | 119 LUT → 66 families; train/validation/test 52/7/7 families; family leakage 0 | threshold is an explicit similarity convention, not semantic metadata | evaluate baselines/MVP with this third contract before family-generalization claims |
| COMPARISON-REPORT-001 | Unified conditional comparison | common 17³ clamped renderer schema across LUT/image/family holdout | all currently valid baseline/MVP results unified; unavailable family V2/MVP explicitly `not_run` | partitions differ for MVP validation-only output | do not compare across policy/partition scopes or impute missing results |
| MVP-TRAJECTORY-CONTROL-001 | Two-epoch trajectory control | identity-logit MVP, same LUT-holdout/seed/budget, epoch-level validation variance | ΔE `23.752600 → 23.268994`; variance retention `0.226% → 1.769%` | improvement remains far below V2/interpolation; 2 epochs is not a success claim | use trajectory evidence for one-factor capacity/optimization ablation, not broad sweeps |
| COMPARISON-REPORT-002 | Updated unified comparison | same schema as 001, trajectory-control MVP validation substituted | retains prior reports and points to improved MVP ΔE `23.268994` | MVP remains validation-only and family/image `not_run` | preserve partition-scope caveat |
| MVP-DECODER-CAPACITY-001 | Decoder width ablation | identity-logit decoder trunk `512 → 1024`, otherwise trajectory control fixed | LUT-holdout ΔE `23.268994 → 20.497773`; variance retention `1.769% → 12.631%` | clear improvement but remains below V2/interpolation | test one optimizer/encoder update change next; do not widen again yet |
| COMPARISON-REPORT-003 | Updated unified comparison | same schema, 1024-width MVP validation substituted | current best MVP LUT-holdout validation ΔE `20.497773` | MVP is still validation-only; family/image remain `not_run` | preserve partition-scope caveat |
| MVP-ENCODER-LR-001 | Encoder LR ablation | 1024-width decoder, encoder LR `1e-5 → 5e-5`; all other 2-epoch settings fixed | LUT-holdout ΔE `20.497773 → 19.655976`; observed ΔE `16.52 → 14.23`; retention `12.63% → 24.79%` | improvement still does not reach V2/interpolation | test only a learning-rate schedule next |
| COMPARISON-REPORT-004 | Updated unified comparison | same schema, encoder-LR MVP validation substituted | current best MVP LUT-holdout validation ΔE `19.655976` | MVP is validation-only; family/image remain `not_run` | preserve partition-scope caveat |
| MVP-COSINE-SCHEDULE-001 | Cosine schedule ablation | current best settings + epoch-level cosine LR decay only | ΔE `19.655976 → 21.158486`, retention `24.79% → 12.81%` | decay harms the 2-epoch trajectory | preserve failure; use fixed LR for longer-trajectory test |
| MVP-FIXED-LR-4EPOCH-001 | Longer fixed-LR trajectory | current best 1024-width fixed LR extended 2 → 4 epochs | LUT-holdout ΔE `19.655976 → 18.867267`; smoothness `0.065131 → 0.051466` | improvement persists but is below interpolation by 3.64 ΔE; output variance plateaus | test Style Consistency weight only, not more epochs/capacity |
| COMPARISON-REPORT-005 | Updated unified comparison | same schema, 4-epoch fixed-LR MVP validation substituted | current best MVP LUT-holdout validation ΔE `18.867267` | MVP is validation-only; family/image remain `not_run` | preserve partition-scope caveat |
| PROTOCOL-AUDIT-001 | Training/evaluation protocol audit | sampler coverage, checkpoint objective contribution, partition alignment, LUT weighting | train/validation paired sampler unique coverage `53.5%/50.1%`, same subset every epoch; Style term 97.6% of selection total; baseline headline mixed validation+test | further ablation conclusions would be confounded | fix protocol before Style-weight or longer-run experiments |
| PROTOCOL-FIX-001 | Full-coverage and accuracy-selection contract | epoch-aware full-coverage train pairs; full 343 validation; separate 24-scene/12-LUT Style monitor; cube checkpoint selection | code/smoke and 4-epoch control complete; train coverage 100%, epoch pairs change; strict comparator supports LUT macro | corrected model ΔE is below interpolation | hold protocol fixed and ablate Style weight only |
| COMPARISON-PROTOCOL-001 | Strict validation-only comparison | LUT-holdout validation 343 samples/12 LUTs; sample-weighted + LUT-macro | sample ΔE V2/interpolation/MVP `17.19/17.88/18.87`; LUT-macro `14.89/14.35/14.81` | MVP checkpoint predates protocol fix | use only as pre-fix reference, not final model selection |
| MVP-PROTOCOL-CORRECTED-CONTROL-001 | Protocol-corrected 4-epoch control | 1024 width, fixed decoder/encoder LR `2e-4/5e-5`, full-coverage sampler, full 343 validation, 24-scene Style monitor | sample ΔE `19.590483`, LUT-macro `15.341602`; V2/interpolation `17.191645/17.877367`; Cube loss `0.040649 → 0.022109` | pre-fix result was optimistic; corrected control is below retrieval/interpolation in sample ΔE | hold all settings and change Style weight only |
| COMPARISON-PROTOCOL-CORRECTED-001 | Corrected strict validation-only comparison | 343 samples/12 LUTs; corrected MVP plus existing identity/V2/retrieval/interpolation reports | all models now use validation-only headline; corrected MVP protocol is recorded in report | only the MVP training protocol changed; baselines are unchanged references | use this as the current model-selection report |
| MVP-PROTOCOL-STYLE-WEIGHT-010-001 | Style weight ablation | corrected control with Style weight only `0.25 → 0.10` | sample ΔE `19.684234` vs control `19.590483`; LUT-macro `15.385093` vs `15.341602`; output-variance retention `24.59%` vs `24.73%` | lower Style weight does not improve accuracy or output diversity | preserve failure and restore `0.25`; test decoder capacity only |
| COMPARISON-PROTOCOL-STYLE-WEIGHT-010-001 | Strict comparison after Style weight ablation | validation-only baseline reports plus Style-0.10 MVP | all headline partitions remain validation-only | Style-0.10 is worse than the corrected control | preserve as ablation artifact, not current best |
| MVP-PROTOCOL-DECODER-CAPACITY-2048-001 | Decoder capacity ablation | corrected control with decoder width only `1024 → 2048` | sample ΔE `20.005080`, LUT-macro `15.656757`, variance retention `23.97%` | extra capacity increases residual-logit variance but harms all ΔE views | preserve failure and restore width `1024`; test epoch budget only |
| COMPARISON-PROTOCOL-DECODER-CAPACITY-2048-001 | Strict comparison after capacity ablation | validation-only baseline reports plus 2048-width MVP | all headline partitions remain validation-only | 2048-width is worse than corrected control | preserve as ablation artifact, not current best |
| MVP-PROTOCOL-LONG-TRAJECTORY-8EPOCH-001 | Corrected long-trajectory control | current corrected control with epoch budget only `4 → 8` | sample ΔE `19.590483 → 19.146559`, LUT-macro `15.341602 → 14.991621`, retention `24.73% → 27.28%` | longer training improves unobserved/canon/crawled but worsens observed/app | current MVP best; hold duration fixed and ablate image weight only |
| COMPARISON-PROTOCOL-LONG-TRAJECTORY-8EPOCH-001 | Strict comparison after long trajectory | validation-only baseline reports plus corrected 8-epoch MVP | all headline partitions remain validation-only | 8-epoch is current best but still below interpolation | use as the current model-selection report |
| MVP-PROTOCOL-IMAGE-WEIGHT-010-001 | Image-loss weight ablation | corrected 8-epoch control with image weight only `0.25 → 0.10` | sample ΔE `19.146559 → 19.104012`, LUT-macro `14.991621 → 14.948234`; all observed/unobserved/group values improve | lower image weight is a small consistent gain | current MVP best; test boundary at image weight `0.00` |
| COMPARISON-PROTOCOL-IMAGE-WEIGHT-010-001 | Strict comparison after image-weight ablation | validation-only baseline reports plus image-0.10 MVP | all headline partitions remain validation-only | image-0.10 is current best but still below interpolation | use as the current model-selection report |
| MVP-PROTOCOL-IMAGE-WEIGHT-000-001 | Cube-only boundary ablation | image-0.10 current best with image weight only `0.10 → 0.00` | sample ΔE `19.104012 → 19.076099`, LUT-macro `14.948234 → 14.923894`; all observed/unobserved/group values improve | image reconstruction term is not needed under this contract | current MVP best; hold image weight at `0.00` and test smoothness weight only |
| COMPARISON-PROTOCOL-IMAGE-WEIGHT-000-001 | Strict comparison after cube-only ablation | validation-only baseline reports plus cube-only MVP | all headline partitions remain validation-only | cube-only is current best but still below interpolation | use as the current model-selection report |
| MVP-PROTOCOL-SMOOTHNESS-WEIGHT-020-001 | Smoothness-weight ablation | cube-only current best with smoothness weight only `0.01 → 0.02` | sample ΔE `19.076099 → 19.073146`, LUT-macro `14.923894 → 14.921591`, roughness `0.047963 → 0.047900` | small improvement without lost variance | current MVP best; test higher-smoothness boundary at `0.04` |
| COMPARISON-PROTOCOL-SMOOTHNESS-WEIGHT-020-001 | Strict comparison after smoothness ablation | validation-only baseline reports plus smoothness-0.02 MVP | all headline partitions remain validation-only | smoothness-0.02 is current best but still below interpolation | use as the current model-selection report |
| MVP-PROTOCOL-SMOOTHNESS-WEIGHT-040-001 | Higher-smoothness boundary ablation | smoothness-0.02 current best with weight only `0.02 → 0.04` | sample ΔE `19.073146 → 19.072239`, LUT-macro `14.921591 → 14.920012`, roughness `0.047900 → 0.047846` | all headline metrics improve but effect is below practical single-seed resolution | single-seed current best; replicate 0.01/0.04 before adopting higher weight |
| COMPARISON-PROTOCOL-SMOOTHNESS-WEIGHT-040-001 | Strict comparison after higher-smoothness ablation | validation-only baseline reports plus smoothness-0.04 MVP | all headline partitions remain validation-only | current single-seed best, not replication-confirmed | use for reference; do not claim robust gain |
| MVP-SMOOTHNESS-MULTISEED-REPLICATION-001 | Paired smoothness replication | corrected cube-only 8-epoch protocol, paired seeds `20260729/30/31`, weights `0.01/0.04` | `.04 − .01` mean sample/LUT-macro ΔE `-0.010659/-0.002594`, roughness `-0.000252`; seed `20260730` LUT-macro worsens `+0.011049` | the small mean gain is not consistently supported by both accuracy views | practical tie; select lower regularization `0.01` and stop this sweep |
| V2-FAMILY-HOLDOUT-001 | Zero-leakage family-trained V2 PCA | 12 PCA bases fit on 94 train LUTs only; predictor early-stopped at epoch 27 with best epoch 12 | validation/test sample ΔE `15.662410/16.431086`, LUT-macro `16.340682/17.111657`; all source-LUT overlaps `0` | family V2 is materially weaker than direct MVP | preserve as valid PCA baseline; do not reuse legacy V2 in family contract |
| MVP-FAMILY-TONE-CURVE-001 | Conditional Tone Curve-only baseline | 17-point monotone luminance curve, chroma-preserving 17³ LUT, no hue residual; same family 8-epoch protocol | validation/test sample ΔE `30.793185/26.891850`, LUT-macro `28.407953/26.666807`; validation monotonicity violations `3.67%`, OOG `0` | modest target-only representation does not transfer to accurate conditional inference; clamp can break 3D luminance monotonicity | preserve failure; audit Hue Anchor residual before adding a residual decoder |
| HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001 | Tone Curve + hue residual target audit | saturation-scaled circular RGB residual anchors after neutral-luminance Tone Curve; 6/12/24/48 anchor counts | validation residual MSE explained `83.39/87.35/88.30/88.52%`; test `86.82/90.09/90.75/90.88%` | increasing anchors beyond 6 gives small target-level gain | choose 6 anchors as the smallest count reaching 90% of best validation explanation; implement conditional decoder |
| MVP-FAMILY-TONE-HUE-ANCHOR-006-001 | Unsupervised conditional 6-anchor decoder | 17-point Tone Curve + six saturation-scaled circular RGB anchors, cube loss only; same family 8-epoch protocol | validation/test sample ΔE `15.601722/15.608163`, LUT-macro `15.985063/17.045819`, monotonicity `17.35%/9.41%`, OOG `0` | target-fit representation does not transfer through cube loss alone and harms 3D safety | preserve failure; add target-derived curve/anchor head supervision only |
| MVP-FAMILY-TONE-HUE-ANCHOR-006-SUP-001 | Supervised conditional 6-anchor decoder | same decoder + model-compatible curve/anchor Smooth L1 weight `0.10`; same family 8-epoch protocol | validation/test sample ΔE `16.135138/15.560297`, LUT-macro `15.778334/16.879931`, monotonicity `13.79%/7.19%`, OOG `0` | test and safety improve slightly but validation sample worsens; still far below direct MVP | stop decoder loss sweep; test labels only as a parallel direct-MVP auxiliary |
| MVP-FAMILY-HOLDOUT-SMOOTH-010-001 | Zero-leakage family-holdout MVP | selected corrected `.01` MVP, 52/7/7 family train/validation/test, 94 train LUT candidates, 8 epochs | validation sample/LUT-macro ΔE `13.571087/13.605198`, test `12.929904/14.001296`; test interpolation/V2 `13.731034/16.431086` | validation LUT-macro is interpolation보다 `+0.014679`으로 사실상 동률 | test에서 MVP가 interpolation/V2보다 sample `0.801130/3.501182`, LUT-macro `0.778402/3.110361` 낮음 |
| FAMILY-HOLDOUT-COMPARISON-001 | Family-contract comparison | identity, train-candidate retrieval/top-3 interpolation, family-trained V2, family-trained MVP; validation and test reported separately | MVP is best available model on test and V2보다 validation/test 모두 우세 | original LUT-holdout gap은 별도 계약으로 남음 | Tone Curve target audit 후 구조화 decoder의 단일 모듈을 구현 |
| BASE-LOWLUT-001 | Direct Low-resolution LUT Prediction | MVP skeleton 17³ 구현 | 일반화 학습 미실행 | 성능 비교 없음 | `MVP-SKELETON-001` 후 controlled run |
| BASE-TONE-PALETTE-001 | Tone Curve + Palette | target 정의 미정 | 미구현 | target extractor 없음 | MVP 이후 curriculum |
| BASE-TONE-RESIDUAL-001 | Tone + Palette + Residual LUT | residual limit 미정 | 미구현 | 선행 decoder 없음 | 단계별 구현 |
| PROPOSED-FULL-001 | 전체 조건부 LUT 생성 모델 | 전체 구조 | 미구현 | MVP와 데이터 계약 미완료 | Phase 0부터 순차 진행 |

### 7.2 확인된 V2 validation 결과

| 그룹 | Count | Coefficient MSE | 17³ Small-LUT RMSE |
|---|---:|---:|---:|
| crawled | 143 | 3.319076 | 2.544930 |
| app | 101 | 0.193171 | 0.166343 |
| canon | 98 | 0.308877 | 0.298119 |
| overall | 342 | 1.533357 | 1.198659 |

이 수치는 기존 V2 report의 지표이며, 새 조건부 생성 모델의 Full Color Cube Error나
비관찰 Hue 성능으로 해석하지 않는다.

### 7.3 실패·불확정 실험 기록

#### LEGACY-DIRECT-001

- 상태: 실패
- 목적: 스타일 이미지에서 직접 3D LUT 회귀
- 결과: 기존 세션 기록 Val ΔE 약 14.12
- 실패 원인: 목표 ΔE 2.0과 큰 차이. 단순 epoch 증가로 해결할 근거 부족
- 분석: 전체 LUT 직접 회귀가 장면 내용과 스타일을 분리하거나 비관찰 색상을 명시적으로
  학습하지 않았다.
- 배운 점: 이미지 reconstruction 또는 LUT tensor loss만으로 현재 생성 목표를 정의하면 안 된다.
- 다음 조치: legacy baseline으로만 유지하고 Full Cube·비관찰 Hue 평가를 추가한다.

#### LEGACY-PCA-V2-001

- 상태: 제한적 baseline 완료, 현재 목표에는 불충분
- 목적: LUT 출처 균형과 LUT 단위 holdout을 적용한 PCA basis coefficient 예측
- 결과: 위 V2 validation 표 참조
- 실패 원인: crawled holdout LUT RMSE가 `2.544930`으로 app/canon보다 크게 높다.
- 분석: 12개 basis와 고정 coefficient 공간은 학습 LUT 분포의 압축에는 유용하지만,
  새로운 전체 색 공간 생성과 비관찰 Hue confidence를 직접 제공하지 않는다.
- 배운 점: source group 균형만으로 unseen LUT/style 일반화가 보장되지 않는다.
- 다음 조치: 공통 Color Cube evaluator에서 legacy PCA baseline으로 재사용한다.

#### LEGACY-PCA-V3-001

- 상태: 실패/불확정
- 목적: crawled/app/canon group weight와 reconstruction weight 자동 탐색
- 오류 기록:

```text
RuntimeError: basis artifact was fit on a different train LUT split; rerun --fit-basis
```

- 현재 확인: V3 코드의 basis split seed와 V2 seed는 일치하며 basis contract smoke check는 통과했다.
- 현재 artifact: `basis_v3_sweep.json`에는 1개 trial만 존재하고 `basis_v3_color.pt` 및
  `basis_v3_color.report.json`은 존재하지 않는다.
- 실패 원인: 초기 sweep의 trial별 split mismatch, 중단/재실행 결과 덮어쓰기, 최종 checkpoint 미생성
- 분석: 현재 저장 artifact만으로 최적 weight 또는 V2 대비 개선을 주장할 수 없다.
- 배운 점: run별 immutable artifact, 완료 상태, 공통 seed, score와 val loss의 분리가 필요하다.
- 다음 조치: 기존 artifact를 삭제하지 않고 legacy 실패 기록으로 보존한다. 새 조건부 생성 모델의
  핵심 설계와 V3 weight tuning을 혼합하지 않는다.

#### DATA-AUDIT-001

- 상태: 성공
- 날짜: 2026-07-28
- 목적: 기존 3,000개 triplet이 조건부 LUT 생성 MVP의 입력 자산으로 사용 가능한지 확인
- 사용 데이터: `data/dataset/manifest.jsonl`, neutral/graded/LUT file 전체
- 구현: `14_audit_conditional_dataset.py`
- 설정: HSV Hue 24 bins, minimum saturation 0.05, neutral/LUT SHA-256 hash 사용
- 평가 결과: manifest/계약 오류 0, 누락 file 0, 잘못된 LUT byte size 0, 중복 sample ID 0
- 구조 결과: 119개 LUT와 515개 원본 이미지. crawled/app/canon LUT 수는 7/30/82
- Hue 결과: 전역 24개 Hue bin은 모두 관찰됐지만, 참조별 관찰 Hue mask는 아직 생성하지 않음
- 문제: source image 재사용이 많아 strict split 정책의 실현 가능성을 추가 검사해야 했음
- 배운 점: 전역 Hue 분포는 비관찰 Hue 평가를 대신하지 못한다.
- 다음 조치: source LUT/source image 연결 그래프를 검사하고 참조별 Hue mask를 구현한다.

#### DATA-SPLIT-001

- 상태: 실패
- 날짜: 2026-07-28
- 목적: source LUT와 source image를 모두 split 경계로 격리하는 train/validation/test split 생성
- 사용 데이터: DATA-AUDIT-001과 동일
- 평가 결과: bipartite graph component가 1개이며 전체 3,000개 sample을 포함
- 실패 원인: LUT와 원본 이미지의 재사용 연결이 전체 데이터에 걸쳐 이어짐
- 분석: 두 기준을 동시에 격리하면 non-empty validation/test split을 만들 수 없다.
- 배운 점: unseen LUT style과 unseen scene content는 현 데이터에서 별도 평가 계약으로 분리해야 한다.
- 다음 조치: strict split을 숨기지 않고 LUT holdout과 image holdout을 병렬로 생성한다.

#### SPLIT-CONTRACT-001

- 상태: 부분 완료
- 날짜: 2026-07-28
- 목적: 현 데이터에서 가능한 일반화 평가를 명시적인 두 계약으로 분리
- 사용 데이터: 3,000개 triplet
- 구현: `15_build_conditional_splits.py`
- 설정: seed 20260728, validation ratio 0.10, test ratio 0.10
- LUT holdout 결과: source LUT 교차 0, source image 교차 396, train/validation/test 2,316/343/341
- Image holdout 결과: source image 교차 0, source LUT 교차 114, train/validation/test 2,421/280/299
- 발생한 문제: 두 계약 모두 상대 계약의 누수를 허용하므로 단일 최종 score로 합치면 안 됨
- 해석: LUT holdout은 unseen style 일반화, image holdout은 unseen scene 일반화를 각각 측정한다.
- 새롭게 결정된 사항: 모든 baseline과 MVP report는 두 split의 결과를 분리 저장한다.
- 다음 작업: 참조별 Hue mask와 공통 Color Cube evaluator 구현

#### HUE-MASK-001

- 상태: 성공
- 날짜: 2026-07-28
- 목적: 참조 이미지에서 관찰된 색상과 비관찰 색상을 17³ RGB Cube에서 분리
- 사용 데이터: 3,000개 graded reference 이미지
- 구현: `16_build_reference_hue_masks.py`
- 설정: HSV hue/saturation/value bins 24/4/3, minimum saturation 0.05, minimum value 0.03,
  minimum cell pixels 32
- 산출물: 3,000 × 4,913 binary mask archive와 sample별 JSONL summary
- 평가 결과: 관찰 Cube 비율 최소 0.001221, 평균 0.095874, 최대 0.560757, empty mask 0
- 검증: archive ID shape `(3000,)`, mask shape `(3000, 4913)`, 값 `{0, 1}` 확인
- 발생한 문제: 현재 mask는 HSV coverage 기반이므로 색의 지각적 유사성과 실제 생성 오차를 아직 반영하지 않음
- 해석: 이후 evaluator는 동일 LUT 오차를 observed/unobserved Cube 영역으로 나눠 보고할 수 있다.
- 새롭게 결정된 사항: 이 mask는 Hue Confidence의 target이나 최종 confidence가 아니라 coverage 입력으로만 사용한다.
- 다음 작업: mask를 이용하는 공통 Color Cube evaluator 구현

#### EVAL-CORE-001

- 상태: 부분 완료
- 날짜: 2026-07-28
- 목적: 모델 종류와 관계없이 Full Cube, 관찰/비관찰 Cube, Smoothness, Monotonicity,
  Out-of-Gamut, Hue Continuity를 동일 schema로 평가
- 구현: `17_evaluate_conditional_lut.py`
- 사용 데이터: 17³ identity LUT self-test, dataset sample `000000` LUT와 HUE-MASK-001 artifact
- 사용 지표: RGB MAE/MSE/RMSE, ΔE2000, observed/unobserved Cube Error, raw LUT OOG,
  luminance monotonicity violation, neighbor smoothness, hue continuity
- 성공 검증: Identity LUT 자기비교에서 RGB MAE/MSE와 ΔE2000 평균 0 확인
- CLI smoke: sample `000000`에서 observed/unobserved Cube count 830/4,083으로 총 4,913 확인
- 발생한 문제: 첫 구현은 raw LUT output을 직접 비교했으나 target LUT raw OOG node ratio가
  0.985085로 dataset renderer 계약과 불일치
- 실패 원인: 기존 dataset LUT application은 렌더 결과를 sRGB 범위로 clamp하지만 evaluator의
  정확도 비교는 clamp 전 raw output을 사용했음
- 수정: RGB·ΔE2000 정확도는 clamp된 rendered RGB로 계산하고, OOG는 raw LUT node 값으로 별도 기록
- 배운 점: LUT 정확도와 LUT 안전성은 같은 수치로 합치면 안 되며, rendering contract를 명시해야 한다.
- 다음 작업: 전 LUT raw OOG 분포를 감사하고 Identity·PCA baseline을 두 split에서 측정

#### BASELINE-DUAL-001

- 상태: 성공
- 날짜: 2026-07-29
- 목적: Identity와 Legacy V2 PCA를 공통 Cube evaluator와 두 split 계약에서 비교
- 사용 데이터: LUT holdout validation/test 684개, image holdout validation/test 579개
- 구현: `18_evaluate_conditional_baselines.py`
- 설정: 17³ Cube, HUE-MASK-001, batch size 32, rendered RGB clamp 후 정확도 비교
- LUT holdout Identity: 전체/관찰/비관찰 ΔE2000 평균 29.911996 / 33.537489 / 29.539171
- LUT holdout V2 PCA: 전체/관찰/비관찰 ΔE2000 평균 15.084822 / 12.740761 / 15.325872
- Image holdout Identity: 전체/관찰/비관찰 ΔE2000 평균 27.454878 / 29.991528 / 27.192334
- Image holdout V2 PCA: 전체/관찰/비관찰 ΔE2000 평균 12.986429 / 10.351472 / 13.259148
- LUT holdout V2 PCA group ΔE2000: crawled 14.914552 / app 16.736547 / canon 13.630988
- Image holdout V2 PCA group ΔE2000: crawled 9.430685 / app 15.797630 / canon 13.369759
- 안전성 결과: V2 PCA raw OOG node 비율은 image/lut holdout에서 0.433934 / 0.462287
- Target raw OOG node 비율: image/lut holdout에서 0.123449 / 0.189880
- 해석: V2는 Identity보다 명확히 낫지만, 관찰 영역보다 비관찰 영역의 오차가 크고 raw OOG가
  target보다 높다. 새 조건부 생성 모델은 Full Cube와 안전성 Loss를 별도 최적화해야 한다.
- 배운 점: 기존 V2 validation loss만으로는 unseen style·unseen scene·비관찰 색의 차이를 설명할 수 없다.
- 다음 작업: source group별 raw OOG 분포를 감사하고 MVP target clamp/safety policy를 확정한다.

#### LUT-OOG-AUDIT-001

- 상태: 성공
- 날짜: 2026-07-29
- 목적: source LUT의 raw output 색역 이탈과 dataset renderer의 clamp 영향이 source group별로
  어떻게 다른지 측정하여 MVP의 target과 safety 계약을 확정
- 사용 데이터: manifest가 참조하는 119개 unique LUT, 17³ RGB input cube
- 구현: `19_audit_lut_rendering_contract.py`
- 사용 지표: raw node/raw render OOG node·value 비율, min/max, clamp affected render ratio,
  clamp adjustment MAE/max
- 평가 결과: 전체 119개 LUT 중 raw render OOG가 있는 LUT는 4개뿐이며 모두 crawled 그룹이다.
  app 30개와 Canon 82개는 raw node/raw render OOG가 모두 0이다. 전체 raw render OOG 비율의
  LUT별 평균은 `0.025186`, median은 `0.0`이다.
- crawled 결과: 7개 LUT의 raw render OOG 비율 평균 `0.428164`, median `0.239976`이며,
  가장 강한 LUT는 OOG 비율 `0.986973`, clamp adjustment MAE `2.590528`, raw max `12.828125`였다.
- 해석: OOG는 전체 데이터의 일반적 특성이 아니라 일부 crawled 강한 look에 집중되어 있다.
  이 raw 값을 생성 target으로 사용하면 앱에 안전한 LUT와 의도된 display clipping을 혼동한다.
- 새롭게 결정된 사항: 정확도는 기존 dataset renderer와 같은 clamp 후 sRGB output으로 비교한다.
  MVP decoder는 sigmoid 등 bounded output으로 `[0,1]` LUT를 생성하고 raw target OOG는 safety
  report 및 향후 강한 look 정책을 위한 metadata로만 보존한다.
- 발생 가능한 문제: bounded decoder는 clamp 전 수치가 큰 crawled LUT의 내부 표현을 복원하지
  않는다. 이는 최종 rendered target과의 일치로 평가하며, 해당 look의 색감 손실 여부는 별도
  image/cube error로 검증해야 한다.
- 다음 작업: bounded low-resolution conditional LUT MVP의 encoder/decoder/renderer를 구현한다.

#### MVP-SKELETON-001

- 상태: 성공, 단 1-batch 기계 검증으로 한정
- 날짜: 2026-07-29
- 목적: PCA 계수 예측과 분리된 조건부 LUT 생성의 최소 forward/backward/export 경로를 실제
  dataset triplet으로 검증
- 사용 데이터: LUT holdout train split의 graded reference/neutral image/target LUT 중 샘플
  `000000`, `000001`; 두 샘플은 같은 source LUT이므로 일반화 또는 style consistency 결과가 아니다.
- 구현: `20_train_conditional_lut_mvp.py`
- 모델 구조: MobileNetV3-Small feature encoder(random initialization) → 128-d Style Code →
  identity-centered residual decoder → sigmoid bounded 17³ LUT
- 사용 Loss: 17³ Full Cube Smooth L1, neutral image에 differentiable LUT를 적용한 image Smooth L1,
  LUT 2차 finite-difference smoothness
- 설정: CPU, 2 samples, 4 optimizer steps, smoke learning rate `0.005`; 장기 학습 미실행
- 평가 결과: total loss `0.130816 → 0.025588`; final cube/image/smoothness loss는 각각
  `0.024123`/`0.003957`/`0.047597`. 첫 sample의 17³ cube ΔE2000은 overall `8.194098`,
  observed `6.603861`, unobserved `8.517365`였으나 같은 batch overfit 결과이므로 baseline과 비교하지 않는다.
- export 검증: generated 17³ float16 LUT reload RMSE `0.000039`, min/max `0.0`/`1.0`.
- 발생한 문제: 초기 decoder가 identity에서 시작하므로 첫 gradient norm이 작았고, 4-step overfit에서
  smoothness loss가 증가했다. 이는 loss interface의 유효성만 보이며 weight의 적절성을 증명하지 않는다.
- 배운 점: full cube와 image renderer의 gradient는 동시에 흐르지만, style code가 장면 불변인지와
  unseen LUT/scene 성능은 아직 전혀 검증되지 않았다.
- 다음 작업: 같은 source LUT의 서로 다른 reference를 한 batch에 넣어 Style Consistency Loss와
  collapse guard를 포함한 smoke test를 구현한다.

#### STYLE-CONSISTENCY-SMOKE-001 ~ 004

- 상태: 실패, artifact 보존
- 날짜: 2026-07-29
- 목적: 동일 LUT의 서로 다른 장면을 같은 Style Code로 모으면서 다른 LUT와는 분리하는 loss가
  Full Cube/Image loss와 함께 안정적으로 동작하는지 확인
- 사용 데이터: Canon source LUT 2개(`Accent Red`, `Bright White`) 각각의 서로 다른 reference
  2개, 총 4 samples. 이는 held-out 일반화 평가가 아니다.
- 구현: `20_train_conditional_lut_mvp.py --consistency-smoke-test`; source LUT positive pair와
  다른 source LUT negative pair를 명시적으로 검증
- 001 결과: squared-distance hinge는 total loss를 낮췄지만 final negative separation penalty가
  `0.099998`가 되어 Style Code collapse를 허용했다.
- 002 결과: supervised contrastive로 교체 후 learning rate `0.005`에서 step 2~5는 positive cosine
  `0.996~1.000`, negative cosine `-0.955~-0.965`를 달성했으나 step 6 이후 불안정해졌다.
- 003 결과: learning rate `0.001`에서도 8-step final state가 positive/negative cosine 약
  `1.0/1.0`으로 collapse했다.
- 004 결과: 7-step 재검증도 final total loss `0.322632`로 initial `0.070862`보다 커지고
  positive/negative cosine 약 `1.0/1.0`이어서 실패했다.
- 분석: batch pair 자체와 positive/negative loss 계산은 연결됐지만, contrastive loss가 포화된 뒤
  Full Cube/Image update가 Style Code 분리를 보존하지 않는다. 현재 단일 loss weight와 Adam update는
  controlled training의 안전한 시작 조건을 만족하지 않는다.
- 배운 점: Style Consistency는 단순 보조항이 아니라 per-step/epoch latent separation monitor,
  best-state checkpoint, 그리고 cube decoder gradient와의 조정이 필요한 별도 안정성 계약이다.
- 다음 조치: 현재 MVP의 controlled train은 보류한다. collapse-resistant objective와 validation의
  positive-vs-negative separation metric을 구현한 후에만 다시 smoke test를 실행한다.

#### STYLE-CONSISTENCY-SMOKE-005 ~ 006

- 상태: 005 실패, 006 smoke 성공
- 날짜: 2026-07-29
- 목적: Style Code collapse가 loss 자체인지, small-batch MobileNet BatchNorm의 train/eval 통계
  불일치인지 분리
- 005 결과: encoder learning rate를 `0.0001`, decoder learning rate를 `0.001`로 분리해도 final
  eval state에서 collapse했다.
- 분석: train step의 latent metric은 정상인데 eval state만 collapse하는 패턴이 반복되어,
  small-batch BatchNorm running statistic drift가 원인으로 확인됐다.
- 006 변경: Style Encoder의 BatchNorm을 train/eval 모두 eval mode로 고정하고 supervised contrastive
  objective를 유지했다.
- 006 결과: 8-step final total loss `0.337308 → 0.085695`; final positive/negative cosine
  `0.909795/0.465582`로 separation 조건 통과. first sample Cube ΔE2000 overall/observed/unobserved는
  `21.177021`/`14.795892`/`21.373838`이며, 4-sample overfit 수치라 baseline 비교에 사용하지 않는다.
- export 검증: bounded 17³ LUT float16 reload RMSE `0.000098`, output min/max 약 `0.000100/1.0`.
- 배운 점: 작은 batch의 Style Encoder에는 frozen BatchNorm 또는 batch-size 독립 normalization이
  필요하다. controlled training은 epoch별 positive/negative separation과 best-state checkpoint를
  함께 저장해야 한다.
- 다음 작업: LUT holdout validation에서 이 monitor를 포함한 짧은 controlled run을 설계한다.

#### RETRIEVAL-BASELINE-001

- 상태: 성공
- 날짜: 2026-07-29
- 목적: conditional LUT generator가 단순 유사 LUT 선택/평균보다 실제로 unseen color rule을
  생성하는지 판정할 leakage-safe 하한선 측정
- 구현: `21_evaluate_retrieval_baselines.py`; graded reference의 normalized HSV `12×4×3` histogram과
  RGB mean/std로 train source LUT별 centroid를 만들고 nearest retrieval 및 top-3 interpolation 평가
- 후보 계약: 각 policy의 train partition에 존재하는 source LUT만 후보로 사용. image holdout은 119개,
  LUT holdout은 95개 후보 LUT를 사용했다.
- Image holdout 결과(579 samples): retrieval overall/observed/unobserved ΔE2000
  `10.205129/9.854047/10.241466`; interpolation `10.699539/9.798974/10.792748`.
- LUT holdout 결과(684 samples): retrieval `16.042751/15.977999/16.049410`; interpolation
  `15.224448/14.978418/15.249748`.
- 해석: image holdout에서는 train LUT 재사용이 허용되므로 retrieval이 V2 PCA `12.986429`보다 좋다.
  그러나 unseen style을 보는 LUT holdout에서는 interpolation도 V2 PCA `15.084822`보다 나쁘고,
  crawled group interpolation ΔE2000은 `19.085941`로 특히 높다.
- 배운 점: retrieval은 scene 일반화의 강한 비교 baseline이지만, 새로운 LUT 규칙 생성의 대체물이
  아니며 proposed MVP의 성공은 LUT holdout 비관찰 Cube에서 이를 넘어야 한다.
- 산출물: `reports/baselines/retrieval_baseline_report.json`
- 다음 작업: frozen-BN Style Consistency monitor를 포함한 bounded MVP validation run.

#### MVP-TRAIN-001

- 상태: 학습/평가 pipeline 성공, 성능 실패
- 날짜: 2026-07-29
- 설정: LUT holdout train 2,316 samples, validation 343 samples, 1 epoch, batch 32, frozen encoder
  BatchNorm, paired Style Consistency, decoder/encoder learning rate `0.0002/0.00001`.
- train/validation total loss: `0.883934/0.870167`; validation positive/negative cosine
  `0.964444/0.934427`.
- validation 결과: overall/observed/unobserved ΔE2000 `23.752600/20.798860/23.986253`, RGB RMSE
  `0.271258`, generated raw OOG node ratio `0.0`.
- group ΔE2000: crawled `28.397935`, app `24.506440`, canon `16.189596`.
- 해석: bounded output과 checkpoint/evaluator contract는 작동하지만 1 epoch direct decoder는 평균적 LUT에
  수축해 V2 PCA와 retrieval baseline을 넘지 못했다. 이 결과를 성능 개선으로 처리하지 않는다.
- 산출물: `checkpoints/conditional_lut_mvp_17.pt`, `reports/mvp/mvp_train_report.json`,
  `reports/mvp/mvp_checkpoint_validation_report.json`.

#### MVP-BOTTLENECK-ANALYSIS-001

- 상태: 성공, read-only checkpoint diagnosis
- 날짜: 2026-07-29
- 목적: `MVP-TRAIN-001`의 낮은 LUT-holdout 성능이 평균 LUT 수축인지, 그룹별 target variation이나
  LUT safety 문제인지 학습을 추가로 실행하지 않고 분리한다.
- 구현: `23_analyze_mvp_bottleneck.py`; checkpoint와 dataset을 읽기만 하며, train partition의 unique
  source LUT target 평균과 validation prediction/target을 같은 17³ bounded renderer 계약으로 비교한다.
- 설정: LUT holdout validation 343 samples, MVP checkpoint `conditional_lut_mvp_17.pt`, target은 기존
  renderer contract에 맞춰 clamp된 17³ LUT target을 사용했다.
- 결과: node-level prediction output variance mean은 `0.000106035`, target variance mean은
  `0.046928547`로 retention ratio `0.002260` (0.226%)이다. prediction→train-mean node RMSE는
  `0.145191 ± 0.000416`, target→train-mean은 `0.227481 ± 0.051423`이다. 즉 sample별 target의
  train-mean 거리 차이를 prediction이 거의 반영하지 못한다.
- 그룹 관찰: prediction→mean RMSE는 crawled/app/canon 각각 `0.145204`/`0.145199`/`0.145162`로
  사실상 동일하지만, target→mean은 `0.243579`/`0.275512`/`0.154000`이다. app/crawled의 큰 target
  style variation이 하나의 거의 고정된 output으로 압축되며, 기존 validation ΔE의 group gap과 일치한다.
- 안정성 관찰: generated raw OOG node ratio는 `0.0`으로 bounded safety contract는 유지했다. 반면
  prediction neighbor smoothness mean은 `0.087292`, target은 `0.011671`로 약 7.48배 높다. 현재의
  low output diversity는 smooth LUT를 의미하지 않으며, sigmoid-logit residual decoder의 grid artifact를
  별도로 다뤄야 한다.
- 실패 원인/배운 점: 단순 epoch 증가나 weight sweep은 수축과 grid roughness의 원인을 분리하지 못한다.
  다음 controlled ablation은 (1) decoder residual/logit magnitude와 gradient norm을 epoch별 저장하고,
  (2) identity-logit 직접 합산 대신 bounded residual amplitude 또는 base+residual representation을
  단일 변경으로 비교하며, (3) cube/image/style/smoothness의 per-term gradient scale을 기록해야 한다.
- 산출물: `reports/mvp/mvp_bottleneck_analysis_report.json`.

#### MVP-INSTRUMENTED-CONTROL-001

- 상태: 성공, controlled measurement; 성능 실패는 재확인
- 날짜: 2026-07-29
- 목적: 평균 LUT 수축의 원인을 구분하기 위해 `MVP-TRAIN-001`과 동일한 1 epoch LUT-holdout run에
  first-batch per-loss gradient, decoder residual logit, prediction variance 계측만 추가한다.
- 설정: train/validation `2,316/343`, batch 32, decoder/encoder LR `0.0002/0.00001`, frozen BN,
  Style Consistency, seed `20260729`, instrumentation batches 1. 기존 checkpoint/report는 덮어쓰지 않고
  `conditional_lut_mvp-instrumented-control-001.pt`와 ID별 report를 새로 저장했다.
- 결과: 시작 batch에서 prediction batch variance `0.0`, decoder residual logit abs mean/std `0.0/0.0`,
  cube/image loss의 encoder gradient L2는 모두 `0.0`이었다. 반면 cube/image loss의 decoder gradient는
  `0.000507`/`0.001243`, style loss의 encoder gradient는 `0.257318`이었다. 즉 zero-initialized residual
  output head는 첫 update에서 Style Consistency만 encoder에 전달하고, cube/image reconstruction은 decoder
  head만 먼저 움직이게 만든다.
- validation: overall ΔE2000 `23.752600`, prediction neighbor smoothness `0.087292`, output variance
  retention `0.002260`으로 `MVP-TRAIN-001`과 동일했다. 이는 fixed seed/budget control이 재현됐음을
  뜻하며 성능 개선은 아니다.
- 실패 원인/배운 점: Style Code가 cube/image target을 직접 받기 전에 decoder head가 평균적 출력을
  형성할 기회가 있다. 이후 epoch에서 encoder gradient가 생기는지와 별개로, 초기 신호 단절 자체는
  관측됐다. 다음 실험에서는 loss weight나 capacity를 바꾸지 않고 bounded residual-amplitude output과
  non-zero small head initialization만 변경해 이 단절을 해소한다.
- 산출물: `checkpoints/conditional_lut_mvp-instrumented-control-001.pt`,
  `reports/mvp/mvp-instrumented-control-001_train_report.json`,
  `reports/mvp/mvp-instrumented-control-001_validation_report.json`,
  `reports/mvp/mvp-instrumented-control-001_bottleneck_report.json`.

#### MVP-BOUNDED-RESIDUAL-001

- 상태: 실패, artifact 보존
- 날짜: 2026-07-29
- 목적: `MVP-INSTRUMENTED-CONTROL-001`에서 확인한 zero-initialized identity-logit head의 초기
  cube/image→encoder gradient 단절을 단일 decoder representation 변경으로 해소할 수 있는지 검증한다.
- 변경: 기존 `sigmoid(identity_logit + residual)` 대신 `clamp(identity + 0.25*tanh(residual), 0, 1)`을
  사용하고 residual head weight를 `Normal(0, 1e-3)`로 초기화했다. seed, data split, batch 32, 1 epoch,
  learning rates, loss weights, frozen BN, Style Consistency, instrumentation budget은 control과 동일하다.
- 초기 계측: cube/image→encoder gradient L2가 `0.0000426`/`0.0000707`로 0이 아니게 되었고, residual
  logit abs mean은 `0.000807`이었다. 따라서 변경은 의도대로 first-step signal path를 열었다.
- validation 결과: overall/observed/unobserved ΔE2000은 `25.005270`/`22.508275`/`25.202792`로 control의
  `23.752600`/`20.798860`/`23.986253`보다 나빴다. output variance retention도 `0.0000234` (0.0023%)로
  control `0.002260` (0.226%)보다 약 97배 낮아졌다. smoothness neighbor L2는 `0.079221`로 control
  `0.087292`보다 낮았지만 target `0.011671`과는 여전히 큰 차이다.
- 실패 원인/배운 점: initial gradient connection 자체는 충분 조건이 아니다. 이 residual amplitude와
  initialization은 output diversity를 더 줄였으며, 단일 epoch에서 accuracy를 악화시켰다. loss/capacity
  sweep이나 이 결과를 성공으로 분류하지 않는다. 다음 decoder 변경 전에는 epoch별 residual scale,
  encoder gradient, variance trajectory를 비교할 수 있도록 instrumentation을 먼저 확장한다.
- 산출물: `checkpoints/conditional_lut_mvp-bounded-residual-001.pt`,
  `reports/mvp/mvp-bounded-residual-001_train_report.json`,
  `reports/mvp/mvp-bounded-residual-001_validation_report.json`,
  `reports/mvp/mvp-bounded-residual-001_bottleneck_report.json`.

#### MVP-DYNAMICS-COMPARISON-001

- 상태: 성공, read-only analysis
- 날짜: 2026-07-29
- 목적: control과 bounded-residual ablation의 failure를 Style Encoder latent collapse와 decoder
  attenuation 중 어느 쪽에 더 가깝게 볼지, 새 학습 없이 같은 343 validation samples에서 비교한다.
- 결과: sample 간 Style Code variance mean은 control/ablation `0.011371/0.011710`으로 유사하다.
  반면 decoder residual-logit variance mean은 `0.003107/0.000916`, final prediction output variance mean은
  `0.000106035/0.000001096`이다. 따라서 ablation은 latent의 sample 차이를 없앴다기보다 decoder에서
  LUT output으로 전달되는 차이를 더 크게 약화시켰다.
- 배운 점: 현재 evidence는 Style Encoder 전체의 collapse를 증명하지 않는다. decoder representation을
  무작정 더 바꾸지 말고, 다음 controlled run에서는 epoch별 latent/residual/output variance trajectory를
  저장해 언제 attenuation이 일어나는지 먼저 확인한다.
- 산출물: `reports/mvp/mvp-instrumented-control-001_dynamics_report.json`,
  `reports/mvp/mvp-bounded-residual-001_dynamics_report.json`.

#### LUT-FAMILY-HOLDOUT-001

- 상태: 성공
- 날짜: 2026-07-29
- 목적: similar LUT family를 train에서 본 상태의 near-duplicate interpolation과 실제 새로운 family
  일반화를 분리하는 세 번째 evaluation contract를 생성한다.
- 구현: `24_build_lut_family_holdout.py`; source LUT의 existing clamped 17³ target output 간 RMSE가
  `0.08` 이하인 edge의 connected component를 하나의 family로 정의한다. 이 기준은 raw OOG가 아니라
  기존 accuracy renderer contract와 같은 clamped sRGB LUT output을 사용한다.
- 결과: 119 unique source LUT가 66 families가 됐다. family size는 singleton 46, 2~4 LUT 17,
  6/8/15 LUT family 각 1개다. family-level train/validation/test는 52/7/7 families, sample은
  2,024/274/702이며 family leakage count는 `0`이다. family는 source group을 교차하지 않았다.
- 주의: RMSE `0.08`은 output similarity 기반의 명시적 운영 기준이며 semantic metadata truth가 아니다.
  향후 threshold sensitivity는 별도 기록한다.
- 산출물: `reports/splits/conditional_lut_family_holdout.jsonl`,
  `reports/splits/conditional_lut_family_holdout_report.json`.

#### COMPARISON-REPORT-001

- 상태: 성공
- 날짜: 2026-07-29
- 목적: Identity, legacy V2 PCA, retrieval, top-3 interpolation, conditional MVP를 동일한 17³
  clamped sRGB renderer schema로 모으고, LUT/image/family holdout의 일반화 계약을 혼동 없이 표시한다.
- 구현: `25_build_conditional_comparison_report.py`. family split에서는 leakage-safe Identity/retrieval/
  interpolation을 새로 평가했다. V2와 MVP는 family-isolated 학습 checkpoint가 없으므로 점수를
  재사용하지 않고 `not_run`으로 명시했다. MVP의 LUT holdout은 validation 343 samples만 있어 baseline의
  validation+test aggregate와 직접 순위 비교하지 않도록 partition scope를 metadata로 기록했다.
- 주요 결과: image holdout ΔE2000은 identity/V2/retrieval/interpolation `27.454878/12.986429/
  10.205129/10.699539`; LUT holdout은 `29.911996/15.084822/16.042751/15.224448`, MVP validation은
  `23.752600`이다. family holdout은 identity/retrieval/interpolation `28.179399/16.390286/14.062808`이다.
- 배운 점: image holdout에서 seen-LUT retrieval이 강하고, family contract에서도 interpolation이
  retrieval보다 낫다. MVP는 family/image contract에서 아직 평가 가능한 checkpoint가 없으며,
  기존 LUT-holdout checkpoint를 재사용해 수치를 채우면 family leakage-safe claim이 무효가 된다.
- 산출물: `reports/baselines/family_identity_baseline_report.json`,
  `reports/baselines/family_retrieval_baseline_report.json`,
  `reports/baselines/conditional_generation_comparison_report.json`.

#### MVP-TRAJECTORY-CONTROL-001

- 상태: pipeline/measurement 성공, 성능 성공 아님
- 날짜: 2026-07-29
- 목적: decoder attenuation이 어느 epoch에서 발생하는지 확인하기 위해 existing identity-logit MVP를
  같은 LUT-holdout split, seed, batch 32, LR `0.0002/0.00001`, frozen BN, paired Style Consistency로
  2 epoch 실행하고 validation 전체의 latent/residual/output variance를 매 epoch 저장한다.
- artifact 보존: 기존 control/ablation checkpoint와 report를 덮어쓰지 않고
  `conditional_lut_mvp-trajectory-control-001.pt` 및 ID별 report를 새로 생성했다.
- epoch trajectory: epoch 1→2에서 validation output variance `0.0001234 → 0.0009192`, decoder
  residual-logit variance `0.003619 → 0.044618`, Style Code variance `0.013891 → 0.016615`로 늘었다.
  따라서 decoder는 학습이 진행되며 latent difference를 LUT output으로 더 전달한다.
- final validation: total `0.870167 → 0.858830`; overall/observed/unobserved ΔE2000
  `23.268994/20.477846/23.489785`; output variance retention `0.017690` (1.769%); neighbor smoothness
  `0.086053`; raw OOG node ratio `0.0`. 1-epoch control의 ΔE `23.752600`, retention `0.002260`보다
  좋아졌지만 V2 LUT-holdout `15.084822` 및 interpolation `15.224448`보다 아직 현저히 낮다.
- 배운 점: 초기 zero-head gradient 단절만으로 전체 실패를 설명할 수 없다. 더 긴 동일-control run이
  diversity를 일부 회복시키는 증거는 있으나 2 epoch는 early trajectory일 뿐 최종 수렴 또는 성공이 아니다.
  다음 ablation은 capacity 또는 optimizer schedule 중 하나만 바꾸고 이 trajectory를 재현해야 한다.
- 산출물: `reports/mvp/mvp-trajectory-control-001_train_report.json`,
  `reports/mvp/mvp-trajectory-control-001_validation_report.json`,
  `reports/mvp/mvp-trajectory-control-001_bottleneck_report.json`.

#### COMPARISON-REPORT-002

- 상태: 성공
- 날짜: 2026-07-29
- 목적: COMPARISON-REPORT-001을 보존한 채 MVP-TRAJECTORY-CONTROL-001 validation 결과를 같은 schema에
  추가한다.
- 결과/제약: LUT-holdout MVP cell은 ΔE2000 `23.268994` validation-only로 갱신했다. image/family MVP와
  family V2 PCA는 대응하는 isolation-trained checkpoint가 없으므로 계속 `not_run`이다.
- 산출물: `reports/baselines/conditional_generation_comparison_report_002.json`.

#### MVP-DECODER-CAPACITY-001

- 상태: 개선 성공, baseline 근접 성공 아님
- 날짜: 2026-07-30
- 목적: MVP-TRAJECTORY-CONTROL-001에서 latent variance가 decoder output으로 일부 전달됨을 확인한 뒤,
  decoder capacity가 residual/output diversity 및 LUT-holdout accuracy를 개선하는지 하나의 변경만으로 검증한다.
- 변경: identity-logit output mode, seed `20260729`, LUT-holdout split, 2 epoch, batch 32, decoder/encoder
  LR `0.0002/0.00001`, loss weights, frozen BN, paired Style Consistency, trajectory instrumentation을 고정하고
  decoder trunk width만 `512 → 1024`로 확장했다.
- 결과: validation total `0.849724`; overall/observed/unobserved ΔE2000 `20.497773/16.522520/20.812231`,
  RGB RMSE `0.224211`, output variance retention `0.126312` (12.631%), smoothness neighbor L2 `0.069122`,
  raw OOG node ratio `0.0`이다. 512-width control 대비 ΔE는 `23.268994 → 20.497773`, output variance는
  `0.000919 → 0.006704`, residual-logit variance는 `0.044618 → 0.216863`로 개선됐다.
- 판단: capacity는 현재 병목에 실제로 기여한다. 그러나 V2 PCA `15.084822` 및 interpolation `15.224448`
  대비 각각 `5.413`/`5.273` ΔE 차이가 남아 있으므로 baseline 근접 또는 프로젝트 성공으로 표기하지 않는다.
  다음은 width를 더 올리는 sweep이 아니라 optimizer schedule 또는 encoder LR 중 하나만 바꾼 같은 2-epoch
  controlled run으로 결정한다.
- 산출물: `checkpoints/conditional_lut_mvp-decoder-capacity-001.pt`,
  `reports/mvp/mvp-decoder-capacity-001_train_report.json`,
  `reports/mvp/mvp-decoder-capacity-001_validation_report.json`,
  `reports/mvp/mvp-decoder-capacity-001_bottleneck_report.json`.

#### COMPARISON-REPORT-003

- 상태: 성공
- 날짜: 2026-07-30
- 목적: COMPARISON-REPORT-001/002를 보존한 채 MVP-DECODER-CAPACITY-001을 current LUT-holdout MVP
  validation entry로 반영한다.
- 결과/제약: MVP LUT-holdout validation ΔE2000은 `20.497773`으로 갱신됐다. MVP image/family 및 family
  V2 PCA는 isolation-trained checkpoint가 없으므로 계속 `not_run`으로 유지했다.
- 산출물: `reports/baselines/conditional_generation_comparison_report_003.json`.

#### MVP-ENCODER-LR-001

- 상태: 개선 성공, baseline 근접 성공 아님
- 날짜: 2026-07-30
- 목적: capacity 개선 이후 Style Encoder가 color-cube supervision에 더 빠르게 적응해야 하는지를
  1024-width MVP에서 encoder learning rate 하나만 변경해 검증한다.
- 변경: decoder width 1024, identity-logit output, seed, split, batch 32, 2 epoch, decoder LR `0.0002`,
  losses, frozen BN, paired Style Consistency, trajectory instrumentation을 고정하고 encoder LR만
  `0.00001 → 0.00005`로 변경했다.
- 결과: validation total `0.794094`; overall/observed/unobserved ΔE2000 `19.655976/14.231916/20.085041`,
  RGB RMSE `0.209510`, output variance retention `0.247939` (24.794%), smoothness `0.065131`, raw OOG
  node ratio `0.0`이다. capacity control 대비 output variance `0.006704 → 0.010978`, Style Code variance
  `0.017244 → 0.031441`가 증가하며 ΔE도 개선됐다.
- 판단: encoder LR `5e-5`는 2-epoch early convergence에 유효하다. 그러나 interpolation `15.224448`과
  `4.432` ΔE, V2 `15.084822`와 `4.571` ΔE 차이가 남아 baseline 근접을 확인하지 못했다. 다음은 width나
  encoder LR을 더 sweep하지 않고 LR schedule 하나만 바꾼 control로 진행한다.
- 산출물: `checkpoints/conditional_lut_mvp-encoder-lr-001.pt`,
  `reports/mvp/mvp-encoder-lr-001_train_report.json`,
  `reports/mvp/mvp-encoder-lr-001_validation_report.json`,
  `reports/mvp/mvp-encoder-lr-001_bottleneck_report.json`.

#### COMPARISON-REPORT-004

- 상태: 성공
- 날짜: 2026-07-30
- 목적: 이전 comparison artifact를 보존한 채 MVP-ENCODER-LR-001을 current LUT-holdout MVP validation
  entry로 반영한다.
- 결과/제약: MVP LUT-holdout validation ΔE2000은 `19.655976`으로 갱신됐다. MVP image/family 및 family
  V2 PCA는 corresponding isolation-trained checkpoint가 없으므로 계속 `not_run`으로 유지했다.
- 산출물: `reports/baselines/conditional_generation_comparison_report_004.json`.

#### MVP-COSINE-SCHEDULE-001

- 상태: 실패, artifact 보존
- 날짜: 2026-07-30
- 목적: current best 1024-width + encoder LR `5e-5` 설정에서 optimizer schedule 하나만 추가했을 때
  2-epoch convergence와 LUT output diversity가 개선되는지 검증한다.
- 변경: 모든 model/data/loss/seed/batch/LR initial value를 MVP-ENCODER-LR-001과 고정하고, validation
  뒤 epoch-level `CosineAnnealingLR(T_max=2, eta_min=0)`만 적용했다. epoch 2 LR은 encoder/decoder
  `5e-5/2e-4 → 2.5e-5/1e-4`였다.
- 결과: overall/observed/unobserved ΔE2000 `21.158486/18.551458/21.364713`, output variance retention
  `0.128126` (12.813%), smoothness `0.088547`, raw OOG node ratio `0.0`이다. fixed-LR control의
  `19.655976/14.231916/20.085041`, retention `0.247939`, smoothness `0.065131`보다 모두 나빴다.
- 배운 점: 이 짧은 2-epoch budget에서 cosine decay는 유효한 output diversity가 형성되기 전에 LR을
  낮춘다. 이후 fixed LR control에 cosine을 다시 적용하지 않고, longer fixed-LR trajectory로 수렴 여부를
  분리한다.
- 산출물: `checkpoints/conditional_lut_mvp-cosine-schedule-001.pt`,
  `reports/mvp/mvp-cosine-schedule-001_train_report.json`,
  `reports/mvp/mvp-cosine-schedule-001_validation_report.json`,
  `reports/mvp/mvp-cosine-schedule-001_bottleneck_report.json`.

#### MVP-FIXED-LR-4EPOCH-001

- 상태: 개선 성공, baseline 근접 성공 아님
- 날짜: 2026-07-30
- 목적: current best 1024-width fixed-LR configuration의 2-epoch early improvement가 지속되는지
  decoder capacity, optimizer, loss, data, seed를 바꾸지 않고 4 epoch trajectory로 확인한다.
- 설정: decoder width 1024, identity-logit output, decoder/encoder LR `0.0002/0.00005`, schedule none,
  batch 32, frozen BN, paired Style Consistency, seed `20260729`.
- trajectory: validation total은 epoch 1~4에서 `0.840946/0.794094/0.783521/0.777358`로 계속 감소했다.
  output variance는 epoch 2/4 `0.010978/0.010930`, residual-logit variance `0.286746/0.286804`로 사실상
  포화됐지만 Style Code variance는 `0.031441 → 0.045679`로 계속 커졌다.
- final validation: overall/observed/unobserved ΔE2000 `18.867267/13.541782/19.288534`, RGB RMSE
  `0.197675`, output variance retention `0.254476` (25.448%), smoothness `0.051466`, raw OOG node ratio
  `0.0`이다. 2-epoch fixed LR 대비 ΔE와 smoothness는 개선됐으나 interpolation `15.224448`과 `3.643`,
  V2 `15.084822`와 `3.782` ΔE 차이가 남는다.
- 판단: 단순 epoch 증가가 여전히 개선을 만들지만 output diversity는 이미 epoch 2 후 포화돼 있다.
  더 긴 동일 run을 먼저 늘리기보다, Style Consistency가 latent variance를 decoder-relevant style signal로
  바꾸는지 weight 하나만 바꾼 4-epoch ablation으로 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-fixed-lr-4epoch-001.pt`,
  `reports/mvp/mvp-fixed-lr-4epoch-001_train_report.json`,
  `reports/mvp/mvp-fixed-lr-4epoch-001_validation_report.json`,
  `reports/mvp/mvp-fixed-lr-4epoch-001_bottleneck_report.json`.

#### COMPARISON-REPORT-005

- 상태: 성공
- 날짜: 2026-07-30
- 목적: previous comparison artifacts를 보존한 채 MVP-FIXED-LR-4EPOCH-001을 current LUT-holdout
  MVP validation entry로 반영한다.
- 결과/제약: MVP LUT-holdout validation ΔE2000은 `18.867267`으로 갱신됐다. MVP image/family 및 family
  V2 PCA는 corresponding isolation-trained checkpoint가 없으므로 계속 `not_run`으로 유지했다.
- 산출물: `reports/baselines/conditional_generation_comparison_report_005.json`.

#### PROTOCOL-AUDIT-001

- 상태: 감사 완료, 기존 결과 해석 정정 필요
- 날짜: 2026-07-30
- 목적: repeated one-factor ablation이 실제 모델 개선을 측정하는지, sampler coverage, validation
  population, checkpoint selection metric, baseline partition, LUT weighting을 독립적으로 점검한다.
- sampler 결과: 기존 `SourcePairBatchSampler`는 seed를 epoch마다 재사용해 train 2,316건 중
  1,239건(53.5%), validation 343건 중 172건(50.1%)만 선택하고 매 epoch 정확히 같은 subset을
  반복했다. 4 epoch는 전체 dataset을 네 번 본 것이 아니다.
- checkpoint 결과: MVP-FIXED-LR-4EPOCH-001 마지막 validation total `0.777358` 중 weighted Style
  term이 약 97.6%를 차지해 best checkpoint가 Color Cube accuracy보다 Style contrastive objective에
  의해 주로 선택됐다.
- comparison 결과: 기존 MVP headline은 validation 343건인데 V2/interpolation headline은
  validation+test 684건이었다. strict validation-only 재계산 결과 sample-weighted overall/observed/
  unobserved ΔE는 V2 `17.191645/15.035029/17.362242`, interpolation
  `17.877367/16.186347/18.011134`, MVP `18.867267/13.541782/19.288534`다.
- 해석 정정: MVP는 interpolation보다 3.64 ΔE 뒤가 아니라 동일 validation에서 0.99 뒤다. Observed
  color는 이미 V2/interpolation보다 좋고, 핵심 병목은 unobserved color와 app/crawled group이다.
- LUT weighting: validation은 crawled 1, app 3, canon 8 LUT이고 sample 수가 매우 불균등하다.
  unique-LUT macro ΔE는 V2/interpolation/MVP `14.890254/14.347211/14.807959`다. Sample-weighted와
  LUT-macro를 모두 보고해야 하며 하나로 대체하지 않는다.
- 다음 조치: 기존 checkpoint accuracy evaluation은 보존하되 training protocol 결과로는 pre-fix
  reference로만 사용한다. sampler/validation/checkpoint contract를 수정한 뒤 current best를 재학습한다.

#### MVP-PROTOCOL-CORRECTED-CONTROL-001

- 상태: 완료, full-coverage protocol의 현재 control
- 날짜: 2026-07-30
- 설정: decoder width `1024`, identity-logit output, decoder/encoder LR `2e-4/5e-5`, fixed LR,
  batch `32`, seed `20260729`, Style weight `0.25`, 4 epoch. 기존 artifact와 별도 이름을 사용했다.
- protocol: 매 epoch train 2,316건 coverage `100%`(odd group repeat 34건), validation accuracy 343건,
  Style monitor 12 LUT/24 scene, sample-weighted Cube Smooth L1 checkpoint selection을 사용했다.
- trajectory: epoch 1~4 validation cube loss `0.040649/0.026392/0.024433/0.022109`; Style separation
  `0.086902/0.051934/0.057573/0.077196`으로 guardrail을 매 epoch 통과했다.
- 결과: sample-weighted overall/observed/unobserved ΔE `19.590483/14.232485/20.014322`, RGB RMSE
  `0.210279`, LUT-macro ΔE `15.341602/13.024376/15.353852`다. raw OOG node/value ratio는 모두 `0`이다.
- 비교: V2/interpolation sample ΔE `17.191645/17.877367`보다 각각 `2.40/1.71` 높다. source group
  ΔE는 canon/app/crawled `12.339338/20.443181/23.951582`로 app/crawled가 주된 병목이다.
- 해석: cube loss의 지속 하락과 Style guardrail 통과만으로 perceptual ΔE 일반화가 보장되지는 않는다.
  pre-fix MVP `18.867267`보다도 `0.72` 악화되어, 이전 sampler subset 반복이 낙관적 결과를 만들었을
  가능성을 확인했다. protocol 수정 자체의 실패로 해석하지 않는다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-corrected-control-001.pt`,
  `reports/mvp/mvp-protocol-corrected-control-001_train_report.json`,
  `reports/mvp/mvp-protocol-corrected-control-001_validation_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_002.json`.

#### MVP-PROTOCOL-STYLE-WEIGHT-010-001

- 상태: 실패, controlled ablation 기록 보존
- 날짜: 2026-07-30
- 설정: corrected control과 data split, seed `20260729`, batch `32`, decoder width `1024`,
  decoder/encoder LR `2e-4/5e-5`, fixed LR, 4 epoch를 동일하게 두고 Style weight만 `0.25 → 0.10`으로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. validation
  cube loss는 `0.040134/0.025614/0.024058/0.022474`, Style separation은
  `0.068528/0.055001/0.057998/0.081229`로 guardrail을 통과했다.
- 결과: sample overall/observed/unobserved ΔE `19.684234/14.360850/20.105335`, LUT-macro ΔE
  `15.385093/13.089679/15.395606`으로 corrected control `19.590483/14.232485/20.014322`보다 모두 악화했다.
  source group ΔE는 canon/app/crawled `12.367760/20.470519/24.137474`다.
- bottleneck 비교: output-variance retention `24.73% → 24.59%`, decoder residual-logit variance
  `0.330033 → 0.340067`, Style Code variance `0.037267 → 0.047459`이다. latent 변화가 output LUT
  다양성으로 충분히 전달되지 않는다는 해석을 지지한다.
- 판단: Style weight를 더 낮추는 방향은 중단한다. corrected control weight `0.25`를 current best로
  복구하고 decoder capacity만 다음 단일 변경으로 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-style-weight-010-001.pt`,
  `reports/mvp/mvp-protocol-style-weight-010-001_train_report.json`,
  `reports/mvp/mvp-protocol-style-weight-010-001_validation_report.json`,
  `reports/mvp/mvp-protocol-style-weight-010-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_003.json`.

#### MVP-PROTOCOL-DECODER-CAPACITY-2048-001

- 상태: 실패, controlled ablation 기록 보존
- 날짜: 2026-07-30
- 설정: corrected control과 data split, seed, batch `32`, decoder/encoder LR `2e-4/5e-5`, Style weight
  `0.25`, fixed LR, 4 epoch를 동일하게 두고 decoder hidden width만 `1024 → 2048`로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. validation
  cube loss는 `0.032211/0.024745/0.024303/0.023001`, Style separation은
  `0.087428/0.052196/0.057330/0.079173`으로 guardrail을 통과했다.
- 결과: sample overall/observed/unobserved ΔE `20.005080/14.582842/20.434001`, LUT-macro ΔE
  `15.656757`로 corrected control `19.590483/15.341602`보다 악화했다. source group ΔE는
  canon/app/crawled `12.756626/20.314498/24.751849`다.
- bottleneck: output-variance retention `23.97%`는 control `24.73%`보다 낮고, decoder residual-logit
  variance `0.380384`는 control `0.330033`보다 높다. width 증가가 output diversity나 ΔE 개선으로
  연결되지 않았다.
- 판단: width `2048`은 current best가 아니다. width `1024`, Style weight `0.25`로 되돌리고 epoch
  budget만 `4 → 8`로 바꿔 corrected trajectory의 추가 개선 여부를 분리 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-decoder-capacity-2048-001.pt`,
  `reports/mvp/mvp-protocol-decoder-capacity-2048-001_train_report.json`,
  `reports/mvp/mvp-protocol-decoder-capacity-2048-001_validation_report.json`,
  `reports/mvp/mvp-protocol-decoder-capacity-2048-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_004.json`.

#### MVP-PROTOCOL-LONG-TRAJECTORY-8EPOCH-001

- 상태: 성공, current corrected MVP best
- 날짜: 2026-07-30
- 설정: corrected 4-epoch control과 data split, seed, batch `32`, decoder width `1024`,
  decoder/encoder LR `2e-4/5e-5`, Style weight `0.25`, fixed LR를 동일하게 두고 epoch budget만 `4 → 8`로 변경했다.
- 재현성: epoch 1~4의 validation cube loss와 Style separation은 4-epoch control과 정확히 일치했다.
  epoch 5~8 cube loss는 `0.022980/0.022461/0.022006/0.021192`; epoch 8 separation은 `0.096669`다.
- 결과: sample overall/observed/unobserved ΔE `19.146559/14.396729/19.522290`, LUT-macro `14.991621`이다.
  4-epoch control 대비 sample ΔE `-0.443924`, unobserved `-0.492033`, LUT-macro `-0.349981` 개선이나,
  observed는 `+0.164244` 악화했다. source group ΔE는 canon/app/crawled `11.671339/21.209529/22.797949`다.
- bottleneck: output-variance retention `27.28%`는 4-epoch control `24.73%`보다 높고, decoder residual-logit
  variance도 `0.330033 → 0.496094`로 증가했다. 더 긴 학습이 LUT 다양성과 unobserved 성능 개선으로 이어졌다.
- 비교: interpolation/V2 sample ΔE `17.877367/17.191645`보다 각각 `1.269192/1.954915` 높다. MVP는
  retrieval `19.018418`보다도 `0.128141` 높아 아직 baseline을 이기지 못했다.
- 판단: 8 epoch를 current best로 채택한다. 다음에는 duration/architecture를 고정하고 image loss weight만
  `0.25 → 0.10`으로 줄여 observed-image supervision과 full-cube/unobserved generalization의 tradeoff를 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-long-trajectory-8epoch-001.pt`,
  `reports/mvp/mvp-protocol-long-trajectory-8epoch-001_train_report.json`,
  `reports/mvp/mvp-protocol-long-trajectory-8epoch-001_validation_report.json`,
  `reports/mvp/mvp-protocol-long-trajectory-8epoch-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_005.json`.

#### MVP-PROTOCOL-IMAGE-WEIGHT-010-001

- 상태: 성공, current corrected MVP best
- 날짜: 2026-07-30
- 설정: corrected 8-epoch control과 data split, seed, batch `32`, decoder width `1024`, decoder/encoder
  LR `2e-4/5e-5`, Style weight `0.25`, fixed LR를 동일하게 두고 image loss weight만 `0.25 → 0.10`으로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. final
  validation cube loss `0.021109`, Style separation `0.096814`이며 raw OOG node/value ratio는 `0`이다.
- 결과: sample overall/observed/unobserved ΔE `19.104012/14.327751/19.481833`, LUT-macro `14.948234`다.
  8-epoch control 대비 각각 `-0.042547/-0.068978/-0.040456/-0.043387`로 모두 소폭 개선했다.
  source group ΔE도 canon/app/crawled `11.624480/21.173604/22.753633`으로 모두 개선했다.
- bottleneck: variance retention `27.11%`은 control `27.28%`과 사실상 동등하고, decoder residual-logit
  variance `0.485189`도 control `0.496094`와 유사하다. 개선은 output diversity 증가보다 loss tradeoff에서 왔다.
- 비교: interpolation/V2 sample ΔE `17.877367/17.191645`보다 각각 `1.226645/1.912367` 높다.
- 판단: image weight `0.10`을 current best로 채택한다. 다음에는 이 설정을 고정하고 weight를 `0.00`으로
  낮춰 image supervision이 완전히 불필요한지 경계 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-image-weight-010-001.pt`,
  `reports/mvp/mvp-protocol-image-weight-010-001_train_report.json`,
  `reports/mvp/mvp-protocol-image-weight-010-001_validation_report.json`,
  `reports/mvp/mvp-protocol-image-weight-010-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_006.json`.

#### MVP-PROTOCOL-IMAGE-WEIGHT-000-001

- 상태: 성공, current corrected MVP best
- 날짜: 2026-07-30
- 설정: image-0.10 control과 data split, seed, batch `32`, decoder width `1024`, decoder/encoder
  LR `2e-4/5e-5`, Style weight `0.25`, smoothness weight `0.01`, fixed 8 epoch를 동일하게 두고
  image loss weight만 `0.10 → 0.00`으로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. final
  validation cube loss `0.021067`, Style separation `0.096812`, raw OOG node/value ratio `0`이다.
- 결과: sample overall/observed/unobserved ΔE `19.076099/14.302511/19.453709`, LUT-macro `14.923894`다.
  image-0.10 대비 각각 `-0.027913/-0.025240/-0.028124/-0.024340`로 모두 소폭 개선했다.
  source group ΔE도 canon/app/crawled `11.609484/21.120881/22.734565`으로 모두 개선했다.
- bottleneck: variance retention `27.00%`, decoder residual-logit variance `0.478469`, Style Code variance
  `0.045305`로 image-0.10과 실질적으로 동등하다. 성능 개선은 diversity가 아니라 image loss 제거로
  cube objective 충돌이 줄어든 결과로 해석한다.
- 비교: interpolation/V2 sample ΔE `17.877367/17.191645`보다 각각 `1.198732/1.884454` 높다.
- 판단: image loss는 이 contract에서 불필요하다. weight `0.00`을 current best로 고정하고 target보다
  높은 prediction grid roughness를 줄이기 위해 smoothness weight만 `0.01 → 0.02`로 올린다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-image-weight-000-001.pt`,
  `reports/mvp/mvp-protocol-image-weight-000-001_train_report.json`,
  `reports/mvp/mvp-protocol-image-weight-000-001_validation_report.json`,
  `reports/mvp/mvp-protocol-image-weight-000-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_007.json`.

#### MVP-PROTOCOL-SMOOTHNESS-WEIGHT-020-001

- 상태: 성공, current corrected MVP best
- 날짜: 2026-07-30
- 설정: cube-only current best와 data split, seed, batch `32`, decoder width `1024`, decoder/encoder
  LR `2e-4/5e-5`, Style weight `0.25`, image weight `0.00`, fixed 8 epoch를 동일하게 두고 smoothness
  weight만 `0.01 → 0.02`로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. final
  validation cube loss `0.021056`, Style separation `0.096710`, raw OOG node/value ratio `0`이다.
- 결과: sample overall/observed/unobserved ΔE `19.073146/14.294989/19.451118`, LUT-macro `14.921591`이다.
  cube-only control 대비 각각 `-0.002953/-0.007523/-0.002592/-0.002303`로 작지만 모두 개선했다.
  app/crawled ΔE도 `-0.010177/-0.000086` 개선했으며 canon은 `+0.000383`으로 사실상 동등하다.
- smoothness/variance: prediction neighbor-L2 mean `0.047963 → 0.047900`, variance retention
  `27.00% → 26.98%`로 diversity 손실 없이 grid roughness가 소폭 감소했다.
- 비교: interpolation/V2 sample ΔE `17.877367/17.191645`보다 각각 `1.195779/1.881501` 높다.
- 판단: smoothness weight `0.02`를 current best로 채택한다. 다음에는 같은 조건에서 `0.04`를 확인해
  추가 이득인지 과도한 평균화 경계인지 검증한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-smoothness-weight-020-001.pt`,
  `reports/mvp/mvp-protocol-smoothness-weight-020-001_train_report.json`,
  `reports/mvp/mvp-protocol-smoothness-weight-020-001_validation_report.json`,
  `reports/mvp/mvp-protocol-smoothness-weight-020-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_008.json`.

#### MVP-PROTOCOL-SMOOTHNESS-WEIGHT-040-001

- 상태: 성공, single-seed current best; replication 필요
- 날짜: 2026-07-30
- 설정: smoothness-0.02 control과 data split, seed, batch `32`, decoder width `1024`, decoder/encoder
  LR `2e-4/5e-5`, Style weight `0.25`, image weight `0.00`, fixed 8 epoch를 동일하게 두고 smoothness
  weight만 `0.02 → 0.04`로 변경했다.
- protocol: 모든 epoch train coverage `100%`, validation 343건, Style monitor 24건을 유지했다. final
  validation cube loss `0.021053`, Style separation `0.096855`, raw OOG node/value ratio `0`이다.
- 결과: sample overall/observed/unobserved ΔE `19.072239/14.290575/19.450488`, LUT-macro `14.920012`다.
  smoothness-0.02 대비 sample ΔE `-0.000907`, LUT-macro `-0.001579`, roughness
  `0.047900 → 0.047846`로 모두 개선했지만 crawled ΔE는 `+0.000877` 악화했다.
- bottleneck: variance retention `27.02%`, decoder residual-logit variance `0.478030`으로 control과
  동등하다. 강한 smoothness가 output diversity를 아직 낮추지 않았지만 효과 크기는 실질적으로 미세하다.
- 비교: interpolation/V2 sample ΔE `17.877367/17.191645`보다 각각 `1.194872/1.880594` 높다.
- 판단: single seed에서는 `0.04`가 current best지만, `.02 → .04` 이득은 seed noise와 구분할 수 없다.
  더 높은 weight sweep은 중단하고 `.01`과 `.04` 후보를 새 2개 seed에서 replication한다.
- 산출물: `checkpoints/conditional_lut_mvp-protocol-smoothness-weight-040-001.pt`,
  `reports/mvp/mvp-protocol-smoothness-weight-040-001_train_report.json`,
  `reports/mvp/mvp-protocol-smoothness-weight-040-001_validation_report.json`,
  `reports/mvp/mvp-protocol-smoothness-weight-040-001_bottleneck_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_009.json`.

#### MVP-SMOOTHNESS-MULTISEED-REPLICATION-001

- 상태: 완료, practical tie; smoothness weight `0.01` 선택
- 날짜: 2026-07-30
- 설정: corrected cube-only 8-epoch protocol(17³ bounded LUT, decoder/encoder LR `2e-4/5e-5`,
  decoder width `1024`, Style weight `0.25`, image weight `0.00`, full-coverage sampler, full 343-sample
  validation)을 고정했다. 기존 paired seed `20260729`와 새 paired seeds `20260730`, `20260731`에서
  smoothness weight `0.01`과 `0.04`를 각각 비교했다.
- 결과: 후보별 3-seed 평균 sample ΔE는 `.01/.04 = 19.385865/19.375206`, LUT-macro는
  `15.106130/15.103536`, roughness는 `0.048929/0.048677`, variance retention은
  `23.025%/22.905%`다. `.04 − .01` paired 차이는 seed `20260729/30/31`에서 sample ΔE
  `-0.003860/-0.008273/-0.019843`, LUT-macro `-0.003882/+0.011049/-0.014949`였다.
- 판단: `.04`는 모든 seed에서 roughness를 낮췄지만, seed `20260730`에서 LUT-macro ΔE가 악화했다.
  완료 조건(모든 paired seed에서 sample 및 LUT-macro ΔE 개선)을 충족하지 못했으므로 mean의 미세한
  이득을 robust improvement로 해석하지 않는다. 더 낮은 regularization인 `.01`을 선택하고 이 sweep을
  종료한다.
- 산출물: 새 4개 checkpoint/train/validation report,
  `reports/mvp/mvp-repl-smooth-{010,040}-seed-{20260730,20260731}-001_bottleneck_report.json`,
  `26_build_smoothness_replication_report.py`,
  `reports/baselines/smoothness_multiseed_replication_report_001.json`.

#### MVP-FAMILY-HOLDOUT-SMOOTH-010-001 / V2-FAMILY-HOLDOUT-001 / FAMILY-HOLDOUT-COMPARISON-001

- 상태: 완료; V2를 포함한 valid family comparison
- 날짜: 2026-07-31
- contract: `LUT-FAMILY-HOLDOUT-001`의 clamped 17³ LUT-output RMSE connected-component family split을
  사용했다. 66개 family를 `52/7/7` train/validation/test로 나누고, train/validation은 source LUT와
  family가 각각 `0`개 교차함을 재확인했다. MVP는 selected smoothness `.01` corrected protocol로 train
  `2,024`건에서 8 epoch 학습했고 validation `274`건으로 checkpoint를 선택했다. family test `702`건은
  model selection에 사용하지 않았다.
- MVP 결과: validation sample/observed/unobserved/LUT-macro ΔE는
  `13.571087/13.647738/13.559699/13.605198`, test는
  `12.929904/11.116733/13.098755/14.001296`이다. final checkpoint는 epoch 7 full-validation Cube loss
  `0.019637`, Style separation `0.195480`로 선택됐고, family split path가 checkpoint와 evaluation report에
  기록된다.
- 비교: leakage-safe top-3 interpolation은 validation/test sample ΔE `14.912828/13.731034`, LUT-macro
  `13.590520/14.779698`이다. MVP는 test에서 sample/LUT-macro `-0.801130/-0.778402`로 이겼다. validation
  sample도 `-1.341742` 개선했지만 LUT-macro는 `+0.014679`으로 사실상 동률이다. Identity와 retrieval도
  MVP보다 모두 높다.
- V2 재학습: `11_train_basis_v2.py`에 explicit split과 artifact-path parameterization을 추가했다. 12개
  PCA basis는 train `94` source LUT에서만 fit했고 predictor는 validation `10` source LUT로 checkpoint를
  선택했다. train/validation/test source-LUT overlap은 모두 `0`이며 test `15` source LUT/`702`건은 fit,
  update, model selection에 사용하지 않았다. epoch 27 early stopping, best epoch 12 validation loss
  `1.643806`으로 종료했다.
- V2 결과: validation/test sample ΔE `15.662410/16.431086`, LUT-macro `16.340682/17.111657`이다. MVP는
  validation에서 sample/LUT-macro `-2.091323/-2.735484`, test에서 `-3.501182/-3.110361`로 더 낮다.
  따라서 이 family contract에서는 MVP가 V2보다 우수하다고 결론낼 수 있다.
- 산출물: `checkpoints/conditional_lut_mvp-family-holdout-smooth-010-001.pt`,
  `reports/mvp/mvp-family-holdout-smooth-010-001_{train,validation,test}_report.json`,
  `reports/mvp/mvp-family-holdout-smooth-010-001_{validation,test}_bottleneck_report.json`,
  `reports/baselines/family_{identity,retrieval}_{validation,test}_baseline_report.json`,
  `checkpoints/basis_v2_family_holdout_001.{npz,pt,report.json}`,
  `reports/baselines/family_v2_{validation,test}_baseline_report.json`,
  `27_build_family_holdout_comparison_report.py`,
  `reports/baselines/family_holdout_generation_comparison_report_001.json`.

#### TONE-CURVE-TARGET-AUDIT-001

- 상태: 완료; Tone Curve를 첫 구조화 decoder 모듈로 채택
- 날짜: 2026-07-31
- 방법: family split의 각 unique target LUT에서 neutral diagonal을 읽어 (a) chroma-preserving
  luminance Tone Curve와 (b) channel-separable neutral-diagonal curve를 구성하고, full 17³ target grid에
  대해 identity 대비 잔차를 측정했다. 이 감사는 target-only이며 checkpoint 선택이나 test tuning을 하지
  않는다.
- 결과: validation 10 LUT에서 identity RGB RMSE `0.400061` 대비 luminance Tone Curve는 `0.359403`,
  MSE variation explained `18.0887%`였고 test 15 LUT에서도 `17.8315%`였다. channel-separable curve는
  validation `10.7586%`로 더 낮아 neutral-luminance curve보다 hue shift를 잘 설명하지 못했다.
- 판단: validation threshold `10%`를 넘고 test에서도 방향이 유지되므로 first module은 monotone,
  chroma-preserving Tone Curve로 한다. 다만 약 `82%`의 variation이 남으므로 Tone Curve-only를 최종
  구조로 주장하지 않으며, 다음 단계에서 Hue Anchor/Palette residual의 필요성을 별도 검증한다.
- 산출물: `28_audit_tone_curve_targets.py`,
  `reports/baselines/tone_curve_target_audit_001.json`.

#### MVP-FAMILY-TONE-CURVE-001

- 상태: 완료, failure preserved; Tone Curve-only를 final structured decoder로 채택하지 않음
- 날짜: 2026-07-31
- 설정: direct MVP의 full-coverage sampler, family train/validation/test split, batch `32`, encoder/decoder
  LR `5e-5/2e-4`, decoder width `1024`, Style weight `0.25`, cube-only 8 epoch protocol을 유지했다.
  decoder 출력만 17개 positive increment를 누적·정규화한 monotone luminance curve로 바꾸고, identity grid를
  mapped/input luminance 비율로 scale했다. Hue-specific residual은 의도적으로 제거했다.
- 학습: validation Cube loss는 epoch 1~7 `0.085343 → 0.081507`로 감소했고 Style separation은 매 epoch
  양수였다. epoch 7을 best checkpoint로 선택했다.
- 결과: validation sample/observed/unobserved/LUT-macro ΔE는
  `30.793185/33.110980/30.448839/28.407953`, test는
  `26.891850/27.034681/26.878549/26.666807`이다. direct MVP test `12.929904/14.001296`보다 크게 나쁘고,
  identity test sample `26.788340`보다도 `+0.103511` 높다. OOG node ratio는 `0`이지만 generated 3D LUT의
  luminance monotonicity violation은 validation/test `3.6707%/0.1381%`로 zero가 아니다.
- 판단: target-level tone explanation `18.09%`는 Tone Curve-only conditional inference의 충분조건이
  아니었다. clipping된 chroma-preserving scale은 3D safety도 완전히 보장하지 않는다. 다음 구조 변화는
  Tone Curve weight sweep이 아니라 Hue Anchor residual target audit으로 제한한다.
- 산출물: `checkpoints/conditional_lut_mvp-family-tone-curve-001.pt`,
  `reports/mvp/mvp-family-tone-curve-001_{train,validation,test}_report.json`,
  updated `reports/baselines/family_holdout_generation_comparison_report_001.json`.

#### HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001

- 상태: 완료; 6-anchor Hue residual을 다음 structured decoder의 최소 표현으로 채택
- 날짜: 2026-08-03
- 방법: 각 target LUT에서 neutral-luminance Tone Curve를 먼저 빼고, 남은 RGB residual을 input HSV hue의
  circular interpolation anchor로 근사했다. anchor는 `residual ≈ saturation × hue_anchor`의 least-squares로
  fit했고, count `6/12/24/48`을 각 LUT 안에서만 fit·재구성했다. 이는 target-only representation audit이며
  test는 anchor count 선택에 사용하지 않았다.
- 결과: validation residual MSE explained는 6/12/24/48 anchors에서
  `83.3869/87.3499/88.3014/88.5156%`, test는
  `86.8177/90.0907/90.7510/90.8781%`이다. validation 6-anchor reconstruction은 target ΔE `10.363001`,
  48-anchor `8.382640`이지만 6 anchor가 best explanation의 90%를 이미 넘는다.
- 판단: validation-only rule에 따라 best(48)의 90% 이상을 만족하는 최소 count `6`을 선택한다. Hue residual
  자체는 Tone Curve residual의 10% 기준을 훨씬 넘게 설명하므로 다음 모델은 `Tone Curve + 6-anchor Hue
  residual` conditional decoder로 구현한다. 더 많은 anchor는 target-level 소폭 이득에 비해 구조 복잡도가
  커 현재 단계에서 채택하지 않는다.
- 산출물: `29_audit_hue_anchor_residuals.py`,
  `reports/baselines/hue_anchor_residual_target_audit_001.json`.

#### MVP-FAMILY-TONE-HUE-ANCHOR-006-001

- 상태: 완료, failure preserved; un-supervised anchor head를 채택하지 않음
- 날짜: 2026-08-03
- 설정: 17-point positive-increment monotone luminance Tone Curve와 6개 circularly interpolated RGB anchor를
  Style Code에서 예측했다. Hue residual은 input saturation으로 scale하고 `±1.25` bounded anchor 및 final
  clamp를 적용했다. data split, full-coverage sampler, batch `32`, width `1024`, LR `2e-4/5e-5`, Style
  weight `0.25`, cube-only 8 epoch은 direct MVP와 동일하다. curve/anchor에는 별도 target loss를 주지 않았다.
- 학습: validation Cube loss는 epoch 1~4 `0.026441 → 0.021786`으로 개선돼 epoch 4를 checkpoint로 선택했다.
  Style separation은 모든 epoch에서 양수였다.
- 결과: validation sample/observed/unobserved/LUT-macro ΔE는
  `15.601722/16.678152/15.441801/15.985063`, test는
  `15.608163/13.674465/15.788238/17.045819`다. direct MVP test `12.929904/14.001296`보다 sample/LUT-macro
  `+2.678259/+3.044524` 나쁘다. OOG node ratio는 `0`이나 generated LUT luminance monotonicity violation은
  validation/test `17.3511%/9.4052%`로 Tone Curve-only보다도 높다.
- 판단: 6 anchor target audit의 83.39% residual explanation은 cube loss만으로 image-conditioned anchor를
  예측할 수 있다는 보장이 아니다. 다음 run은 architecture·data·optimizer를 고정하고 target LUT에서 직접
  추출한 curve/anchor label supervision만 추가한다. 더 많은 anchor, 더 긴 학습, amplitude sweep은 하지 않는다.
- 산출물: `checkpoints/conditional_lut_mvp-family-tone-hue-anchor-006-001.pt`,
  `reports/mvp/mvp-family-tone-hue-anchor-006-001_{train,validation,test}_report.json`,
  updated `reports/baselines/family_holdout_generation_comparison_report_001.json`.

#### MVP-FAMILY-TONE-HUE-ANCHOR-006-SUP-001

- 상태: 완료, mixed improvement but structured decoder still rejected
- 날짜: 2026-08-03
- 설정: un-supervised 6-anchor decoder와 architecture/data/seed/batch/LR/epoch/sampler/style guardrail을
  모두 고정하고, target LUT에서 추출한 normalized neutral-luminance curve와 bounded 6-anchor label에
  Smooth L1 auxiliary loss weight `0.10`만 추가했다. checkpoint selection은 auxiliary loss가 아닌 full
  validation Cube loss로 유지했다.
- 학습: validation Cube loss best는 epoch 3 `0.022805`로 un-supervised epoch 4 `0.021786`보다 높았다.
  Style separation은 모든 epoch에서 양수였다.
- 결과: validation sample/observed/unobserved/LUT-macro ΔE는
  `16.135138/16.998423/16.006883/15.778334`, test는
  `15.560297/13.470978/15.754864/16.879931`이다. un-supervised 대비 test sample/LUT-macro는
  `-0.047866/-0.165888`, monotonicity는 `9.4052% → 7.1893%`로 개선됐지만 validation sample은
  `+0.533416` 악화했다. direct MVP test `12.929904/14.001296`보다 sample/LUT-macro
  `+2.630392/+2.878635` 높다.
- 판단: structured target labels는 anchor decoder의 test와 safety를 약간 개선하지만 full-LUT generation의
  bottleneck을 해소하지 못한다. anchor count/weight/schedule sweep은 중단하고, 다음에만 direct full-LUT
  MVP의 Style Code를 regularize하는 병렬 auxiliary head로 label을 재사용한다.
- 산출물: `checkpoints/conditional_lut_mvp-family-tone-hue-anchor-006-sup-001.pt`,
  `reports/mvp/mvp-family-tone-hue-anchor-006-sup-001_{train,validation,test}_report.json`,
  updated `reports/baselines/family_holdout_generation_comparison_report_001.json`.

#### PROTOCOL-FIX-001

- 상태: 구현·smoke·corrected-control 학습 완료
- 날짜: 2026-07-30
- 구현:
  - train pair sampler는 각 source LUT scene을 epoch마다 다시 shuffle하고 모든 eligible record를
    최소 한 번 포함한다. smoke에서 train coverage 100%, odd group repeat 34건, epoch pair 변화 확인.
  - accuracy validation은 paired replacement sampler 대신 343건 전체 sequential loader를 사용한다.
    train/validation epoch loss는 마지막 작은 batch가 과대 반영되지 않도록 batch 크기로 가중한
    sample mean으로 집계한다.
  - Style Consistency validation은 12 held-out LUT별 고정 2 scene, 총 24건의 별도 monitor로 분리한다.
  - checkpoint는 full-validation cube Smooth L1 최소값으로 선택하고 positive-negative cosine
    separation `> 0`을 guardrail로 둔다. bounded decoder의 OOG 0 contract는 유지한다.
  - evaluator는 sample-weighted와 unique-LUT macro overall/observed/unobserved metric을 함께 저장한다.
  - retrieval runner는 validation/test partition을 명시적으로 선택할 수 있다.
- smoke: Python compile, train sampler full coverage/epoch variation, validation 343건 coverage, 24-sample
  Style monitor positive/negative metric, 4-sample baseline LUT-macro aggregation 통과.
- 다음 조치: corrected-control의 고정 조건에서 Style Consistency weight만 `0.25 → 0.10`으로 변경한다.

#### COMPARISON-PROTOCOL-001

- 상태: 성공, pre-fix MVP reference
- 날짜: 2026-07-30
- 목적: LUT-holdout validation 343건/12 LUT로 Identity, V2, retrieval, interpolation, MVP partition을
  완전히 맞추고 sample-weighted 및 LUT-macro를 한 schema에 저장한다.
- 결과: sample-weighted ΔE는 identity/V2/retrieval/interpolation/MVP
  `29.933970/17.191645/19.018418/17.877367/18.867267`; LUT-macro는
  `27.279277/14.890254/15.928260/14.347211/14.807959`다.
- 주의: MVP evaluation은 343건 전체라 유효하지만 checkpoint는 PROTOCOL-FIX-001 이전 sampler로
  학습됐다. corrected-control과 비교하기 위한 reference이며 최종 model-selection 결과가 아니다.
- 산출물: `reports/baselines/lut_holdout_validation_baseline_report.json`,
  `reports/baselines/lut_holdout_validation_retrieval_report.json`,
  `reports/mvp/mvp-fixed-lr-4epoch-001_validation_protocol_report.json`,
  `reports/baselines/conditional_generation_validation_comparison_report_001.json`.

#### AXIS-V2-DATASET-001

- 상태: G1/G2 통과; 후속 G3 완료, G4 실패
- 날짜: 2026-08-28
- 데이터: 기존 `data/dataset`을 보존하고 `data/dataset_axis_v2_001`에 seed 42로 3,000쌍 생성.
  source group은 crawled/app/Canon 각 1,000건이고 119개 source LUT를 포함한다.
- 직접 색값 감사: source 및 생성기 SHA-256 전부 일치, float16 양자화 후 저장 오차 `0.0`,
  256색 보간 probe 최대 절대오차 `0.000243604`, 불필요한 R/B 전치의 LUT별 중앙 MAE `0.213623`.
  LUT별 대표 neutral/graded JPEG 119쌍은 생성기 재실행 결과와 byte exact였다.
- 회귀: dataset/evaluator/active V2 baseline loader의 R-fastest 계약을 포함한 Python unit test 5개와
  strict 축 검사가 통과했다. 교정 전 V2 basis/checkpoint는 새 baseline으로 재사용하지 않는다.
- split: train/validation/test record `2,024/274/702`, source LUT `94/10/15`, family leakage 0.
- hue mask: 3,000개, 빈 mask 0, 평균 observed 17³ cube fraction `0.103710`.
- G2 smoke: CPU 2 samples·4 steps에서 total loss `0.042686 → 0.014806`(-65.3%), export 범위
  `[0.00009996, 1.0]`, reload RMSE `0.00009758`. 이는 학습 코드와 gradient의 동작성 증거일 뿐
  validation 또는 제품 품질 개선 증거가 아니다.
- 고정 SHA-256: manifest `ad2517c66d9af38474143e22df6e0556be9b073e8478f44aaa634f1a1cc1b5a6`,
  split `b03b8db19015243731f53fe847c60f95455af186a97b23543f9a8c7c3fc4c8b7`, mask
  `d0acaf51bc9fa5327a60c18bdf56c29c6c4ee0f9ff04e7e6be389141277adfb9`.
- 다음 조치: 아래 `AXIS-V2-MULTISEED-001` 결과에 따라 동일 설정 추가 학습을 중단하고 원인 진단.

#### AXIS-V2-MULTISEED-001

- 상태: G3 통과, G4 실패, test/G5 미진입
- 날짜: 2026-08-28
- 통제 설정: identity-logit, decoder 1024, encoder/decoder LR `5e-5/2e-4`, image `0`,
  smoothness `0.01`, style `0.25`, cosine 12 epoch, early stopping patience 2. 기존 checkpoint는
  resume하지 않았다.
- seed `20260828/29/30`은 각각 epoch `4/5/4`에서 종료되고 best epoch `2/3/2`, validation cube
  `0.019759/0.020766/0.019848`을 기록했다.
- interpolation 대비 sample 평균 ΔE 차이는 `-1.9889/-1.2318/-2.0821`로 세 seed 모두 개선됐다.
  그러나 LUT-macro paired 차이는 `+0.0767/-0.1207/-0.0896`, 20,000회 bootstrap 95% CI는 각각
  `[-1.2789,+1.3258]`, `[-1.0744,+0.8604]`, `[-1.4538,+1.1737]`로 모두 0을 포함한다.
- 판정: strict pass `0/3`. 중앙 seed는 `20260830`이지만 프로덕션 후보가 아니다. test 702건은
  열지 않았고 ONNX/TFLite 변환도 실행하지 않았다.
- 다음 조치: epoch·seed·capacity 증가는 중단한다. validation LUT별 reference identifiability,
  색역 coverage, source group 및 합성 domain gap을 분석한다.
- 산출물: `reports/validation/axis_v2_001_multiseed_validation_summary.json` 및 seed별 train,
  validation, paired comparison report.

#### AXIS-V2-FAILURE-DIAGNOSIS-001

- 상태: validation-only 탐색 완료; test 미사용
- 날짜: 2026-08-28
- 중앙 seed `20260830`에서 app/crawled는 각 1개 LUT 모두 interpolation보다 `-1.416/-4.077 ΔE`
  개선됐지만 Canon은 8개 중 3개만 이기고 평균 `+0.575 ΔE` 악화했다. Canon의 관찰/비관찰 차이는
  `+1.257/+0.395`다.
- interpolation error와 MVP-minus-interpolation Spearman은 `-0.939`, coverage와 차이는 `+0.442`다.
  n=10이며 Canon 8개로 불균형하므로 가설 생성용으로만 사용한다.
- 판단: 단순 coverage 부족 또는 epoch 부족보다 Canon CLog→sRGB transfer/gamut 합성, CLog2/CLog3
  family 중복, 쉬운 look 보존 실패를 먼저 점검한다.
- 산출물: `reports/validation/axis_v2_001_seed_20260830_failure_diagnosis.json`.

#### CANON-COLOR-CONTRACT-AUDIT-001

- 상태: 원인 확정, 생성 계약 교정 완료
- 날짜: 2026-08-28
- 원본 계약: Canon 65³ LUT 82/82가 `Canon Log 2/3 / Cinema Gamut → BT.709`를 선언한다.
  axis-v2 생성기는 Cinema Gamut 변환을 생략했고 CLog2/3 transfer 계수·piecewise 구간도 ACES Canon
  참조 transform과 달랐다.
- 직접 색값: 동일 41개 look의 CLog2/CLog3 macro 평균 차이는 `11.321772 → 0.076504 ΔE2000`,
  41/41 look이 개선됐다. 구형 타깃과 교정 타깃의 macro 평균 차이는 CLog2 `13.905690`,
  CLog3 `10.330872 ΔE2000`이다.
- 판단: axis-v2 Canon 타깃은 유효하지 않아 폐기한다. `canon_color_contract.py`에 Cinema Gamut primaries,
  sRGB→Cinema Gamut matrix, ACES CLog2/3 full-range 수식을 고정하고 단위 테스트 5개를 추가했다.
- 산출물: `43_audit_canon_color_contract.py`,
  `reports/validation/canon_color_contract_audit.json`.

#### COLOR-V3-DATASET-001

- 상태: G1 통과, family threshold 재교정 완료
- 날짜: 2026-08-28
- 데이터: `data/dataset_color_v3_001`, 3,000건, 119 source LUT, crawled/app/Canon 각 1,000건.
  오류 0, source checksum 119/119, 대표 neutral/graded JPEG 119/119 byte exact, float16 저장 오차 0,
  256 probe 최대 절대오차 `0.000243485`.
- family calibration: 동일 CLog2/3 look RMSE 최대 `0.003618`, 다른 look 최소 `0.017395`라 임계값을
  `0.01`로 고정했다. 78 family(단독 37, CLog 쌍 41), CLog 쌍 41/41 동일 family, source-group 교차와
  leakage 0. split record는 train/validation/test `2,318/339/343`.
- SHA-256: manifest `e60bf8971293d5e0d090ef4763cac726fa91c7c56be6712d9c1ac3ceefb49dfb`,
  split `f8f2b2e206e8a4560888195d07a60b03a7d47b60824f67b771287b3ad19b8644`, mask
  `3c677fd9aebe240593eed48cc8a0edb52ee4f2705cf9edb64ac59e727c8a4ce2`.

#### COLOR-V3-PILOT-001

- 상태: Canon 개선 확인, G4 전체 실패, test/G5 미진입
- 날짜: 2026-08-28
- 통제 설정: axis-v2 seed `20260830`과 identity-logit 1024, encoder/decoder LR `5e-5/2e-4`,
  image `0`, smoothness `0.01`, style `0.25`, cosine 12 epoch, patience 2를 고정했다.
- 학습: epoch 6 종료, best epoch 4, validation cube `0.009078`.
- 품질: validation sample/LUT-macro MVP `13.412063/13.425439`, interpolation
  `10.091518/10.422167 ΔE2000`. paired 차이 `+3.003272`, 20,000회 bootstrap 95% CI
  `[-1.215095,+7.793562]`, MVP 우세 7/12로 strict G4 실패.
- group: Canon 8개 중 6개 우세·평균 `-1.333457`, crawled 1개 `-2.588759` 개선. app 3개는
  평균 `+16.431893` 악화했고 `fuji_mono_g/ye`, `leica_chocolate_hc`가 각각
  `+15.513829/+16.660382/+17.121468 ΔE`였다.
- 판단: Canon 합성 교정은 원래 차단 원인을 해결했지만 모델의 app low-coverage/monochrome family
  일반화 실패가 새 차단 원인이다. 같은 모델의 epoch·seed·capacity 증가는 중단한다. 별도 calibration
  family에서 interpolation fallback 또는 app-family 보강을 한 변경씩 검증하기 전 test를 열지 않는다.
- 산출물: `checkpoints/conditional_lut_color-v3-smooth010-seed-20260830.pt`,
  `reports/mvp/color-v3-smooth010-seed-20260830_{train,validation}_report.json`,
  `reports/validation/color_v3_001_seed_20260830_{paired_comparison,failure_diagnosis}.json`.

#### COLOR-V3-CANDIDATE-SELECTION-002

- 상태: 2개 10분 제한 pilot 완료, coverage fallback 선발·보류
- 날짜: 2026-08-28
- 후보 A: style consistency weight만 `0.25 → 0.10`, 최대 6 epoch. best epoch 5 validation cube
  `0.009004`. validation sample/LUT-macro 차이는 interpolation 대비 `+3.138377/+2.658945 ΔE`,
  LUT paired CI `[-1.523984,+7.426862]`, app 평균 `+15.846832`라 탈락했다.
- 후보 B: 기존 MVP와 interpolation을 reference hue coverage threshold로 선택. source LUT 하나를 평가할 때
  나머지 11개로 threshold를 고르는 LOO pilot에서 4/12 LUT에 interpolation을 사용했다. LUT-macro
  `9.685693`, interpolation `10.422167`, 차이 `-0.736474`, CI `[-1.691714,+0.216757]`다.
- group: 후보 B는 app 3개를 모두 interpolation으로 보호해 차이 0, Canon/crawled은 각각
  `-0.781116/-2.588759 ΔE`다. 선택 threshold는 11 fold에서 `0.03`, 1 fold에서 `0.05`였다.
- 결정: 후보 A 추가 seed/epoch는 중단한다. 후보 B를 다음 calibration 대상으로 선발하지만 CI 상한이 0보다
  크므로 G4 통과가 아니다. 별도 app monochrome/강한 tone LUT에서 fixed threshold를 정하기 전 test를
  열거나 배포 로직을 구현하지 않는다.
- 산출물: `44_evaluate_coverage_fallback.py`,
  `reports/validation/color_v3_001_coverage_fallback_loo.json`,
  `reports/mvp/color-v3-style010-seed-20260830_{train,validation}_report.json`,
  `reports/validation/color_v3_style010_seed_20260830_{paired_comparison,failure_diagnosis}.json`.

#### COLOR-V3-FALLBACK-READINESS-003

- 상태: fixed threshold 동작 확인, 독립 calibration 부재로 승격 보류
- 날짜: 2026-08-28
- 로컬 catalog 감사: `assets/luts`, `data/luts`, `data/synthetic_luts`의 물리 LUT 67개는 SHA-256
  기준 37개 고유 내용이며 67/67 모두 `color-v3-001`에 이미 포함된 내용이다. 독립 보정 가능 LUT는 0개다.
- app 분할: train/validation/test source LUT는 `24/3/3`. threshold `0.03` 미만은 train 10개,
  validation 3개지만 각각 모델 fitting과 threshold 탐색에 이미 사용됐다. test 3개는 coverage와 score를
  읽지 않고 예약 상태를 유지했다.
- 동결 적용: LOO에서 11/12 fold가 선택한 `0.03`을 더 조정하지 않고 기존 validation 12 LUT에 한 번
  적용했다. 3개 app LUT에만 interpolation을 사용했고 LUT-macro는 `9.317466`, interpolation은
  `10.422167`, paired 차이는 `-1.104701`, bootstrap 95% CI는 `[-2.213332,-0.006943]`였다.
- 판정: 수치상 개선이나 동일 validation에서 threshold가 유래했으므로 독립 검증이 아니다. 3자 평가는
  **조건부**이며 G4·test·배포 승격은 계속 보류한다.
- 다음 진입 조건: 라이선스와 source provenance를 기록한 별도 app-like LUT 세트에서 threshold, coverage
  extractor, checkpoint, interpolation 구현, family dedup 계약을 scoring 전에 고정한다. low/high coverage와
  monochrome/strong-tone strata를 모두 포함하고, LUT-macro paired CI 상한 `< 0` 및 strata 비악화를 만족해야 한다.
- 산출물: `45_audit_coverage_fallback_readiness.py`, `46_evaluate_frozen_coverage_fallback.py`,
  `reports/validation/color_v3_001_coverage_fallback_{readiness,frozen_003}.json`.

#### EXTERNAL-CALIBRATION-HIGH-COVERAGE-004

- 상태: 후보 B high-coverage 분기 독립 통과, low-coverage 취약 계열 보류
- 날짜: 2026-08-28
- 데이터: MIT `t0saki/lumix-original-looks` commit
  `5694792f25598ec626e3e7527e2352f203a33317`의 sRGB 33³ CUBE 10개를 LUT당 12장, 총 120장으로
  별도 생성했다. source SHA-256은 color-v3 train과 0/10 중복이다.
- 범위: source LUT 평균 coverage `0.068119~0.108708`로 모두 fixed threshold `0.03` 이상이다.
  따라서 이 세트는 MVP high-coverage route만 검증하며 monochrome/low-coverage route는 검증하지 않는다.
- 결과: 10 LUT 중 MVP 9개 우세. selected/MVP LUT-macro `9.284110`, interpolation `11.612427`,
  paired 차이 `-2.328317`, bootstrap 95% CI `[-3.418580,-1.167311]`로 high branch는 통과했다.
- 결정: 후보 B 전체 평가는 계속 **조건부**다. high branch의 독립 우위는 확인됐지만 별도 monochrome·strong-tone
  low-coverage LUT가 없어 threshold의 취약 계열 재현성과 분기 안정성을 승인하지 않는다. test는 열지 않는다.
- 산출물: `47_generate_external_lut_calibration.py`, `48_evaluate_external_coverage_calibration.py`,
  `reports/validation/external_calibration_001_coverage_fallback.json`.

#### EXTERNAL-MONOCHROME-CALIBRATION-005

- 상태: low-coverage 분기 독립 통과, 결합 calibration gate 통과
- 날짜: 2026-08-28
- 데이터: RawTherapee Film Simulation Collection의 CC BY-SA 4.0 흑백 HaldCLUT 31개,
  `cedeber/hald-clut` commit `3b3180f82d4dcea1e6e8c5648473539a910d7f49`. 평가 전용이며 원본은
  저장소에 포함하거나 학습에 사용하지 않았다. LUT당 12장, 총 372장, train SHA 중복 0개다.
- coverage: source LUT 평균 `0.003274~0.003460`, 31/31이 fixed threshold `0.03` 아래다.
- 결과: 31/31 interpolation 선택, selected와 interpolation ΔE가 exact 동일(`8.617983`), 차이와 CI는
  `0/[0,0]`. 강제 MVP는 `22.315603`, 기준선 대비 평균 `+13.697620`, 31/31 패배했다.
- 결합 gate: high 10 + low 31 = 41 LUT에서 routing recall 각각 100%, selected/interpolation
  `8.780453/9.348335`, 차이 `-0.567882`, CI `[-1.011339,-0.188623]`로 통과했다.
- 산출물: `49_generate_hald_monochrome_calibration.py`, `50_combine_external_fallback_calibration.py`,
  `reports/validation/external_{monochrome,combined}_calibration_001_*.json`.

#### COLOR-V3-FALLBACK-ONE-TIME-TEST-006

- 상태: one-time test G4 통과, 재평가·재튜닝 금지, G5만 진입
- 날짜: 2026-08-28
- 고정 계약: checkpoint SHA `3674a5a79bc68235bf80c99f8592933d3f83f92f84e016fc189a84bf8385cf47`,
  split SHA `f8f2b2e206e8a4560888195d07a60b03a7d47b60824f67b771287b3ad19b8644`, mask SHA
  `3c677fd9aebe240593eed48cc8a0edb52ee4f2705cf9edb64ac59e727c8a4ce2`, threshold `0.03`.
- 결과: test 12 source LUT 중 interpolation 5, MVP 7. selected/interpolation LUT-macro
  `12.041410/12.872148`, 차이 `-0.830738`, bootstrap CI `[-1.821283,-0.109400]`로 strict G4 통과.
- group 차이: app `-0.488930`(fallback 1/3), Canon `-0.727863`(4/8), crawled `-2.679160`(0/1).
  forced MVP는 app/Canon에서 각각 평균 `+4.898114/+0.739976` 악화해 routing 필요성을 재확인했다.
- 결정: 색값 품질 후보는 G5 deployment parity로 승격한다. test는 다시 평가하거나 threshold/model 튜닝에
  사용하지 않는다. G5/G6 미완료이므로 제품 릴리스 3자 평가는 계속 **조건부**다.
- 산출물: `51_summarize_fallback_one_time_test.py`,
  `reports/validation/color_v3_001_coverage_fallback_one_time_test{,_summary}.json`.

#### COLOR-V3-FALLBACK-G5-PARITY-007

- 상태: desktop G5 배포 동등성 통과, 실기기 G6 보류
- 날짜: 2026-08-28
- 고정 checkpoint SHA: `3674a5a79bc68235bf80c99f8592933d3f83f92f84e016fc189a84bf8385cf47`.
- ONNX: opset 17, 72,494,561 bytes, SHA
  `62a6f8683474802c6ac059c0c2e97686e268d922551ddecd8a2a0cd43e53fcbc`, PyTorch 최대 절대오차
  `2.682209e-6`로 허용치 `1e-5` 통과.
- FP16 TFLite: 36,264,272 bytes, SHA
  `a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`, PyTorch 최대 절대오차
  `0.000838310`로 허용치 `0.002`의 41.9% 사용, 통과.
- 계약: ONNX/TFLite 모두 float32 NCHW `[1,3,256,256]` 입력과 `[1,17,17,17,3]` 출력, R-fastest
  65³ persistence 축 검사가 통과했다.
- desktop benchmark: TFLite/XNNPACK 2 threads, 50회 평균/p50/p95 `3.171/3.171/3.239ms`.
- Flutter wrapper: 새 TFLite 경로를 dart-define으로 주입해 실제 `LutPredictor` load, JPEG→65³ LUT,
  deterministic recipe 2개 테스트가 통과했다. wrapper 전체는 `440ms`; 모바일 latency 주장이 아니다.
- 결정: desktop 범위 G5는 통과. 앱 asset/registry에는 아직 교체하지 않았으며 G6 iOS/Android 실기기
  latency·메모리·내보내기·권한 검증 전 릴리스 3자 평가는 **조건부**다.
- 산출물: `52_summarize_color_v3_deployment_parity.py`,
  `reports/deployment/color_v3_fallback_003_{onnx_export,tflite_conversion,tflite_benchmark,g5_summary}.json`,
  `color_v3_fallback_003.{onnx,fp16.tflite}`.

#### COLOR-V3-FALLBACK-G6-SIM-PROXY-008

- 날짜: 2026-08-29
- 상태: iOS Simulator 선행 측정 통과, 물리 iOS/Android G6 보류
- artifact: fixed FP16 SHA-256
  `a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`
- 환경: iPhone 17 Simulator, iOS 26.5 (23F77), debug. 연결된 물리 모바일 기기 없음.
- Direct MVP: interpreter cold proxy 5회 generate p95 `454.980ms`; warm 30회 p50/p95
  `392.202/418.660ms`; peak RSS 증가 `284,672,000 bytes`(`271.5MiB`), 종료 후 baseline 대비
  `-1,605,632 bytes`.
- 편집: frame 38개 p95 `11.172ms`, warm preview 36개 p95 `33.972ms`.
- 내보내기: 첫 진행 표시 `211.397ms`, 취소 복귀 `281.006ms`; 완주·저장·공유는 측정하지 않음.
- 검증: 전용 후보 측정 1개와 editor performance 2개 모두 통과; 두 파일 모두 `flutter analyze` 통과.
- 증거: `reports/device/color_v3_fallback_003_ios_simulator_g6_proxy.json`.
- 제한: debug Simulator, same-process cold proxy, runner 포함 RSS이므로 실기기 성능·jetsam·LMK 주장이 아님.
  물리 iOS/Android release/profile, 4K export 완주, 권한 matrix, background resume 전까지 **조건부** 유지.

#### COLOR-V3-BUNDLE-SWAP-BRANCH-009

- 날짜: 2026-08-29
- 브랜치: `test/color-v3-fallback-routing`, base `964e14cac61bb7ff5a3588bd7390bebd9acbf335`
- 변경: 앱 번들 TFLite와 model ID/version/SHA를 G5 고정 후보
  `a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`로 교체.
- 검증: 관련 50개 및 전체 504개 Flutter 테스트 통과, analyze 0건. wrapper `437ms`.
- iOS Simulator: cold proxy p95 `229.520ms`, warm p95 `129.699ms`, peak RSS 증가 `120.2MiB`,
  종료 후 증분 `-5.2MiB`; debug 선행값이며 실기기 주장이 아님.
- 차단: 앱에 fixed coverage `<0.03`와 G4 동일 top-3 interpolation asset/runtime이 없어 현재는 pure MVP다.
  low-coverage 강제 MVP 위험이 남으므로 모델 교체만으로는 승격하지 않고 **교체보류**.

#### COLOR-V3-RUNTIME-FALLBACK-REJECTION-010

- 날짜: 2026-08-29
- 범위: 외부 흑백 31 LUT, LUT당 대표 reference 1장, Dart 65³ algorithmic output 직접 색값 평가.
- routing: Dart coverage 분석기가 대표 high/boundary/monochrome 사례의 fixed `<0.03` 분기를 재현했다.
- 결과: algorithmic/interpolation/identity LUT-macro ΔE `26.1940/8.9159/26.6727`.
- paired algorithmic-minus-interpolation `+17.2781`, 95% CI `[+15.1380,+19.1832]`, 우세 `0/31`.
- 결정: 기존 algorithmic 및 identity fallback 모두 거부. 실패한 제품 연결은 제거하고 coverage 분석기와
  수동 품질 fixture만 유지한다.
- 원래 top-3 차단: train-only 94 LUT에는 재배포 권리가 확인되지 않은 Canon/수집 source가 포함되며,
  앱 LUT로 대체하면 test leakage 위험이 있다. 그대로 번들링하지 않는다.
- 다음 선택: 라이선스가 명확한 fallback 모델/asset을 새로 만들거나, 당장은 저 coverage 생성을 차단하고
  다른 reference를 요청한다. 전체 모델 교체 판정은 **교체보류**.
- 산출물: `53_evaluate_runtime_algorithmic_fallback.py`,
  `reports/validation/color_v3_runtime_algorithmic_monochrome_001.json`.

---

## 8. Ablation Study

| Ablation ID | 제거 항목 | 확인할 내용 | 핵심 비교 지표 | 상태 |
|---|---|---|---|---|
| ABL-001 | Full Color Cube Loss | 이미지에 없는 색 생성에 cube supervision이 필요한지 | 비관찰 Hue Error, 전체 Cube Error | 실험 필요 |
| ABL-002 | Style Consistency Loss | encoder가 장면 내용에 과적합하는지 | 동일 LUT Style Code 거리, 장면별 cube error | 실험 필요 |
| ABL-003 | Semantic Code | 장면·피부 의미 정보의 기여 | Skin Tone Error, 풍경/인물 Error | 실험 필요 |
| ABL-004 | Palette Decoder | 대표 색 관계가 비관찰 Hue에 미치는 영향 | 비관찰 Hue Error, palette error | 실험 필요 |
| ABL-005 | Hue Anchor Decoder | Hue별 연속 변환 학습의 기여 | Hue Error, Hue Continuity | 실험 필요 |
| ABL-006 | Residual LUT | 구조화된 base만으로 충분한지 | Cube Error, residual norm, smoothness | 실험 필요 |
| ABL-007 | Confidence Module | confidence mixing이 tail error를 줄이는지 | calibration, worst-k Error, OOG | 실험 필요 |
| ABL-008 | Identity Regularization | 과도한 색 이동을 억제하는지 | Identity distance, OOG, Creative 품질 | 실험 필요 |
| ABL-009 | Smoothness Loss | 불연속과 밴딩을 억제하는지 | 인접 Grid 차이, Hue Continuity, 밴딩 | 실험 필요 |
| ABL-010 | 동일 LUT 다중 장면 학습 | scene invariance가 실제로 학습되는지 | Style Code 거리, 장면 holdout Error | 실험 필요 |
| ABL-011 | Curriculum Learning | 단계적 학습이 수렴과 안정성을 개선하는지 | 수렴 속도, Cube Error, 모듈별 안정성 | 실험 필요 |

Ablation은 한 번에 하나의 요소만 바꾸고 동일 dataset version, split, seed, compute budget을
사용한다. 모든 실패 결과도 삭제하지 않고 실험 기록에 추가한다.

---

## 9. 학습 설정 기록

### Experiment EXP-000

- 날짜:
- 작성자:
- Git Commit:
- 데이터 버전:
- 데이터 Manifest:
- Train/Validation/Test Split:
- 모델 버전:
- 실험 상태: `계획 / 실행 중 / 성공 / 실패 / 중단`
- 실험 목적:
- 핵심 가설:
- 변경 사항:
- 비교 Baseline:
- Backbone:
- Style Code 구성:
- Latent Code 차원:
- LUT 표현 방식:
- LUT 출력 해상도:
- Color Cube 해상도:
- 관찰 Hue 정의:
- Batch Size:
- Epoch:
- Optimizer:
- Learning Rate:
- Scheduler:
- Weight Decay:
- Mixed Precision:
- Random Seed:
- 사용 Loss:
- Loss Weight:
- Freeze 모듈:
- 학습 시간:
- 장치/GPU:
- 최대 메모리:
- Checkpoint:
- Config:
- Log:
- 전체 Color Cube 결과:
- 비관찰 Hue 결과:
- Hue Continuity:
- LUT Smoothness:
- Monotonicity:
- Out-of-Gamut:
- 피부색 안정성:
- Style Consistency:
- Confidence Calibration:
- 이미지 품질:
- 실패 원인:
- 오류 로그:
- 분석:
- 배운 점:
- 다음 조치:
- 다음 실험:

### 실험 저장 규칙

- [ ] run마다 고유 experiment ID를 사용한다.
- [ ] config, checkpoint, report, stdout/stderr log를 함께 보존한다.
- [ ] 중단된 run은 `중단` 상태와 완료 epoch/trial 수를 기록한다.
- [ ] best metric뿐 아니라 마지막 상태와 전체 curve를 저장한다.
- [ ] 기존 artifact를 새 run으로 덮어쓰지 않는다.
- [ ] dataset version, Git commit, random seed를 필수 기록한다.
- [ ] 실패 experiment를 삭제하거나 성공 결과로 재분류하지 않는다.

---

## 10. 학습 진행 현황

### 진행 예정

- [ ] 최종 모델 선택용 split 정책 확정
- [ ] LUT 정규화 및 중복 탐지
- [ ] Color Cube 생성기 구현
- [x] Identity LUT baseline 측정
- [ ] Retrieval/Interpolation baseline 구현
- [x] 기존 PCA baseline 공통 평가
- [x] Identity와 V2 PCA baseline을 LUT/image holdout에서 공통 evaluator로 측정 (`BASELINE-DUAL-001`)
- [x] Direct Low-resolution LUT MVP skeleton 및 1-batch overfit/export smoke (`MVP-SKELETON-001`)
- [ ] Style Consistency batch sampler 구현

### 진행 중

- [ ] Phase 0 baseline 및 평가 계약 확정
- [x] Full Cube + Style Consistency 학습 smoke test: `STYLE-CONSISTENCY-SMOKE-006` frozen-BN contract로 통과

### 완료

- [x] 프로젝트 최종 목적 정의
- [x] 기존 V3 PCA 방식과 조건부 LUT 생성 방식 구분
- [x] 조건부 LUT 생성 방향 결정
- [x] 계층적 Style Decoder 구조 초안 작성
- [x] MVP 흐름 정의
- [x] 기존 3,000개 neutral/graded/LUT triplet 존재 확인
- [x] DATA-AUDIT-001: dataset 무결성·중복·Hue Coverage 감사
- [x] DATA-SPLIT-001: source LUT/source image strict split 불가 판정
- [x] SPLIT-CONTRACT-001: LUT holdout과 image holdout JSONL 생성
- [x] HUE-MASK-001: reference별 observed/unobserved 17³ Cube mask 생성
- [x] LUT-FAMILY-HOLDOUT-001: output-similarity family-level holdout split 생성
- [x] EVAL-CORE-001: 공통 17³ Color Cube evaluator와 identity/CLI smoke test
- [x] LUT-OOG-AUDIT-001: raw LUT와 clamp된 sRGB renderer의 dataset-wide 계약 감사
- [x] MVP-SKELETON-001: bounded 17³ conditional LUT forward/backward/export smoke
- [x] 기존 V2 checkpoint와 validation report 존재 확인
- [x] 기존 V3 최종 checkpoint 미생성 상태 확인

### 보류

- [ ] V3 weight sweep 재실행: 새 조건부 생성 MVP의 baseline 계약을 먼저 확정
- [ ] Semantic Mask 생성: MVP cube 학습 이후 모델과 비용 결정
- [ ] Creative Mode: 안정적인 Faithful/Balanced 기반 모델 이후 진행
- [ ] 모바일/서버 배포 결정: 모델 크기와 latency 측정 이후 진행

---

## 11. 위험 요소와 대응 방안

| 위험 요소 | 영향 | 확인 방법 | 대응 방안 |
|---|---|---|---|
| 이미지 내용과 스타일의 혼동 | 장면마다 다른 LUT 생성 | 동일 LUT 다중 장면 Style Code 평가 | Style Consistency Loss와 group sampler |
| 카메라 기본 처리와 개인 보정 혼동 | 기기별 색을 스타일로 오인 | device/domain holdout | camera profile·WB·HDR augmentation, metadata 활용 |
| 보이지 않은 색상 추론 실패 | 특정 Hue 왜곡 | 비관찰 Hue Cube Error | Full Cube Loss, Style Prior, Hue Anchor |
| 낮은 confidence의 과도한 생성 | 참조에 없는 색이 극단적으로 이동 | confidence-error calibration과 tail error | Confidence 기반 Identity Mixing |
| LUT 불연속 | 밴딩과 색상 경계 발생 | 인접 Grid 차이, Hue Continuity | Smoothness Loss와 연속 interpolation |
| Monotonicity 위반 | 명도 역전과 비정상 대비 | 밝기·채널 순서 검사 | Monotonicity Loss와 안전 gate |
| 과도한 색상 이동 | 비현실적 결과 | ΔE, Identity distance, OOG | Identity Regularization과 mode별 제한 |
| Raw LUT와 rendered output 계약 불일치 | 학습 target·정확도·안전성 판단 왜곡 | raw OOG와 clamp 후 Cube Error를 분리 측정 | 정확도는 clamp 후 rendered RGB, OOG는 raw node로 별도 report |
| 피부색 왜곡 | 인물 결과 품질 하락 | skin mask ΔE와 hue shift | Semantic Code와 Skin Tone Preservation |
| Residual LUT 과의존 | 해석 가능성·안정성 저하 | Residual Magnitude와 base/residual ablation | Residual 크기 정규화 및 staged training |
| LUT 데이터 품질 불균형 | 특정 스타일·회사 LUT 편향 | LUT embedding/cube 분포 분석 | 중복 제거, family split, 재샘플링 |
| Strict split 불가능 | unseen LUT와 unseen scene을 동시에 엄격히 측정할 수 없음 | source LUT/source image 연결 컴포넌트 | 두 split 계약을 분리하고 결과를 단일 score로 합치지 않음 |
| 합성 데이터 domain gap | 실제 게시 이미지에서 성능 저하 | 실제 최종 이미지 blind test | camera/압축/local edit augmentation과 실제 test set |
| 로컬 보정을 전역 LUT로 모사 | 얼굴·하늘 등 특정 영역 왜곡 | semantic region error 비교 | 로컬 효과는 confidence를 낮추고 전역 변환만 생성 |
| Loss 간 충돌 | 평균적 LUT로 수축 또는 불안정 | gradient norm과 ablation | curriculum, loss normalization, weight sweep |
| CPU 학습 비용 | 실험 속도 저하 | epoch·cube resolution별 latency | 17³ MVP, random cube sampling, 캐싱 |
| artifact 덮어쓰기 | 실패 원인과 best 결과 유실 | run directory audit | immutable experiment ID와 완료 상태 저장 |

---

## 12. 모델 성공 기준

### 12.1 정량 기준

| 항목 | 목표 | 현재 값 | 판정 상태 |
|---|---|---|---|
| 전체 Color Cube Error | 목표값 결정 필요 | 미측정 | 실험 필요 |
| 비관찰 Hue Error | 목표값 결정 필요 | 미측정 | 실험 필요 |
| 관찰/비관찰 Hue Error 차이 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| ΔE2000 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Hue별 변환 연속성 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| LUT Smoothness | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Monotonicity 위반 비율 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Out-of-Gamut 비율 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Style Consistency | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Skin Tone Error | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Confidence-Error 상관 | 목표값 결정 필요 | 미측정 | 실험 필요 |
| Confidence Calibration Error | 목표값 결정 필요 | 미측정 | 실험 필요 |
| 추론 시간 | 요구사항 결정 필요 | 미측정 | 검토 필요 |
| LUT 생성 메모리 | 요구사항 결정 필요 | 미측정 | 검토 필요 |

정량 목표는 Identity, retrieval, interpolation, PCA, direct low-resolution LUT baseline을
동일 test set에서 측정한 뒤 확정한다.

### 12.2 정성 기준

- [ ] 참조 이미지의 색감과 톤의 규칙이 유지된다.
- [ ] 참조 이미지에 없던 색상도 전체 팔레트와 조화를 이루며 자연스럽게 변환된다.
- [ ] 같은 LUT 스타일을 가진 서로 다른 장면에서 일관된 LUT가 생성된다.
- [ ] 하늘·식물·피부 등 장면 내용이 필터 자체로 잘못 복사되지 않는다.
- [ ] 밴딩, 색상 단절, clipping, 명도 역전이 보이지 않는다.
- [ ] 인물의 피부색이 비정상적으로 변하지 않는다.
- [ ] Faithful·Balanced·Creative 모드의 차이가 명확하다.
- [ ] Creative 모드도 안전 gate를 넘는 극단적 색상 왜곡을 만들지 않는다.
- [ ] 실제 게시 이미지 blind test에서 단순 retrieval보다 유용하다고 평가된다.

---

## 13. 현재 결정 사항

- [x] 단순 LUT 검색 모델이 아닌 조건부 생성 모델을 개발한다.
- [x] 참조 이미지에서 Style Code를 추출한다.
- [x] 전체 RGB Color Cube를 정답으로 사용한다.
- [x] 동일 LUT가 적용된 서로 다른 장면을 함께 학습한다.
- [x] 참조 이미지에 없는 Hue를 핵심 평가 대상으로 둔다.
- [x] MVP는 저해상도 3D LUT를 직접 생성한다.
- [x] MVP 이후 Style Encoder와 계층적 Style Decoder로 확장한다.
- [x] Base LUT와 Residual LUT를 분리한다.
- [x] Tone Curve, Palette, Hue Anchor를 순차적으로 추가한다.
- [x] Semantic Code와 피부색 안정성을 별도로 평가한다.
- [x] 비관찰 Hue에 대해 Confidence 기반 Identity Mixing을 사용한다.
- [x] Faithful·Balanced·Creative 생성 모드를 지원하는 방향으로 개발한다.
- [x] 기존 V3 PCA 방식은 legacy baseline으로만 유지한다.
- [x] 실패한 실험과 중단 artifact를 삭제하지 않고 기록한다.
- [x] 현 데이터의 최종 모델 평가는 LUT holdout과 image holdout을 분리해 보고한다.

### 13.1 변경 이력

| 날짜 | 변경 | 근거 | 영향 |
|---|---|---|---|
| 2026-07-28 | source LUT와 source image를 모두 격리하는 단일 split 요구를 이중 split 계약으로 변경 | DATA-SPLIT-001에서 전체 데이터가 1개 연결 컴포넌트임을 확인 | 최종 report는 unseen LUT와 unseen scene 결과를 별도로 기록 |
| 2026-07-29 | 정확도 target을 clamp 후 sRGB render로, raw LUT OOG를 별도 safety metric으로 확정 | LUT-OOG-AUDIT-001에서 OOG가 crawled 7개 중 4개 LUT에 집중됨을 확인 | MVP decoder는 bounded output을 사용하고 target clipping을 raw OOG로 모사하지 않음 |
| 2026-07-29 | MVP를 PCA coefficient prediction이 아닌 bounded direct 17³ LUT generation으로 최초 구현 | MVP-SKELETON-001에서 실제 triplet의 backward 및 export/reload를 확인 | 성능 수치는 동일-batch overfit과 held-out generalization을 분리해 기록 |
| 2026-07-29 | Style Consistency를 MVP controlled train의 선행 안전 조건으로 격상 | STYLE-CONSISTENCY-SMOKE-001~004에서 short-run latent collapse 확인 | separation monitor와 best-state checkpoint 없이 long-run 학습 금지 |
| 2026-07-29 | Style Encoder의 small-batch BatchNorm을 고정 | STYLE-CONSISTENCY-SMOKE-005/006에서 train/eval 통계 불일치가 collapse 원인임을 확인 | MVP train은 frozen BatchNorm과 latent separation monitor를 사용 |
| 2026-07-29 | MVP-TRAIN-001의 평균-LUT 수축을 read-only 분석으로 확정 | MVP-BOTTLENECK-ANALYSIS-001에서 validation output variance retention이 0.226%에 그침 | broad sweep/epoch 증가 전에 decoder residual scale, grid smoothness, loss-gradient를 통제 ablation으로 측정 |

MVP 이후 확장 순서는 다음과 같이 고정한다.

```text
Tone Curve
→ Palette Decoder
→ Hue Anchor Transform
→ Base LUT
→ Residual LUT
→ Semantic Code
→ Hue Confidence Module
→ Faithful·Balanced·Creative 생성 모드
→ End-to-End Fine-tuning
```

---

## 14. 미결정 사항

- [ ] LUT 출력 해상도: 미정
- [ ] 학습용 Color Cube 해상도: 미정
- [ ] validation/test Full Cube 해상도: 미정
- [ ] Style Encoder Backbone: 미정
- [ ] Semantic Mask 생성 모델: 미정
- [ ] 추가 LUT 데이터 출처와 라이선스: 검토 필요
- [ ] Latent Code 차원: 미정
- [ ] Tone/Palette/Anchor target 추출 방식: 검토 필요
- [ ] Base LUT 생성 방식: 미정
- [ ] Residual LUT 크기 제한: 실험 필요
- [ ] Confidence 계산 방식: 미정
- [ ] 관찰 Hue bin과 threshold 정의: 미정
- [ ] Creative Mode Latent Sampling 방식: 미정
- [ ] Loss Weight: 실험 필요
- [ ] Optimizer와 Scheduler: 실험 필요
- [ ] 학습 GPU 환경: 미정
- [ ] 실시간 추론 요구사항: 미정
- [ ] 모바일 또는 서버 배포 여부: 미정
- [ ] 최종 LUT binary format과 metadata schema: 검토 필요
- [ ] 실제 인스타그램·블로그 이미지 test set의 수집 및 이용 기준: 검토 필요

---

## 15. 다음 작업 우선순위

### Priority 1. Multi-Seed Smoothness Replication

- [x] 작업 내용: smoothness weight `0.01`과 `0.04`를 새 seed 2개에서 같은 cube-only 8-epoch protocol로
  각각 재실행한다. 후보별 2개 새 run, 총 4개 artifact를 기존 single-seed 결과와 함께 집계한다.
- 작업 목적: single-seed sample ΔE `0.00091` 차이가 실제 regularization 효과인지 seed noise인지 판정한다.
- 필요한 입력: MVP-PROTOCOL-IMAGE-WEIGHT-000-001, MVP-PROTOCOL-SMOOTHNESS-WEIGHT-040-001,
  PROTOCOL-FIX-001
- 산출물: 4개 checkpoint/train/evaluation/bottleneck report,
  `reports/baselines/smoothness_multiseed_replication_report_001.json`.
- 완료 판정: seed `20260730`에서 `.04` LUT-macro ΔE가 `+0.011049` 악화했다. practical tie로 선언하고
  `.01`을 채택했다.
- 후속: 더 높은 smoothness weight sweep은 하지 않는다.

### Priority 2. LUT-family Holdout V2 Baseline

- [x] 작업 내용: family-train records만으로 V2 17³ PCA basis와 coefficient predictor를 새 artifact 이름에
  fit/train하고 family validation/test를 평가한다.
- 작업 목적: 같은 계열 LUT를 본 상태의 근사와 실제 새 스타일 규칙 생성 능력을 V2까지 포함해 분리한다.
- 필요한 입력: family labels/split/leakage report, V2 trainer의 split·artifact-path parameterization
- 산출물: `basis_v2_family_holdout_001.npz/.pt/.report.json`, family validation/test baseline reports,
  updated `family_holdout_generation_comparison_report_001.json`.
- 완료 판정: V2 train/validation/test source-LUT overlap은 모두 `0`으로 checkpoint metadata에 기록됐고,
  MVP/V2/retrieval/interpolation의 sample/LUT-macro metrics가 같은 report에 저장됐다.
- 결론: MVP는 family validation/test에서 V2보다 sample/LUT-macro 모두 낮다.

### Priority 3. Tone Curve Target Audit

- [x] 작업 내용: 모든 target LUT의 neutral diagonal 및 channel-wise curve를 추출하고, identity 대비
  tone-only reconstruction error와 hue-dependent residual을 group/family partition별로 측정한다.
- 작업 목적: LUT-holdout gap을 줄이기 위한 첫 구조화 decoder를 Tone Curve로 시작할 근거를 확보한다.
- 필요한 입력: LUT-family split, 17³ common evaluator, target LUT grid
- 산출물: `reports/baselines/tone_curve_target_audit_001.json`.
- 완료 판정: validation/test luminance-tone variation explained `18.0887%/17.8315%`; Tone Curve를 first
  module로 채택하고 Hue Anchor/Palette residual은 후속 module로 보류한다.

### Priority 4. Tone Curve-only Conditional Baseline

- [x] 작업 내용: Style Encoder에서 monotone, chroma-preserving Tone Curve를 직접 예측하는 17³ LUT
  baseline을 구현하고, 선택된 family split에서 8 epoch로 학습·validation/test 평가한다.
- 작업 목적: target-level 표현력 `18.09%`가 참조 이미지에서의 conditional inference에도 재현되는지
  확인하고, 직접 MVP 대비 residual architecture의 필요성을 정량화한다.
- 필요한 입력: TONE-CURVE-TARGET-AUDIT-001, corrected full-coverage sampler, family split
- 산출물: Tone Curve-only checkpoint/train/evaluation reports, updated family comparison.
- 완료 판정: direct MVP 대비 validation/test ΔE가 크게 나쁘고 validation 3D monotonicity violation `3.67%`가
  남았다. failure를 보존하고 Hue Anchor/Palette residual 필요 근거로 기록했다.

### Priority 5. Hue Anchor Residual Target Audit

- [x] 작업 내용: target LUT에서 neutral-luminance Tone Curve를 제거한 residual을 hue/saturation/value anchor로
  요약하고, anchor interpolation이 남은 target MSE를 얼마나 설명하는지 family train/validation/test에 측정한다.
- 작업 목적: Tone Curve-only가 남긴 약 `82%` target variation을 표현할 최소 hue-dependent residual을 정한다.
- 필요한 입력: TONE-CURVE-TARGET-AUDIT-001, MVP-FAMILY-TONE-CURVE-001, family split
- 산출물: `reports/baselines/hue_anchor_residual_target_audit_001.json`.
- 완료 판정: validation best residual explanation은 48 anchor `88.52%`이며, 6 anchor `83.39%`가 90% rule을
  충족한다. circular interpolation·saturation scaling·6 anchors를 다음 decoder contract로 고정했다.

### Priority 6. Tone Curve + 6-anchor Hue Residual Conditional Baseline

- [x] 작업 내용: Style Code에서 17-point monotone Tone Curve와 6개 circular RGB hue residual anchor를
  예측해 17³ LUT를 생성하는 decoder를 구현하고, family split 8-epoch protocol로 학습·평가한다.
- 작업 목적: target representation audit의 `83.39%` residual explanation이 reference-image conditional
  inference에서도 Tone Curve-only보다 유의미하게 전이되는지 확인한다.
- 필요한 입력: HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001, corrected sampler/style guardrail, family split
- 산출물: checkpoint/train/evaluation reports, family comparison update, monotonicity/OOG diagnosis.
- 완료 판정: Tone Curve-only보다 ΔE는 개선됐지만 direct MVP보다 크게 나쁘고 safety violation도 높다. target
  anchor representation과 image-to-anchor inference 사이의 gap을 직접 supervision으로 분리한다.

### Priority 7. Curve/Anchor Target-supervision Ablation

- [x] 작업 내용: target LUT에서 추출한 17-point Tone Curve와 6-anchor hue residual label을 dataset에 추가하고,
  current decoder head에 auxiliary Smooth L1 loss만 추가한다.
- 작업 목적: cube loss-only anchor prediction의 conditional transfer failure가 head target ambiguity 때문인지
  검증한다.
- 필요한 입력: HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001, MVP-FAMILY-TONE-HUE-ANCHOR-006-001, family split
- 산출물: target-label extractor, supervised checkpoint/train/evaluation reports, direct ablation comparison.
- 완료 판정: test and safety는 소폭 개선됐지만 validation sample은 악화하고 direct MVP와 큰 gap이 유지됐다.
  structured decoder 설정의 추가 sweep은 하지 않는다.

### Priority 8. Direct MVP with Parallel Structured Auxiliary Head

- [x] 작업 내용: direct full-LUT MVP decoder를 유지하고 Style Code에서 별도 17-point curve/6-anchor head를
  병렬 예측해 target labels로만 supervise한다.
- 작업 목적: structured labels가 output bottleneck이 아닌 Style Encoder regularizer로 direct MVP의
  LUT-holdout/family generalization 또는 safety를 개선하는지 확인한다.
- 필요한 입력: MVP-PROTOCOL-IMAGE-WEIGHT-000-001, HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001,
  MVP-FAMILY-TONE-HUE-ANCHOR-006-SUP-001
- 예상 산출물: multi-task checkpoint/train/evaluation reports, direct-MVP controlled comparison
- 완료 조건: direct output capacity를 바꾸지 않은 상태에서 auxiliary head weight·label protocol·validation/test
  ΔE·monotonicity/OOG가 기록된다.
- 관련 위험: auxiliary task가 direct cube objective와 충돌해 성능을 악화할 수 있다.
- 구현 상태 (2026-08-03): `20_train_conditional_lut_mvp.py`에 direct rendering path와 분리된
  `StructuredAuxiliaryHead` 및 `--parallel-structured-aux-weight`를 추가했다. `identity_logit`에서만 허용하며,
  17-point normalized curve + 6×RGB anchor target Smooth L1은 Style Code와 보조 head에만 gradient를 전달한다.
  evaluator/bottleneck loader도 auxiliary state dict를 재로딩할 수 있다.
- 실행 결과: `MVP-FAMILY-DIRECT-STRUCTURED-AUX-010-001`은 family split 8 epoch, auxiliary weight `0.10`에서
  epoch 7 validation cube loss `0.019689`을 선택했다. validation sample/macro ΔE는 `13.538183 / 13.633965`,
  test는 `13.008246 / 14.055034`, test monotonicity/OOG는 `2.2036% / 0%`다.
- 결정: direct MVP control의 test sample/macro ΔE `12.929904 / 14.001296`보다 각각 `+0.078342 / +0.053738`
  나쁘다. monotonicity는 `2.5183% → 2.2036%`로 소폭 개선됐지만 정확도 개선을 보이지 못했으므로 auxiliary
  weight 추가 sweep은 하지 않는다. Priority 8은 negative result로 완료하고, direct full-LUT MVP를 유지한다.
- bottleneck 확인: validation/test output-variance retention은 `0.484432 → 0.498960` / `0.668017 → 0.688733`,
  Style Code variance mean은 `0.062695 → 0.066129` / `0.021460 → 0.022349`로 올랐다. auxiliary가 latent
  collapse를 유발한 것은 아니지만, 이 변화가 held-out LUT accuracy 향상으로 이어지지 않았음을 확정했다.

### Priority 9. Retrieval-Inclusive MVP Comparison Report

- [x] 작업 내용: Identity, V2 PCA, retrieval, interpolation, bounded MVP를 우선 LUT-holdout
  validation-only의 한 schema에 비교했다. corrected-control 완료 후 같은 builder로 결과를 갱신한다.
- 작업 목적: MVP의 개선 여부를 scene reuse, unseen LUT, 비관찰 Hue 조건에서 혼동 없이 판단한다.
- 필요한 입력: RETRIEVAL-BASELINE-001, MVP controlled validation report
- 예상 산출물: baseline comparison JSON/Markdown table
- 완료 조건: 모든 모델의 overall/observed/unobserved Cube metric과 stability metric이 같은 report에 저장된다.
- 선행 작업: pre-fix reference report 완료, 최종 갱신은 Priority 1
- 관련 위험: 서로 다른 output resolution 또는 renderer contract를 섞으면 비교가 무효가 된다.

### Priority 10. Semantic Mask Readiness Audit

- [x] 작업 내용: semantic scene-content disentanglement 학습에 필요한 현재 mask interface, model artifact,
  Python runtime, family split 및 평가 계약을 read-only로 감사한다.
- 작업 목적: placeholder mask 또는 라이선스 불명 가중치로 direct MVP 기준선을 오염시키지 않고, semantic
  feature 실험의 실제 진입 조건을 명확히 한다.
- 산출물: `reports/baselines/semantic_mask_readiness_audit_001.json`.
- 완료 판정: Dart 6-class score-mask interface와 정확히 맞는 `MediaPipe Selfie Multiclass Segmentation`
  (`selfie_multiclass.tflite`)을 Apache-2.0 허용 결정으로 선택했고 SHA-256
  `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0`을 고정했다.
- 결과: `tensorflow`, `tflite_runtime`, `mediapipe`는 없지만 호환 runtime `ai-edge-litert==2.1.6`을
  설치·고정했고, `31_generate_semantic_mask_cache.py`가 3,000개 reference의
  `6×64×64` float16 softmax probability cache를 생성했다. 평균 class coverage는 background `81.43%`,
  hair `2.74%`, bodySkin `2.82%`, faceSkin `2.85%`, clothes `7.51%`, other `2.66%`다.

### Priority 11. Semantic-pooled Style Feature Ablation

- [x] 작업 내용: selected direct 17³ LUT decoder와 family split을 고정하고, global Style Code에
  checksum-pinned six-class semantic mask pooled feature만 추가한다.
- 작업 목적: 참조 이미지의 scene content가 style encoding을 교란하는지를 direct full-LUT capacity 변경 없이
  검증한다.
- 필요한 입력: `SEMANTIC-MASK-CACHE-001`, `MVP-FAMILY-HOLDOUT-SMOOTH-010-001`, fixed family split.
- 완료 조건: global-only control 대비 validation/test sample/LUT-macro ΔE, monotonicity/OOG, subject-present/absent
  strata 및 same-LUT style consistency를 같은 renderer contract에서 기록한다.
- 관련 위험: selfie-focused segmentation은 풍경 위주의 reference에 background-dominant mask를 만들 수 있으므로,
  semantic coverage strata 없이 전체 평균만으로 채택하지 않는다.
- 실행 결과: `MVP-FAMILY-SEMANTIC-POOLED-001`의 validation sample/macro ΔE는 `13.517104 / 13.520685`로
  control보다 개선됐지만, test는 `13.244072 / 14.030392`로 control `12.929904 / 14.001296`보다 악화했다.
  test monotonicity는 `2.5183% → 6.7396%`, OOG는 모두 `0%`다.
- bottleneck: test output-variance retention은 `0.668017 → 0.721359`로 증가했다. 출력 다양성이 늘었지만
  robust LUT-family generalization이 아니라 unsafe variation으로 전이됐으므로 semantic pooled feature는 채택하지 않는다.

### Priority 12. Family-holdout V3 Weight Sweep

- [x] 작업 내용: V3 basis-residual predictor를 explicit family split과 family-train-only V2 basis로 전환하고,
  기존 V3 artifact와 분리된 3-trial weight sweep을 수행한다.
- 실행 결과: best balanced score는 `1.302743`이었고 validation small-LUT RMSE는 crawled/app/canon
  `1.126430 / 0.555100 / 0.220208`이었다.
- 결정: app metric이 V2 baseline `0.166343`보다 크게 악화돼 baseline penalty `0.583135`를 받았다.
  3-epoch sweep 단계에서 이미 group-balance contract를 통과하지 못했으므로 60-epoch final train과 test는
  실행하지 않는다. V3 weight tuning은 direct MVP의 경쟁 경로가 아니다.

### Priority 13. Direct MVP Deployment Feasibility

- [~] 작업 내용: 선택된 direct MVP checkpoint의 CPU 기준 성능, export graph 동등성, 앱 TFLite 입출력
  contract와 desktop interpreter 실행을 검증한다. 실기기 검증은 아직 남아 있다.
- 산출물: `conditional_lut_mvp_model.py`, `33_benchmark_direct_mvp_deployment.py`,
  `34_export_direct_mvp_onnx.py`, `35_convert_direct_mvp_tflite.py`,
  `36_benchmark_direct_mvp_tflite.py` 및 `reports/deployment/`의 JSON/artifact들.
- 안정적 export: 모델 class를 번호가 붙은 실험 runner에서 `conditional_lut_mvp_model.py`로 분리했다.
  기존 checkpoint는 변경 없이 로드됐고, TorchScript 저장·재로딩의 LUT·Style Code 최대 오차는 모두 `0`이다.
- ONNX: legacy opset `17` artifact (`72,494,561` bytes)는 앱의 NCHW `[1,3,256,256]` 입력과
  `[1,17,17,17,3]` float32 output을 정확히 갖는다. ONNX Runtime의 PyTorch 최대 절대 오차는 `4.05e-6`이다.
- TFLite: ONNX→SavedModel 변환에서 지원되지 않는 LayerNormalization 한 개를 동등한 primitive 연산으로
  export graph에만 분해했다. float16-weight TFLite는 `36,264,272` bytes이며 SavedModel/PyTorch 최대 절대
  오차는 각각 `0.001597 / 0.001598`로, 사전 명시한 float16 허용치 `0.002` 이내다.
- desktop benchmark: XNNPACK 2 threads에서 TFLite end-to-end inference(입력 설정·invoke·출력 읽기)는 평균
  `3.266ms`, p95 `3.410ms`(20 samples)였다. 이는 desktop 수치이며 Android/iOS latency claim이 아니다.
- Flutter wrapper integration: `test/direct_mvp_tflite_candidate_test.dart`가 release candidate를 직접
  `LutPredictor.fromPath`로 열어 `test/원본_1.jpg → 65³ LUT`를 생성했다. macOS Flutter test에서
  `571ms`가 걸렸으며, 이는 JPEG decode·256 resize·nested input build·TFLite invoke·Dart 65³ upsample을
  포함한 전체 wrapper 수치다. 앱 asset 및 download registry는 변경하지 않았다.
- 다음 진입 조건: release candidate를 앱의 model delivery 경로에 등록한 뒤, Android와 iOS 실기기에서
  동일한 preprocessing, LUT shape/axis order, output parity, cold/warm latency, 메모리 사용량을 측정한다.
  현재 `kModelColorTransfer.url`이 비어 있으므로, model hosting URL과 release SHA-256이 결정되기 전에는
  download registry를 채우거나 사용자에게 배포 모델을 노출하지 않는다.

### 2026-08-29 Color-v3 low-coverage product gate

- 브랜치: `test/color-v3-fallback-routing`
- 결정: 재배포 가능한 품질 fallback이 준비될 때까지 단일 reference coverage `<0.03` 입력은 생성하지 않는다.
- 구현: Dart coverage extractor를 백그라운드 분석 isolate에서 실행하고 모델·생성 worker·artifact 생성 전에
  검사해 typed exception으로 중단한다. 분석 중 취소도 생성 진입 전에 반영한다.
- UX: 한국어·영어 원인 설명과 다른 사진 선택 action을 제공한다. 일반 오류나 성공으로 표시하지 않는다.
- 정상 경로: coverage `>=0.03`은 기존 neural 생성 계약을 유지하고 결과 metadata에 coverage를 기록한다.
- 회귀 검증: `flutter analyze` 0건, Flutter 508 pass/fixture 1 skip, ML 계약 13 pass,
  `git diff --check` 통과.
- 객관 판정: 저 coverage는 지원된 것이 아니라 안전하게 거부된다. 실제 사용자 분포의 오탐·미탐과 물리
  iOS/Android G6가 남아 있으므로 릴리스 평가는 **조건부**다.

### 2026-08-31 Color-v3 iPhone 17 physical Profile G6

- 기기: iPhone 17 (`iPhone18,3`), iOS 26.6.1 (23G83), USB, Profile build.
- 후보 생성: cold interpreter proxy 5회 p95 `158.671ms`, warm 30회 p50/p95
  `130.158/135.138ms`, peak RSS delta `160.8MiB`, after delta `51.7MiB`.
- 편집: frame p95 `0.808ms`, warm preview p95 `34.045ms`, 첫 export progress `473.294ms`,
  cancel 복귀 `266.527ms`; preview와 export-cancel gate 통과.
- 4K: production isolate가 3840×2160 JPEG를 `2,466.671ms`에 완주했고 signature·크기 검증 통과.
  peak RSS delta `141.7MiB`, 2초 후 `-11.5MiB`로 회수됐다.
- 실패: 4K progress update 최대 공백 `1,192.904ms`로 500ms full-export 기준 초과.
- 상태 계약: 편집 적용/초기화/back, crop reset, v3 draft 복원 5/5 통과.
- 권한: 실제 첫 실행에서 전체 사진 library 권한 선요청 없음. Profile 전용 local-network 팝업만 관측.
- 신규 위험: 실제 앱 시작 시 `LiteRtMetalAccelerator`/`LiteRt` Objective-C class 중복 경고 다수. 앱은
  실행됐지만 경고가 casting/crash 가능성을 명시하므로 릴리스 전 제거 또는 upstream 고정이 필요하다.
- 미측정: PhotoKit picker·limited/denied/re-authorize·실제 저장, Android 전체 G6.
- 판정: iOS 성능은 좁은 범위 통과이나 전체 릴리스는 **조건부**.
