<div align="center">

<img src="assets/icons/memoria-mark.png" alt="Memoria 로고" width="140" height="140">

# Memoria

[![iOS Build](https://github.com/cres17/memoria/actions/workflows/ios-build.yml/badge.svg?branch=test/color-v3-fallback-routing)](https://github.com/cres17/memoria/actions/workflows/ios-build.yml?query=branch%3Atest%2Fcolor-v3-fallback-routing)
[![MIT License](https://img.shields.io/badge/License-MIT-2EA44F)](LICENSE)
![Flutter 3.44.6](https://img.shields.io/badge/Flutter%203.44.6-02569B?style=flat&logoColor=white&logo=flutter)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logoColor=white&logo=dart)
![go_router](https://img.shields.io/badge/go__router-02569B?style=flat&logoColor=white)
![LiteRT / TFLite](https://img.shields.io/badge/LiteRT%20%2F%20TFLite-FF6F00?style=flat&logoColor=white&logo=tensorflow)
![MediaPipe](https://img.shields.io/badge/MediaPipe-0097A7?style=flat&logoColor=white&logo=mediapipe)
![Swift](https://img.shields.io/badge/Swift-F05138?style=flat&logoColor=white&logo=swift)
![Core Image](https://img.shields.io/badge/Core%20Image-000000?style=flat&logoColor=white)
![SharedPreferences](https://img.shields.io/badge/SharedPreferences-4D5868?style=flat&logoColor=white)
![Google AdMob](https://img.shields.io/badge/Google%20AdMob-EA4335?style=flat&logoColor=white&logo=googleadmob)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logoColor=white&logo=python)
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?style=flat&logoColor=white&logo=pytorch)
![timm](https://img.shields.io/badge/timm-FFD21E?style=flat&logoColor=black)
![ONNX](https://img.shields.io/badge/ONNX-005CED?style=flat&logoColor=white&logo=onnx)
![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=flat&logoColor=white&logo=tensorflow)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat&logoColor=white&logo=githubactions)

</div>

사진을 고르고 보정하고, 마음에 드는 사진의 색을 나만의 필터로 만들어 다시 쓰는 모바일 사진 편집 앱입니다. 모든 편집과 필터 생성은 서버 없이 기기 안에서 처리합니다. iOS 15.0 이상을 기준으로 개발 중이며 Android 프로젝트도 함께 들어 있습니다.

> 이 브랜치(`test/color-v3-fallback-routing`)는 `main`에서 갈라져 참조 사진의 색 범위를 먼저 검사하는 라우팅, 로컬로 줄인 `flutter_litert` 패키지, 편집 화면 분리, 실기기 검증 테스트를 추가한 작업 브랜치입니다.

- **편집**: Fuji 18종 · Leica 5종 LUT 필터, 노출 · 커브 · HSL 등 기본 보정, 크롭 · 원근, 부분 보정, 인물 영역 보정, 텍스트 · 프레임, undo/redo
- **나만의 필터**: 참조 사진 1장, 여러 장, 또는 보정 전후 사진 한 쌍으로 65³ LUT 필터 생성. 참조 사진 1장의 색 범위가 부족하면 생성 전에 다른 사진을 고르도록 안내
- **내보내기**: JPEG · PNG · TIFF · WebP(iOS), 원본 해상도, 사진 앱 저장과 공유

## 전체 아키텍처

<p align="center">
  <img src="docs/assets/readme/architecture.svg" alt="Memoria 전체 아키텍처" width="100%">
</p>

| 흐름 | 설명 |
|------|------|
| 편집 | 편집기가 현재 보정값을 불변 `EditorRenderRecipe`로 묶어 이미지 엔진에 넘기고, 미리보기(긴 변 720px)와 원본 해상도 내보내기를 각각 별도 isolate에서 렌더링 |
| 기록 · 복구 | 적용한 작업은 `EditorHistoryController`가 최대 100개까지 보관하고, 편집 중 상태는 500ms debounce 후 `EditorDraftStore`가 SharedPreferences에 저장 |
| 색 범위 검사 | 참조 사진 1장이 17³ RGB 격자 색의 3% 미만만 덮으면 `LowReferenceCoverageException`으로 생성을 중단하고 다른 사진을 고르게 안내 |
| 필터 제작 | 검사를 통과한 참조 사진을 LiteRT 모델에 넣어 17³ LUT를 예측하고 65³로 보간, 썸네일 렌더까지 성공하면 LUT와 recipe를 `filters/<id>/`에 저장 |
| 인물 보정 | MediaPipe Selfie Segmenter(landscape)로 사람 영역 마스크를 만들어 부드럽게 · 밝기 · 색조 보정에 사용 |
| 내보내기 | JPEG · PNG · TIFF는 Dart 인코더, WebP는 MethodChannel로 Swift의 ImageIO에 넘겨 인코딩 |
| 모델 준비 | `ml_pipeline`에서 PyTorch로 학습 → ONNX → TFLite(fp16)로 변환해 앱에 번들 |

```text
lib/
├── features/        home · editor · create_filter · filters · settings 화면과 서비스
│   └── editor/      page_shell · runtime · controls · menus · history 등으로 나눈 편집 화면
├── engine/          LUT · 색 · 참조 색 범위 검사 · crop · blur · portrait · export 엔진 (Flutter 위젯 의존 없음)
├── ai/              모델 설치 상태 관리와 TFLite 입출력 래퍼
├── domain/          EditOperation, FilterRecipe 모델과 저장소 계약
├── data/            JSON 파일 · SharedPreferences 저장 구현
├── core/            라우터 · 테마 · 언어 · 오류 로그 · 시작 단계(startup)
└── monetization/    광고 flag와 배너 · 전면 광고
ios/Runner/          LutEnginePlugin.swift (MethodChannel)
third_party/         Interpreter 런타임만 남긴 flutter_litert 3.8.0 로컬 패키지
ml_pipeline/         데이터 생성 · 학습 · 평가 · ONNX/TFLite 변환 스크립트
```

## 각 기술 설명

### Flutter · go_router

화면은 HOME · GALLERY(필터 보관함) · EDIT · CREATE · 설정으로 나뉩니다. `core/router/app_router.dart`의 GoRouter가 HOME과 GALLERY는 하단 내비게이션을 공유하는 shell로, EDIT과 CREATE는 독립 화면으로 띄우며 iOS에서는 `CupertinoPage` 전환을 씁니다. 오류 로그 · 언어 · 모델 설치 같은 초기화는 `core/startup/app_startup.dart`의 이름 있는 단계로 첫 화면 뒤에 실행하고, 한 단계가 실패해도 기록만 남기고 다음 단계를 계속합니다. 설정에는 개인정보 처리방침 · 고객 지원 화면(`legal_support_pages.dart`)이 있습니다.

### 이미지 엔진 (Dart · isolate)

`lib/engine/`의 순수 Dart 함수들이 픽셀 연산을 담당합니다. LUT 적용(`lut_engine.dart`), 화이트밸런스 · HSL · 커브, 블러 · 브러시 · dodge/burn, 원근 변환, 인물 마스크 기반 보정, 프레임 · 텍스트 합성이 여기에 있습니다. 위젯에 의존하지 않기 때문에 미리보기 isolate와 내보내기 isolate가 같은 코드를 쓰고, 작은 fixture로 단위 테스트할 수 있습니다. 미리보기는 같은 상태의 결과를 캐시해 반복 렌더링을 줄입니다.

### 참조 색 범위 검사 (reference_coverage_router)

참조 사진 1장으로 필터를 만들 때, 모델을 돌리기 전에 `engine/reference_coverage_router.dart`가 별도 isolate에서 사진의 색 분포를 셉니다. 사진 픽셀을 HSV 기준 색조 24 × 채도 4 × 명도 3칸(무채색은 명도 3칸)으로 나눠 센 뒤, 17³ RGB 격자의 4,913개 색마다 그 색이 속한 칸에 사진 픽셀이 32개 이상 있는지 확인해 비율을 냅니다. 이 비율이 3% 미만이면 모델이 사진에 없는 색을 추측해야 하는 범위가 너무 넓다고 보고 생성을 멈춘 뒤, "여러 색상과 밝기가 포함된 사진을 선택해 주세요" 안내와 다른 사진 선택 버튼을 띄웁니다. 사진을 읽지 못하는 등 검사 자체가 실패하면 기록만 남기고 기존 생성 경로로 진행합니다.

### LiteRT (flutter_litert) — 나만의 필터

`CreateFilterPage`에서 고른 방식에 따라 LUT를 만듭니다. `flutter_litert`는 pub.dev 패키지 대신 `third_party/flutter_litert`의 로컬 사본(3.8.0+memoria.3)을 씁니다. 원본 3.8.0에 함께 들어 있는 LiteRT Next 런타임이 iOS에서 Objective-C 클래스를 중복시키고 Android에 쓰지 않는 네이티브 라이브러리를 더하기 때문에, 기존 Interpreter 런타임만 남겼습니다. 생성 작업은 `IsolateCreateFilterGenerator`가 별도 isolate에서 45초 제한으로 실행하며, 취소나 실패 시 만들던 폴더를 지웁니다.

| 방식 | 구현 |
|------|------|
| 참조 사진 1장 | 번들 모델 `direct_mvp_color_transfer_fp16.tflite`가 256×256 입력에서 17³ LUT를 예측하고 `LutPredictor`가 65³로 보간. 모델 파일은 크기와 SHA-256을 확인한 뒤 사용 |
| 참조 사진 2~5장 | 사진별 색 분포를 통계적으로 합치는 알고리즘 방식 (다중 입력 모델은 없음) |
| Before / After 한 쌍 | `personal_filter_core.dart`가 대응 픽셀로 전역 affine 색 변환을 맞추고, 남은 오차를 작은 3D residual grid로 학습한 뒤 65³ LUT로 변환 |

추론이 실패하면 알고리즘 경로로 대체하고 그 이유를 `FilterRecipe`에 남깁니다. recipe에는 생성 방식 · 모델 버전 · 참조 수 · 안전성 지표가 함께 기록됩니다.

### MediaPipe Selfie Segmenter

인물 영역 보정에 쓰는 분할 모델입니다. 앱에 번들하지 않고, `ai_manager.dart`가 처음 필요할 때 Google Storage의 `selfie_segmenter_landscape.tflite`(float16)를 30초 제한으로 내려받아 저장합니다. 결과는 얼굴 피부가 아니라 사람 전체 영역 마스크입니다.

### Swift · Core Image · ImageIO

`ios/Runner/LutEnginePlugin.swift`가 `com.memoria/lut_engine` MethodChannel을 엽니다. Core Image의 `CIColorCube`로 LUT를 적용하는 네이티브 경로와, Dart에 인코더가 없는 WebP를 ImageIO(`CGImageDestination`)로 저장하는 경로를 제공합니다. Dart 쪽에서는 PNG 중간 파일을 넘깁니다.

### SharedPreferences · JSON 파일

편집 기록(`EditOperation` snapshot)과 화면 상태는 사진 경로별 키로 SharedPreferences에 draft로 저장해, 앱을 닫았다 열어도 이어서 편집할 수 있습니다. 사용자 필터는 앱 문서 디렉터리의 `filters/<id>/`에 LUT · 썸네일 · recipe · metadata 파일로 보관하고, `FilterCommitTransaction`이 썸네일 생성까지 끝난 필터만 목록 index에 추가합니다.

### PyTorch · ONNX · TensorFlow Lite (ml_pipeline)

번호 순 스크립트로 데이터 준비 · 학습 · 평가 · 변환을 진행합니다. LUT 수집과 학습 데이터 생성(`1_`, `2_`, `4_`, `5_`)부터 조건부 LUT 모델 학습(`20_train_conditional_lut_mvp.py`)과 평가 · 홀드아웃 비교를 거쳐, `34_`에서 `torch.onnx.export`로 ONNX를 만들고 `35_`에서 onnx-tf로 SavedModel을 거쳐 `TFLiteConverter`로 fp16 TFLite를 만듭니다. 인코더는 timm의 `mobilenetv3_small_100`입니다. `36_`은 변환된 모델의 추론 속도를 측정합니다.

이 브랜치는 `37_`~`53_` 스크립트로 color-v3 검증을 이어 갑니다. LUT 축 순서 계약(`lut_axis_contract.py`)과 Canon LUT 색 계약(`canon_color_contract.py`) 감사, axis-v2 데이터셋의 다중 seed 검증, 참조 색 범위 기준의 fallback 평가(`44_`~`51_`), 배포본 parity 요약(`52_`), 앱의 Dart 알고리즘 fallback 비교(`53_`)가 있습니다. `TRAINING_PROGRESS.md` 기준으로 axis-v2는 G0~G3를 통과했지만 3-seed 검증에서 보간 대비 우위를 통계적으로 확인하지 못해(G4 실패) test 평가와 배포 승격을 멈추고 원인을 진단하는 단계입니다.

### google_mobile_ads

`lib/monetization/`의 배너 · 전면 광고 위젯입니다. `feature_flags_service.dart`의 flag로 필터 제작 후 · 적용/내보내기 후 전면 광고 노출 여부를 따로 제어합니다. 광고 SDK 초기화는 release가 아닌 빌드에서만 실행합니다.

### 테스트 · GitHub Actions

`test/`에는 엔진 · recipe · history · draft의 단위 테스트와 위젯 테스트가, `integration_test/`에는 실제 `EditorPage`를 띄우는 시나리오가 있습니다. `integration_test/`에는 WebP 네이티브 인코딩 · 4K 내보내기 · 사진 권한 · 공유 완료 · 인물 보정 메모리를 확인하는 실기기용 테스트도 있습니다. `ios-build.yml`은 `main`과 이 브랜치에서 macOS runner로 Flutter 3.44.6을 설치해 잠긴 의존성 설치 → 필수 asset 테스트 → `flutter analyze` → 서명 설정 테스트 → `flutter test --coverage` → iOS 시뮬레이터 통합 테스트 → 서명 없는 release 빌드와 IPA artifact 업로드를 실행합니다.
