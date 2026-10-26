# 온디바이스 참조 사진 기반 전역 룩 생성 설계

> 검토 기준일: 2026-07-15
>
> 대상 저장소: `memoria`
>
> 문서 성격: 현재 구현 감사, 장애 진단, 목표 설계, 검증 기준, 단계별 개발 계획

## 0. 기술 요약

사용자가 제공한 참조 사진 1~5장의 공통 색감을 추정해 하나의 전역 필터로 저장하는 제품 방향은 타당하다. 다만 현재 품질 문제를 LUT 해상도 부족이나 모델 부재로만 보면 안 된다. 현재 코드에는 색 통계 과적용 외에도 모델 입출력 불일치, LUT 축 순서 위험, 색공간·EXIF 처리 누락, 약한 다중 이미지 융합, 안전성 검사 부재가 함께 존재한다.

따라서 개발 순서는 다음으로 고정한다.

1. **현재 회색화·색반전 문제를 재현하고 처리 단계별로 원인을 분리한다.**
2. **LUT 축, 텐서 layout, 입력 정규화, 색공간을 하나의 계약으로 통일한다.**
3. **identity 기반 residual LUT와 정량 안전성 검사를 먼저 완성한다.**
4. **1~5장 강건 융합과 신뢰도 기반 강도 조절을 추가한다.**
5. **안전한 알고리즘 기준선이 확보된 후에만 LUT bank나 경량 ML을 도입한다.**

현재 신경망 경로는 배포 가능한 상태가 아니다. 컬러 전이 모델 URL과 체크섬이 비어 있고, 앱이 기대하는 5³ NHWC 출력과 학습 파이프라인의 17³ NCHW 출력이 일치하지 않는다. 현재 사용자 기능은 사실상 알고리즘 경로가 담당하고 있으므로, 1차 목표는 새 모델 도입이 아니라 기존 경로의 정확도와 안전성 확보다.

## 1. 제품 목표와 명시적 비목표

### 1.1 목표

사용자가 제공한 참조 사진 **1~5장**에서 공통적인 전역 색감 신호를 추정해, 다른 사진에 반복 적용할 수 있는 **하나의 전역 룩 필터**를 생성한다.

- 색온도, 틴트, 대비, 톤 분포, 채도, 색조 편향을 재현한다.
- 참조 사진의 피사체나 조명을 필터 자체로 오인하는 정도를 줄인다.
- 결과가 위험하면 강도를 자동으로 낮추거나 identity에 가까운 안전한 결과로 폴백한다.
- 생성과 적용은 모두 온디바이스에서 처리한다.
- 필터 적용은 GPU LUT 기반으로 즉시 반응해야 한다.
- 서버로 원본 사진, 특징 벡터 또는 생성 결과를 전송하지 않는다.

### 1.2 비목표

- 참조 사진의 구도, 피사체, 얼굴, 하늘 또는 질감을 새로 생성하지 않는다.
- 영역마다 서로 다른 보정을 적용하는 국소 편집 필터를 만들지 않는다.
- 한 장의 완성 사진만 보고 원래 편집자의 정확한 슬라이더 값을 복원한다고 약속하지 않는다.
- 대형 diffusion 또는 image-to-image 모델을 온디바이스에서 실행하지 않는다.
- Image-Adaptive-3DLUT이나 AdaInt의 사전학습 가중치를 그대로 넣으면 참조 룩 복제가 해결된다고 가정하지 않는다.

### 1.3 사용자에게 약속할 수 있는 결과

참조 사진에는 피사체 색, 촬영 조명, 카메라 ISP, 압축, 후보정이 함께 섞여 있다. 원본과 보정본 쌍이 없는 상태에서는 실제 편집 과정을 유일하게 역산할 수 없다.

따라서 제품 문구는 다음 수준이 적절하다.

> 참조 사진 1~5장에서 반복적으로 나타나는 전역 색감과 톤을 분석해, 다른 사진에도 안정적으로 적용할 수 있는 룩으로 만든다.

삼성 달 촬영과 같은 기술을 그대로 적용하는 것은 아니다. 삼성의 공식 설명은 달 객체 인식, 10장 이상의 멀티프레임 합성, 노이즈 제거, 딥러닝 디테일 향상을 조합한다. 이 제품은 해당 구현이 아니라 **입력이 부족한 상황에서도 결과를 안전하게 정돈한다는 제품 철학**만 참고한다.

## 2. 용어와 처리 범위

| 용어 | 정의 |
| --- | --- |
| 참조 사진 | 사용자가 원하는 색감이 포함된 1~5장의 사진 |
| 대상 사진 | 생성된 필터를 적용할 별도의 사진 |
| 전역 룩 | 모든 픽셀에 동일한 함수로 적용되는 색·톤 변환 |
| 스타일 기술자 | 참조 사진의 톤, 색 편향, 채도, 품질 등을 요약한 수치 벡터 |
| identity LUT | 입력 RGB를 같은 RGB로 반환하는 LUT |
| residual LUT | identity에서 얼마나 변화하는지만 표현한 LUT |
| 통계 마스크 | 피부·하늘·중성색 등을 룩 추정에서 보호하기 위한 마스크. 최종 적용 영역을 나누는 용도가 아님 |
| 안전성 검사 | 저장 전 LUT의 clipping, 중성축, 연속성, 휘도 단조성 등을 검사하는 절차 |
| `FilterRecipe` | 목표 데이터 모델. 현재 코드에는 아직 없으며 기존 `FilterPreset + AdjustParams + lut.bin`을 버전화해 대체 또는 감싸야 함 |

## 3. 현재 구현 감사

### 3.1 연결되어 있는 기능

현재 앱은 다음 사용자 흐름까지 연결되어 있다.

1. 사용자가 사진을 여러 장 선택한다.
2. 최대 5장만 유지한다.
3. 별도 isolate에서 이미지를 디코딩하고 LUT를 생성한다.
4. 65³ float16 LUT를 `lut.bin`으로 저장한다.
5. 썸네일과 grain 기본값을 저장한다.
6. `FilterPreset`으로 영속화하고 편집기의 CPU/GPU 경로에서 적용한다.

이 연결 자체는 재사용 가치가 높다. 새 설계에서도 파일 선택, isolate, 저장소, LUT atlas, GPU shader 경로는 유지하는 편이 효율적이다.

### 3.2 실제 실행 경로

| 조건 | 실제 실행 경로 | 현재 상태 |
| --- | --- | --- |
| 참조 1장 + 컬러 모델 `ready` | `LutPredictor` 신경망 경로 | 모델 미배포 및 계약 불일치로 실사용 준비 안 됨 |
| 참조 1장 + 모델 미준비/실패 | 알고리즘 경로 | 현재 일반적인 실행 경로 |
| 참조 2~5장 | 항상 알고리즘 경로 | 현재 다중 이미지 실행 경로 |

신경망 호출 실패는 빈 `catch`로 삼켜지고 알고리즘 경로로 폴백된다. 사용자 경험은 유지되지만 장애 원인과 폴백 비율을 파악할 수 없다. 개인정보를 남기지 않는 범위에서 오류 코드, 모델 버전, 폴백 이유, 소요 시간은 로컬 진단 로그로 기록해야 한다.

### 3.3 알고리즘 경로의 실제 동작

다중 이미지 경로는 LUT 셀을 직접 평균하지 않는다. 각 이미지에서 RGB 곡선, Lab 톤·색 편향, Oklab 통계, TPS 제어점을 추출한 후 특징별로 융합하고 LUT를 생성한다.

그러나 현재 융합은 충분히 강건하지 않다.

- 참조가 2장이면 특징별 산술평균을 사용한다.
- 3장 이상도 평균과 표준편차 기반 `1.5σ` 필터라 극단값이 남을 수 있다.
- 사진 전체가 다른 룩인지 판단하지 않고 각 특징을 따로 제거한다.
- 사진의 품질, 색역 범위, 노출 상태, 다른 참조와의 유사도를 가중치에 반영하지 않는다.
- UI 태그 생성용 `StyleAnalyzer.fuseProfiles()`와 실제 LUT 생성용 내부 융합 로직이 중복되어 서로 다른 결과를 낼 수 있다.

또한 다중 이미지 grain 크기는 누적값을 `1.0`에서 시작한 뒤 이미지 수로 나누므로 `1 / N`만큼 커지는 편향이 있다. 이 값은 `0.0`에서 누적하거나 별도의 강건 융합을 사용해야 한다.

### 3.4 신경망 경로의 차단 이슈

현재 모델 관련 문제는 장기 개선 사항이 아니라 **배포 전 차단 이슈**다.

| 항목 | 현재 상태 | 필요한 조치 |
| --- | --- | --- |
| 모델 배포 | URL, SHA-256, asset이 비어 있음 | 배포 전까지 기능 플래그로 명시적 비활성화 |
| 출력 LUT 차원 | 앱 래퍼는 5³ 고정, 학습은 `DECODER_DIM=17` | 출력 tensor shape를 런타임에서 읽거나 하나로 통일 |
| 입력 layout | 앱 래퍼 NHWC, 학습 NCHW | export 산출물과 앱 계약을 자동 테스트 |
| 입력 정규화 | 앱은 ImageNet 정규화, 학습·평가는 0~1 RGB | 학습·평가·Dart에서 같은 전처리 함수 사용 |
| LUT 축 순서 | 현재 래퍼의 순회 순서와 `r + gD + bD²` 인덱스가 다름 | `b → g → r` 순회 또는 명시 인덱스 대입으로 통일 |
| 구현 중복 | 해결: 검증된 `lut_predictor.dart`만 유지 | 공통 tensor contract 테스트 유지 |
| 테스트 | 모델이나 샘플 이미지가 없으면 smoke test가 성공처럼 종료 | CI fixture 모델을 포함하거나 명시적 skip 처리 및 별도 필수 잡 구성 |

모델 경로는 위 항목이 모두 통과하기 전까지 제품 품질 개선 수단으로 계산하지 않는다.

### 3.5 현재 증상을 만들 수 있는 위험 요소

사용자가 보고한 회색화, 채널이 0으로 떨어지는 현상, 완전히 다른 색조는 한 가지 원인으로 단정할 수 없다.

| 처리 층 | 가능한 원인 | 대표 증상 |
| --- | --- | --- |
| 입력 디코딩 | EXIF 회전, ICC/P3/HDR 미처리 | 분석 영역 불일치, 기기별 색 차이 |
| 스타일 추정 | 피사체나 조명을 룩으로 오인 | 특정 장면에서만 강한 색 편향 |
| 다중 융합 | 서로 다른 룩의 약한 평균 | 색이 탁해지거나 중간 톤으로 수렴 |
| LUT 생성 | covariance/TPS 변환 과적용, 반복 clamp | 0/1 clipping, 회색화, 색 반전 |
| 직렬화 | 축 순서, 차원, byte order 불일치 | 특정 채널 또는 색역이 완전히 바뀜 |
| GPU 적용 | atlas 좌표 또는 CPU/GPU 보간 차이 | 미리보기와 저장 결과 불일치 |

## 4. 가장 먼저 수행할 장애 진단

새 알고리즘을 추가하기 전에 현재 문제를 아래 테스트로 재현하고 어느 처리 층에서 시작되는지 확인한다.

### 4.1 최소 진단 fixture

- 17³, 33³, 65³ identity LUT
- R, G, B 단색 ramp
- 중성 회색 ramp
- 24색 ColorChecker 유사 synthetic swatch
- 피부색, 하늘색, 식물색, 네온색의 경계 swatch
- sRGB JPEG, Display P3 JPEG/PNG, 회전 EXIF JPEG, HEIC/HDR 입력
- 실제 회색화가 발생한 참조 사진과 대상 사진

실제 사용자 사진은 저장소에 넣지 않는다. 사용 허가가 명확한 재현 이미지만 테스트 fixture로 관리한다.

### 4.2 필수 교차 검증

| 검사 | 합격 조건 |
| --- | --- |
| identity CPU 적용 | 모든 fixture에서 허용 오차 내 원본 유지 |
| identity GPU 적용 | CPU 결과와 육안 차이가 없고 채널별 오차가 기준 이하 |
| 축 순서 검사 | 순수 R/G/B 입력이 대응 채널 ramp로 출력 |
| 직렬화 round trip | float → float16 bytes → float 복원 후 LUT 축과 값 유지 |
| 33³→65³ 업샘플 | identity와 선형 LUT의 단조성 유지 |
| 미리보기/내보내기 일치 | 동일 입력·recipe의 CPU 저장 결과와 GPU 미리보기 차이가 기준 이하 |
| 입력 정규화 | Python, TFLite, Dart 전처리 결과의 샘플 tensor가 일치 |
| tensor shape | 모델 실제 입력·출력 shape가 선언된 계약과 일치하지 않으면 로드 실패 |

### 4.3 진단 결과 기록

각 실패 사례에 다음 정보를 남긴다.

- 입력 포맷, 색공간, 방향 정보
- 참조 사진 수
- 선택된 생성 경로와 알고리즘 버전
- 생성 시간과 단계별 시간
- LUT 차원, 축 순서, 최소/최대값
- pre-clamp 및 post-clamp 비율
- 안전성 지표와 폴백 이유

원본 경로, 사진 내용, 얼굴 정보는 로그에 저장하지 않는다.

## 5. 목표 파이프라인

```text
참조 사진 1~5장
  → 방향 보정 및 표준 색공간 변환
  → 품질/색역/장면 커버리지 검사
  → 사진별 스타일 기술자 추출
  → 사진 전체 단위 일관성 검사
  → 특징별 강건 융합과 confidence 계산
  → versioned FilterRecipe 생성
  → identity + constrained residual LUT 생성
  → 런타임 안전성 검사
  → 실패 시 residual 강도 축소 및 재검사
  → 안전한 LUT와 recipe 저장
  → GPU 전역 LUT로 즉시 적용
```

색 통계 분석과 grain 분석은 같은 축소 이미지를 공유하지 않는다.

- 색·톤 분석: 긴 변 기준 256~512px의 방향 보정된 이미지
- grain 분석: 원본 크기에 가까운 평탄 영역의 여러 crop 또는 별도 다중 스케일 분석
- 썸네일: 별도 128px 결과

## 6. 입력 정규화와 색 관리

색 정확도를 높이려면 LUT 이전에 입력 계약부터 고정해야 한다.

### 6.1 표준 내부 표현

첫 구현의 표준 내부 표현은 다음으로 제한한다.

- RGB primaries: sRGB
- white point: D65
- transfer: sRGB encoded RGB
- 채널 범위: `[0, 1]`
- LUT 축 순서: `r + g × dim + b × dim²`, RGB interleaved
- LUT 저장: little-endian IEEE 754 float16
- alpha: LUT 분석에서 제외하고, 적용 시 원본 alpha 보존

3D LUT를 linear RGB에 적용할지 encoded sRGB에 적용할지는 결과가 크게 다르다. 현재 색 변환 함수와 shader 흐름에 맞춰 첫 버전은 encoded sRGB로 고정하고, 추후 linear workflow를 도입하면 recipe 버전을 올린다.

### 6.2 입력 처리 규칙

1. EXIF 방향을 bake한다.
2. ICC profile이 있으면 sRGB로 변환한다.
3. Display P3, HDR, wide-gamut 입력을 지원하지 못하는 플랫폼에서는 명시적으로 SDR sRGB로 tone-map하거나 생성 기능에서 제외한다.
4. 디코더가 색공간 정보를 버리는지 플랫폼별 fixture로 검증한다.
5. 분석, 미리보기, 내보내기가 동일한 표준 표현을 사용한다.

색 관리가 구현되기 전에는 Display P3/HDR 사진에서 정확한 색 복제를 보장한다고 표시하면 안 된다.

## 7. 사진별 스타일 기술자

스타일 기술자는 원본 픽셀 배열이나 팔레트 자체가 아니라 다음 특징으로 구성한다.

### 7.1 전역 톤

- 휘도 histogram 또는 quantile 1/5/10/25/50/75/90/95/99%
- 검정점, 흰점, 중간 회색 위치
- 그림자·중간톤·하이라이트의 국소 기울기
- 대비와 dynamic-range 압축 정도
- 과다 노출 및 암부 뭉침 비율

### 7.2 전역 색감

- Lab/Oklab의 그림자·중간톤·하이라이트 중심
- 중성 후보 픽셀의 색온도·틴트 편향
- hue band별 채도와 밝기 분포
- 색역 면적과 색상 커버리지
- 강한 단색 피사체가 차지하는 비율

### 7.3 보호 통계

- 중성색 후보 비율
- 피부색 후보 비율
- 하늘·식물·네온 등 강한 의미색 후보 비율
- 각 후보 영역의 confidence

통계 마스크는 전역 LUT 추정값의 가중치를 조절할 뿐, 최종 사진에서 영역별로 다른 LUT를 적용하지 않는다. 첫 버전은 Lab/Oklab 기반 휴리스틱으로 시작하고, 휴리스틱이 반복적으로 실패할 때만 경량 세그멘테이션 모델을 비교한다.

### 7.4 품질과 신뢰도

- 심한 블러
- 과다·과소 노출
- JPEG block/noise
- 작은 색역 또는 거의 단색인 이미지
- 중성점 부재
- 다른 참조와의 스타일 거리

grain은 스타일 기술자와 분리한다. 1차 출시에서는 정확한 grain 추정이 검증되지 않으면 사용자가 직접 조절하도록 기본값을 0으로 두는 편이 잘못된 자동 추정보다 안전하다.

## 8. 참조 사진 1~5장 융합

### 8.1 단순 평균을 사용하지 않는 이유

픽셀, 팔레트 또는 LUT 셀을 단순 평균하면 장면 내용이 섞인다. 따뜻한 인물 사진 네 장과 강한 네온 야경 한 장을 평균했을 때 네온 피사체가 전체 필터를 푸르게 만들 수 있다.

### 8.2 참조 수별 정책

| 참조 수 | 정책 |
| --- | --- |
| 1장 | 참조 간 일관성을 계산할 수 없으므로 색역·중성점·노출 커버리지로 confidence 산출 |
| 2장 | 어느 한 장이 이상치인지 자동 판정하지 않음. 거리가 크면 약한 룩 생성 또는 재선택 안내 |
| 3~5장 | 사진 단위 medoid와 MAD 기반 거리로 이상치 후보를 찾고, 특징별 Huber/weighted median 융합 |

### 8.3 권장 융합 절차

1. 특징별 단위를 정규화한다.
2. 각 사진 쌍의 스타일 거리를 계산한다.
3. 전체 거리 합이 가장 작은 사진을 medoid로 선택한다.
4. medoid와의 거리가 `median + k × MAD`를 넘으면 이상치 후보로 표시한다.
5. 품질, 장면 커버리지, medoid 유사도를 이용해 사진별 가중치를 계산한다.
6. tone quantile은 weighted median, 연속 곡선은 Huber 평균 후 단조성 보정, 원형 hue는 circular mean으로 융합한다.
7. 융합 후에도 참조 간 분산을 `confidence`에 반영한다.

초기 `k`와 각 가중치는 고정 진리가 아니다. synthetic fixture와 실제 사용자 평가로 조정해야 한다.

### 8.4 낮은 신뢰도 처리

- confidence 높음: 요청 강도까지 생성
- confidence 중간: residual 강도를 자동 축소하고 미리보기 제공
- confidence 낮음: identity에 가까운 결과와 사진 재선택 안내
- 참조가 서로 상충: 무리하게 평균하지 않고 상충 사실을 표시

사용자 흐름을 막지 않기 위해 완전 실패보다 “약하게 생성 + 이유 표시”를 기본으로 하되, 안전성 검사 실패는 저장을 금지한다.

## 9. `FilterRecipe` 목표 스키마

현재 코드에는 `FilterRecipe`가 없다. 아래 구조는 목표 스키마이며, 기존 `FilterPreset`, `AdjustParams`, `lut.bin`과의 마이그레이션을 포함해 구현해야 한다.

```text
FilterRecipe v1
  - recipeVersion
  - engineVersion
  - presetId
  - lutPath
  - lutDim
  - lutAxisOrder
  - colorSpace
  - transferFunction
  - residualStrength
  - toneCurve or toneParameters
  - optional HSL/split-tone parameters
  - grainStrength / grainSize / grainSeed
  - confidence
  - referenceCount
  - safetyMetrics
  - fallbackReason
  - generatorType
  - modelId / modelVersion, if used
  - assetProvenance, if LUT bank or external weights are used
```

### 9.1 보정 책임 분리

같은 톤 변환을 `AdjustParams`와 3D LUT에 동시에 넣으면 이중 보정이 발생한다. 각 요소의 책임을 고정한다.

- 1D tone curve: 전역 휘도와 대비
- 3D residual LUT: 색 편향, 채도, hue interaction
- grain: LUT 이후 별도 효과
- intensity: 원본과 전체 recipe 결과 사이의 최종 보간

현재 엔진의 `Adjust → LUT → intensity → grain` 순서와 호환되도록 설계하되, 저장 결과와 GPU 미리보기가 동일한 순서를 사용해야 한다.

## 10. LUT 생성 원칙

### 10.1 Identity residual

참조 분포로 LUT를 직접 덮어쓰지 않는다.

```text
candidateColor = identityColor + strength × constrainedResidual(identityColor)
```

`strength`는 참조 confidence와 안전성 검사 결과에 의해 제한한다. residual은 생성 중에는 clamp하지 않은 값도 유지해 clipping 원인을 측정하고, 안전성 검사가 끝난 최종 LUT만 `[0, 1]`로 저장한다.

### 10.2 필요한 제약

- 검정과 흰색 endpoint는 고정하지 않고 허용 범위 안에서만 이동시킨다. lifted black이나 soft white 같은 의도적 룩을 허용해야 한다.
- 회색 ramp의 휘도는 단조 증가해야 한다.
- 중성축 tint는 허용하되 갑작스러운 hue 전환을 금지한다.
- 인접 LUT 셀의 변화율을 제한한다.
- 서로 다른 입력 색이 넓은 영역에서 같은 출력으로 수렴하는 fold-over를 제한한다.
- 피부색, 중성색, 고채도 기본색의 채도 붕괴를 검사한다.
- pre-clamp 값과 post-clamp 값을 모두 검사한다.

### 10.3 LUT 차원

생성 후보는 33³으로 시작하고 기존 엔진이 요구하면 65³으로 업샘플할 수 있다. 다만 “33³이면 충분하다”를 전제로 확정하지 않는다. 17³, 33³, 65³을 동일한 synthetic LUT 세트에서 비교한 뒤 결정한다.

| 차원 | 셀 수 | RGB float16 크기 |
| --- | ---: | ---: |
| 17³ | 4,913 | 29,478 bytes / 0.029 MB |
| 33³ | 35,937 | 215,622 bytes / 0.216 MB |
| 65³ | 274,625 | 1,647,750 bytes / 1.648 MB |

65³ 해상도를 높이는 것만으로 스타일 추정 오류는 해결되지 않는다. 잘못된 변환을 더 촘촘하게 저장할 뿐이다.

## 11. 런타임 안전성 검사와 폴백

### 11.1 런타임 검사 대상

온디바이스 생성 시에는 고정 RGB grid, 회색 ramp, 기본 hue/saturation swatch만 검사한다. 실제 대표 이미지 세트는 앱에 포함하지 않고 CI visual regression에서 사용한다.

### 11.2 초기 안전 지표

아래 값은 **초기 제안치**이며 실제 fixture와 사용자 평가로 보정해야 한다.

| 지표 | 초기 기준 | 실패 시 처리 |
| --- | --- | --- |
| finite 값 | NaN/Inf 0개 | 즉시 폐기 |
| interior pre-clamp | 내부 grid에서 `[0,1]` 밖 비율 1% 미만 | residual 축소 |
| endpoint 휘도 | black ≤ 0.08, white ≥ 0.92 | tone strength 축소 |
| 회색 ramp 단조성 | 역전 0개 | tone curve 재보정 |
| 인접 변화율 | p99와 최대값이 캘리브레이션 상한 이하 | smoothness 증가 |
| 중성축 색 변화 | 연속적이고 캘리브레이션 상한 이하 | neutral 보호 증가 |
| 고채도 swatch 유지 | 의도적 저채도 룩이 아니면 급격한 0 수렴 금지 | chroma residual 축소 |

CPU/GPU parity는 필터 생성 때마다 수행하지 않는다. identity, 단색 ramp, 대표 recipe를 대상으로 CI와 출시 검증에서 수행한다.

중성축 ΔE나 채도 유지율을 너무 낮게 고정하면 의도적인 warm film, bleach bypass, faded 룩을 제거할 수 있다. 안전 기준은 절대값과 참조에서 추정된 의도를 함께 사용해야 한다.

### 11.3 폴백 절차

1. residual 강도 `1.0`으로 검사한다.
2. 실패하면 `0.75 → 0.5 → 0.25` 순으로 줄이며 재검사한다.
3. 모두 실패하면 identity 또는 검증된 안전 baseline으로 폴백한다.
4. 저장 결과에 최종 강도, 실패 지표, `fallbackReason`을 기록한다.
5. 안전성 실패를 빈 `catch`로 숨기지 않는다.

## 12. 온디바이스 성능 설계

### 12.1 처리 원칙

- 색 분석은 256~512px에서 수행한다.
- 참조별 분석은 독립적이므로 isolate 내부에서 순차 처리하되 메모리 상황에 따라 제한적 병렬화를 검토한다.
- 65³ 전체를 여러 번 생성하기보다 33³ 후보에서 검사하고 최종 한 번만 업샘플한다.
- 미리보기와 재적용은 GPU shader/LUT를 사용한다.
- 고해상도 원본은 저장 시 한 번만 렌더링한다.
- 디코딩된 원본 5장을 동시에 장시간 보관하지 않는다.
- 모델을 추가해도 출력은 이미지가 아니라 작은 recipe와 LUT여야 한다.

### 12.2 잠정 성능 예산

실제 목표 기기군을 확정한 뒤 수치를 조정한다.

| 항목 | 잠정 목표 |
| --- | --- |
| 1장 필터 생성 | 중급 기기 p95 1초 이내 |
| 5장 필터 생성 | 중급 기기 p95 3초 이내 |
| LUT 안전성 검사 | 300ms 이내 |
| 편집 미리보기 | 일반 화면 크기에서 30fps 미만으로 지속 하락하지 않음 |
| 필터 재적용 준비 | 저장된 recipe 로드 후 100ms 이내 |
| peak memory | 5장 입력에서 OS 메모리 압박 없이 동작; 기기별 수치 계측 필수 |

성능은 평균만 기록하지 않고 p50/p95, 입력 해상도, 기기 모델, 배터리 상태, cold/warm 실행을 함께 기록한다.

## 13. 학습 없이 품질을 올리는 순서

### 13.1 1단계: 안전한 분석 기반 생성

- 강건한 기술자와 융합
- identity residual
- 정량 안전성 gate
- 신뢰도 기반 강도 조절
- 사용자가 직접 조절할 수 있는 최종 intensity

이 단계만으로 현재 회색화와 극단적 색반전 문제를 먼저 줄여야 한다.

### 13.2 2단계: 권리가 확인된 LUT/recipe bank

1. 상업적 사용과 재배포 권리가 명확한 LUT만 수집한다.
2. 각 LUT를 공통 기술자 공간에 임베딩한다.
3. 참조 기술자와 가까운 후보를 검색한다.
4. 상위 후보의 residual을 제한적으로 합성한다.
5. 최종 후보도 동일한 안전성 검사를 통과시킨다.

LUT bank는 라이브러리에 없는 임의 룩을 정확히 복제할 수 없다. 안전한 초기값과 탐색 공간을 제공하는 용도로 한정한다.

### 13.3 3단계: 선택적 임베딩 모델

CLIP류 모델은 `warm film`, `muted green`, `high contrast` 같은 무드 분류나 LUT 후보 순위에만 사용할 수 있다. 정밀 색 변환을 직접 출력하는 모델로 사용하지 않는다. 모델 크기와 라이선스가 온디바이스 요구에 맞지 않으면 기술자 기반 검색을 유지한다.

## 14. 외부 모델 평가 기준

사용자는 MIT 라이선스 활용을 우선한다. Apache-2.0도 상업적으로 널리 사용되는 permissive 라이선스지만, 정책상 MIT만 허용한다면 후보에서 제외해야 한다.

| 후보 | 코드 라이선스 | 원래 목적 | 참조 룩 복제 적합성 | 현재 판단 |
| --- | --- | --- | --- | --- |
| OpenAI CLIP | MIT | 이미지·텍스트 임베딩 | 낮음. 후보 검색 보조만 가능 | 선택 기능 후보 |
| Image-Adaptive-3DLUT | Apache-2.0 | 학습된 자동 사진 향상 | 구조 참고는 유용하나 임의 참조 복제 모델은 아님 | 논문·구조 참고 |
| AdaInt | Apache-2.0 | adaptive interval 기반 자동 향상 | 구조 참고는 유용하나 임의 참조 복제 모델은 아님 | 논문·구조 참고 |
| MediaPipe segmentation | 구성요소별 확인 필요 | 온디바이스 영역 분할 | 보호 통계에는 보조적 | 휴리스틱 실패 후 검토 |

각 후보는 다음을 별도로 확인한다.

- 코드 라이선스
- 사전학습 가중치 라이선스
- 학습 데이터 라이선스와 상업적 사용 제한
- 수정 가중치의 재배포 조건
- 앱 고지 및 NOTICE 의무
- iOS/Android 변환 가능성
- 모델 크기, 메모리, p95 지연시간
- 참조 룩 복제 문제에 실제로 도움이 되는지에 대한 baseline 비교

저장소에 라이선스 파일이 있다는 사실만으로 외부 체크포인트와 데이터 사용 권리까지 자동으로 확정하지 않는다. 법률 자문이 필요한 배포 결정은 별도로 검토한다.

## 15. ML 확장 조건

직접 학습이나 외부 모델 결합은 다음 조건을 모두 만족한 뒤 시작한다.

- 알고리즘 baseline이 안전성 gate를 안정적으로 통과한다.
- Python, export, TFLite/CoreML, Dart의 전처리와 tensor 계약이 동일하다.
- LUT axis와 color-space 계약이 테스트로 고정되어 있다.
- 권리가 확인된 synthetic 정답 세트와 실제 선호 평가 세트가 분리되어 있다.
- 실패 사례와 사용자의 강도 조절·저장·삭제 신호가 개인정보 없이 수집 가능하다.
- ML이 baseline보다 품질 또는 속도를 유의하게 개선한다.

모델은 65³ LUT 전체를 직접 출력하기보다 다음처럼 제한된 recipe를 예측하는 편이 안전하다.

```text
ML output
  - basis LUT weights
  - small residual LUT or residual coefficients
  - tone/chroma parameters
  - confidence
```

최종 LUT는 모델 출력 뒤에도 동일한 deterministic 안전성 gate를 통과해야 한다.

## 16. 품질 평가 계획

### 16.1 평가 세트

1. **Synthetic 정확도 세트**: 권리가 확인된 LUT를 다양한 중립 이미지에 적용해 원본·보정본·정답 LUT를 모두 보유한다.
2. **안전성 fixture**: 회색 ramp, 단색 ramp, 고채도 swatch, skin/sky/foliage 색상, 색공간·회전 입력.
3. **실제 참조 세트**: 장면이 다른 1~5장에 동일한 룩이 적용된 사례와 서로 다른 룩이 섞인 실패 사례.
4. **사용자 선호 세트**: 익명화되고 사용 권리가 명확한 A/B 평가 결과.

### 16.2 핵심 지표

| 목표 | 지표 |
| --- | --- |
| 정답 LUT 복원 | ColorChecker 및 random RGB grid의 ΔE00, PSNR |
| 참조 룩 유사도 | tone quantile 거리, Lab/Oklab zone 거리, hue-band 거리 |
| 안전성 | clipping 비율, 중성축 변화, saturation collapse, monotonicity, 인접 변화율 |
| 일관성 | 같은 룩의 서로 다른 장면에서 생성된 recipe 간 거리 |
| 다중 참조 효과 | 1장 대비 3장/5장의 정확도와 실패율 변화 |
| 사용자 품질 | 저장률, 즉시 삭제율, intensity 수정량, A/B 선호율 |
| 속도 | 생성 p50/p95, preview fps, peak memory, 모델/앱 크기 |

ΔE만 낮다고 좋은 룩은 아니다. 정확도, 안전성, 사용자의 시각적 선호를 따로 측정한다.

### 16.3 출시 gate

정확한 숫자는 평가 세트를 만든 뒤 확정하되, 최소한 다음 조건이 필요하다.

- identity와 축 순서 테스트 100% 통과
- CPU/GPU 미리보기·저장 parity 통과
- 회색화·색반전 알려진 재현 사례 0건
- 안전성 검사 실패 결과가 저장되는 사례 0건
- 기준 기기에서 성능 예산 충족
- 외부 asset의 라이선스 체크리스트 완료
- 알고리즘 baseline보다 나쁜 ML 모델은 배포하지 않음

## 17. 단계별 구현 계획

### P0. 현재 결함 제거와 진단 기반 구축

- 완료: 중복 native/stub 구현을 제거하고 `lut_predictor.dart`의 단일 계약으로 통합했다.
- 모델 output dimension을 런타임 검증한다.
- LUT 축 저장 순서를 수정하고 단색 ramp 테스트를 추가한다.
- 학습·평가·Dart 전처리를 동일하게 만든다.
- 모든 참조 디코딩에 EXIF 방향 보정을 적용한다.
- grain 크기 누적 초기값 편향을 수정한다.
- 빈 `catch`를 구조화된 로컬 진단과 `fallbackReason`으로 교체한다.
- identity, 직렬화, CPU/GPU parity 테스트를 필수 CI로 만든다.

### P1. 안전한 알고리즘 baseline

- 색·톤 기술자를 단일 모듈로 통합한다.
- tone과 chroma residual의 책임을 분리한다.
- identity residual LUT 생성을 구현한다.
- pre-clamp 지표와 런타임 안전성 gate를 추가한다.
- 강도 단계 축소와 identity 폴백을 구현한다.
- 실제 회색화 사례를 회귀 테스트로 고정한다.

### P2. 1~5장 강건 융합

- 사진 단위 거리, medoid, MAD 기반 이상치 검사를 구현한다.
- 참조 수별 정책과 confidence를 구현한다.
- 낮은 신뢰도 UX와 사진 재선택 안내를 추가한다.
- 동일 룩/다른 장면과 상충 룩 세트로 평가한다.

### P3. 버전 recipe와 LUT bank

- `FilterRecipe v1`과 기존 preset 마이그레이션을 구현한다.
- color-space, axis, engine version, safety metrics를 저장한다.
- 권리가 확인된 LUT bank와 provenance manifest를 추가한다.
- 기술자 기반 후보 검색을 baseline과 비교한다.

### P4. 선택적 경량 ML

- MIT 우선 라이선스 후보를 재검토한다.
- 작은 basis weight 또는 residual coefficient 예측 모델만 실험한다.
- baseline 대비 품질·속도·메모리를 동일 세트에서 비교한다.
- deterministic 안전성 gate를 통과한 모델만 제품 경로에 연결한다.

현재 구현은 **실험 전용**이다. `ml_pipeline/8_train_basis.py`는 외부
사전학습 가중치 없이(`pretrained=False`) 17³ residual basis 8개와 bounded
coefficient 예측기를 학습한다. `9_benchmark_basis.py`는 coefficient RMSE,
CPU p50/p95, Python-visible peak memory를 JSON으로 기록하고,
`10_export_basis.py`는 coefficient-only TFLite와 basis binary를 내보낸다.
앱 제품 경로에는 아직 연결하지 않으며, 입력 asset과 coefficient 모델 계약이
확정되지 않은 runtime scaffold도 제거했다. 향후 다시 도입할 때는 현재
`constrainCustomLut`과 동일한 deterministic safety gate를 통과해야 한다.

외부 후보의 2026-07 검토 결과는 다음과 같다.

- Apple MobileCLIP은 저장소 코드는 MIT이지만, 모델 가중치는 연구 목적만
  허용하므로 제품 가중치 후보에서 제외한다.
- OpenAI CLIP 저장소 코드는 MIT이지만, 해당 모델 카드는 일반 배포 사용을
  권장하지 않으므로 제품 경로에 사용하지 않는다.
- 따라서 현 단계에는 외부 이미지 모델이나 가중치를 번들·다운로드하지 않고,
  자체 생성 데이터로 학습한 작은 coefficient head만 비교한다.

## 18. 코드 변경 예상 지점

| 영역 | 주요 파일 | 변경 방향 |
| --- | --- | --- |
| 생성 라우팅 | `lib/engine/lut_engine.dart` | 오류 가시화, 폴백 사유, grain 편향 수정, recipe 반환 |
| LUT 생성 | `lib/engine/custom_lut_core.dart` | residual 생성, 강건 융합, pre-clamp 지표, 안전성 검사 |
| 스타일 분석 | `lib/engine/style_analyzer.dart` | 중복 제거, 공용 기술자, 품질·coverage·confidence |
| 모델 계약 | `lib/ai/models/lut_predictor.dart` | tensor shape/layout/축 동적 검증, 단일 구현 |
| 모델 배포 | `lib/ai/ai_manager.dart` | 미배포 상태 명시, 버전·체크섬 검증 |
| 데이터 모델 | `lib/domain/models/filter_preset.dart` 및 신규 recipe 모델 위치 | 버전 필드와 마이그레이션 |
| GPU 적용 | `lib/engine/gpu_image_view.dart`, `assets/shaders/adjust.frag` | CPU/GPU parity와 axis contract 고정 |
| 학습·평가 | `ml_pipeline/3_train.py`, `6_evaluate.py`, `7_export_model.py` | 전처리·차원·layout 통일 |
| 테스트 | `test/whitebox_lut_core_test.dart`, `test/neural_lut_predictor_test.dart` 등 | 축, safety, multi-ref, 색공간, 실제 회귀 fixture |

## 19. 아직 결정해야 할 제품·기술 사항

다음 항목은 구현 전에 제품 결정이 필요하다.

1. MIT만 허용할지, Apache-2.0까지 허용할지
2. 첫 출시에서 Display P3, HEIC, HDR을 지원할지 sRGB SDR로 제한할지
3. grain 자동 복제를 첫 출시 범위에 포함할지
4. 참조가 상충할 때 생성을 막을지, 약한 결과를 제공할지
5. 지원할 최소 iPhone/Android 기기와 성능 기준 기기
6. 사용자 피드백 로그를 완전 로컬로만 둘지, 명시적 동의 후 익명 집계할지
7. recipe bank를 앱에 번들할지, 앱 업데이트로만 갱신할지

기본 권장값은 **sRGB SDR 우선, grain 자동 추정 제외, 상충 시 약한 결과 제공, 모든 생성 로그 로컬 유지**다.

## 20. 참고 자료

- [Samsung Galaxy 달 촬영 AI 설명](https://www.samsung.com/uk/support/mobile-devices/how-galaxy-cameras-combine-super-resolution-technologies-with-ai-to-produce-high-quality-images-of-the-moon/): 객체 인식, 멀티프레임 합성, AI detail enhancement의 역할.
- [Image-Adaptive-3DLUT](https://github.com/HuiZeng/Image-Adaptive-3DLUT): basis LUT와 작은 CNN을 조합하는 자동 사진 향상 구조. Apache-2.0.
- [AdaInt](https://github.com/ImCharlesY/AdaInt): 비균일 LUT 구간을 학습하는 실시간 자동 사진 향상 구조. Apache-2.0.
- [OpenAI CLIP](https://github.com/openai/CLIP): 이미지·텍스트 임베딩. 저장소 코드 라이선스 MIT.
- [MediaPipe Image Segmenter](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter): 온디바이스 segmentation 구현 참고.
- [TensorFlow Lite post-training quantization](https://www.tensorflow.org/model_optimization/guide/quantization/post_training): float16/int8 양자화 선택 참고.

> 라이선스는 코드, 모델 가중치, 학습 데이터, 변환 산출물 각각을 별도로 확인한다. 이 문서는 법률 자문이 아니다.
