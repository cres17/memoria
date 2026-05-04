# Memoria 개발 학습 가이드

> 이 앱을 완전히 이해하고 확장하기 위한 단계별 학습 경로.  
> 순서대로 공부하면 각 Phase의 코드가 왜 그렇게 짜여 있는지 자연스럽게 이해된다.

---

## 사전 준비 (공통 기반)

### Dart / Flutter 기초
- `async/await`, `Future`, `Stream`
- `StatefulWidget` 생명주기, `setState`
- `CustomPainter` — 커브 에디터, 오버레이 드로잉에 필수
- `GestureDetector` — 브러시/드래그 도구에 필수
- `Isolate` — 이미지 처리를 백그라운드에서 돌릴 때
- **연습**: `image` 패키지로 사진 픽셀 읽기/쓰기 10줄 코드 작성

### 이미지의 기본 구조
| 개념 | 핵심 내용 |
|------|---------|
| sRGB | 화면에 보이는 표준 색공간. 0~255 또는 0.0~1.0 정규화 |
| 채널 | R, G, B 각각 독립 0~255 값. 혼합하면 색 |
| 비트 깊이 | 8bit=256단계, 16bit=65536단계. float16은 LUT 저장용 |
| 픽셀 순서 | Row-major: `image[y * width + x]` |

---

## Phase 1 — 픽셀 단위 조절 (Adjust)

### 배워야 할 개념

**1. 선형 vs 비선형 밝기**
```
sRGB gamma: 모니터는 비선형. 0.5가 실제로는 절반 밝기가 아님
Exposure: 2^EV 배수 → 2EV = 4배 밝기 (stops 개념)
```

**2. S-Curve Contrast**
```python
# Snapseed/Photoshop 공식
factor = (259 * (contrast + 255)) / (255 * (259 - contrast))
output = factor * (input - 0.5) + 0.5
```
- 왜 이 공식인가: `contrast > 0`이면 중간값을 더 극단으로 밀어냄

**3. Gaussian Mask (Highlights/Shadows)**
```
mask = 픽셀 밝기에 따른 가중치 → 밝은 픽셀만, 또는 어두운 픽셀만 조절
weight = exp(-distance^2 / 2σ^2)   ← 가우시안 공식
```

**4. Unsharp Mask (Sharpen)**
```
sharp = original + strength × (original - gaussian_blur(original))
직관: 블러 이미지와의 차이 = 엣지/디테일 → 이걸 더하면 선명해짐
```

**5. Vignette (방사형 그라디언트)**
```
dist = sqrt((x/W - 0.5)^2 + (y/H - 0.5)^2) / 0.707
mask = 1 - dist^2 * strength
```
0.707 = 코너까지 거리(√(0.5²+0.5²)). 이걸 나누면 코너가 항상 최대 어두움

**6. Structure vs Clarity 차이**
| | Structure | Clarity |
|-|----------|---------|
| 커널 반경 | 3px (미세 엣지) | 15px (중간 주파수) |
| 대상 | 텍스처/디테일 | 미드톤 명료도 |
| 수식 | `orig - blur(r=1)` | `orig - blur(r=7)` × midMask |

### 핵심 파일
- [`lib/engine/lut_engine.dart`](lib/engine/lut_engine.dart) — `applyAdjustParams()` 함수
- [`lib/domain/models/adjust_params.dart`](lib/domain/models/adjust_params.dart) — 파라미터 정의

### 실습 과제
1. `applyAdjustParams()`에서 contrast 수식을 직접 바꿔서 차이 확인
2. `structure` 값을 +100으로 놓고 실제 사진에 적용해보기
3. Gaussian mask 공식에서 sigma를 바꾸면 어떻게 달라지는지 확인

---

## Phase 2 — 커브 에디터 (Curves)

### 배워야 할 개념

**1. LUT (Look-Up Table) 개념**
```
LUT = 미리 계산된 변환 테이블
input[0~255] → output[0~255]
적용: output = LUT[input_pixel]
빠른 이유: 복잡한 계산을 런타임에 하지 않고 테이블 참조만 함
```

**2. Cubic Spline 보간**
```
문제: 4개 컨트롤 포인트 사이를 부드러운 곡선으로 연결
해법: Natural Cubic Spline
  → 각 구간을 3차 다항식 a + bx + cx² + dx³ 으로 표현
  → 경계에서 2차 미분이 연속 (부드러운 연결)
```

**3. 색 채널별 커브 차이**
```
Luminance 커브: RGB → Lab → L채널에 적용 → RGB 변환
  장점: 색조 변경 없이 밝기만 조절
RGB 커브: R, G, B 동시에 동일 커브 적용
개별 채널: 특정 색상 강조/억제 가능
  예: R 커브 들어올리기 → 전체적으로 붉은 색감
```

**4. Lab 색공간** (Phase 3에서 자세히, 여기서 기초만)
```
L = 밝기 (0~100)
a = 초록↔빨강 (-128~+127)
b = 파랑↔노랑 (-128~+127)
특징: 인간 시각에 균등한 거리 → 색차 계산에 적합
```

### 핵심 파일
- [`lib/domain/models/curve_data.dart`](lib/domain/models/curve_data.dart) — 스플라인 보간 구현
- [`lib/features/editor/widgets/curve_editor.dart`](lib/features/editor/widgets/curve_editor.dart) — 드래그 UI

### 실습 과제
1. `CurveData.toLut()`를 직접 호출해서 포인트 [(0,0),(0.5,0.8),(1,1)]의 LUT 출력 확인
2. `_naturalCubicSpline()` 함수를 Step-by-Step 디버그 (Thomas algorithm)
3. `CurveEditorPanel`에서 점을 추가/삭제하며 UI 동작 확인

---

## Phase 3 — 색공간 & 색상 과학

### 배워야 할 개념

**1. White Balance 원리**
```
카메라 색온도: 태양(5500K) vs 텅스텐(3200K) vs 형광등(4000K)
보정: 차가운 광원(텅스텐) → R 올리기 + B 내리기
Memoria 구현: temperature → R/B 증감, tint → G 증감
```

**2. CIE Lab 완전 이해**
```
sRGB → Linear RGB → XYZ (D65) → Lab
각 단계:
  1. Gamma 제거: linear = ((srgb + 0.055) / 1.055)^2.4  (if > 0.04045)
  2. 행렬 변환: XYZ = M × [R, G, B]  (M = sRGB→XYZ 행렬)
  3. Lab 변환:
     f(t) = t^(1/3)        (if t > 0.008856)
           = 7.787t + 16/116  (otherwise)
     L = 116 × f(Y/Yn) - 16
     a = 500 × (f(X/Xn) - f(Y/Yn))
     b = 200 × (f(Y/Yn) - f(Z/Zn))
```

**3. ΔE 색차 (목표 정확도 < 2.0)**
```
ΔE = sqrt((L1-L2)^2 + (a1-a2)^2 + (b1-b2)^2)
ΔE < 1: 육안 구분 불가
ΔE < 2: 전문가만 인식
ΔE < 3: 일반인 겨우 인식
Memoria 목표: ΔE < 2.0 (98%+ 정확도)
```

**4. Black & White 채널 믹서**
```
L = wr×R + wg×G + wb×B + wy×(R+G)/2
기본(BT.601): wr=0.299, wg=0.587, wb=0.114
Film style: 레드 채널 올리기 → 피부 밝아지고 하늘 어두워짐
Darken Sky: 블루 채널 낮추기 → 드라마틱한 하늘
```

**5. Tonal Contrast (존별 S-Curve)**
```
각 픽셀 밝기(L)로 3구간 분류:
  Shadow  (L < 0.35): tonalShadows 파라미터로 S-curve 강도
  Midtone (0.35~0.65): tonalMidtones
  Highlight (L > 0.65): tonalHighlights
구간 가중치: Gaussian weight으로 부드러운 전환
  → 이게 Lightroom "Tone Curve" 패널의 존별 조절과 같은 원리
```

### 핵심 파일
- [`lib/engine/color_utils.dart`](lib/engine/color_utils.dart) — sRGB↔Lab 변환
- [`lib/engine/white_balance.dart`](lib/engine/white_balance.dart) — WB 프리셋 테이블
- [`lib/engine/lut_engine.dart`](lib/engine/lut_engine.dart) — `applyTonalContrast()`, `applyBnW()`

### 실습 과제
1. `rgbToLab(RgbColor(1.0, 0, 0))`의 결과 계산해보기 (순수 빨강의 Lab값)
2. WB 프리셋에서 텅스텐(-60 temp)을 적용했을 때 R/B 채널이 어떻게 변하는지 픽셀 추적
3. tonalShadows=+50, tonalMidtones=0, tonalHighlights=-30 적용 결과 확인

---

## Phase 4 — 아티스틱 이펙트

### 배워야 할 개념

**1. 블렌드 모드 공식**
```
Overlay:  dst<0.5 → 2×src×dst,  dst≥0.5 → 1-2×(1-src)×(1-dst)
Screen:   1 - (1-src)×(1-glow)         ← Glamour Glow
Multiply: src × dst                     ← 어둡게, Vignette 텍스처
Add:      src + dst (클리핑 주의)

Overlay 특징: 중간값(0.5) 불변, 극단값 강조 → 명암 대비 강화
```

**2. Grain (필름 입자) 구현**
```
grain_nils*.png = 실제 카메라 노이즈를 스캔/촬영한 PNG
적용: overlay blend로 중간 밝기 유지하면서 입자감 추가
타일링: 이미지보다 작은 텍스처 → x%tw, y%th로 반복
두 세트(nils vs nilsnew): 다른 입자 크기 → 레이어링으로 자연스러움
```

**3. Film Curves (필름 에뮬레이션)**
```
film_curves_def.png = Snapseed의 실제 필름 커브
구조: 256px 너비 PNG, 각 x 위치의 픽셀 색 = LUT 변환값
  → x=0: 입력 0의 출력, x=255: 입력 255의 출력
특징: 필름은 어두운 부분 올리고(faded blacks) 밝은 부분 압축
```

**4. HDR Scape (로컬 톤 매핑)**
```
개념: 전체 밝기 압축 + 로컬 디테일 강조
알고리즘:
  1. Gaussian blur = 저주파(ambient light)
  2. detail = L - lowpass    ← 고주파(엣지/텍스처)
  3. L_out = sigmoid(lowpass × compression) + detail × boost
  
sigmoid로 하이라이트 압축 → HDR 느낌
detail boost → 텍스처 선명
```

**5. Drama (고대비 스타일)**
```
= contrast 높이기 + clarity 강하게 + saturation 약간 낮추기
기술적으로는 Phase 1 파라미터 조합이지만
Snapseed는 이걸 preset 이름으로 노출
→ 사용자는 "Drama"라는 감성 레이블로 이해
```

### 핵심 파일
- [`lib/engine/artistic_effects.dart`](lib/engine/artistic_effects.dart) — 모든 이펙트 구현
- `assets/overlays/grain/` — grain_nils1~9.png
- `assets/overlays/curves/` — film_curves_def.png, noir curves

### 실습 과제
1. `_blendOverlay()` 공식을 엑셀에서 그래프로 확인 (0~1 입력 범위)
2. `film_curves_def.png`를 이미지 뷰어로 열어서 어떤 모양인지 확인
3. HDR Scape의 `_sigmoid()` 함수 그래프 그려보기 (compression 0.5 vs 0.9)

---

## Phase 5 — 기하학 변환

### 배워야 할 개념

**1. 이미지 변환 행렬 (Matrix4)**
```dart
// 회전
Matrix4.rotationZ(angle_rads)

// 크롭: 좌상단 (x1,y1) ~ 우하단 (x2,y2)
img.copyCrop(image, x: x1, y: y1, width: x2-x1, height: y2-y1)
```

**2. Perspective 변환 (원근 교정)**
```
문제: 건물을 아래서 찍으면 상단이 좁아 보임 (키스톤 왜곡)
해법: 4점 대응 → Homography 행렬 계산 → 역변환 적용

H = [h11 h12 h13]   (3×3 행렬)
    [h21 h22 h23]
    [h31 h32  1 ]

8개 자유도 → 4쌍의 대응점(x,y)으로 연립방정식 풀기
```

**3. Bilinear Interpolation (중간 픽셀 계산)**
```
변환 후 소수점 위치 (3.7, 5.2) → 4개 인접 픽셀로 가중 평균
  P(3.7, 5.2) ≈ (1-0.7)(1-0.2)×P(3,5) + 0.7(1-0.2)×P(4,5)
             + (1-0.7)×0.2×P(3,6) + 0.7×0.2×P(4,6)
역방향 매핑이 더 안정적: 출력 좌표 → 입력 좌표 역계산
```

### 구현 우선순위
1. **Crop** — 가장 단순, `img.copyCrop()` 래핑
2. **Rotate** — `img.copyRotate()` + Matrix4 프리뷰
3. **Perspective** — 직접 Homography 구현 필요
4. **Expand** — Phase 8 Healing과 연계

### 실습 과제
1. Flutter의 `Transform.rotate()`로 실시간 회전 프리뷰 구현
2. `img.copyCrop()`으로 4개 비율 프리셋 구현 (Free/1:1/16:9/4:3)

---

## Phase 6 — 로컬 / 선택적 조정

### 배워야 할 개념

**1. 마스크 기반 합성**
```
핵심: mask[x,y] ∈ [0,1]
  → 0: 원본 그대로
  → 1: 효과 100% 적용
  → 0.5: 원본 50% + 효과 50%

출력: output = original × (1-mask) + filtered × mask
```

**2. Gaussian Weight (Selective 가중치)**
```
색상+거리 이중 가중치:
  w = exp(-dist²/(2σ_spatial²)) × exp(-colorDiff²/(2σ_color²))

거리 가중치: 선택한 점에서 멀수록 효과 줄어듦
색상 가중치: 비슷한 색깔 픽셀만 선택 (다른 객체 보호)
→ 이게 Snapseed Selective의 핵심 아이디어
```

**3. Dodge & Burn (명암 도구)**
```
Dodge (밝게): L += strength × (1 - L)
  → 이미 밝은 픽셀은 조금만 올라감 (자연스러움)
Burn  (어둡게): L -= strength × L
  → 이미 어두운 픽셀은 조금만 내려감

Lab L채널 기준으로 조작 → 색조 변경 없이 밝기만 조절
```

**4. Tilt-Shift (초점 밴드)**
```
선형 모드:
  mask[y] = 0 (포커스 밴드 내부)
  mask[y] = 1 (밴드 외부)
  전환 구간: cos 또는 linear ramp

타원 모드:
  dist = sqrt((x/rx)² + (y/ry)²)  ← 타원 방정식
  mask = smoothstep(1.0-t, 1.0+t, dist)
```

**5. Lens Blur (Depth-Map Blur)**
```
depth map → 각 픽셀의 깊이 정보
포커스 거리와의 차이 → 블러 반경 계산
블러 반경에 따라 미리 준비된 여러 단계 블러 이미지에서 샘플링

실제 카메라 보케(bokeh)는 원형 aperture → 더 정확한 구현은
  PSF(Point Spread Function)으로 각 픽셀 컨볼루션 필요
```

### 핵심 파일
- [`lib/engine/local_adjust.dart`](lib/engine/local_adjust.dart) — Selective + Dodge&Burn
- [`lib/engine/blur_engine.dart`](lib/engine/blur_engine.dart) — Tilt-Shift + Lens Blur

### 실습 과제
1. Selective 가중치 w를 시각화: 선택 포인트 중심 원형 그라디언트로 확인
2. Dodge 수식 `L += s×(1-L)`을 그래프 그려보기 (밝기 0~1에 따른 변화량)
3. Tilt-Shift 마스크를 직접 Float32List로 만들어서 회색조 PNG로 저장/확인

---

## Phase 7 — AI 기반 인물 기능

### 배워야 할 개념

**1. 세그멘테이션 마스크**
```
입력: 256×256 이미지
출력: 각 픽셀이 어느 클래스인지 확률값
  selfie: 0=배경, 1=인물
  multiclass: background/hair/body-skin/face-skin/clothes/other

Memoria 기존 코드: lib/ai/models/segmenter.dart
→ MediaPipe 기반 TFLite 모델
```

**2. Bilateral Filter (피부 스무딩)**
```
일반 가우시안: 공간 거리만 고려 → 엣지 블러
Bilateral: 공간 거리 + 색상 차이 모두 고려
  weight = exp(-dist²/σ_s²) × exp(-colorDiff²/σ_c²)

σ_c 작게 → 색상 경계(눈/입술) 보호
σ_c 크게 → 색상 무시하고 강한 스무딩
피부 스무딩: σ_c=30, σ_s=5 (적당한 엣지 보존)
```

**3. Face Detection (.emd 모델)**
```
Snapseed .emd = 구글 내부 ML 모델 포맷
→ TFLite 또는 ML Kit으로 대체

얼굴 랜드마크 68점:
  0-16: 얼굴 윤곽
  17-26: 눈썹
  27-35: 코
  36-47: 눈
  48-67: 입

이 포인트들로 정밀한 마스크 생성 → eye clarity, skin toning
```

**4. HSV 색공간 (Skin Toning)**
```
H (Hue): 색조 0~360°  → 피부 색조 조절
S (Saturation): 채도
V (Value): 밝기

피부 색조 변경:
  1. RGB → HSV
  2. H를 목표 피부톤 Hue로 이동
  3. HSV → RGB
  
세그멘테이션 마스크로 피부 영역만 적용
```

### 핵심 파일
- [`lib/ai/models/segmenter.dart`](lib/ai/models/segmenter.dart) — TFLite 세그멘테이션
- [`lib/engine/portrait_engine.dart`](lib/engine/portrait_engine.dart) — 피부 처리 함수들

### 실습 과제
1. SelfieSegmenter로 인물 사진의 마스크 추출 → 흑백 이미지로 저장
2. Bilateral filter에서 σ_color를 5, 30, 100으로 바꿔가며 차이 확인
3. `_rgbToHsv()` 함수로 피부톤 색상(#F4C2A1)의 H값 계산

---

## Phase 8 — 합성 & 오버레이

### 배워야 할 개념

**1. 6개 블렌드 모드 (Double Exposure)**
```
Normal:   단순 투명도 합성 (가장 기본)
Add:      밝아짐. 두 이미지 합산 (빛 겹치기 효과)
Lighten:  더 밝은 픽셀만 살아남
Darken:   더 어두운 픽셀만 살아남
Overlay:  대비 강화 (Normal + Soft Light 중간)
Subtract: 두 번째가 첫 번째를 잡아먹음. 어두워짐
```

**2. 프레임 오버레이 합성**
```
hp_frame_*.png = 알파 채널 포함된 PNG
합성: dst.compositeImage(frameImg, blend: img.BlendMode.overlay)

주의: 프레임 크기 != 이미지 크기 → 이미지 크기로 리사이징 필요
크기 유지: 프레임 비율 고정 → 이미지를 프레임 안에 맞춤
```

**3. 텍스트 오버레이 렌더링**
```dart
// Flutter CustomPainter 방식
final textPainter = TextPainter(
  text: TextSpan(text: 'Hello', style: TextStyle(font: ...)),
  textDirection: TextDirection.ltr,
);
textPainter.layout();
textPainter.paint(canvas, Offset(x, y));
```

**4. Stacks Brush (선택적 필터 적용)**
```
원본 이미지 + 필터 적용 이미지 두 장 유지
브러시 스트로크 → Float32List mask 업데이트
output = lerp(original, filtered, mask[x,y])

Reveal 모드: mask = 1 (필터 드러냄)
Erase 모드:  mask = 0 (원본 복구)
```

### 핵심 파일
- [`lib/engine/blend_modes.dart`](lib/engine/blend_modes.dart) — 블렌드 모드 구현

### 실습 과제
1. 같은 사진 두 장을 6개 블렌드 모드로 합성해서 차이 시각화
2. `hp_frame_1.png` (있다면)를 이미지에 오버레이하는 간단한 앱 작성

---

## Phase 9 — RAW & 노이즈 제거

### 배워야 할 개념

**1. 이미지 노이즈의 종류**
```
Shot noise: 광자 수 부족 (어두운 환경)
Read noise: 카메라 회로 노이즈
Fixed pattern noise: 센서 결함
→ 대부분 Gaussian 분포를 따름
```

**2. Non-Local Means (NLM) 개념**
```
아이디어: 비슷한 패치를 찾아서 평균냄
  patch(x) ≈ patch(y) → y를 x 복원에 사용

기본 구현 (v1 단순화):
  → Bilateral filter로 충분히 유사한 결과

진짜 NLM:
  각 픽셀 주변 7×7 패치 추출
  전체 이미지에서 비슷한 패치 탐색 (반경 21px)
  유사도 가중치로 평균 → 패턴 보존하면서 노이즈 제거
```

**3. Bayer Demosaicing (DNG RAW 처리)**
```
카메라 센서: RGGB 패턴 (각 픽셀이 한 색만 감지)
Demosaic: 나머지 색 보간 → 풀컬러 이미지
→ libraw 또는 Android CameraX RAW_SENSOR 포맷
```

### 핵심 파일
- [`lib/engine/raw_processor.dart`](lib/engine/raw_processor.dart) — Noise Reduction v1

---

## ML 모델 학습 (Neural Color Transfer)

### 전체 흐름
```
[학습]
중립 이미지 + 스타일 LUT → 스타일 적용 이미지 쌍 생성
MobileNetV3 인코더로 스타일 이미지 특징 추출
65³ LUT 디코더로 색상 변환 예측
Loss = ΔE + histogram + smoothness

[추론]
스타일 이미지 (256×256) → 모델 → 5³ LUT → 업샘플 → 65³ LUT
```

### 배워야 할 개념

**1. MobileNetV3 (경량 모델)**
```
일반 CNN 대비 3~4배 경량
Inverted Residuals: 좁은→넓은→좁은 채널 (메모리 효율)
Squeeze-and-Excite: 채널 중요도 가중치 학습
학습: ImageNet pretrained → fine-tune (색상 특징 추출에 집중)
```

**2. LUT 디코더**
```
MobileNetV3 출력 → GAP(Global Average Pooling) → 공간 정보 제거
FC 256 → FC 512 → reshape → 5³×3
업샘플: 5³ → 65³ (trilinear interpolation)
```

**3. Loss 함수**
```python
loss = 1.0 × deltaE_loss    # Lab 색차 ΔE < 2 목표
     + 0.5 × histogram_loss # 색 분포 일치 (색감 전체)
     + 0.1 × smoothness_loss # LUT 연속성 (밴딩 방지)

smoothness = sum(|LUT[r,g,b] - LUT[r+1,g,b]|²)  # 인접 차이 최소화
```

**4. 학습 환경 (GTX 1650 Max-Q 기준)**
```
fp16 mixed precision (VRAM 절약)
배치 4, 이미지 256×256
gradient checkpointing (메모리 부족 시)
목표: ΔE < 2.0 (약 8~12시간 학습)
```

### 학습 데이터 생성 스크립트
```
ml_pipeline/ 폴더 참고
중립 이미지 컬렉션 + 기존 LUT 500~2000개
→ (neutral_img, lut_applied_img, gt_lut) 쌍 자동 생성
→ 총 50,000~100,000쌍 목표
```

### 핵심 파일
- [`lib/ai/models/lut_predictor.dart`](lib/ai/models/lut_predictor.dart) — TFLite 추론
- [`ml_pipeline/`](ml_pipeline/) — 학습 파이프라인 (Python)

---

## 전체 학습 순서 요약

```
Week 1-2:   Phase 1 (픽셀 조절 수식 이해 + 직접 구현)
Week 3:     Phase 2 (LUT 개념 + Cubic Spline 코딩)
Week 4:     Phase 3 (Lab 색공간 완전 이해)
Week 5-6:   Phase 4 (블렌드 모드 + 이펙트 적용)
Week 7:     Phase 5 (기하학 변환, Homography)
Week 8-9:   Phase 6 (마스크 기반 로컬 조정)
Week 10-11: Phase 7 (TFLite 세그멘테이션 + 피부 처리)
Week 12:    Phase 8 (블렌드 모드 + 텍스트/프레임)
Week 13:    Phase 9 (노이즈 제거 이론)
Week 14+:   ML 모델 학습 파이프라인
```

## 공부할 때 유용한 도구

| 도구 | 용도 |
|------|------|
| Desmos (desmos.com) | 수식 그래프 (S-curve, sigmoid, gaussian) |
| Image J / GIMP | 픽셀 값 직접 확인 |
| Python + matplotlib | LUT 시각화, 히스토그램 비교 |
| Dart DartPad | 작은 알고리즘 빠르게 테스트 |
| ColorHexa.com | Lab, RGB, HSV 변환 확인 |

## 검증 방법 (각 Phase 완료 후)

1. **수치 검증**: 알려진 픽셀 값으로 수동 계산 후 코드 결과와 비교
2. **극단값 테스트**: 파라미터 최소/최대값에서 클리핑 없이 정상 동작 확인
3. **성능 측정**: 1000×1000 이미지 처리 시간 (목표: 프리뷰 <500ms)
4. **시각 확인**: 실제 사진(인물/풍경/음식) 3종으로 결과 육안 검사
5. **ΔE 측정**: `color_utils.dart`의 Lab 변환으로 색차 계산
