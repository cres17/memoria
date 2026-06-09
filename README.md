
# Memoria

![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.0-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0-blue?logo=dart)
![Riverpod](https://img.shields.io/badge/Riverpod-2.x-blueviolet)
![go_router](https://img.shields.io/badge/go_router-13.x-lightgrey)
![tflite_flutter](https://img.shields.io/badge/tflite__flutter-0.12.1-9cf)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![GitHub stars](https://img.shields.io/github/stars/cres17/memoria?style=social)

**Memoria**는 전문가 수준의 사진 편집을 목표로 한 크로스플랫폼 Flutter 애플리케이션입니다. LUT 기반 색 보정, GPU 실시간 프리뷰, 모듈화된 편집 파이프라인과 선택적 ML 도구를 결합하여 모바일 및 데스크톱에서 일관된 고품질 결과물을 제공합니다.

테크 스택
- UI/프레임워크: Flutter (Dart)
- 플랫폼: Android, iOS, Windows, Web
- 이미지 처리 엔진: 커스텀 Dart/C++ 파이프라인 (lib/engine)
- ML 파이프라인: TensorFlow Lite (선택적, ml_pipeline/)
- 빌드/CI: Flutter tooling, 권장: GitHub Actions / Azure Pipelines

주요 기능(상세)

- LUT 기반 필터
	- 고해상도 3D/2D LUT(.bin/.npy)를 이용해 필터를 구현합니다.
	- 사용자 정의 LUT을 추가하고, 런타임에서 빠르게 적용할 수 있도록 최적화되어 있습니다.

- 실시간 GPU 프리뷰
	- 회전, 원근(perspective), 기울기(tilt) 등 공간 변형을 GPU 레이어에서 즉시 렌더링합니다.
	- 드래그 중에는 경량 GPU 변환을 사용해 60fps 수준의 응답성을 목표로 합니다.

- 비파괴 편집 파이프라인
	- 편집 스택(노출, 대비, 곡선, HSL, 그레인 등)을 기록하고 되돌리기/재실행이 가능합니다.
	- 편집 이력은 세션 기반으로 저장되어 재현 가능성을 제공합니다.

- 선택적 ML 지원
	- LUT 생성, 스타일 전송, 분할(segmentation) 같은 워크플로를 위한 학습/추론 스크립트를 포함합니다.
	- ML 모델은 선택적 자산으로 관리되며, CI에서만 사용하거나 수동으로 배포할 수 있습니다.

- 지역 선택/브러시/히일링
	- 포괄적인 로컬 편집 도구(브러시, 힐링, 클론 등)를 제공하여 픽셀 단위 복구/보정 작업을 지원합니다.

- 포커스(틸트-시프트) 오버레이
	- 터치/드래그로 중심/폭을 조정할 수 있는 인터랙티브 포커스 오버레이를 지원합니다.

- 프레임·텍스트 오버레이 및 레이아웃
	- 내장 프레임 템플릿, 커스텀 텍스트 오버레이(폰트 포함)로 다양한 스타일을 적용할 수 있습니다.

- 고급 컬러 도구
	- 곡선(Curves) 에디터, HSL/채널 분리, 스플릿토닝 등 전문적인 색 보정 기능을 제공합니다.

- 내보내기
	- 고품질 이미지 내보내기(다양한 해상도, 포맷)와 메타데이터 보존 옵션을 제공합니다.

빠른 시작 (개발자)

```bash
git clone https://github.com/cres17/memoria.git
cd memoria
flutter pub get
flutter run -d <device-id>
```

테스트

```bash
flutter test
```

CI 권장사항
- GitHub Actions에서 플랫폼별 빌드(ubuntu/macos/windows)와 테스트를 구성하세요.
- Windows 환경에서 ML 관련 테스트를 수행하려면 필요한 네이티브 바이너리(TFLite 등)를 워크플로에서 설치하거나 아티팩트로 제공하세요.

기여 가이드
- 기능은 분기 생성 → PR → 코드 리뷰 순으로 제출하세요.
- 변경 사항에는 가능한 경우 단위/위젯 테스트를 추가해 주세요.

라이선스
- 이 저장소의 소스 코드는 기본적으로 MIT 라이선스 하에 제공됩니다. 자세한 내용은 `LICENSE` 파일을 확인하세요.

문의 및 유지보수
- Maintainer: https://github.com/cres17

