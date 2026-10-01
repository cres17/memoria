# memoria 코드 수정 및 재검토 — 2026-10-01

## 범위와 원격 상태

검토 기준은 로컬 `test/color-v3-fallback-routing` 브랜치의 `d99346d0a`와 기존 미커밋 변경이다. 기존 Android·실기기 검증 변경은 보존했다. 첫 검증 및 후속 리뷰 단계에서는 커밋하거나 푸시하지 않았다. 이후 사용자의 브랜치 푸시 요청에 따라 이번 코드 수정·테스트·iOS CI 설정을 커밋 대상으로 정리했다. 기존 Android 및 실기기 검증 작업은 로컬에 남긴다.

GitHub main은 검토 당시 `964e14cac61bb7ff5a3588bd7390bebd9acbf335`로 로컬보다 6개 커밋 뒤에 있었다. 최신 실패 실행 [32927516139](https://github.com/cres17/memoria/actions/runs/32927516139)은 `CF-12 neural generate save reload and apply are byte-stable` 테스트가 30초 제한을 넘겨 종료했다. 같은 커밋의 IPA 전용 빌드는 성공했다. 로컬에 이미 있던 Flutter arm64 설정과 CF-12의 2분 테스트 제한은 유지했다. 테스트 제한과 필터 생성 워커 제한은 서로 다른 값이다.

### 다른 클론의 main 리뷰와 대조

사용자가 전달한 후속 리뷰는 미커밋 변경이 없는 별도 main 클론을 대상으로 했다. 후속 리뷰 당시 이 작업 공간은 `test/color-v3-fallback-routing`, `d99346d0a163c98ab03e03018f09e8b534490497`와 미커밋 변경 상태다. GitHub API로 main이 위 `964e14c` 해시임을 다시 확인했다. 따라서 main에서 수정 사항이 보이지 않는다는 결과와 이 문서의 로컬 수정 결과는 서로 다른 코드를 대상으로 한다. GitHub main에 반영되었다는 주장은 하지 않는다.

CF-12에서 생성기에 전달하는 `Duration(seconds: 30)`은 **워커 제한**이다. 로컬 테스트 끝의 `Timeout(Duration(minutes: 2))`는 **테스트 전체 제한**이며, 제품 생성기의 기본 제한은 **45초**다. main에는 로컬의 명시적인 테스트 전체 2분 제한이 없다. 줄 번호나 워커 제한 하나만으로 테스트 전체 제한을 판단하면 안 된다.

## 수정 내용

### 릴리스 서명

- 존재하지 않는 `apple-actions/import-codesign@v1`을 공식 `import-codesign-certs` v7의 고정 커밋으로 교체했다.
- 인증서 입력을 `p12-file-base64`로 수정했다.
- `IOS_PROVISIONING_PROFILE`은 base64로 인코딩한 App Store 배포 프로파일을 받는다. 보조 도구는 임시 파일을 통해 CMS를 해독하고, UUID를 검증한 뒤 Xcode의 프로파일 디렉터리에 설치한다. 서명 원문은 출력하지 않는다.
- CI 체크아웃의 Runner Release 설정만 프로파일의 팀·UUID와 Apple Distribution 서명으로 구성한다. Debug 설정은 유지한다.
- 개발용·기기 제한용·다른 앱의 프로파일은 거부하고, 실제 앱 식별자에 맞는 수동 서명 exportOptions를 생성한다.
- CI에 서명 설정 회귀 테스트를 연결하고, 빌드 실패 때도 생성된 로그를 업로드한다.
- 후속 리뷰에서 지적한 자산 검증 누락을 반영했다. signed release, unsigned IPA, 일반 iOS CI 모두 `test/runtime_assets_test.dart`를 빌드 전에 실행한다. `rootBundle`로 앱에 포함되는 모델의 크기·SHA-256, 모든 기본 프리셋의 LUT 크기와 썸네일 JPEG 시그니처를 확인한다. 파일 개수만 맞추거나 Git LFS 포인터가 남은 상태를 통과시키지 않는다.
- 서명 잡의 checkout에 `persist-credentials: false`를 적용했다. 기존 수동 서명 exportOptions 대체 과정에서 `compileBitcode`도 이미 제거됐다.

공식 입력 명세: [Apple-Actions action.yml](https://github.com/Apple-Actions/import-codesign-certs/blob/5142e029c445c10ffc7149d172e540235a065466/action.yml).

### 모델 다운로드와 인물 분리

- HTTP 200, 실제 수신 길이, 모델 파일 크기·SHA-256을 확인한 후 임시 파일을 최종 경로로 교체한다.
- HTTP 오류, 손상·빈 파일, 요청 또는 스트림 정지, 전송 중 오류에서는 클라이언트와 임시 파일을 정리한다. 실패 후 재시도와 동시 요청 공유를 테스트했다.
- 기존 Selfie 설정은 정사각형 모델 주소와 잘못된 파일 크기를 사용했다. 가로형 v1 모델로 고정하고 크기 250,177바이트와 실제 SHA-256을 기록했다.
- MediaPipe의 `Convolution2DTransposeBias` 연산을 등록하고 입력 `[1,144,256,3]`, 출력 `[1,144,256,1]`을 확인한다.
- 모델이 이미 확률을 출력하므로 중복 sigmoid를 제거했다. 검은 배경의 확률이 약 0.5로 올라가는 문제를 실제 네이티브 추론으로 확인·수정했다.
- 후속 리뷰에서 발견한 `SegmentMask.resize`의 한 픽셀 축 나눗셈 오류를 수정했다. 폭·높이 1은 원본 축 중심을 샘플링하고, 0 이하의 출력 크기는 명시적으로 거부한다. 한 픽셀 출력·입력 확대와 잘못된 크기 회귀 테스트 3개가 통과했다.

모델 규격: [Google MediaPipe 모델 안내](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter#selfie_segmentation_model). 실제 모델은 임시 폴더에서 내려받아 검증했고 앱 자산이나 Git에 추가하지 않았다. 명시적으로 실행하는 검증 도구는 `tool/selfie_segmenter_smoke_test.dart`에 보존했다.

### iPad 공유

- 공유 버튼에 고정 키를 연결하고 공유 시점의 실제 화면 좌표를 읽어 `sharePositionOrigin`으로 전달한다.
- 렌더링이 끝난 뒤 좌표를 읽으므로 내보내기 도중 위치가 바뀌어도 최신 좌표를 전달한다.
- 회귀 테스트에서 네이티브 공유 채널의 좌표 네 값과 공유 파일의 유지·정리 예약을 확인했다.

요구 사항: [share_plus iPad 안내](https://pub.dev/packages/share_plus/versions/10.1.4#ipad). 실제 iPad 공유 창을 조작해 완주하는 테스트는 이번 작업에서 실행하지 않았다.

### 시뮬레이터 아키텍처

- 가로형 모델 실행 검증과 별도로 iOS 빌드 검증에서 Xcode 사전 준비 단계가 arm64·x86_64를 동시에 요청하는 문제를 발견했다.
- vendored LiteRT SwiftPM 시뮬레이터 프레임워크가 arm64만 지원하므로 Debug/Release의 시뮬레이터 설정과 Scheme 준비 단계를 arm64에 맞췄다. Intel 시뮬레이터 지원을 주장하지 않는다.
- 포함된 SwiftPM 라이브러리의 `-ObjC` 옵션을 Swift 컴파일러에 직접 넘기던 링크 오류도 발견했다. `-Xlinker`로 링커에 전달하도록 수정했다.
- `ios/Flutter/SimulatorCI.xcconfig`를 시뮬레이터 CI 단계에 적용해 SwiftPM 제품에도 arm64 설정을 전달한다.
- 이후 서명 없는 실제 기기용 릴리스 빌드에서도 iOS 13 타깃 거부를 재현했다. Runner와 Flutter 앱 프레임워크, vendored LiteRT의 최소 iOS 버전을 15.0으로 맞췄다. **iOS 13·14 지원은 제외**되며 README와 지원 범위 문서에 반영했다. iOS 15의 저메모리 기기 검증은 여전히 필요하다.

지원 범위 근거: [Apple Xcode 시스템 요구 사항](https://developer.apple.com/xcode/system-requirements).

## 검증 결과

- Flutter 정적 분석: **오류 및 경고 없음**.
- 후속 수정 후 Flutter 전체 단위·위젯 테스트: **535개 통과, 1개 조건부 건너뛰기**. 건너뛴 기존 테스트는 로컬 `color_transfer.tflite` 실험 파일을 요구한다. 최초 수정 단계의 529개에 후속 회귀 테스트 6개를 추가했다.
- 브랜치 커밋 대상으로 선택된 테스트만 재실행: **531개 통과, 1개 조건부 건너뛰기**. 기존 미커밋 실기기 메타데이터 테스트 4개는 이번 푸시에 포함하지 않아 로컬 전체 수치와 차이가 난다.
- 다운로드 경계 회귀 테스트: 9개 통과.
- 후속 마스크 경계·릴리스 자산 테스트: **6개 통과**.
- 서명 프로파일·Runner Release 설정 회귀 테스트: 4개 통과.
- 고정 인물 분리 모델의 SHA-256·실제 추론 검사: 통과. 기존 C 연산을 임시 dylib로 빌드해 macOS에서 검증했으며 모바일 성능이나 품질 지표로 해석하지 않는다.
- 실제 Runner 프로젝트 사본을 대상으로 서명 설정 변경과 exportOptions 생성 후 `plutil` 검증: 통과.
- 워크플로 YAML·실행 스크립트 및 Scheme XML·사전 준비 스크립트 문법: 통과.
- 수정 diff의 공백·충돌 검사: 통과.
- iOS 시뮬레이터 앱 빌드: **통과**. 최종 Runner·LiteRT 최소 버전 변경 후에도 저장된 arm64·타깃 15.0 설정으로 `Runner.app` 생성.
- iOS 실제 기기용 서명 없는 릴리스 빌드: **통과**. iOS 13 설정에서는 실패했고 최소 버전 15.0 수정 후 `flutter build ios --no-codesign --release --no-pub`로 `build/ios/iphoneos/Runner.app` 생성. 이 앱을 실기기에 설치하거나 실행하지는 않았다.
- iPad mini (A17 Pro), iOS 26.5 시뮬레이터 편집기 통합 테스트: **4개 통과**. 저장된 `SimulatorCI.xcconfig`를 적용해 빌드 및 실행했다. 편집 취소·적용, 뒤로 가기, 자르기 초기화, 초안 복원을 확인했다.

네이티브 빌드·추론·iPad 통합 결과는 최초 수정 단계에서 실행한 결과다. 후속 자산 게이트·마스크 한 픽셀 경계 수정 후에는 전체 Flutter 테스트·정적 분석·워크플로 문법 검사를 다시 실행했으며 네이티브 빌드·기기 통합은 반복하지 않았다.

## 남은 검증 경계

수정한 다운로드·인물 분리·공유·서명·iOS 빌드 설정을 다시 검토했고, 실행한 검사에서 추가 실패는 발견하지 않았다. 기존 Android 및 실기기 검증 변경을 이번 수정의 검증 결과로 포함하지 않았다.

분할 추론과 feather가 UI isolate에서 동기 실행되는 것은 코드로 확인했다. 프리뷰에서는 축소된 이미지를 사용하지만 내보내기에서는 큰 원본 마스크 준비가 필요하다. 프레임 지연의 실제 수치는 이번 작업에서 측정하지 않았다. 별도 isolate 이전은 interpreter 생성·재사용·취소·오류·결과 정렬을 함께 검증해야 하므로, 성능 개선 완료로 기록하지 않고 실측 및 후속 설계 과제로 남긴다.

설치된 Xcode는 27.0(`27A266a`)이고 기존 iOS 13 타깃을 거부했다. 앱의 최소 지원 버전을 15.0으로 올렸으며 전용 `SimulatorCI.xcconfig`에서는 타깃 15.0과 arm64를 사용한다. CI와 같은 로컬 빌드를 검증하려면 `XCODE_XCCONFIG_FILE="$PWD/ios/Flutter/SimulatorCI.xcconfig" flutter build ios --simulator --debug --no-pub`를 실행한다. 이 검증은 최소 사양 실기기나 서명 빌드 검증을 대신하지 않는다.

실제 인증서·App Store 프로파일을 사용한 서명 IPA, iPad 공유 완주, GitHub 원격 CI 재실행은 미검증이다. 워크플로는 main push·PR 또는 수동 실행을 받으므로 이번 작업 브랜치 push만으로 원격 CI가 자동 실행되지는 않는다. 원격 CI는 별도로 실행해 확인해야 한다. 이번 리뷰의 통과 결과는 수정 범위와 실행한 검증에 한정되며 전체 앱의 출시 승인을 의미하지 않는다.
