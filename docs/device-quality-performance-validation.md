# Memoria 필터 품질·실기기 출시 검증 계획 및 제3자 평가

- 기준일: 2026-08-28 KST
- 대상: 현재 `memoria` release-candidate 작업 트리
- 독자: 제품 책임자, 모바일 엔지니어, QA, 출시 승인자
- 문서 성격: 검증 계획 + 현재 증거에 대한 독립적 판정
- 현재 종합 판정: **실패(FAIL)**

## 1. 기술 요약

현재 코드는 필터 제작, 편집, 저장·공유, 권한 최소화 흐름을 구현했고 단위·위젯·iOS 시뮬레이터 검증도 보유한다. 그러나 다음 두 영역이 출시를 막는다.

1. 생성된 필터가 앱의 LUT 축 규약으로 해석했을 때 목표 색값을 기준선보다 정확히 재현하는가.
2. 지원 범위의 저사양 iOS·Android 실기기에서 모델 준비, 생성, 12/24MP 내보내기, 취소와 메모리 압박을 견디는가.

직접 색값 감사에서 현재 배포 중인 단일 참조 필터의 R/B LUT 축 계약 불일치가 확인됐다. 축 교정 뒤에는 Canon LUT 합성도 입력 헤더의 `Canon Log 2/3 / Cinema Gamut` 계약과 다르게 구현된 사실이 확인됐다. ACES 참조 수식과 Cinema Gamut 변환으로 수정한 dataset color-v3는 직접 색값 감사를 통과했고 Canon validation은 개선됐지만, 앱 LUT 3개가 interpolation보다 LUT당 `+15.51~+17.12 ΔE` 악화해 G4 전체 게이트에 다시 실패했다. 따라서 현 시점의 객관적 표현은 **“축·Canon 색공간 데이터 계약은 교정됐으나 현재 Direct MVP는 source-group 일반화에 실패했고, 실기기 출시는 미검증”**이다. G4~G6을 통과하기 전에는 해당 필터 제작 경로를 출시하지 않는다.

## 2. 판정 체계

모든 항목은 다음 3단계로만 판정한다.

| 판정 | 정의 | 출시 처리 |
| --- | --- | --- |
| 통과(PASS) | 정해진 표본·기기·빌드에서 모든 필수 기준 충족 | 해당 기능 승인 가능 |
| 보류(HOLD) | 기능은 동작하지만 증거 부족, 표본 부족 또는 비차단 품질 편차 존재 | 베타 유지 또는 출시 차단 유지 |
| 실패(FAIL) | 충돌, 데이터 손상, 권한 오용, 심각한 화질 결함 또는 필수 수치 초과 | 수정 후 전체 관련 게이트 재검증 |

판정 원칙:

- 시뮬레이터 수치는 실기기 성능 승인의 대체물이 아니다.
- 평균값만으로 통과시키지 않는다. p50·p95, 최악 사례, 기기별 결과를 함께 본다.
- 한 플랫폼의 통과를 다른 플랫폼에 일반화하지 않는다.
- 필터 품질은 고정 입력 RGB, 전체 17³ 색 큐브, 목표 LUT 출력의 CIEDE2000·RGB 오차로 판단한다.
- 미관 선호를 통과 조건으로 사용하지 않는다. 따라서 이 문서는 목표 변환 재현성과 안전성만 평가하며 주관적 아름다움을 증명한다고 표현하지 않는다.
- 측정하지 않은 항목은 실패가 아니라 보류다. 다만 출시 필수 항목의 보류는 출시 차단으로 취급한다.
- 디버그 빌드는 기능 진단에만 사용하며 성능 판정은 profile 또는 release 빌드로만 수행한다.

## 3. 현재 증거와 제3자 평가

### 3.1 필터 제작 품질: 실패

`DIRECT-MVP-COLOR-VALUE-AUDIT-001`은 앱에 포함된 TFLite 파일을 직접 실행하고 앱의 bilinear 전처리, 17³→65³ 보간, float16 저장, LUT 안전성 감쇠까지 재현했다. 표본은 family-holdout test의 702장, 미관측 source LUT 15개, 각 사진당 4,913개 RGB 색점으로 총 3,448,926쌍이다.

기존 평가기의 축 해석을 그대로 재현한 평균 ΔE2000은 `12.9290`으로 기존 PyTorch 보고서 `12.9299`와 거의 일치한다. 그러나 기존 평가기는 R-fastest 바이너리를 NumPy C-order `[R,G,B]`로 간주한다. 앱은 같은 버퍼를 `r + g·D + b·D²`로 읽으므로 기존 평가기와 실제 앱의 R/B 축 계약이 반대다.

앱 규약으로 목표 LUT를 올바르게 해석한 결과는 다음과 같다.

| 비교 | 평균 ΔE2000 | p95 ΔE2000 | RGB MAE | LUT-macro 평균 | 기준선 대비 paired 차이 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 현재 앱 Direct MVP | 21.6425 | 41.3823 | 0.1949 | 22.9874 | +8.2077 |
| R/B 축 교정 가상 Direct MVP | 13.0330 | 25.6103 | 0.1339 | 14.4061 | -0.3736 |
| interpolation top-3 기준선 | 13.7310 | 30.6269 | 0.1382 | 14.7797 | 기준 |

현재 앱 출력은 15개 source LUT 모두에서 기준선보다 나빴다. LUT 단위 paired 평균 차이의 20,000회 bootstrap 95% 구간은 `[+6.8402, +9.7074]`로 0을 포함하지 않는다. 반면 축 교정 가상 결과는 15개 중 11개에서 이겼지만 차이의 95% 구간이 `[-1.1855, +0.5616]`이므로 기준선 우위를 확정할 수 없다.

고정 sRGB probe에서도 현재 앱의 채널 축 오류가 직접 드러난다.

| 입력 | 목표 평균 RGB | 현재 앱 평균 RGB | 평균 ΔE2000 | p95 ΔE2000 |
| --- | --- | --- | ---: | ---: |
| 50% 회색 `#808080` | `#818182` | `#7F837F` | 8.89 | 20.08 |
| 밝은 피부 probe `#F2C6A0` | `#F0C5A4` | `#B7CDD1` | 25.33 | 33.64 |
| 중간 피부 probe `#C68662` | `#CA8463` | `#798C9E` | 31.42 | 42.22 |
| 짙은 피부 probe `#7D4A35` | `#814531` | `#3E3A58` | 27.20 | 38.21 |
| 빨강 `#CC3333` | `#D33839` | `#584277` | 35.34 | 45.70 |
| 초록 `#4F9D55` | `#3F9D4D` | `#4F9653` | 7.85 | 17.00 |
| 파랑 `#3569C8` | `#4275CE` | `#AE675B` | 37.58 | 44.89 |
| 하늘색 `#6FA8DC` | `#74AEDD` | `#CFB08E` | 34.60 | 45.71 |

피부 probe는 고정 합성 RGB 좌표이며 인구집단별 피부 품질을 증명하지 않는다. 이 표는 채널·색상 재현 결함 진단용이다. 안전성 게이트는 702건 중 687건을 full strength로 승인하고 15건만 감쇠했으며 identity fallback은 0건이었다. 즉 현재 안전성 검사는 매끄럽지만 축이 뒤바뀐 LUT를 탐지하지 못한다.

후속 `CANON-COLOR-CONTRACT-AUDIT-001`에서 82/82 Canon LUT 헤더가 Cinema Gamut 입력을 요구함을 확인했다. 구형 합성은 색역 변환을 생략하고 비참조 CLog 계수를 사용했다. 동일한 41개 룩의 CLog2/CLog3 결과 차이는 구형 평균 `11.3218 ΔE`에서 교정 후 `0.0765 ΔE`로 감소했고 41/41 룩이 개선됐다. 구형 타깃과 교정 타깃의 평균 차이는 CLog2 `13.9057 ΔE`, CLog3 `10.3309 ΔE`다.

교정 dataset `color-v3-001`의 대표 seed validation 결과는 MVP `13.4254`, interpolation `10.4222` LUT-macro ΔE로 paired 차이 `+3.0033`, 95% CI `[-1.2151, +7.7936]`였다. Canon은 8개 중 6개에서 평균 `-1.3335 ΔE`, crawled는 `-2.5888 ΔE` 개선됐지만 app 3개는 평균 `+16.4319 ΔE` 악화했다.

제3자 판정: **현재 단일 참조 프로덕션 경로는 실패다. 축과 Canon 데이터 계약은 통과했지만 Direct MVP가 앱 LUT family에 일반화되지 않는다. 같은 모델의 epoch·seed·capacity 증가는 중단하고, app monochrome/강한 tone family 식별 또는 validation-only fallback을 별도 사전등록 실험으로 검증해야 한다. 다중 참조와 Before/After는 별도 정량 증거가 없어 보류다.**

### 3.2 필터 제작 성능: 보류

저장된 CPU benchmark에서 17³ LUT 생성은 20회 기준 평균 `36.89ms`, p95 `45.29ms`다. 보고서 자체가 이 수치는 모바일 latency 주장이 아니라고 명시한다. 실제 앱 경로에는 이미지 디코드, 전처리, TFLite 초기화, 65³ 보간, 안전성 검사, 미리보기, 파일 저장이 추가된다.

제3자 판정: **호스트 CPU microbenchmark는 구현 가능성만 보여준다. iOS·Android cold/warm latency와 peak memory가 없으므로 실기기 성능은 미검증이다.**

### 3.3 편집·내보내기 안정성: 보류

현재 구현에는 공통 preview/export recipe, typed failure, 진행률, 취소, 임시 파일 정리, 메모리 부족 시 해상도 재시도가 있다. 시뮬레이터 통합 테스트는 3072×2304 내보내기의 진행 표시와 취소를 확인한다.

하지만 현재 성능 테스트는 완주 내보내기 시간, 결과 파일 무결성, Photos 저장 성공, share sheet 수신 결과, peak RSS를 측정하지 않는다. `perf_gate --scope full`이 요구하는 `exportProgressIntervalMs`도 현재 integration report에서 생성되지 않는다.

제3자 판정: **오류 처리 구조는 양호하지만 실기기 완주 증거가 없어 출시 승인은 보류다.**

### 3.4 권한 설계: 조건부 통과

기본 사진 선택은 시스템 사진 선택기를 사용하며 전체 보관함 접근을 먼저 요구하지 않는다. 최근 사진 탐색은 실제 진입 시 `PhotoManager.requestPermissionExtend()`를 호출한다. 카메라 권한은 제거됐다.

남은 위험:

- iOS limited PhotoKit, 권한 거부 후 재허용, iCloud 원본 다운로드를 실제 기기에서 확인하지 않았다.
- Android manifest는 API 33+ `READ_MEDIA_IMAGES`, API 34+ 제한 접근용 `READ_MEDIA_VISUAL_USER_SELECTED`, API 32 이하 읽기, API 29 이하 쓰기 권한을 OS 범위별로 선언한다. `requestLegacyExternalStorage`는 제거했다.
- 최근 사진 권한 요청은 `RequestType.common` 기본값 대신 image-only로 제한했다. Android 14 선택 사진 접근의 실제 상태 전이는 SDK·기기 부재로 아직 증명되지 않았다.

제3자 판정: **권한 최소화 방향은 타당하지만 양 플랫폼의 상태 전이 검증 전에는 완전 통과로 볼 수 없다.**

### 3.5 메모리·지원 범위: 보류

현재 iOS deployment target은 13.0이고 Android minSdk는 24다. 이 범위를 그대로 공개하면 2GB급 구형 iPhone과 저메모리 Android도 지원 주장에 포함될 수 있다. 이 기기군을 시험할 수 없다면 최소 OS 또는 지원 기기 정책을 현실적으로 올려야 한다.

현재 unsigned iPhoneOS 앱 디렉터리는 약 `147 MiB`, asset은 약 `92 MiB`이며 이 중 LUT가 약 `47 MiB`, 모델이 약 `35 MiB`다. 설치 크기와 실행 중 peak RSS는 다른 지표이므로 용량만으로 메모리 안전성을 추론하지 않는다.

제3자 판정: **저사양 기기 증거가 없고 지원 범위가 넓어 메모리 위험이 남아 있다.**

## 4. 검증 범위와 표본 정의

### 4.1 필터 품질 표본

최소 60개의 독립 평가 사례를 사용한다. 한 사례는 참조 사진 집합, 대상 사진, 고정 목표 변환, 생성 방식, 기준선 결과와 후보 결과로 구성한다.

| 코호트 | 최소 사례 수 | 필수 포함 조건 |
| --- | ---: | --- |
| 같은 스타일·다른 장면 | 15 | 참조와 대상의 피사체·구도·노출이 다름 |
| 피부·인물 | 15 | 다양한 피부 명도, 혼합광, 역광, 실내·실외 |
| unseen hue·강한 색 | 10 | 네온, 청록, 자홍, 붉은 조명, 강한 녹색 |
| 저조도·고대비 | 10 | 야간, 암부, 하이라이트 clipping 위험 |
| 입력 형식·색역 | 10 | sRGB JPEG/PNG, EXIF 회전, HEIC, Display P3; HDR은 지원 정책에 따라 포함 또는 명시 제외 |

추가 구성 규칙:

- 단일 참조, 2~5장 다중 참조, Before/After를 각각 최소 20사례 확보한다.
- 학습·validation·기존 test에 사용한 사진과 동일 파일은 제외한다.
- 개인 사진은 저장소에 커밋하지 않는다. 배포·재현이 가능한 허가된 fixture만 ID와 checksum으로 관리한다.
- 평가 시작 전에 fixture ID, 입력 checksum, 목표 LUT checksum, 모델 checksum과 색공간을 고정한다.
- 단일·다중 참조는 알려진 목표 LUT로 만든 참조 fixture를 사용해 생성 LUT와 목표 LUT를 직접 비교한다.
- Before/After는 정렬된 pixel pair 또는 합성 ground truth를 사용하며, 정렬 오차가 있는 실사진 pair는 ΔE 승인 표본에서 제외한다.

### 4.2 실기기 매트릭스

#### iOS

| 계층 | 필수 기기 조건 | 목적 |
| --- | --- | --- |
| 최소 지원 | iOS 13 지원 범위의 2GB급 기기 또는 지원 최소 버전 상향 후 새 최소 기기 | jetsam·최초 모델 준비·12MP export |
| 대표 | 4GB RAM급 iPhone, 현재 사용자층의 일반 OS | 일반 성능·Photos·iCloud·limited access |
| 최신 | 최신 iOS의 현행 iPhone | 최신 PhotoKit·share sheet·회귀 확인 |

#### Android

| 계층 | 필수 기기 조건 | 목적 |
| --- | --- | --- |
| 최소 지원 | API 24~28, 2~3GB RAM, arm64-v8a | legacy storage·저메모리·TFLite ABI |
| 전환기 | API 29~32, 4GB RAM | scoped storage 이전/이후 경계 |
| 현대 | API 33, 4GB 이상 | Photo Picker·`READ_MEDIA_IMAGES` |
| 최신 | API 34~35 | 선택된 사진 접근·권한 재선택·최신 공유 흐름 |

대체 원칙:

- 물리 기기를 확보하지 못한 계층은 클라우드 실제 기기 팜을 사용할 수 있다.
- 에뮬레이터만으로 메모리, 카메라 롤, iCloud/제조사 갤러리 통합을 통과 처리하지 않는다.
- 최소 지원 기기 검증이 불가능하면 해당 OS 지원을 유지한 채 예외 승인하지 않고 최소 지원 범위를 조정한다.

## 5. 필터 제작 결과 품질 검증

### 5.1 비교 대상

각 생성 방식은 다음 대상과 비교한다.

| 생성 방식 | 후보 | 필수 기준선 |
| --- | --- | --- |
| 단일 참조 | Direct MVP TFLite | identity, 현재 algorithmic fallback, interpolation/retrieval 중 test 성능이 가장 좋은 것 |
| 2~5장 참조 | reference fusion | 단일 대표 사진 결과, 단순 평균 또는 기존 fusion 기준선 |
| Before/After | affine + residual grid | identity, affine-only, residual 없는 전역 보정 |

기준선 선택은 test 결과를 본 뒤 유리한 대상을 고르는 방식으로 바꾸지 않는다. 평가 시작 전에 고정하고 문서에 checksum과 버전을 기록한다.

### 5.2 자동 정량 검사

모든 생성 결과에 대해 다음을 기록한다.

| 지표 | 정의 | 필수 기준 |
| --- | --- | --- |
| out-of-gamut node ratio | LUT 노드 중 `[0,1]` 밖의 비율 | 저장 직전 0% |
| NaN/Inf | LUT의 비정상 값 | 0건 |
| 중성축 편차 | 회색 ramp에서 최대 색 편향 | 기준선 대비 악화 금지; 별도 fixture 기준 고정 |
| 휘도 단조성 위반 | 밝기 증가 입력에서 출력 휘도가 역전된 비율 | 승인 fixture에서 사전 정의 한도 이하 |
| smoothness | 인접 LUT 노드 차이의 평균·최대 | 현재 승인 모델 범위와 비교, 급격한 spike 0건 |
| clipping | 실제 결과의 0/255 포화 픽셀 증가율 | 기준선 대비 사전 정의 한도 이하 |
| preview/export parity | 같은 recipe의 축소 export와 preview 차이 | golden tolerance 이내 |

중성축·단조성·clipping 한도는 평가 데이터를 본 뒤 정하지 않는다. 첫 정식 실행 전에 fixture baseline을 계산하고 승인자가 수치를 고정한다.

### 5.3 색값 기반 정량 비교

블라인드 선호 평가는 사용하지 않는다. 각 fixture에서 동일 RGB 입력을 목표 LUT, 후보 LUT, 고정 기준선 LUT에 각각 통과시키고 출력 sRGB와 CIELAB 값을 직접 추출한다.

필수 계산:

- 전체 17³ 큐브의 RGB MAE·RMSE와 ΔE2000 mean·median·p95·max.
- 관측 hue mask와 미관측 영역의 ΔE2000 분리.
- black/white, 25/50/75% 회색, 세 단계 피부색 probe, RGB/CMY, sky, foliage 고정점의 목표·후보 출력 RGB.
- source LUT별 평균을 먼저 구한 LUT-macro 결과와 sample-weighted 결과를 함께 기록.
- 후보와 사전 고정 최강 기준선의 source-LUT 단위 paired 차이를 bootstrap 20,000회로 계산.
- R/G/B 단일 채널 golden LUT로 저장·모델 출력·GPU atlas·CPU sampler의 축 계약을 검증.

단일 참조 필수 통과 기준:

- 후보의 LUT-macro 평균 ΔE2000이 기준선보다 낮아야 한다.
- paired 차이 95% 신뢰구간의 상한이 0 미만이어야 한다.
- app/canon/crawled 및 필수 실사진 코호트 중 어느 것도 기준선보다 악화되지 않아야 한다.
- R/G/B 축 golden 불일치, NaN/Inf, 채널 붕괴, identity fallback은 1건이라도 실패다.
- fixed swatch의 목표·후보 RGB와 ΔE 원자료를 보존한다. 평균 RGB만으로 통과시키지 않는다.

이 기준은 목표 색 변환 재현성을 평가한다. 미관 선호나 창의적 품질에 대한 주장은 이 시험 범위 밖이다.

### 5.4 품질 결과 기록표

| 실행 ID | 생성 방식 | 사례/LUT | 평균 ΔE2000 | 기준선 대비 LUT paired 차이 | 95% CI | 판정 |
| --- | --- | ---: | ---: | ---: | --- | --- |
| DIRECT-MVP-COLOR-VALUE-AUDIT-001 | 현재 단일 참조 | 702/15 | 21.6425 | +8.2077 | `[+6.8402, +9.7074]` | 실패 |
| DIRECT-MVP-COLOR-VALUE-AUDIT-001 | 축 교정 가상 단일 참조 | 702/15 | 13.0330 | -0.3736 | `[-1.1855, +0.5616]` | 보류 |
| COLOR-V3-SEED-20260830 | 축·Canon 계약 교정 validation | 339/12 | 13.4121 | +3.0033 | `[-1.2151, +7.7936]` | 실패 |
| 미실행 | 다중 참조 | 0/0 | - | - | - | 보류 |
| 미실행 | Before/After | 0/0 | - | - | - | 보류 |

## 6. 필터 제작 실기기 성능 검증

### 6.1 측정 경계

다음 구간을 분리해 기록한다.

1. 사진 선택 완료 → 디코드 완료
2. 디코드 완료 → 모델/알고리즘 준비 완료
3. 생성 시작 → 17³ 또는 내부 LUT 생성 완료
4. 안전성 검사·65³ 보간 완료
5. 샘플 preview 표시 완료
6. 필터 파일·metadata 저장 완료

Cold는 앱 설치 또는 프로세스 재시작 후 모델/interpreter/cache가 없는 첫 실행이다. Warm은 같은 프로세스에서 동일 생성 방식을 한 번 성공한 뒤의 실행이다.

### 6.2 반복과 통계

- 기기·생성 방식·입력 크기별 cold 5회, warm 30회.
- cold 실행 사이에는 앱 프로세스를 종료하고 메모리 상태를 초기화한다.
- warm 결과는 p50, p95, 최대값을 기록한다.
- 측정 중 thermal state, 배터리 상태, 저전력 모드, 가용 저장 공간을 기록한다.
- 최초 모델 다운로드가 존재하는 구성은 네트워크 시간을 별도 지표로 분리한다.

### 6.3 제안 승인 기준

아래 수치는 현재 제품 UX를 위한 사전 승인 기준이며 실제 결과를 보고 완화하지 않는다.

| 지표 | 통과 기준 |
| --- | ---: |
| 단일 참조 cold 전체 완료 p95 | 5,000ms 이하 |
| 단일 참조 warm 전체 완료 p95 | 2,000ms 이하 |
| 2~5장 warm 전체 완료 p95 | 4,000ms 이하 |
| Before/After warm 전체 완료 p95 | 5,000ms 이하 |
| 생성 중 UI frame total p95 | 16ms 이하 |
| 취소 요청 → idle 복귀 p95 | 500ms 이하 |
| 생성 실패 후 잔여 filter/temp artifact | 0건 |
| 연속 10회 생성 중 crash/ANR/jetsam | 0건 |

메모리 기준:

- 앱 idle baseline과 생성 중 peak RSS/PSS를 함께 기록한다.
- 2~3GB 기기에서 peak 증가량 500MiB 이하, 4GB 이상 기기에서 750MiB 이하를 1차 경계로 사용한다.
- 절대 수치가 경계 이하여도 OS memory warning, jetsam, Android LMK/ANR가 발생하면 실패다.
- 모델 준비 후 회수 가능한 임시 buffer가 다음 warm 실행 전까지 지속적으로 증가하면 memory leak 의심으로 보류한다.

## 7. 편집 반응성과 장시간 조작 검증

현재 `perf_gate.dart`의 기준을 그대로 사용한다.

| 지표 | 기존 통과 기준 |
| --- | ---: |
| UI frame total p95 | 16ms 이하, 최소 30 sample |
| warm preview p95 | 80ms 이하, 최소 30 sample |
| cold preview | 250ms 이하 |
| export 첫 진행 표시 | 500ms 이하 |
| export 취소 완료 | 500ms 이하 |

추가 장시간 시나리오:

- 15분간 노출·대비·HSL·커브 슬라이더를 반복 조작한다.
- 인물 모델 최초 준비 후 인물 보정을 10회 열고 닫는다.
- 부분 보정 지점 20개, 브러시 stroke 200개, 텍스트·프레임·LUT를 함께 적용한다.
- 측정 전후 RSS/PSS, frame p95, preview p95를 비교한다.
- 메모리가 3회 연속 10% 이상 증가하고 회수되지 않으면 보류, crash/ANR이면 실패다.

## 8. iOS 실기기 내보내기 검증

### 8.1 입력 매트릭스

| 입력 | 최소 크기·특성 |
| --- | --- |
| JPEG | 12MP, 24MP, EXIF 회전 1/3/6/8 |
| PNG | 투명 alpha 포함 12MP 상당 |
| HEIC | 12MP, iCloud 원본 1건 포함 |
| Display P3 | JPEG 또는 HEIC 1건 이상 |
| 메모리 압박 | 다른 앱이 메모리를 사용하는 상태 또는 Instruments 제한 환경 |

### 8.2 출력 매트릭스

iOS v1 제품 기능은 JPEG·PNG·TIFF만 통과 대상으로 한다. WebP capability가 false인 기기에서는 선택지가 숨겨지고 과거 WebP 설정값이 JPEG로 정규화되어야 한다.

각 형식에서 확인할 항목:

- Photos 저장 성공 및 중복 저장 여부.
- share sheet에서 Files·메신저 등 최소 2개 수신 앱으로 전달.
- 실제 magic bytes와 확장자 일치.
- 예상 해상도·orientation·alpha 정책 일치.
- preview와 export의 crop, perspective, portrait mask, LUT, text/frame 위치 일치.
- 취소·실패 후 임시 파일 0개.
- 앱 백그라운드·복귀 중 저장 결과가 중복 publish되지 않음.

### 8.3 성능 기준

| 지표 | 12MP | 24MP |
| --- | ---: | ---: |
| JPEG 완주 p95 | 10초 이하 | 20초 이하 또는 4096px fallback을 사용자에게 명시 |
| PNG 완주 p95 | 20초 이하 | 30초 이하 또는 명시적 제한 |
| TIFF 완주 p95 | 25초 이하 | 40초 이하 또는 명시적 제한 |
| 진행률 갱신 간격 최대 | 500ms | 500ms |
| 취소 완료 p95 | 500ms | 500ms |
| 결과 파일 signature 오류 | 0건 | 0건 |
| crash/jetsam/중복 publish | 0건 | 0건 |

완주 시간 기준을 넘긴다고 자동으로 해상도를 몰래 낮추지 않는다. 해상도 fallback을 제품 정책으로 유지한다면 원본 크기와 출력 크기를 사용자에게 알리고 결과표에 별도로 기록한다.

## 9. Android 실기기 내보내기 검증

### 9.1 API별 권한·저장 경로

| API | 기본 시스템 선택기 | 최근 사진 탐색 | 저장·공유 |
| --- | --- | --- | --- |
| 24~28 | 사진 선택 성공, 선요청 최소화 | legacy 읽기 권한 허용/거부 | 갤러리 저장, 재부팅 후 MediaStore 표시 |
| 29~32 | 시스템/호환 선택기 | 읽기 권한 상태 전이 | scoped storage와 legacy flag 영향 확인 |
| 33 | Android Photo Picker | `READ_MEDIA_IMAGES` 허용/거부 | MediaStore 저장·공유 URI 읽기 |
| 34~35 | 선택된 사진 접근 포함 | limited/selected/full 상태 | 재선택 후 접근 범위·공유 URI 검증 |

Android 14 이상에서 선택된 사진 접근을 지원하려면 현재 manifest와 `photo_manager`가 `READ_MEDIA_VISUAL_USER_SELECTED` 흐름을 올바르게 제공하는지 확인한다. 제공하지 못하면 기능을 full/denied로 오판할 수 있으므로 수정 전 통과 처리하지 않는다.

### 9.2 출력·성능 기준

- JPEG·PNG·TIFF 각각 12MP/24MP를 대상으로 iOS와 동일한 완주·무결성 검사를 수행한다.
- share sheet 수신 앱에서 URI가 열리고 앱 종료 후에도 허용된 시간 동안 읽을 수 있어야 한다.
- API 24~28에서 File URI 노출 예외가 없어야 한다.
- API 29 이상에서 앱 전용 경로가 잘못 gallery 결과로 표시되지 않아야 한다.
- 저사양 기기 12MP JPEG p95 15초 이하, 취소 p95 700ms 이하를 1차 기준으로 둔다.
- 연속 5회 export에서 crash, ANR, LMK, 0-byte 결과, 중복 MediaStore row가 없어야 한다.
- arm64-v8a release 빌드에서 TFLite 모델 load·inference를 확인한다. 지원 ABI를 명시하지 않은 상태로 다른 ABI 성공을 추정하지 않는다.

## 10. 권한 상태 전이 검증

각 플랫폼은 삭제 후 재설치 또는 권한 초기화 상태에서 시작한다.

### 10.1 공통 시나리오

1. 홈·필터·편집 빈 화면·필터 제작의 기본 사진 선택을 각각 실행한다.
2. 전체 보관함 권한을 먼저 요구하지 않고 시스템 선택기가 열리는지 확인한다.
3. 선택 취소 시 앱이 이전 화면으로 안전하게 복귀하는지 확인한다.
4. 선택한 사진만 앱이 읽고 편집할 수 있는지 확인한다.
5. 최근 사진 탐색에 처음 진입할 때만 읽기 권한 요청이 나타나는지 확인한다.
6. 거부, 제한/선택, 전체 허용을 각각 적용한다.
7. 앱 설정에서 권한을 변경한 뒤 앱으로 복귀하여 상태가 즉시 갱신되는지 확인한다.
8. 저장 권한을 거부하고 내보낸 뒤 오류 안내와 임시 파일 정리를 확인한다.

### 10.2 iOS 추가 시나리오

- limited library에서 허용 사진만 최근 목록에 표시.
- limited selection 변경 후 목록 갱신.
- iCloud에만 있는 사진의 다운로드 중 표시, 취소, 네트워크 실패와 재시도.
- Photos add-only 허용과 read 거부 조합에서 저장 가능 여부.
- 앱 삭제·재설치 뒤 권한과 앱 데이터가 독립적으로 초기화되는지 확인.

### 10.3 Android 추가 시나리오

- API 33+ 기본 선택기에서 `READ_MEDIA_IMAGES` 선요청이 없는지 확인.
- API 34+ 선택된 사진만 허용한 뒤 최근 목록이 허용 범위를 넘지 않는지 확인.
- “다시 묻지 않음” 후 설정 이동과 복귀 안내.
- 앱 데이터 삭제, 권한 자동 재설정, OS 업그레이드 모사 후 상태 처리.
- API 29 이하 저장 권한 거부 시 갤러리 저장 실패가 정확히 안내되는지 확인.

권한 테스트에서 앱이 요청 이유와 무관한 접근을 요구하거나, 거부 후 반복 팝업을 띄우거나, 허용 범위 밖 사진을 읽으면 실패다.

## 11. 메모리·열·안정성 검증

### 11.1 측정 도구

#### iOS

- Xcode Organizer 또는 Instruments의 Allocations, VM Tracker, Memory Graph.
- MetricKit 또는 기기 로그의 peak memory·hang·crash·jetsam 기록.
- profile/release 빌드, Debug Memory Graph가 주는 추가 오버헤드는 별도 표기.

#### Android

- Android Studio Memory Profiler.
- `adb shell dumpsys meminfo <package>`의 PSS/RSS.
- Perfetto, `adb logcat`, ANR·LMK 기록.
- release 빌드와 동일 ABI·minification 설정.

### 11.2 필수 스트레스 시퀀스

1. 앱 cold launch 후 12MP 사진 선택.
2. 단일 참조 필터 최초 생성.
3. 인물 모델 최초 준비 및 효과 적용.
4. 15분 슬라이더 조작.
5. 24MP JPEG → PNG → TIFF 연속 export.
6. 각 export 중 한 번씩 취소.
7. 앱을 5분 백그라운드로 보낸 뒤 복귀.
8. 같은 편집 초안을 복원하고 다시 export.
9. 위 시퀀스를 앱 재시작 없이 3회 반복.

실패 기준:

- crash, ANR, jetsam, watchdog termination, native OOM.
- 반복마다 idle RSS/PSS가 계속 증가하며 3회차에 첫 회 대비 20% 이상 높음.
- 취소 후 isolate·temporary file·model buffer가 해제되지 않음.
- 메모리 fallback 뒤 UI와 실제 출력 해상도가 서로 다르거나 사용자에게 알려지지 않음.
- thermal serious/critical 상태에서 입력이 멈추거나 결과 파일이 손상됨.

## 12. 실행 절차와 산출물

### 12.1 빌드 고정

각 실행은 다음을 기록한다.

- Git commit SHA와 dirty tree 여부.
- Flutter/Dart/Xcode/Android Gradle Plugin 버전.
- app version/build number, profile 또는 release 모드.
- 모델 ID·version·SHA-256, LUT catalog checksum.
- 기기 모델, RAM, SoC, OS build, 배터리·thermal state.

dirty tree 결과는 탐색용으로 사용할 수 있지만 최종 출시 승인 근거로 사용하지 않는다.

### 12.2 권장 명령

```bash
flutter analyze --no-fatal-infos
flutter test --coverage --reporter compact

flutter drive --profile \
  --driver test_driver/editor_performance_driver.dart \
  --target integration_test/editor_performance_test.dart \
  -d <physical-ios-device-id> --publish-port

dart run tool/perf_gate.dart \
  --report build/perf/editor_perf.json --scope preview

dart run tool/perf_gate.dart \
  --report build/perf/editor_perf.json --scope export-cancel
```

`--scope full`은 integration report가 `exportProgressIntervalMs`와 완주 결과를 실제로 기록하도록 보강한 뒤 사용한다. 현재 상태에서 필드가 없는 보고서를 억지로 통과시키지 않는다.

Android는 release APK/AAB를 설치한 뒤 기기별 계측 로그와 `dumpsys meminfo` 원본을 보존한다. 계측 명령은 실제 application ID와 선택한 빌드 변형을 확인한 뒤 기록한다.

### 12.3 보존할 산출물

```text
build/validation/<commit>/<device>/<run-id>/
  environment.json
  quality-cases.jsonl
  color-value-comparison.json
  filter-generation-performance.json
  editor-performance.json
  export-results.json
  permissions-results.json
  memory-samples.csv
  crash-anr-jetsam.log
  output-signatures.json
  reviewer-signoff.md
```

사진 원본은 산출물 폴더에 복사하지 않는다. fixture ID, checksum, 입력 특성과 사용 허가만 기록한다.

## 13. 최종 승인표

| 게이트 | 현재 판정 | 통과 증거 | 출시 영향 |
| --- | --- | --- | --- |
| 단일 참조 정량 품질 | 실패 | 현재 배포 모델은 축 계약 기준 평균 ΔE 21.6425. color-v3 대표 seed도 validation LUT-macro가 interpolation보다 +3.0033 ΔE이고 app 3개가 평균 +16.4319 ΔE 악화해 G4 실패 | 단일 참조 출시 차단 |
| 단일 참조 R/B 축 계약 | 통과 | 교정 pipeline strict 최대 오차 0, dataset float16 직렬화 오차 0. 현재 배포 모델은 교체 전까지 품질 실패로 별도 차단 | 축 자체는 통과, 모델 승격은 차단 |
| Canon Log/Cinema Gamut 계약 | 통과 | 82/82 헤더 확인, ACES 참조 수식·색역 행렬 적용, 동일 룩 CLog2/3 평균 차이 11.3218→0.0765 ΔE | 데이터 계약 통과, 모델 품질은 별도 실패 |
| 다중 참조 품질 | 보류 | 자동 flow·rollback test만 존재 | 베타 해제 차단 |
| Before/After 품질 | 보류 | 생성·저장 경로 test만 존재 | 베타 해제 차단 |
| iOS 필터 생성 성능 | 보류 | 호스트 CPU benchmark만 존재 | 베타 해제 차단 |
| Android 필터 생성 성능 | 보류 | 실기기 결과 없음 | Android 출시 차단 |
| iOS 완주 export·Photos·share | 보류 | 시뮬레이터 진행·취소만 검증 | iOS 일반 출시 차단 |
| Android export·MediaStore·share | 보류 | 실기기 결과 없음 | Android 일반 출시 차단 |
| iOS 권한 상태 전이 | 보류 | 기본 picker 시뮬레이터 확인 | iOS 출시 전 필수 |
| Android 권한 상태 전이 | 보류 | 코드·manifest만 확인 | Android 출시 차단 |
| 저메모리·장시간 안정성 | 보류 | 구조적 fallback만 존재 | 양 플랫폼 출시 차단 |

## 14. 권장 실행 순서

1. app monochrome/강한 tone LUT를 포함한 별도 validation-calibration split을 만들고, Direct MVP가 full-cube 색을 복원하지 못하는 조건을 고정한다.
2. current MVP를 더 오래 학습하지 말고 interpolation fallback 또는 app-family 보강 중 한 변경만 사전등록해 validation에서 비교한다.
3. G4를 통과한 후보가 생길 때만 test를 한 번 열고 TFLite 변환·702개 색값 감사를 실행한다.
4. 다중 참조와 Before/After의 ground-truth 색값 fixture를 고정한다.
5. `editor_performance_test`를 완주 export·진행 간격·peak memory 기록까지 확장한다.
6. 대표 iPhone과 Android API 34+ 기기에서 빠른 smoke를 수행해 차단 결함을 찾는다.
7. 최소 지원 기기에서 메모리·12MP export를 수행한다. 실패하면 최적화 또는 지원 범위 조정을 결정한다.
8. 전체 기기 매트릭스와 권한 상태 전이를 완료하고 깨끗한 commit에서 재검증한다.

## 15. 추가로 답해야 할 질문

- iOS 13과 Android API 24 지원을 실제로 유지할 제품 이유와 검증 기기가 있는가.
- 24MP에서 메모리 fallback이 발생할 때 원본 해상도 보존과 빠른 완료 중 어느 쪽을 우선할 것인가.
- Display P3·HDR 입력을 v1에서 지원할지, SDR sRGB로 명시적으로 제한할지.
- 실제 카메라 사진 일반화 표본에서 허용할 코호트별 ΔE2000 상한을 어떤 제품 수준으로 고정할 것인가.
- Android 14 선택된 사진 접근을 최근 사진 UI에서 완전히 지원할지, 시스템 선택기로 단순화할지.

이 질문에 답하지 않은 상태에서도 탐색 테스트는 가능하지만, 최종 출시 판정은 보류한다.

## 16. 근거 파일

- `ml_pipeline/reports/mvp/mvp-family-holdout-smooth-010-001_test_report.json`
- `ml_pipeline/reports/baselines/family_holdout_generation_comparison_report_001.json`
- `ml_pipeline/reports/deployment/direct_mvp_deployment_benchmark_001.json`
- `ml_pipeline/reports/validation/direct_mvp_color_value_audit_001.json`
- `ml_pipeline/reports/validation/canon_color_contract_audit.json`
- `ml_pipeline/reports/validation/color_v3_001_value_audit.json`
- `ml_pipeline/reports/validation/color_v3_001_seed_20260830_paired_comparison.json`
- `ml_pipeline/reports/validation/color_v3_001_seed_20260830_failure_diagnosis.json`
- `ml_pipeline/reports/validation/color_v3_001_coverage_fallback_loo.json`
- `ml_pipeline/43_audit_canon_color_contract.py`
- `ml_pipeline/44_evaluate_coverage_fallback.py`
- `ml_pipeline/canon_color_contract.py`
- `ml_pipeline/37_audit_direct_mvp_color_values.py`
- `ml_pipeline/17_evaluate_conditional_lut.py`
- `lib/ai/models/lut_predictor.dart`
- `integration_test/editor_performance_test.dart`
- `tool/perf_gate.dart`
- `lib/features/create_filter/create_filter_services.dart`
- `lib/features/editor/editor_export_service.dart`
- `lib/features/editor/editor_media_export_coordinator.dart`
- `lib/core/services/media_permission_service.dart`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- `docs/architecture-connectivity-code-quality-review.md`

## 17. 2026-08-28 재검증 결과와 재학습 계획

### 17.1 이번 실행에서 확인한 사실

| 검사 | 결과 | 해석 |
| --- | --- | --- |
| `flutter test test/neural_lut_predictor_test.dart` | 통과 | Dart의 `r + g·D + b·D²` R-fastest 인덱스 계약은 유지됨 |
| 구형 `color_transfer.tflite` smoke | 미실행 | 파일이 없어 테스트 본문이 조기 반환했다. 현재 Direct MVP 품질 증거로 사용하지 않음 |
| `flutter test test/direct_mvp_tflite_candidate_test.dart` | 2개 통과 | 현재 35MB Direct MVP가 Flutter 래퍼에서 65³ LUT를 생성하고 같은 입력을 결정적으로 저장함. 최근 호스트 elapsed `458ms`는 실기기 성능 수치가 아님 |
| 마이그레이션 전 `LUT-AXIS-CONTRACT-001` | 실패 | 앱 인덱스는 identity LUT를 정확히 복원했지만 Python evaluator, dataset BIN loader, dataset CUBE loader는 최대 채널 오차 `1.0`으로 R/B가 뒤바뀜 |
| 공용 helper 마이그레이션 후 `LUT-AXIS-CONTRACT-001 --strict` | 통과 | 앱 인덱스, evaluator, dataset BIN/CUBE loader, RGB·혼합색 probe가 모두 최대 오차 `0.0`; 불필요한 R/B 재전치는 최대 오차 `1.0`으로 탐지됨 |
| Direct MVP 30장 smoke 색값 감사 | 방향 재현 | 현재 앱 평균 ΔE `20.5948`, 축 교정 가정 `12.1698`, interpolation `13.4552`. 단, 1개 source LUT만 포함하므로 승격 통계로 사용하지 않음 |
| dataset `axis-v2-001` 무결성 감사 | 통과 | 3,000건, 119개 source LUT, 누락·잘못된 LUT 크기·manifest 오류·중복 ID 0건 |
| dataset `axis-v2-001` 직접 색값 감사 | 통과 | 119/119 source·생성기 SHA 일치, 대표 neutral/graded JPEG 119/119 byte exact, float16 직렬화 오차 `0.0`, 256색 보간 probe 최대 오차 `0.000244` |
| family holdout 재구축 | 통과 | train/validation/test `2,024/274/702`, source LUT `94/10/15`, family leakage 0건 |
| G2 1-batch 학습 smoke | 통과 | total loss `0.042686 → 0.014806`(-65.3%), 유한값 유지, export 범위 `[0.000100, 1.0]`, reload RMSE `0.0000976` |

축 검사는 `ml_pipeline/38_verify_lut_axis_contract.py`로 재현한다. 축 마이그레이션 후
`--strict`가 통과하며, 이 명령은 dataset v2 생성 전 필수 gate로 유지한다.

```bash
.venv-ml-tflite/bin/python \
  ml_pipeline/38_verify_lut_axis_contract.py --strict
```

이번 결과는 모델 호출 실패와 LUT 의미 계약 실패를 분리한다. 모델 파일·Flutter 호출·결정적
저장은 동작하고 Python load/save/evaluator 계약도 앱과 일치하도록 교정됐다. 그러나 기존
dataset과 checkpoint는 교정 전 계약으로 만들어졌으므로 재사용하거나 이어서 학습하지 않는다.

### 17.2 재학습 의사결정 게이트

| 게이트 | 필수 조건 | 실패 시 처리 |
| --- | --- | --- |
| G0 축 계약 | 앱, CUBE/BIN loader, saver, evaluator의 identity·단일 채널 golden 모두 최대 오차 `≤ 0.001`; strict 검사 통과 | 데이터 생성·학습 금지 |
| G1 데이터 v2 | 3,000쌍과 split의 `2,024/274/702` record, `94/10/15` source LUT 격리 유지; NaN/Inf·누락·중복 ID 0건 | 데이터 재생성 또는 split 재구축 |
| G2 학습 smoke | loss finite, 1-batch total loss 감소, export/reload 축·값 범위 통과 | full run 금지 |
| G3 validation 선택 | test를 보지 않고 full-validation cube loss 최저 checkpoint 선택; seed 간 결과와 p95 기록 | 설정 한 번만 수정해 pilot 재실행 |
| G4 holdout 품질 | interpolation 대비 LUT-macro 평균 ΔE 개선, LUT paired 차이 95% CI 상한 `< 0`, sample mean·p95 비악화 | 추가 epoch 반복 금지; 데이터/목표 정의 재검토 |
| G5 배포 parity | FP16 TFLite 최대 절대 오차 `≤ 0.002`, 앱 축 색값 감사 통과, NaN/Inf·identity fallback 0건 | 변환 또는 앱 통합 수정 |
| G6 실기기 | iOS/Android release/profile에서 생성·미리보기·저장·메모리 기준 통과 | 베타 유지 또는 지원 범위 조정 |

현재 상태는 G0·G1·G2·G3 통과, G4 실패, G5 미진입, G6 보류다. G4 실패 후 test
702건을 열거나 배포 변환을 계속하지 않는 중단 규칙을 적용했다.

`G4`의 주 KPI는 source LUT를 동일 가중한 **LUT-macro 평균 ΔE2000의 기준선 대비 paired
차이**다. 사진 수가 많은 LUT가 평균을 지배하지 않도록 sample-weighted 평균은 보조 지표로
유지한다. p95, 고정 swatch, source group별 결과는 평균 개선이 극단 색 오류를 숨기지 못하게
하는 guardrail이다.

### 17.3 실행 단계

#### 단계 A — 축 계약 교정

1. [완료] `[R,G,B,channel]`을 메모리 텐서 계약, `r_fastest_rgb`를 파일 계약으로 명시한 공용 Python helper를 만들었다.
2. [완료] `2_generate_dataset.py`의 CUBE/BIN load와 BIN save, `17_evaluate_conditional_lut.py`의 load, `19_audit_lut_rendering_contract.py`의 load, `20_train_conditional_lut_mvp.py`의 export/reload를 공용 helper로 이동했다.
3. [완료] identity, RGB primary, 비대칭 혼합 LUT의 Python round-trip과 Dart R-fastest 인덱스를 고정했다.
4. [완료] dataset/evaluator/active V2 baseline loader를 포함한 Python unit test 5개, strict 축 검사, 관련 Flutter 테스트 4개가 통과했다. 구형 모델 smoke의 조기 반환 1건은 현재 모델 증거에서 제외한다.

#### 단계 B — 데이터셋 v2 재생성

1. [완료] 기존 `ml_pipeline/data/dataset`을 덮어쓰지 않고 `ml_pipeline/data/dataset_axis_v2_001`에 3,000쌍을 생성했다.
2. [완료] 119개 source LUT의 전체 node와 256개 고정 RGB probe를 저장·재로드 LUT와 직접 비교했다.
3. [완료] float16 양자화 후 직렬화 오차는 `0.0`, 보간 probe 최대 절대오차는 `0.000244`였다. LUT별 대표 neutral/graded JPEG 119쌍은 동일 인코더 재생성 결과와 byte 단위로 일치했다.
4. [완료] manifest에 dataset version, seed, 축 계약, 생성 코드 SHA-256, source LUT SHA-256을 기록하고 전 행의 일관성을 검사했다.
5. [완료] family holdout은 record `2,024/274/702`, source LUT `94/10/15`, family leakage 0건이다.

고정 checksum:

- manifest: `ad2517c66d9af38474143e22df6e0556be9b073e8478f44aaa634f1a1cc1b5a6`
- family split: `b03b8db19015243731f53fe847c60f95455af186a97b23543f9a8c7c3fc4c8b7`
- 17³ hue mask: `d0acaf51bc9fa5327a60c18bdf56c29c6c4ee0f9ff04e7e6be389141277adfb9`

#### 단계 C — 통제된 새 학습

기존 checkpoint는 resume하지 않는다. 먼저 현재 선택 모델과 동일한 direct MVP·smoothness
`0.01`만 사용해 축 교정의 효과를 분리한다. 구조 변경은 이 단계에서 금지한다.

- seed: `20260828`, `20260829`, `20260830`의 3개 독립 run.
- 최대 12 epoch, cosine scheduler 사용.
- validation cube loss 기준 early stopping patience 2를 학습기에 추가한다.
- decoder/encoder learning rate, batch size, loss weight는 기존 선택 run과 동일하게 유지한다.
- checkpoint 선택은 각 seed의 validation만 사용하며 test set은 최종 후보 하나가 정해진 뒤 한 번 평가한다.
- 각 epoch에 train/validation cube·image·smoothness loss, style cosine, 출력 variance, learning rate를 보존한다.

예시 실행 형태는 다음과 같다. 이 실행은 G1/G2 통과 후에만 허용한다.

```bash
.venv-ml-tflite/bin/python ml_pipeline/20_train_conditional_lut_mvp.py \
  --train --epochs 12 --lr-scheduler cosine \
  --smoothness-weight 0.01 --seed 20260828 \
  --experiment-id axis-v2-smooth010-seed-20260828 \
  --dataset-dir ml_pipeline/data/dataset_axis_v2_001 \
  --split-path ml_pipeline/reports/splits/axis_v2_001/conditional_lut_family_holdout.jsonl \
  --mask-path ml_pipeline/reports/hue_masks/axis_v2_001/hue_coverage_17.npz
```

#### 단계 D — 선택과 중단 규칙

1. 세 seed의 validation 결과를 먼저 비교하고 중앙값 seed를 재현성 대표로 기록한다.
2. 선택 후보를 PyTorch → ONNX → FP16 TFLite로 변환해 `≤ 0.002` parity를 확인한다.
3. 702장·15개 LUT 전체 색값 감사를 실제 앱 축으로 다시 실행한다.
4. G4를 통과하면 실기기 단계로 이동한다.
5. 세 seed 모두 기준선을 통계적으로 이기지 못하면 epoch나 모델 크기를 즉시 늘리지 않는다. reference 이미지가 LUT를 식별할 정보량, 합성 데이터 domain gap, source group 품질을 먼저 분석한다.

### 17.4 현재 최종 판단

- **지금 바로 추가 학습:** 동일 설정 3-se드 통제 학습은 완료됐으며 모두 G4 엄격 기준에 실패했다. 같은 데이터·목표로 epoch나 용량만 늘리는 추가 학습은 중단한다.
- **축만 교정한 기존 모델:** 내부 베타 비교용으로만 사용 가능. interpolation fallback 유지.
- **프로덕션 후보:** 없음. 중앙 validation seed `20260830`도 paired CI를 통과하지 못해 test·TFLite 승격 대상이 아니다.
- **다음 구현 작업:** 참조 이미지의 LUT 식별 가능성, 합성 데이터 domain gap, crawled/app/Canon source 품질을 seed 추가 없이 진단한다.

### 17.5 G3/G4 3-seed validation 결과

기존 선택 checkpoint의 설정을 고정하고 dataset만 axis-v2로 교체했다. identity-logit decoder
1024, encoder/decoder LR `5e-5/2e-4`, image weight `0`, smoothness `0.01`, style weight
`0.25`, cosine 최대 12 epoch, early stopping patience 2다. checkpoint 선택과 비교에는 validation
274건·10 LUT만 사용했으며 test 702건은 열지 않았다.

| seed | 종료/best epoch | best validation cube | sample ΔE 차이 | LUT-macro paired 차이 | bootstrap 95% CI | MVP 우세 LUT | 판정 |
| ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |
| 20260828 | 4/2 | 0.019759 | -1.9889 | +0.0767 | `[-1.2789, +1.3258]` | 4/10 | 실패 |
| 20260829 | 5/3 | 0.020766 | -1.2318 | -0.1207 | `[-1.0744, +0.8604]` | 6/10 | 실패 |
| 20260830 | 4/2 | 0.019848 | -2.0821 | -0.0896 | `[-1.4538, +1.1737]` | 5/10 | 실패 |

세 seed 모두 sample-weighted 평균은 interpolation보다 낮았지만 주 KPI의 CI 상한이 0보다
작지 않았다. seed 평균 LUT-macro 차이는 `-0.0446 ± 0.0867`이며 중앙 seed는 `20260830`이다.
이 결과는 “평균 사진에서는 개선 방향”이라는 신호일 뿐 미관측 LUT family 전반의 확정 우위가
아니다. G4는 **실패**이며 동일 설정 추가 학습, test 공개, 배포 변환을 중단한다.

### 17.6 앱·빌드·기기 재검증

| 검사 | 결과 | 객관 판정 |
| --- | --- | --- |
| `flutter analyze` | 문제 0건 | 통과 |
| 전체 Flutter unit/widget | 504개 통과, 로컬 모델/사진 fixture 1개 조건부 skip | 통과 |
| iPhone 17 simulator integration | 8개 통과 | 통과. 실기기 성능 증거는 아님 |
| iOS simulator Debug | `build/ios/iphonesimulator/Runner.app` 생성 | 통과 |
| iOS unsigned Release | `build/ios/iphoneos/Runner.app`, 153.4MB | 통과. 서명·설치 증거는 아님 |
| 실제 iPhone 무선 설치 | 서명 선택·Xcode build 후 Developer Disk Image mount 실패 | 보류. USB 연결 또는 Xcode device support 복구 필요 |
| Android build/device | Android SDK, AVD, 연결 기기 없음 | 보류 |
| Android 사진 권한 정적 계약 | image-only 요청, API 34 limited permission 선언, legacy storage mode 제거 | 코드 통과, 실기기 상태 전이는 보류 |

실제 iPhone과 Android에서 생성 latency, export 완주, Photos/MediaStore 저장, share 수신, peak RSS,
권한 허용·limited·거부·재허용을 측정하지 못했으므로 G6은 **보류**다.

### 17.7 validation 실패 원인 탐색

중앙 seed `20260830`의 10개 validation LUT만 사용했다. app/crawled는 각각 1개뿐이고 Canon이
8개라 group 결론은 탐색적이다.

| group | LUT | MVP 우세 | 평균 paired ΔE 차이 | 관찰 영역 차이 | 비관찰 영역 차이 |
| --- | ---: | ---: | ---: | ---: | ---: |
| app | 1 | 1 | -1.416 | -1.239 | -1.445 |
| crawled | 1 | 1 | -4.077 | -5.173 | -3.927 |
| Canon | 8 | 3 | +0.575 | +1.257 | +0.395 |

최대 열세 3개는 Canon Tasty Cool CLog2 `+2.571`, Rich Sepia CLog2 `+2.087`, Tasty Warm
CLog2 `+1.465 ΔE`였다. interpolation 난이도와 MVP-minus-interpolation의 Spearman은 `-0.939`,
coverage와 차이는 `+0.442`였다. 표본이 작아 인과 증거는 아니지만 “색역 coverage가 부족해서
epoch만 늘리면 해결된다”는 설명과 맞지 않는다. 어려운 look에서는 MVP가 도움을 주고, interpolation이
이미 잘 맞히는 Canon look에서 손해가 집중됐다.

다음 실험은 학습 반복이 아니라 Canon CLog→sRGB 합성의 transfer/gamut 가정, 동일 look의
CLog2/CLog3 중복 family, 참조 이미지가 전역 LUT를 식별할 수 있는지부터 검증해야 한다.

### 17.8 Canon 색공간 계약 감사와 dataset color-v3

Canon 원본 65³ LUT 82개는 전부 입력을 `Canon Log 2/3 / Cinema Gamut`, 출력을 BT.709로
선언한다. axis-v2 생성기는 sRGB 선형화 뒤 로그 함수만 적용했고 Cinema Gamut 변환을 생략했으며,
CLog2/3 계수와 CLog3의 piecewise 구간도 ACES 참조 구현과 달랐다. 이는 **높은 심각도·높은 신뢰도**의
학습 타깃 오류다. 원본 파일 누락이나 손상은 아니며 변환 단계에 국한된다.

외부 근거는 Canon의 [Canon Log 감마 공식 백서](https://downloads.canon.com/nw/learn/white-papers/cinema-eos/white-paper-canon-log-gamma-curves.pdf)와
ACES의 [Canon 입력·색공간 참조 변환](https://github.com/aces-aswf/aces-input-and-colorspaces/tree/main/canon)이다.
Canon 백서는 3D LUT가 색역 변환을 포함한다고 명시하며, ACES 변환은 Cinema Gamut primaries와
CLog2/3 full-range 수식 및 `0.9` 노출 스케일을 코드로 제공한다.

교정은 ACES Canon transform의 Cinema Gamut primaries와 CLog2/3 full-range 수식을 적용했다.
동일 룩 쌍을 독립 검증 기준으로 사용한 결과는 다음과 같다.

| 검사 | 구형 합성 | 교정 합성 | 판정 |
| --- | ---: | ---: | --- |
| CLog2/3 동일 룩 macro 평균 ΔE2000 | 11.3218 | 0.0765 | 41/41 개선, 통과 |
| 출력 0 경계 macro 평균, CLog2 | 8.004% | 0.256% | 개선 |
| 출력 0 경계 macro 평균, CLog3 | 7.228% | 0.251% | 개선 |
| 구형→교정 타깃 변화, CLog2 | 13.9057 ΔE | - | 구형 타깃 폐기 |
| 구형→교정 타깃 변화, CLog3 | 10.3309 ΔE | - | 구형 타깃 폐기 |

`color-v3-001`은 기존 데이터셋을 삭제하거나 덮어쓰지 않고 별도 3,000건으로 생성했다. source group은
crawled/app/Canon 각 1,000건이다. 무결성 감사의 manifest·파일·LUT 크기·source checksum 오류는 0건,
119/119 대표 neutral/graded JPEG는 byte exact, float16 양자화 후 저장 오차는 `0`, 256 probe 최대
절대오차는 `0.0002435`다. 생성기와 별도 Canon 계약 모듈 SHA도 전 행에서 일치했다.

기존 family RMSE 임계값 `0.08`은 교정 데이터에서 서로 다른 source group까지 연결하므로 사용하지 않았다.
41개 동일 룩 CLog2/3 RMSE는 최대 `0.003618`, 다른 룩은 최소 `0.017395`로 분리됐다. 그 사이의
`0.01`을 v3 임계값으로 고정한 결과 family는 78개(단독 37, CLog 쌍 41), CLog 쌍 41/41 동일 family,
source-group 교차와 split leakage는 0건이다. train/validation/test는 `2,318/339/343`건이다.

고정 checksum:

- manifest: `e60bf8971293d5e0d090ef4763cac726fa91c7c56be6712d9c1ac3ceefb49dfb`
- family split: `f8f2b2e206e8a4560888195d07a60b03a7d47b60824f67b771287b3ad19b8644`
- 17³ hue mask: `3c677fd9aebe240593eed48cc8a0edb52ee4f2705cf9edb64ac59e727c8a4ce2`

### 17.9 color-v3 통제 학습 결과와 학습 중단 판정

axis-v2 대표 seed와 아키텍처·LR·loss·cosine·patience를 고정하고 데이터와 split만 color-v3로 바꿨다.
seed `20260830`은 epoch 6에서 조기 종료됐고 best epoch 4의 validation cube loss는 `0.009078`이다.
이는 axis-v2 같은 seed의 `0.019848`보다 낮지만, 선택 loss 감소가 기준선 대비 ΔE 우위를 보장하지 않았다.

| 지표 | MVP | interpolation | MVP - 기준선 |
| --- | ---: | ---: | ---: |
| validation sample 평균 ΔE2000 | 13.4121 | 10.0915 | +3.3205 |
| validation LUT-macro 평균 ΔE2000 | 13.4254 | 10.4222 | +3.0033 |
| LUT paired bootstrap 95% CI | - | - | `[-1.2151, +7.7936]` |
| MVP 우세 source LUT | 7/12 | - | 엄격 게이트 실패 |

group별로 Canon 8개는 6개 우세·평균 `-1.3335 ΔE`, crawled 1개는 `-2.5888 ΔE`로 Canon
데이터 교정의 방향성은 확인됐다. 반면 app의 `fuji_mono_g`, `fuji_mono_ye`,
`leica_chocolate_hc`는 각각 `+15.5138/+16.6604/+17.1215 ΔE` 악화했다. 이 3개 참조의 평균
관측 cube fraction은 `0.72%`이고 비관찰 영역 악화가 평균 `+16.5323 ΔE`다. 이 결과는 app 전체에
대한 일반화 주장이 아니라, 현재 validation의 monochrome/강한 tone family에 대한 명확한 실패다.

객관적 결정:

1. **현재 상태로 출시하지 않는다.** G4 실패이며 test 343건, ONNX/TFLite, 실기기 모델 검증에 진입하지 않는다.
2. **같은 모델을 더 학습하지 않는다.** best epoch 이후 validation이 악화했고 실패가 특정 family에 집중돼 epoch·seed 증가는 원인에 맞지 않는다.
3. **다음 실험은 하나만 바꾼다.** app low-coverage family를 위한 interpolation fallback과 해당 family 학습 보강을 각각 별도 사전등록하고, 동일 validation을 재사용할 경우 post-hoc 과적합임을 표시한다.
4. **새 calibration/evaluation LUT를 확보한다.** fallback threshold를 현재 12개 LUT에서 정하고 같은 12개로 승인하지 않는다. 최소한 별도 app monochrome/강한 tone family에서 threshold와 선택 규칙을 고정해야 한다.
5. **실기기 작업은 필터 모델 승격과 분리한다.** export·권한·메모리 점검은 계속할 수 있지만, 현 checkpoint의 생성 품질을 제품 성능 수치로 측정하거나 배포 후보로 등록하지 않는다.

열린 질문은 app monochrome 계열을 제품의 필수 스타일 범위로 유지할지, interpolation을 공식 fallback으로
허용할지, 그리고 fallback 선택에 사용할 수 있는 런타임 신호를 reference hue coverage로 제한할지다.

### 17.10 10분 제한 후보 2개 선발 결과

후보당 최대 6 epoch 또는 10분 이내로 제한하고 test는 열지 않았다. 후보 A는 모델의 style consistency
weight만 `0.25 → 0.10`으로 바꿨고, 후보 B는 모델을 재학습하지 않고 reference hue coverage가 낮을 때
interpolation을 선택했다. 후보 B의 threshold는 한 LUT를 평가할 때 나머지 11개 LUT만 사용하는
leave-one-source-LUT-out 방식으로 선택했다.

| 후보 | 변경 | validation LUT-macro ΔE | interpolation 대비 | 95% CI | app 평균 차이 | 판정 |
| --- | --- | ---: | ---: | --- | ---: | --- |
| A | style weight `0.10` | 13.0811 | +2.6589 | `[-1.5240, +7.4269]` | +15.8468 | 탈락 |
| B | coverage LOO fallback | 9.6857 | -0.7365 | `[-1.6917, +0.2168]` | 0.0000 | 1순위 선발·보류 |

후보 A는 best validation cube가 `0.009004`로 control `0.009078`보다 0.8% 낮았지만 ΔE 실패를
해결하지 못했다. 이는 cube loss의 작은 개선만으로 후보를 선발하면 안 된다는 재확인이다. 후보 B는
12개 LUT 중 4개에 interpolation을 사용했고 app 3개를 모두 보호했으며 Canon/crawled 평균 차이는
`-0.7811/-2.5888 ΔE`였다.

선발 결정은 **B 우선, A 중단**이다. 그러나 B의 CI 상한이 0보다 크고 validation LUT가 12개뿐이므로
G4 통과나 배포 승격은 아니다. 다음 10분 작업은 새로운 app monochrome/강한 tone calibration LUT를
별도로 마련해 threshold `0.03` 부근을 고정하고, 기존 12개 validation LUT에는 고정 threshold를 한 번만
적용하는 순서다. 같은 12개에서 threshold를 다시 조정해 통과 처리하지 않는다.

### 17.11 coverage fallback 독립 보정 준비도 감사

후보 B의 임계값을 조정하기 전에 로컬 LUT catalog가 실제로 독립 보정 자료를 제공하는지 SHA-256으로
감사했다. 경로 또는 패키지가 달라도 내용이 같은 LUT는 하나로 취급했다.

| 항목 | 결과 | 객관 판정 |
| --- | ---: | --- |
| 조사한 물리 LUT 파일 | 67개 | app/crawled/synthetic catalog 전체 |
| 고유 SHA-256 내용 | 37개 | 복사본 30개 존재 |
| 기존 color-v3에 포함된 파일 | 67/67 | 모두 학습·validation·test 분할 중 하나에 속함 |
| 독립 보정 가능 내용 | 0개 | 보정 세트 구성 불가 |
| app train/validation/test LUT | 24/3/3 | train은 fitting 오염, validation은 threshold 탐색 오염, test는 예약 |
| threshold 0.03 미만 app LUT | train 10개, validation 3개 | 현상 확인에는 유효하나 독립 승인에는 사용 불가 |

LOO에서 12 fold 중 11 fold가 선택한 `0.03`을 고정한 뒤, 더 조정하지 않고 기존 validation에 한 번
적용했다. interpolation 사용은 app 3개뿐이었고 결과는 다음과 같다.

| 지표 | fixed fallback | interpolation | 차이 |
| --- | ---: | ---: | ---: |
| validation LUT-macro ΔE2000 | 9.3175 | 10.4222 | -1.1047 |
| paired bootstrap 95% CI | - | - | `[-2.2133,-0.0069]` |
| app 평균 차이 | - | - | 0.0000 |
| Canon 평균 차이 | - | - | -1.3335 |
| crawled 평균 차이 | - | - | -2.5888 |

이 결과는 **동작 확인**이지 독립 검증이 아니다. `0.03`이 같은 validation의 LOO 탐색에서 유래했기
때문에 CI 상한이 0 아래로 내려갔어도 G4 통과로 재분류하지 않는다. test 343건의 score·coverage는 열지
않았고 test LUT를 보정에 전용하지 않았다.

현재 3자 평가는 **조건부**다. 모델 추가 학습보다 먼저 라이선스와 출처가 기록된 별도 app-like LUT를
확보해야 한다. 그 세트는 coverage `< 0.03`과 `>= 0.03`, monochrome과 strong-tone을 모두 포함해야 하며,
scoring 전에 threshold `0.03`, coverage extractor와 모델·interpolation SHA, family dedup 계약을 고정한다.
독립 세트에서 LUT-macro paired 차이의 95% CI 상한 `< 0`이고 두 취약 strata가 악화하지 않을 때만 test를
한 번 공개한다.

### 17.12 외부 LUT 독립 보정 1차 결과

로컬 중복 문제를 피하기 위해 [LUMIX Original Looks](https://github.com/t0saki/lumix-original-looks)의
MIT 라이선스 commit `5694792f25598ec626e3e7527e2352f203a33317`을 고정했다. 이 저장소는 기존 LUT를
샘플링하거나 변환한 것이 아니라 수학적으로 생성한 sRGB 33³ CUBE 10개와 생성·QC 코드를 제공한다.
각 LUT 12장, 총 120장의 별도 calibration dataset을 만들었고 color-v3 train과 source SHA-256 중복은
0/10이다.

| 지표 | 후보 B fixed 0.03 | interpolation | 판정 |
| --- | ---: | ---: | --- |
| source LUT 평균 coverage 범위 | 6.81%~10.87% | - | 전부 high branch |
| LUT-macro ΔE2000 | 9.2841 | 11.6124 | -2.3283 개선 |
| paired bootstrap 95% CI | `[-3.4186,-1.1673]` | - | 상한 < 0 |
| MVP 우세 source LUT | 9/10 | - | Skylight 1개만 +1.3283 열세 |
| test partition | 미공개 | 미공개 | 유지 |

이 결과로 후보 B의 **high-coverage MVP 분기**는 독립 자료에서 통과했다. 그러나 10개 LUT 모두 threshold
위이고 흑백 전용 look이 없어서, low-coverage에서 interpolation으로 안전하게 전환되는지와 monochrome·
strong-tone 취약 계열의 재현성은 검증하지 못했다. 따라서 전체 3자 평가는 여전히 **조건부**다. 추가
학습보다 별도 low-coverage LUT 확보가 우선이며, 그 전에는 test·TFLite·제품 노출로 승격하지 않는다.

### 17.13 외부 흑백 LUT로 low-coverage 분기 검증

[RawTherapee Film Simulation Collection](https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation)은
컬렉션 README에서 CC BY-SA 4.0과 sRGB level-12 HaldCLUT 형식을 명시한다. commit
`3b3180f82d4dcea1e6e8c5648473539a910d7f49`의 Agfa·Ilford·Kodak 흑백 31개를 평가 전용으로 사용했고,
원본 LUT를 앱·학습 데이터·저장소에 포함하지 않았다. LUT당 12장, 총 372장이며 train content SHA 중복은 0개다.

| 지표 | 결과 | 판정 |
| --- | ---: | --- |
| LUT 평균 coverage 범위 | 0.327%~0.346% | 31/31 threshold 3% 미만 |
| interpolation 선택 | 31/31 | low branch recall 100% |
| selected / interpolation ΔE | 8.6180 / 8.6180 | exact 비악화 |
| 강제 MVP ΔE | 22.3156 | interpolation보다 +13.6976 악화 |
| 강제 MVP 우세 | 0/31 | fallback 필수 |

high 10개와 low 31개를 결합하면 selected/interpolation LUT-macro는 `8.7805/9.3483`, 차이는
`-0.5679`, 95% CI는 `[-1.0113,-0.1886]`다. 양쪽 routing recall 100%, train 중복 0건으로 외부
calibration gate를 통과해 one-time test 진입 조건을 만족했다.

### 17.14 고정 후보 B one-time test 결과

threshold·checkpoint·split·mask 체크섬을 먼저 고정하고 test를 한 번만 공개했다. 이후 결과를 이용한
threshold 변경, 모델 재학습, test 재평가는 금지한다.

| 지표 | 후보 B | interpolation | 차이/판정 |
| --- | ---: | ---: | --- |
| test source LUT | 12 | 12 | 동일 |
| 선택 분기 | MVP 7 / interpolation 5 | interpolation 12 | fixed 0.03 |
| LUT-macro ΔE2000 | 12.0414 | 12.8721 | -0.8307 |
| paired bootstrap 95% CI | - | - | `[-1.8213,-0.1094]` |
| app 평균 차이 | - | - | -0.4889, fallback 1/3 |
| Canon 평균 차이 | - | - | -0.7279, fallback 4/8 |
| crawled 평균 차이 | - | - | -2.6792, fallback 0/1 |

엄격 G4 기준인 LUT-macro 평균 개선과 paired CI 상한 `< 0`을 모두 만족했다. 특히 fallback을 제거하고
MVP를 강제하면 app/Canon은 interpolation 대비 각각 평균 `+4.8981/+0.7400 ΔE` 악화하므로 coverage
라우팅은 품질 안전장치로 유지해야 한다.

색값 품질 후보는 **G4 통과**이며 다음 단계는 고정 모델과 routing 정책의 ONNX/FP16 TFLite parity다.
다만 G5 배포 동등성과 G6 iOS/Android 실기기 성능·메모리가 아직 남아 있으므로 전체 릴리스 3자 평가는
여전히 **조건부**다.

### 17.15 color-v3 후보 B G5 배포 동등성

one-time test에 사용한 checkpoint SHA를 유지한 채 ONNX opset 17과 FP16-weight TFLite를 새 artifact
이름으로 변환했다. 앱 asset이나 모델 registry는 교체하지 않았다.

| 검사 | 결과 | 기준 | 판정 |
| --- | ---: | ---: | --- |
| ONNX 크기 | 72,494,561 bytes | 기록 | 통과 |
| ONNX↔PyTorch 최대 절대오차 | 0.00000268 | ≤0.00001 | 통과 |
| FP16 TFLite 크기 | 36,264,272 bytes | 기록 | 통과 |
| TFLite↔PyTorch 최대 절대오차 | 0.00083831 | ≤0.002 | 통과, 한도의 41.9% |
| 입력 계약 | float32 `[1,3,256,256]` | NCHW 일치 | 통과 |
| 출력 계약 | float32 `[1,17,17,17,3]` | RGB cube 일치 | 통과 |
| R-fastest 축·65³ persistence | loader/probe 전부 통과 | 오류 0 | 통과 |
| desktop TFLite 2-thread | 평균 3.171ms, p95 3.239ms, 50회 | 참고값 | 통과, 모바일 주장은 아님 |
| Flutter 앱 wrapper | 2개 테스트 통과, 전체 440ms | load·65³·결정성 | 통과, 모바일 주장은 아님 |

고정 artifact SHA-256:

- checkpoint: `3674a5a79bc68235bf80c99f8592933d3f83f92f84e016fc189a84bf8385cf47`
- ONNX: `62a6f8683474802c6ac059c0c2e97686e268d922551ddecd8a2a0cd43e53fcbc`
- FP16 TFLite: `a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`

desktop 범위의 G5는 **통과**했다. 남은 차단 조건은 G6으로, iOS/Android 실제 기기에서 cold/warm 생성,
peak RSS, 4K 내보내기, 권한 허용·limited·거부·재허용, 저장·공유를 측정해야 한다. 실제 모바일 증거가
없으므로 전체 릴리스 3자 평가는 계속 **조건부**다.

### 17.16 iOS 시뮬레이터 G6 선행 측정

2026-08-29 연결 기기를 조회한 결과 iPhone 17 Simulator, macOS, Chrome만 확인됐고 물리 iPhone과
Android 기기는 없었다. 따라서 G6 실기기 판정 대신 고정 FP16 후보를 임시 asset으로만 번들링해 iOS 26.5
Simulator debug에서 선행 측정을 수행했다. 제품 model registry와 배포 asset은 교체하지 않았다.

| 후보 생성 지표 | 결과 | 실기기 사전 기준 | 선행 판정 |
| --- | ---: | ---: | --- |
| interpreter cold proxy 표본 | 5회 | cold 5회 | 충족 |
| cold generate p95 | 454.980ms | ≤5,000ms | 통과 |
| warm generate 표본 | 30회 | warm 30회 | 충족 |
| warm generate p50 / p95 | 392.202 / 418.660ms | p95 ≤2,000ms | 통과 |
| baseline / peak RSS | 691.0 / 962.4MiB | 함께 기록 | 참고 |
| peak RSS 증가량 | 271.5MiB | ≤500MiB(2~3GB 기준) | 통과 |
| 종료 후 RSS 증분 | -1.5MiB | 지속 증가 없음 | 관측상 통과 |

Cold 값은 앱 프로세스를 재시작한 것이 아니라 같은 프로세스에서 interpreter를 5회 재생성한 proxy다.
RSS에는 integration-test runner가 포함되며 Simulator는 memory warning·jetsam을 재현하지 못한다. 따라서
절대 RSS가 아니라 증분과 회수 여부만 선행 신호로 사용한다.

| 편집·내보내기 지표 | 결과 | 기준 | 선행 판정 |
| --- | ---: | ---: | --- |
| frame total 표본 / p95 | 38 / 11.172ms | 30개 이상 / ≤16ms | 통과 |
| warm preview 표본 / p95 | 36 / 33.972ms | 30개 이상 / ≤80ms | 통과 |
| cold preview proxy | 22.290ms | ≤250ms | 통과 |
| export 첫 진행 표시 | 211.397ms | ≤500ms | 통과 |
| export 취소 복귀 | 281.006ms | ≤500ms | 통과 |
| 4K export 완주 | 미실행 | 완주·저장 검증 | 보류 |

전용 `direct_mvp_device_performance_test.dart` 1개와 기존 `editor_performance_test.dart` 2개는 모두
통과했다. 원시 요약은
`ml_pipeline/reports/device/color_v3_fallback_003_ios_simulator_g6_proxy.json`에 저장했다.

객관적 결론은 **Simulator preflight 통과, G6 실기기 보류**다. 물리 iOS/Android에서 release/profile cold
프로세스 재시작, peak RSS/PSS, 연속 10회, 4K 내보내기 완주, 권한 허용·limited·거부·재허용,
백그라운드 복귀를 측정하기 전까지 전체 릴리스 3자 평가는 **조건부**다.

### 17.17 후보 모델 교체 테스트 브랜치 기준선

2026-08-29 `main`의 `964e14cac61bb7ff5a3588bd7390bebd9acbf335`에서
`test/color-v3-fallback-routing` 브랜치를 만들었다. 기존 171개 미커밋 변경은 그대로 보존했다.
번들 `assets/models/direct_mvp_color_transfer_fp16.tflite`를 고정 후보 SHA
`a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`로 교체하고 모델 ID·버전·SHA
metadata를 함께 갱신했다.

| 검사 | 결과 | 판정 |
| --- | ---: | --- |
| 번들 asset ↔ 고정 후보 SHA | 완전 일치 | 통과 |
| 관련 AI/LUT 테스트 | 50개 통과 | 통과 |
| 전체 `flutter analyze` | 문제 0건 | 통과 |
| 전체 Flutter 테스트 | 504개 통과, 기존 fixture 조건 skip 1개 | 통과 |
| Flutter wrapper 전체 생성 | 437ms | 데스크톱 참고값 |
| iOS Simulator cold proxy p95 | 229.520ms, 5회 | 선행 통과 |
| iOS Simulator warm p95 | 129.699ms, 30회 | 선행 통과 |
| iOS Simulator peak RSS 증가 | 126,074,880 bytes(120.2MiB) | 선행 통과 |
| 종료 후 RSS 증분 | -5,455,872 bytes(-5.2MiB) | 누적 증가 미관측 |

이번 Simulator 입력은 기본 asset `summer_sapporo.jpg`이고 앞선 4.2MB fixture와 다르므로 두 실행의
절대 지연시간을 모델 개선 수치로 직접 비교하지 않는다.

현재 브랜치에는 후보 모델만 교체됐고 coverage `<0.03` 판단과 G4의 leakage-safe top-3 interpolation
fallback은 아직 없다. 따라서 저 coverage 입력도 neural path를 강제하며, 외부 흑백 31 LUT에서 이미 확인된
forced-MVP 악화 `+13.6976 ΔE` 위험이 남는다. 기술 배포 기준선은 통과했지만 품질 시스템은 미완성이므로
브랜치 평가는 **교체보류**다.

### 17.18 배포 가능한 routing fallback 대안 평가

G4의 원래 top-3 interpolation은 color-v3 train partition의 94개 source LUT와 각 reference feature centroid를
검색한다. Canon 및 출처가 불명확한 수집 LUT가 포함돼 LUT 원본·파생 index를 앱에 재배포할 권리가 확인되지
않았고, 현재 앱 LUT 32개로 바꾸면 test source LUT가 검색 후보에 들어갈 수 있어 평가 누출이 발생한다.
따라서 원래 top-3를 그대로 앱 asset으로 복사하지 않았다.

배포 가능한 대안으로 `단일 사진 coverage <0.03 → 기존 on-device algorithmic 생성`을 테스트 브랜치에
연결해 외부 CC BY-SA 흑백 31 LUT에서 source LUT당 대표 reference 1장으로 평가했다. 생성 LUT의 65³
float16 색값을 동일 target·17³ Color Cube·reference mask에서 직접 비교했다.

| 저 coverage fallback | LUT-macro ΔE2000 | top-3 대비 | 판정 |
| --- | ---: | ---: | --- |
| G4 top-3 interpolation | 8.9159 | 기준 | 통과 기준 |
| 기존 앱 algorithmic | 26.1940 | +17.2781 | 실패 |
| identity | 26.6727 | +17.7568 | 실패 |

algorithmic-minus-interpolation paired bootstrap 95% CI는 `[+15.1380,+19.1832]`, algorithmic 우세는
`0/31`이다. 한 장/LUT 선행 평가만으로도 명백한 열세이므로 12장/LUT 전체 확장은 중단했다.

Dart coverage 분석은 대표 컬러·경계·흑백 사례의 `<0.03` 분기를 모두 재현했다. 분석기는 후속 후보 검증을
위해 유지하지만, 실패한 algorithmic 라우팅의 제품 연결은 제거했다. 현재 가능한 안전한 선택은
`(1)` 재배포 가능한 별도 fallback 모델·asset을 마련하거나 `(2)` 저 coverage 입력에서는 생성을 거부하고
다른 컬러 reference를 요청하는 것이다. 품질 보존 관점에서는 `(2)`가 즉시 구현 가능한 권장안이며,
fallback이 준비되기 전 후보 모델의 일반 교체 평가는 계속 **교체보류**다.

### 17.19 저 coverage 생성 차단 구현

배포 가능한 fallback이 없는 상태에서 품질이 크게 악화하는 입력을 조용히 처리하지 않도록 권장안 `(2)`를
테스트 브랜치에 구현했다. 단일 reference 방식은 백그라운드 분석 isolate에서 파일을 디코딩한 직후 고정
coverage extractor와 threshold `0.03`을 적용한다. coverage가 threshold보다 낮으면 typed
`LowReferenceCoverageException`을 발생시키며 모델 설치·로드, 생성 worker isolate, `filters/` 작업 디렉터리와
LUT artifact 생성을 모두 시작하지 않는다. 분석 중 사용자 취소도 생성 진입 전에 확인한다. 다중 reference와
before/after 방식은 기존 계약을 변경하지 않았다.

사용자 화면은 일반 생성 오류와 구분해 한국어·영어 설명을 표시하고 `다른 사진 선택`/`Choose another`
동작을 제공한다. 이 정책은 fallback이 아니라 **abstention(생성 거부)** 이므로 저 coverage 품질을 지원한다고
해석하지 않는다.

| 검증 | 결과 | 판정 |
| --- | ---: | --- |
| 고정 대표 컬러·경계·흑백 routing | 전부 기대 분기 | 통과 |
| 실제 monochrome fixture | typed 차단, coverage `<0.03` | 통과 |
| 차단 후 `filters/` artifact | 생성 없음 | 통과 |
| 고 coverage fixture | neural 생성 및 coverage metadata 기록 | 통과 |
| 한국어 차단 UI | 설명·재선택 action·저장 없음 | 통과 |
| 한국어·영어 l10n | 문구·action 검증 | 통과 |
| 관련 집중 Flutter 테스트 | 19개 | 전부 통과 |
| 전체 `flutter analyze` | 문제 0건 | 통과 |
| 전체 Flutter 테스트 | 508개 통과, fixture 조건 skip 1개 | 통과 |
| ML 계약 테스트 | 13개 | 전부 통과 |
| `git diff --check` | 오류 0건 | 통과 |

알려진 forced-MVP 저 coverage 악화는 제품 경로에서 차단됐으므로 후보 교체 브랜치의 품질 안전장치는
구현됐다. 다만 threshold는 기존 G4 고정값이고 실제 사용자 사진 분포에서 false reject/false accept를
측정하지 않았으며 iOS/Android 물리 기기 G6도 남아 있다. 따라서 현재 3자 평가는 **조건부**다. 다음 승격
조건은 실제 기기에서 컬러·저채도·흑백 reference를 순회하며 차단률, cold/warm 지연, 메모리, 4K 내보내기와
권한 흐름을 함께 기록하는 것이다.

### 17.20 iPhone 17 Profile 실기기 G6 측정

2026-08-31 물리 `iPhone 17 (iPhone18,3)`, iOS `26.6.1 (23G83)`을 USB로 연결해 Profile 모드로
실행했다. Xcode는 `26.6 (17F113)`이고 후보 TFLite SHA는
`a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`다. 작업 트리가 dirty이므로
이번 결과는 후보 선발과 결함 탐색 증거이며 최종 출시 서명 증거로 사용하지 않는다.

#### Direct MVP 생성·메모리

| 지표 | 결과 | 기준 | 판정 |
| --- | ---: | ---: | --- |
| cold interpreter load p95, 5회 | 36.292ms | 기록 | 참고 |
| cold generate proxy p95, 5회 | 158.671ms | ≤5,000ms | 통과 |
| warm generate p50 / p95, 30회 | 130.158 / 135.138ms | p95 ≤2,000ms | 통과 |
| baseline / peak RSS | 174.0 / 334.8MiB | 함께 기록 | 참고 |
| peak RSS 증가 | 160.8MiB | ≤500MiB | 통과 |
| 종료 후 RSS 증가 | 51.7MiB | 반복 증가 여부 확인 | 단일 실행만으로 누수 판정 불가 |

`cold`는 앱 프로세스 재기동이 아니라 동일 Profile 프로세스에서 interpreter를 매회 다시 만든 proxy다.
따라서 실제 cold launch 판정은 남아 있다. 원시 JSON은
`build/perf/direct_mvp_iphone_physical_20260831.json`이고 SHA-256은
`5ce6135513eb72a939ab955e952eee07bc7b1077741858c18ed08857f3bd7419`다.

#### 편집·내보내기

| 지표 | 결과 | 기준 | 판정 |
| --- | ---: | ---: | --- |
| frame total 표본 / p95 | 38 / 0.808ms | 30개 이상 / ≤16ms | 통과 |
| warm preview 표본 / p95 | 36 / 34.045ms | 30개 이상 / ≤80ms | 통과 |
| cold preview proxy | 8.886ms | ≤250ms | 통과 |
| export 첫 non-zero 진행 표시 | 473.294ms | ≤500ms | 통과 |
| export 취소 복귀 | 266.527ms | ≤500ms | 통과 |
| 4K JPEG 완주 | 3840×2160, 2,466.671ms | 완주·서명·해상도 | 통과 |
| 4K 결과 크기 / 서명 | 4,009,603 bytes / 정상 | JPEG 검증 | 통과 |
| 4K peak RSS 증가 | 141.7MiB | ≤500MiB | 통과 |
| 4K 종료 2초 후 RSS 증분 | -11.5MiB | 지속 증가 없음 | 통과 |
| 4K 진행 update 최대 공백 | 1,192.904ms | ≤500ms | **실패** |

4K 결과는 production `EditorExportService` isolate로 생성하고 앱 임시 저장소에서 디코드 해상도와 JPEG
signature를 검증한 뒤 삭제했다. PhotoKit 저장은 수행하지 않았다. preview와 export-cancel 공식 gate는 모두
통과했지만, full-export의 진행 갱신 간격은 기준을 넘으므로 full gate를 통과 처리하지 않는다. 원시 파일은
`build/perf/editor_perf_iphone_physical_20260831.json`과
`build/perf/editor_4k_export_iphone_physical_20260831.json`이며 SHA-256은 각각
`4701901a6d065ee10c78f866abe8e36d057be7ce4ffdac02557ff6dd09a4d00c`,
`bddcf80572c53ac23d0f9ee767546fccb9daae338289f97481726a7fe809c78c`다.

#### 상태 계약·권한·런타임 위험

- Profile white-box는 `WB-ED-01/02/06`, `WB-CR-01`, `WB-DRAFT-01` 5/5 통과했다.
- 실제 Profile 앱 첫 화면에는 전체 사진 보관함 권한 팝업이 없었다. Flutter 도구 연결용 iOS 로컬 네트워크
  팝업만 표시됐고 해당 팝업 자체에 release build에서는 나타나지 않는다고 명시돼 있다.
- 시작 화면 증거는 `build/validation/20260831/iphone17/startup-permission-screen.png`, white-box JSON은
  `build/test-results/editor/whitebox_device_iphone_physical_20260831.json`이다.
- 실제 앱 시작 로그에서 `LiteRtMetalAccelerator.framework`와 `LiteRt.framework`에 동일 Objective-C class가
  중복 구현됐다는 런타임 경고가 다수 발생했다. 앱 프로세스는 계속 살아 있었지만 경고 자체가 casting failure와
  crash 가능성을 명시하므로 원인 제거 전 릴리스 위험으로 취급한다. 현재 앱은 classic interpreter를 쓰지만
  `flutter_litert 3.8.0`이 LiteRT Next와 Metal accelerator를 함께 번들한다.
- 시스템 사진 선택기 선택·취소, 최근 사진 진입 시점의 허용/limited/거부/재허용, PhotoKit 실제 저장은 이번
  자동 측정에 포함되지 않았다.
- 연결된 Android 실기기가 없어 Android 생성·PSS·권한·내보내기는 미측정이다.

iOS 후보 모델 생성, 편집 반응성, 4K 렌더링과 메모리는 실기기에서 통과했다. 그러나 export 진행 공백 실패,
LiteRT 중복 class 런타임 경고, PhotoKit 권한 matrix와 Android 미측정이 남아 있다. 전체 3자 평가는
**조건부**이며 일반 릴리스 승격은 아직 보류한다.

### 17.21 긴급 결함 수정과 재빌드

2026-08-31 요청 우선순위대로 LiteRT 중복 프레임워크, 4K 진행 갱신, PhotoKit 권한 경계를 수정했다.

#### LiteRT iOS·Android 런타임

Memoria는 `Interpreter` API만 사용하는데 `flutter_litert 3.8.0`의 Swift Package가 사용하지 않는
LiteRT Next와 Metal accelerator까지 항상 링크하고 있었다. 동일 Objective-C class가
`LiteRt.framework`와 `LiteRtMetalAccelerator.framework`에 중복된 직접 원인이므로, 프로젝트에
classic-Interpreter 전용 package variant를 고정했다. Dart API와 실제 사용하는 classic TensorFlow Lite
Interpreter는 유지하고, iOS와 Android에서 사용하지 않는 LiteRT Next 런타임만 제외했다.

완전 clean 후 Profile 빌드에서 두 프레임워크는 앱 번들과 `flutter-litert` 동적 링크 목록에서 모두
사라졌다. 남은 ML 프레임워크는 `TensorFlowLiteC`, `TensorFlowLiteCMetal`,
`TensorFlowLiteCCoreML`이다. 최종 Profile 앱은 `build/ios/iphoneos/Runner.app`, Flutter 보고 크기는
141.8MB다. 수정 전 156.2MB 빌드보다 약 14.4MB 작다. 이 비교는 서로 다른 증분 빌드 상태의 Flutter
표시값이므로 런타임 제거 확인의 보조 자료로만 쓴다.

로컬 package의 SwiftPM뿐 아니라 CocoaPods 대체 경로에서도 LiteRT Next 다운로드, vendored framework와
accelerator shim 연결을 제거했다. 최종 상태의 unsigned Release 재빌드는 139.0MB로 성공했고 앱 bundle 및
`otool -L` 결과에도 `LiteRt.framework`와 `LiteRtMetalAccelerator.framework`가 없었다. unsigned 산출물이므로
서명 검증 대상이나 설치용 artifact로 취급하지 않는다.

같은 최종 상태로 개발팀 서명 Profile 앱도 141.8MB로 다시 빌드했다. `codesign --verify --deep --strict`를
통과했고 물리 iPhone에 설치한 뒤 bundle identifier `com.260715.memoria`로 실행까지 성공했다.

제거 후 classic Interpreter 자체도 물리 iPhone Profile에서 다시 실행했다. TensorFlow Lite runtime 초기화와
35회 LUT 생성이 모두 통과했으며 warm p50/p95는 128.783/133.287ms, cold generate proxy p95는
158.460ms였다. peak RSS 증가는 187.0MiB다. 원시는
`docs/device-evidence/2026-08-31/perf/direct_mvp_iphone_physical_20260831_litert_fix.json`, SHA-256은
`0d07aa0130a00d64af66a29d6f2cac6a656f16d49dab866563c51e125e8074f6`다.

#### 4K 진행 표시

worker의 실제 milestone은 그대로 유지하고 메인 isolate가 200ms 간격으로 보수적인 monotonic pulse를
보낸다. pulse는 완료를 주장하지 않도록 0.949 아래로 수렴하고 worker의 0.95 완료 직전 milestone을
넘지 않는다. 취소·성공·실패 시 timer를 즉시 해제한다.

| 검사 | 결과 | 기준 | 판정 |
| --- | ---: | ---: | --- |
| 서비스 회귀 테스트 | 11개 통과 | 전부 통과 | 통과 |
| iPhone 17 Simulator Debug 4K | 3840×2160 JPEG, 1,299.162ms | 완주·서명·해상도 | 통과 |
| Simulator 진행 callback 최대 공백 | 202.088ms | ≤500ms | 통과 |
| 시뮬레이터 peak RSS 증가 | 171.6MiB | 참고 | 성능 판정 제외 |
| iPhone 17 Profile 4K | 3840×2160 JPEG, 2,477.709ms | 완주·서명·해상도 | 통과 |
| 실기기 진행 callback 최대 공백 | 201.209ms | ≤500ms | **통과** |
| 실기기 peak RSS 증가 | 174.5MiB | ≤500MiB | 통과 |
| 실기기 종료 2초 후 RSS 증분 | 12.1MiB | 지속 반복 증가 여부 확인 | 단일 실행 참고 |

원시는 `docs/device-evidence/2026-08-31/perf/editor_4k_export_ios_simulator_20260831_progress_fix.json`과
`docs/device-evidence/2026-08-31/perf/editor_4k_export_iphone_physical_20260831_progress_fix.json`이다. 실기기 JSON SHA-256은
`ad65862184682090740bfe7114df3429f91fa3950502b91c7c94b107508b6a1b`다. 기존 1,192.904ms 실패는
동일 물리 iPhone Profile 재측정에서 201.209ms로 개선돼 full-export 500ms gate를 통과했다.

#### PhotoKit 권한 matrix

| 기능 | iOS 접근 수준 | 요청 시점 | denied/limited 처리 |
| --- | --- | --- | --- |
| 기본 사진 선택 | 없음, 시스템 picker | 사용자가 선택 버튼을 누를 때 picker만 표시 | 전체 보관함 거부와 무관 |
| 최근 사진 탐색 | `readWrite` | 최근 사진 영역을 실제로 열 때 | denied는 fallback, limited는 제한 상태 표시 |
| 편집 결과 저장 | `addOnly` | 파일 검증 완료 후 PhotoKit publish 직전 | 거부 시 typed `permissionDenied`, 임시 파일 정리 |
| 공유 | 없음 | 공유 시트 직전 | PhotoKit 권한을 요청하지 않음 |

read/write와 add-only를 하나의 generic photo permission으로 합치지 않았다. 물리 iPhone에서는 두 상태가
모두 `notDetermined`일 때 read-only 진단을 실행했고 권한 프롬프트를 발생시키지 않았다. 실기기 원시는
`docs/device-evidence/2026-08-31/test-results/photo_permission_matrix_iphone_physical_20260831.json`, SHA-256은
`a396961e629ea59165528d9c5bbd97c4aa216c7c9d8dd42473e9d26fab4fb195`다.

iPhone 17 Simulator에서는 기대 상태를 명시한 자동 gate로 다음 세 상태를 검증했다.

| 사전 상태 | readWrite 관측 | addOnly 관측 | 판정 |
| --- | --- | --- | --- |
| 초기 상태 | `notDetermined` | `notDetermined` | 통과 |
| add-only 허용 | `notDetermined` | `authorized` | 통과 |
| 거부 | `denied` | `denied` | 통과 |

원시는 각각
`docs/device-evidence/2026-08-31/test-results/photo_permission_matrix_ios_simulator_not_determined_20260831.json`,
`docs/device-evidence/2026-08-31/test-results/photo_permission_matrix_ios_simulator_add_only_20260831.json`,
`docs/device-evidence/2026-08-31/test-results/photo_permission_matrix_ios_simulator_denied_20260831.json`이다. 이 자동 결과로는 시스템
picker 선택·취소, readWrite 전체 허용, limited 선택과 설정에서 재허용하는 사용자 UI 흐름을 증명할 수 없다.
해당 네 항목은 물리 기기 수동 matrix로 남긴다.

#### Android Release 패키징

Android SDK를 설치한 뒤 Google Mobile Ads 25.4.0의 Kotlin metadata와 맞도록 Kotlin을 2.3.20으로,
API 36 빌드에 맞도록 Android Gradle Plugin을 8.11.1로 올렸다. Release APK와 AAB는 모두 성공했다.

| 검사 | 결과 | 판정 |
| --- | --- | --- |
| universal Release APK | 156.8MB, SHA-256 `ddd3246e245b50adb512d5f3aeb7ec0ba1162adc2ff6937889da991f7515638a` | 빌드 통과 |
| Release AAB | 149.5MB, SHA-256 `f3e9c6cccb01eb649804abb1b050caa04e47095f4ea7d8e9a2195a03e7576fdc` | 빌드 통과 |
| APK 서명 구조 | APK Signature Scheme v2 검증 성공 | 구조 통과 |
| 서명 인증서 | `CN=Android Debug` | **배포 불가** |
| 미사용 LiteRT Next `.so` | `libLiteRt.so`, `libLiteRtClGlAccelerator.so` 모두 0개 | 통과 |
| 사용 중 Interpreter `.so` | 세 ABI의 `libtensorflowlite_jni.so`, `libtensorflowlite_gpu_jni.so` 유지 | 통과 |
| Android 물리 기기 | ADB 연결 장치 0개 | 미검증 |

수정 전 universal APK의 Flutter 보고값은 179.4MB였고 수정 후는 156.8MB로 22.6MB 감소했다. AAB에는
세 ABI가 모두 들어가므로 149.5MB를 실제 사용자 다운로드 크기로 해석하지 않는다. Play App Signing과
기기별 split이 적용된 설치 크기는 Play Console 또는 `bundletool` device spec으로 별도 측정해야 한다.
현재 프로젝트의 release signing fallback은 debug 인증서이므로 이 산출물은 설치·구조 검증용일 뿐 스토어에
업로드할 최종 artifact가 아니다.

merged manifest에는 API 34 partial-photo, API 33 images, API 32 이하 read, API 29 이하 write 권한이
의도한 version gate와 함께 존재한다. 다만 Android 실기기가 없어 시스템 picker 무권한 동작, 최근 사진의
허용·부분 허용·거부·재허용, 갤러리 저장, 공유, 4K 내보내기와 PSS는 실행하지 못했다.

전체 `flutter analyze`는 문제 0건, Flutter 테스트는 515개 통과와 기존 fixture 조건 skip 1개,
`git diff --check`는 통과했다. iOS의 긴급 런타임·진행률 결함과 정적 권한 경계, Android Release 빌드와
미사용 런타임 패키징은 해결됐다. 그러나 iOS 사용자 선택 권한 matrix와 Android 물리 기기 권한·내보내기·
메모리 검증, 정식 Android release signing이 남아 있으므로 제3자 관점의 전체 플랫폼 릴리스 평가는 계속
**조건부**다.

### 17.22 기존 모델 대 color-v3 G4/G5 후보 iPhone 실기기 A/B

`test/color-v3-fallback-routing` 브랜치에서 기존 배포 모델과 G4·G5를 통과한 color-v3 후보를 같은 물리
iPhone 17, iOS 26.6.1, Profile, `summer_sapporo.jpg`, classic TensorFlow Lite Interpreter 조건으로
비교했다. 테스트 bundle에 두 모델을 함께 넣고 각 모델을 독립 프로세스로 2회 실행했다. 모델당 cold proxy
10회와 warm 60회다. 측정 후 기존 모델을 위한 임시 asset 선언은 제거했다.

| 항목 | 기존 모델 `4a9439…` | G5 후보 `a1b8ec…` | 후보 차이 | 판정 |
| --- | ---: | ---: | ---: | --- |
| cold generate 평균 | 132.991ms | 136.297ms | +2.49% | 실질 동급 |
| cold generate run별 p95 평균 | 151.382ms | 166.783ms | +10.17% | 둘 다 5,000ms 기준 통과 |
| warm generate 평균 | 127.393ms | 128.241ms | +0.67% | 실질 동급 |
| warm generate run별 p95 평균 | 131.410ms | 134.722ms | +2.52% | 둘 다 2,000ms 기준 통과 |
| peak RSS 증가 평균 | 180.3MiB | 170.3MiB | -5.6% | 후보 비악화, 실행 간 편차 큼 |
| 종료 후 RSS 증가 평균 | 51.8MiB | 51.9MiB | +0.1% | 동급, 반복 누수 증거 없음 |

각 실행의 첫 interpreter 생성에서 약 3ms 또는 34~36ms가 관측돼 cold p95가 5개 중 한 표본에 민감했다.
두 모델에서 모두 발생했으므로 특정 모델 결함으로 분류하지 않는다. 이 테스트의 cold는 프로세스 재시작이
아니라 한 프로세스 안에서 interpreter를 다시 만드는 proxy이고, RSS에는 integration-test runner가 포함된다.

원시 파일과 SHA-256은 다음과 같다.

- 기존 run 1: `docs/device-evidence/2026-08-31/perf/direct_mvp_baseline_iphone_physical_20260831.json`,
  `a3fe9fc5b7790865ce49de8934f9e23b2ca4c09e73e60d73ccd8c62bcbe9e151`
- 기존 run 2: `docs/device-evidence/2026-08-31/perf/direct_mvp_baseline_iphone_physical_run2_20260831.json`,
  `0a4e0b94e9f095b31f7c7fa8b0ff8423449d6def60cbe7c8395c0d59b3e158c6`
- 후보 run 1: `docs/device-evidence/2026-08-31/perf/direct_mvp_g5_candidate_iphone_physical_ab_20260831.json`,
  `f8868cc0386a101b3455534b81f31cc02936b1e5d5caf43acf0104a00bd81c1a`
- 후보 run 2: `docs/device-evidence/2026-08-31/perf/direct_mvp_g5_candidate_iphone_physical_ab_run2_20260831.json`,
  `a88887d20da06adea509e68f2f0fc099f4689508d84efb14443d7898bd0c00dd`

실기기 성능만 보면 두 모델은 제품 의사결정을 바꿀 수준의 차이가 없다. 기술 선택의 근거는 성능이 아니라
색값 품질이다. 기존 배포 모델의 이전 고정 감사는 실제 축 출력 LUT-macro ΔE2000 `22.9874`, top-3
interpolation 대비 `+8.2077`과 paired CI `[+6.8402,+9.7074]`로 실패했다. color-v3 후보 B는 별도로 고정한
one-time test에서 coverage routing 적용 LUT-macro ΔE2000 `12.0414`, interpolation `12.8721`, 차이
`-0.8307`, CI `[-1.8213,-0.1094]`로 G4를 통과했고 TFLite parity G5도 통과했다. 두 수치는 서로 다른
dataset 계약이므로 `22.9874-12.0414`를 직접 개선량으로 계산하지 않는다.

객관적 선택은 **G5 후보 + coverage 차단 유지**다. 후보가 성능상 기존 모델과 동급이면서 고정된 자기 품질
gate를 통과했기 때문이다. 다만 앱에는 라이선스가 확인된 interpolation fallback이 없으므로 coverage `<0.03`
입력은 현재 구현처럼 생성을 거부해야 한다. Android 실기기 G6 전에는 일반 릴리스 승격은 **조건부**다.

### 17.23 G5 후보 필터 제작 iPhone 실기기 블랙박스

2026-08-31 물리 iPhone 17, iOS 26.6.1, Profile에서 한국어 `CreateFilterPage`를 UI로
조작했다. 사진 소스 경계만 결정적 fixture로 대체했고 생산용 coverage 판정, G5 TFLite
모델과 worker, 미리보기 렌더러, repository transaction은 그대로 사용했다. 생성 버튼은
제품 메서드를 직접 호출하지 않고 accessibility semantics의 tap action으로 눌렀다.

| 검사 | 실기기 관측 | 판정 |
| --- | ---: | --- |
| 번들 G5 SHA-256 | `a1b8ecf00632...e02241a6` | 일치 |
| coverage 임계 | `0.03` | 유지 |
| 저색상 입력 | 242.221ms, 안내·다른 사진 선택 표시, 저장 0건 | **차단 통과** |
| 정상 색상 사진 | 2,244.870ms, 성공 sheet 표시 | **생성 통과** |
| 산출물 | preset 1건, LUT·preview 파일 존재 | **저장 통과** |
| 테스트 전체 UI 흐름 | 5,271.437ms | 참고 |
| RSS 증분 | 185,942,016 bytes, 약 177.3MiB | 단일 실행 참고 |
| 정리 | 생성한 정확한 preset ID를 `finally`에서 삭제 | 통과 |

입력한 사용자 이름보다 사진 분석에서 제안된 `내추럴 톤`이 최종 preset 이름으로
저장됐다. 이는 생성·차단 gate의 합격 조건은 아니며, 수동 이름 편집을 보존해야 하는
제품 정책인지는 별도 UI 요구사항으로 확인할 필요가 있다.

원시 결과는 `docs/device-evidence/2026-08-31/test-results/create_filter_blackbox_iphone_physical_20260831.json`,
SHA-256은 `87642f6fca0bd5f5acac59886be828e3d2c9f60fdfc023b60ddef640ba5e4c7e`다. 시스템
사진 picker와 PhotoKit 권한은 fixture 주입 경계 밖이므로 이 테스트로 합격을 주지 않는다.
또한 RSS는 integration-test runner가 포함된 단일 실행 프로세스 증분으로 반복 누수를
증명하지 않는다. 이 범위에서는 **G5 후보 유지 + coverage `<0.03` 생성 차단**이
실기기 UI 경계에서 검증됐다.
