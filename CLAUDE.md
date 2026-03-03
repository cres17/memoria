# AI 기반 커스텀 사진 필터 앱 — 엔진/광고/데이터 설계 기획서 (Claude 지시용, v1.0)

작성 목적: 아래 내용을 **그대로 구현 사양(Spec)** 으로 사용한다. 누락 없이 모두 반영한다.  
범위: (1) 온디바이스 “스타일 사진→필터(LUT)” 생성 엔진 (2) 필터 적용/편집 파이프라인 (3) 프리셋 저장 포맷 (4) 광고(배너/풀스크린 토글) 정책/아키텍처 (5) Flutter↔Native 인터페이스.

---

## 0. 핵심 요구사항(절대 조건)

### 0.1 제품 목표
- 사용자가 **필터로 만들고 싶은 사진(스타일 이미지)** 을 1장 업로드하면, 앱 내 AI/엔진이 **자동으로 “커스텀 필터 프리셋”을 생성**한다.
- 생성된 필터는 사용자가 **밝기/노출/명암 등 조절 슬라이더로 취향대로 튜닝** 후 “내 필터”로 저장해 재사용할 수 있어야 한다.
- 생성/적용된 필터는 다른 사진들에 **빠르게 적용**되며, **강도(intensity) 조절**이 가능해야 한다.
- 서버 운영 없이(추가 비용 0) **완전 온디바이스**로 동작해야 한다.
- 광고는 **상단 또는 하단 배너 1개 상시**만 기본으로 노출한다.
- 풀스크린 광고는 **필터 제작/필터 적용(또는 export) 같은 특정 액션에서만** 발생시키되,
  - **광고 실패(로드 실패/타임아웃/노쇼) 시에는 그냥 기능을 계속 진행**한다.
  - **기본 배포 설정에서는 풀스크린 광고 OFF**로 하고,
  - 코드/기능은 모두 구현해두되, **앱 내 토글(feature flag)로 on/off** 할 수 있어야 한다.

### 0.2 “광고 길이(30초/5초) 고정” 관련 전제(사양)
- Google Mobile Ads(AdMob)에서 앱이 “광고 길이(초)”를 고정할 수 없다.
- 따라서 아래 방식으로 “체감” 목표를 달성한다:
  - 필터 제작: Rewarded(또는 Rewarded Interstitial) 사용 (완료 시청을 보상 조건으로 설정 가능)
  - 필터 적용/Export: Interstitial 사용 (짧은 1회 노출)
- 단, 본 버전에서는 풀스크린 광고는 기본 OFF이며, 토글로 켠 경우에만 위 룰을 적용한다.

---

## 1. 전체 아키텍처(모듈 구성)

### 1.1 레이어 구분
- Presentation (Flutter UI)
- Domain (Dart use-case, 순수 로직)
- Engine (Native/Plugin: iOS Core Image / Android GPU shader)
- Storage (로컬 DB + 파일 저장소)
- Monetization (광고 + 네트워크 체크 + feature flag)

### 1.2 주요 모듈
- `editor`: 사진 편집(자르기/회전/조절/필터/미리보기/Export)
- `filters`: 기본 필터 + 커스텀 필터(생성/저장/목록/썸네일)
- `engine`: 이미지 파이프라인 실행(Preview/Export) + LUT 적용 + AI LUT 생성
- `monetization`: 배너 광고 상시 + 풀스크린 광고(토글) + 실패 시 bypass
- `feature_flags`: 광고/기능 on/off 저장(로컬)

---

## 2. “필터 프리셋” 데이터 모델(핵심 산출물)

### 2.1 FilterPreset 정의 (기본/커스텀 공통)
- `id: string` (UUID)
- `name: string`
- `type: enum { builtin, custom }`
- `lut_path: string` (custom은 앱 sandbox 파일 경로, builtin은 asset 경로)
- `params: AdjustParams` (사용자 튜닝값)
- `default_intensity: float` (0.0~1.0)
- `thumbnail_path: string`
- `created_at, updated_at: ISO8601`

### 2.2 AdjustParams(권장 파라미터)
- Exposure(EV): `-2.0 ~ +2.0`
- Contrast: `-100 ~ +100`
- Saturation: `-100 ~ +100`
- Temperature: `-100 ~ +100`
- Tint: `-100 ~ +100`
- Highlights: `-100 ~ +100`
- Shadows: `-100 ~ +100`
- (선택) Sharpen: `0 ~ 100`
- (선택) Vignette: `0 ~ 100`

> Note: LUT와 params는 독립 적용한다. v1에서는 “params를 LUT에 bake”하지 않는다(추후 옵션).

---

## 3. 색공간/정확도 표준(플랫폼 간 일관성)

### 3.1 표준
- 입력: sRGB
- 내부 처리: Lab (D65 기준) — “AI 필터 생성” 단계에서 사용
- 출력/렌더: sRGB

### 3.2 주의
- iOS/Android의 색관리 차이로 동일 LUT가 다르게 보일 수 있음.
- 구현 시 **sRGB 강제**(가능한 범위 내) 및 gamma/linear 여부를 명확히 고정한다.

---

## 4. 온디바이스 “스타일 사진 → LUT(필터)” 생성 엔진

### 4.1 개념
- 서버/딥러닝 스타일 트랜스퍼가 아니라, **필터 형태로 저장 가능한 색보정 기반**으로 “AI 필터 생성” 경험을 제공한다.
- 생성 결과는 3D LUT + 기본 params(0) 로 저장한다.

### 4.2 입력/출력
- Input: `style_image_path` (사용자 선택 1장)
- Output:
  - `lut.bin` (33³ 3D LUT)
  - `meta.json` (FilterPreset 메타 + params)
  - `thumbnail.jpg`

### 4.3 Neutral 기준(입력 고정 기준) — 상수(필수)
필터가 입력 이미지에 따라 달라지면 안 되므로, 입력 통계를 쓰지 않고 **Neutral 기준**을 고정한다.

Neutral Lab 통계(고정 상수):
- L mean = 50
- L std = 18
- a mean = 0
- a std = 8
- b mean = 0
- b std = 8

### 4.4 스타일 분석(Style Analyzer)
스타일 이미지 S를 다운스케일(max 512px) 후 Lab 변환하여 다음을 계산한다:
- μL_s, σL_s
- μa_s, σa_s
- μb_s, σb_s
- L histogram (256 bins)
- L CDF (누적분포)

### 4.5 Tone Curve 생성(256 LUT)
목표: 스타일의 명암 분포를 반영하는 톤커브 `f(L)` 생성.

- Neutral L CDF는 “고정 중립 CDF”를 사용한다.
- Style L CDF와 CDF 매칭하여 `f(L)`(0..255 → 0..255) 생성
- **단조 증가 보장**: f(L[i+1]) ≥ f(L[i]) (톤 역전 방지)
- 결과는 256-entry 1D LUT로 저장(메모리에만 유지해도 됨; LUT 생성에 사용)

### 4.6 Color Transfer 변환 정의 (Neutral → Style)
최종 변환 함수 T(rgb) 정의:

1) rgb → Lab
2) L에 tone curve 적용: `L1 = f(L)`
3) 분산/평균 매칭(Neutral → Style):
- `L2 = (L1 - μL_neutral) * (σL_s / σL_neutral) + μL_s`
- `a' = (a  - μa_neutral) * (σa_s / σa_neutral) + μa_s`
- `b' = (b  - μb_neutral) * (σb_s / σb_neutral) + μb_s`
4) Lab → rgb
5) clamp 0..1
6) (옵션) soft clipping(하이라이트 날림 방지) — v1은 선택

#### 안정화(필수)
- σ ratio가 과도하면 색 왜곡 발생 → ratio clamp 적용(예: 0.5~2.0)
- 톤커브는 단조성 보장

---

## 5. 3D LUT 사양 및 생성

### 5.1 LUT 해상도(필수)
- **33 × 33 × 33**
- 총 샘플: 35,937

### 5.2 LUT 생성 방식(필수)
각 그리드에서 T(rgb)를 평가:

```
for r in 0..32:
  for g in 0..32:
    for b in 0..32:
      rgb = (r/32, g/32, b/32)
      rgb_out = T(rgb)
      LUT[r,g,b] = rgb_out
```

### 5.3 저장 포맷(권장: float16 binary)
- 파일: `lut.bin`
- order: row-major
- channel order: RGB
- dtype: float16(권장) 또는 uint8(대체)

크기(33³):
- 35937 × 3 × 2 bytes ≈ 210 KB (float16)

---

## 6. Android: 2D LUT 텍스처 전개 규격(필수)

Android GPU shader에서 3D LUT를 2D 텍스처로 펼친다.

### 6.1 텍스처 크기
- width = 33 × 33 = 1089
- height = 33

### 6.2 인덱싱 규칙(필수)
- slice = b (0..32)
- x = r + g * 33  (0..1088)
- y = slice        (0..32)

즉, b 슬라이스마다 가로로 (r,g) 타일.

### 6.3 샘플링
- shader에서 trilinear interpolation 수행:
  - r,g,b를 0..32 공간으로 맵
  - b0,b1 slice 보간 + 각 slice에서 (r,g) bilinear 보간

> 주의: 실제 구현에서는 텍스처 좌표가 0..1이므로 (x+0.5)/W 식으로 중심 샘플링.

---

## 7. iOS: Core Image `CIColorCube` 규격(필수)

### 7.1 적용
- iOS는 `CIColorCube` 사용
- dimension = 33

### 7.2 cubeData 포맷
- channel: RGBA (A=1.0 고정)
- dtype: float32 또는 float16 (가능하면 float32로 시작)
- order:
  - R fastest
  - G next
  - B slowest

cubeData length:
- dimension³ × 4 floats

---

## 8. 필터 적용/편집 파이프라인(Preview/Export)

### 8.1 연산 순서(고정)
1) Crop/Rotate
2) Adjust(params) — 노출/명암/채도/색온도 등
3) Apply LUT (builtin/custom)
4) Intensity mix (원본/필터 결과 보간)
5) (옵션) Sharpen/Vignette

### 8.2 Intensity mix 정의(필수)
- intensity ∈ [0,1]
- `final = original*(1-intensity) + filtered*intensity`

### 8.3 Preview vs Export
- Preview:
  - 최대 1080p 수준으로 다운스케일
  - GPU 파이프라인
  - 실시간 반응(슬라이더/강도 조절)
- Export:
  - 원본 해상도
  - 타일링 렌더링(메모리 안정)
  - 백그라운드/스레드 처리 + 진행률 UI

---

## 9. 프리셋/파일 저장 규칙(필수)

### 9.1 디렉토리 구조
```
/filters/
  <preset_id>/
    lut.bin
    meta.json
    thumbnail.jpg
```

### 9.2 meta.json 예시
```json
{
  "id": "uuid",
  "name": "My Filter",
  "type": "custom",
  "lut_path": "filters/uuid/lut.bin",
  "thumbnail_path": "filters/uuid/thumbnail.jpg",
  "default_intensity": 0.8,
  "params": {
    "exposure": 0.0,
    "contrast": 0,
    "saturation": 0,
    "temperature": 0,
    "tint": 0,
    "highlights": 0,
    "shadows": 0
  },
  "created_at": "2026-03-04T00:00:00+09:00",
  "updated_at": "2026-03-04T00:00:00+09:00"
}
```

---

## 10. 광고/토글(Feature Flags) 설계(필수)

### 10.1 기본 정책
- **배너 광고 1개 상시**(상단 또는 하단 중 하나)
- 풀스크린 광고는 기본적으로 **없음**
- 풀스크린 광고 코드/플로우는 구현하되, **토글로만 활성화**

### 10.2 풀스크린 광고 트리거(토글 ON일 때만)
- `CreateFilter`(필터 제작)
- `ApplyFilter` 또는 `Export`(선택: 적용/내보내기 중 어디에 붙일지는 구현에서 분리 가능)

### 10.3 광고 실패 처리(필수)
- 광고 로드 실패/타임아웃/표시 실패 시:
  - **무조건 기능 계속 진행** (bypass)
- 로드 타임아웃 권장: 2500~3500ms

### 10.4 Feature Flags(필수)
- `enableFullScreenAdsForCreateFilter: bool` (default OFF)
- `enableFullScreenAdsForApplyOrExport: bool` (default OFF)
- `enableBannerAd: bool` (default ON)

### 10.5 토글 제공 방식
- 앱 내부 “숨김 관리자 메뉴”:
  - 예: 설정 화면에서 버전 7회 탭 → Dev panel 표시
  - 사용자는 기본적으로 접근 불가(또는 최소화)
- 토글은 로컬 DB에 저장(Isar/sqflite 등)

---

## 11. Flutter ↔ Native 인터페이스(필수)

### 11.1 MethodChannel API (권장)
- `generateLut(styleImagePath) -> {presetId, lutPath, thumbnailPath, defaultParams}`
- `renderPreview(imagePath, editOps) -> {textureId | imageBufferRef}`
- `export(imagePath, editOps, outPath, format, quality) -> {outPath}`

### 11.2 editOps 데이터 구조(권장)
- crop rect, rotate angle
- selected preset id
- intensity
- params(AdjustParams)
- output resolution/format

---

## 12. 구현 로드맵(필수)

### Phase 1 (MVP 기반)
1) LUT 적용 엔진 (builtin 프리셋 + intensity)
2) 기본 Adjust(params) + Crop/Rotate
3) Preview/Export 분리 + export 안정화(타일링)

### Phase 2
4) 스타일 이미지 → LUT 생성(Style Analyzer + Tone Curve + Color Transfer)
5) 프리셋 저장/목록/썸네일

### Phase 3
6) 사용자 튜닝 UI(노출/명암/채도/색온도 등) + 프리셋 저장
7) 배너 광고 상시

### Phase 4
8) 풀스크린 광고 코드 경로 구현 + feature flag 토글(기본 OFF)
9) 고급 안정화(soft clipping, 컬러 왜곡 방지 강화)

---

## 13. 리스크/품질 관리(필수)

- 색공간 차이: sRGB 강제/일관 처리
- 밴딩: LUT float16 권장
- 메모리: export 타일링 필수
- 과도한 색 왜곡: σ ratio clamp + tone curve 단조성 보장

---

## 14. 최종 산출물 체크리스트(Claude가 반드시 제공해야 할 것)

1) Android: 3D LUT(33³) → 2D 텍스처 전개 + fragment shader 샘플링(트릴리니어) 설계/코드 스켈레톤
2) iOS: CIColorCube에 넣을 cubeData 구성 방식 + 적용 파이프라인 스켈레톤
3) Flutter 플러그인 인터페이스(MethodChannel) 설계 + Dart side API 스켈레톤
4) Style→LUT 생성 구현(Neutral 기준, tone curve 256, color transfer 수식, ratio clamp)
5) FilterPreset 저장 포맷(폴더 구조 + meta.json) 구현 지침
6) 광고: 배너 상시 + 풀스크린 feature flag(기본 OFF) + 실패 시 bypass 로직

---

## 부록 A. 간단 의사코드 (Style→LUT)

```python
# inputs: style_image (RGB), neutral_stats, dimension=33

style = downscale(style_image, max=512)
style_lab = rgb_to_lab(style)

muL_s, sigL_s = mean_std(style_lab.L)
mua_s, siga_s = mean_std(style_lab.a)
mub_s, sigb_s = mean_std(style_lab.b)

hist_s = histogram(style_lab.L, bins=256)
cdf_s  = cumsum(hist_s) / sum(hist_s)

cdf_neutral = NEUTRAL_CDF_256  # fixed
tone_curve = cdf_match_curve(cdf_neutral, cdf_s)  # 256 LUT
tone_curve = enforce_monotonic(tone_curve)

ratioL = clamp(sigL_s / sigL_neutral, 0.5, 2.0)
ratioA = clamp(siga_s / siga_neutral, 0.5, 2.0)
ratioB = clamp(sigb_s / sigb_neutral, 0.5, 2.0)

LUT = zeros([33,33,33,3], dtype=float16)

for r in range(33):
  for g in range(33):
    for b in range(33):
      rgb = (r/32, g/32, b/32)
      lab = rgb_to_lab(rgb)

      L1 = tone_curve[int(lab.L)]    # 0..255 map
      L2 = (L1 - muL_neutral) * ratioL + muL_s
      a2 = (lab.a - mua_neutral) * ratioA + mua_s
      b2 = (lab.b - mub_neutral) * ratioB + mub_s

      rgb2 = lab_to_rgb(L2, a2, b2)
      LUT[r,g,b] = clamp01(rgb2)

save_binary_float16("lut.bin", LUT)
```

---

## 부록 B. Android 2D LUT 좌표

- W = 1089, H = 33
- slice = b
- x = r + g*33
- y = slice

텍스처 좌표:
- u = (x + 0.5) / W
- v = (y + 0.5) / H

---

(끝)
