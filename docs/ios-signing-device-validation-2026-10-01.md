# 서명 IPA·실기기 공유·메모리 검증 — 2026-10-01

## 현재 판정

기존 원격 CI의 unsigned 빌드 성공과 아래의 서명·실기기 검증은 별도 결과다. 현재 **서명 IPA 생성, 실제 공유 완주, 저메모리 실기기 검증은 보류**다. 실행 가능한 검증 도구를 추가했지만 실기기 결과를 생성하지 못했다.

| 항목 | 직접 확인한 결과 | 다음 실행 조건 |
| --- | --- | --- |
| 로컬 개발용 인증서 | 유효한 Apple Development identity 1개. 팀은 프로젝트 설정과 일치하며 2027-07-14까지 유효 | Xcode의 해당 팀 Apple 계정과 앱 개발 프로파일 |
| 개발용 서명 IPA 시도 | `flutter build ipa --release --export-method development --no-pub` 실패. `No Accounts`, `No profiles for com.260715.memoria` | Xcode Settings → Accounts에서 해당 팀 계정을 등록하고 앱 프로파일 준비 |
| 배포용 서명 자료 | 로컬 배포 인증서·프로파일 없음. GitHub repository secrets·variables 목록도 비어 있음 | 배포 인증서·App Store 프로파일 및 릴리스 설정 |
| 현재 등록된 실제 기기 | iPhone 17, iOS 26.6.2. 네트워크 페어링, Developer Mode 활성화 | 화면 잠금 해제, 정상 개발자 디스크 연결 |
| 기기 준비 오류 | CoreDevice 12040의 하위 오류 10003: `The device is currently locked` | 사용자가 잠금 해제하고 화면을 유지 |
| 실제 iPad·2GB급 iPhone | 해당 기기 연결을 확인하지 못함 | iPad 공유 popover와 최소 지원 기기 메모리 검증용 실기기 |

GitHub signed release는 `IOS_CERT_P12`, `IOS_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE` secrets와 `PRIVACY_POLICY_URL`, `PRIVACY_CONTACT_EMAIL`, `ADVERTISING_RELEASE_MODE` variables를 요구한다. v1의 광고 설정은 `disabled`다. 비밀키·비밀번호·프로파일 원문을 문서나 Git에 저장하지 않는다. 개발용 IPA는 App Store 배포용 IPA와 다르다.

## 추가한 검증 도구

- `integration_test/ios_portrait_memory_device_test.dart`: 고정 Selfie 모델을 실제 LiteRT로 실행하고 12MP(4000×3000), 24MP(6000×4000) 마스크·feather와 JPEG 내보내기를 확인한다. 출력 해상도·시그니처·배경 확률·유한값을 검사하고 처리 시간 및 RSS를 기록한다. 사전 설정 RSS 증가량 상한은 500MiB다.
- `integration_test/support/process_memory_sampler.dart`: 별도 Dart isolate에서 10ms 간격으로 프로세스 RSS를 측정한다. UI isolate의 동기 추론·feather 중에도 샘플링을 계속한다.
- `integration_test/ios_share_completion_device_test.dart`: 실제 `EditorPage` 내보내기 → native share-plus 경로를 사용한다. 채널 관찰자는 실제 엔진에 메시지를 그대로 전달하며 네이티브 결과를 꾸며내지 않는다. 실제 파일 공유 완료 결과, source SHA-256, 파일 유지와 실제 공유 버튼 좌표를 기록한다. 취소 또는 unavailable 결과는 통과시키지 않는다.
- `test_driver/ios_device_validation_driver.dart`: 테스트가 실패해도 가능한 결과 JSON을 보존한다. 테스트의 최종 성공·실패와 서명·설치 오류는 함께 저장된 로그에서 확인한다.
- `tool/run_ios_device_validation.sh`: profile 실행과 결과·로그 저장을 묶는다. Flutter 3.44.6의 `flutter test`는 debug 빌드를 강제하므로 실제 profile 검증에는 `flutter drive --profile`을 사용한다.

이 도구들은 물리 iOS 기기·profile 모드·기기명 입력을 요구한다. 해당 조건 없이 시뮬레이터를 실행해 실기기 통과로 기록하지 않는다. 실제 기기 식별은 실행 전에 `flutter devices` 또는 `devicectl`로 확인해야 한다.

## 실행 절차

프로젝트 루트에서 실행한다. 각 실행은 앱을 빌드·서명·설치하므로 Xcode 서명 설정을 먼저 준비해야 한다. 개인 사진 대신 앱의 임시 디렉터리에 합성 입력을 만든다.

```bash
bash tool/run_ios_device_validation.sh memory PHYSICAL_DEVICE_ID iPhone-17
```

```bash
bash tool/run_ios_device_validation.sh share PHYSICAL_DEVICE_ID iPhone-17
```

공유 테스트에서는 실제 기기의 시스템 공유 창에서 **파일에 저장**을 완료한다. 결과의 `sourceSha256`과 수신한 파일의 SHA-256·해상도·시그니처를 별도로 비교한다. 메시지나 이메일 전송을 자동으로 수행하지 않는다. iPad와 저메모리 iPhone에서도 각각 기기 ID·기기명을 바꿔 실행한다.

출력은 Git에서 제외되는 `build/device-validation/memory.json`, `share.json` 및 각각의 로그다. JSON만 보고 통과를 판단하지 않는다. 명령 종료 코드와 테스트 로그를 함께 확인해야 한다.

## 검증 한계

- 메모리 도구는 해상도별 합성 검은 배경 1회다. 전경 인물 품질, 반복 실행 leak, latency p95를 증명하지 않는다.
- RSS는 integration runner를 포함한 프로세스 전체 수치다. iOS physical footprint나 jetsam 한계와 같은 지표가 아니다.
- OS memory warning, 외부 메모리 압박, jetsam 로그와 thermal 상태는 이 도구에서 수집하지 않는다. 저메모리 출시 검증에는 별도 Instruments/기기 로그와 반복 실행이 필요하다.
- 현대 iPhone에서 성공해도 iOS 15를 지원하는 2GB급 기기 검증을 대체하지 않는다. iPhone 공유 성공도 iPad popover 검증을 대체하지 않는다.
- 네이티브 공유 완료 응답은 수신 파일 원본 일치의 증거와 별도다. 수신 측 파일 검증까지 끝나야 공유 완주로 기록한다.

## 이번 환경에서 검증한 범위

- 메모리 샘플러 회귀 테스트 **2개 통과**: 호출 isolate가 동기로 막혀도 샘플이 수집됨, 중복 종료가 같은 결과를 반환함.
- 추가 검증 도구를 포함한 Flutter 정적 분석 **문제 0건**.
- 메모리 도구의 iPhone용 **서명 없는 profile 앱 컴파일 통과**. 실제 기기에 설치·실행한 결과가 아니다.
- 공유 도구의 iPhone용 **서명 없는 profile 앱 컴파일도 통과**. 실제 공유 창을 실행하거나 완료한 결과가 아니다.
- 기존 Android·실기기 증거 관련 미커밋 작업은 보존했고 이번 검증의 통과 근거로 포함하지 않았다.
