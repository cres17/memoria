# Memoria 퍼블리시 체크리스트

기준일: 2026-08-20
현재 판정: **내부 베타 가능 / App Store·Play Store 일반 출시 보류**

## 자동 검증 완료

- [x] Flutter 3.44.6과 lockfile 기반 `pub get --enforce-lockfile` 재현.
- [x] CocoaPods lockfile 기반 `pod install --deployment` 재현.
- [x] analyzer error/warning 0. info lint는 legacy 코드에 남아 있음.
- [x] 전체 Flutter unit/widget test 통과.
- [x] iPhone 17 Pro 시뮬레이터 EditorPage 화이트박스 3건 통과.
- [x] 시뮬레이터 debug 성능 측정: frame p95 약 9.7ms, preview p95 약 33.7ms, export 첫 진행 약 188.6ms, 취소 약 280.1ms.
- [x] Fuji 18종·Leica 5종 LUT/썸네일/브랜드가 실제 catalog와 editor에 연결됨.
- [x] local/brush/blur/artistic state를 history schema v2, draft, preview, export에 포함.
- [x] 커스텀 필터 생성 진입점과 화면에 `BETA` 표시.
- [x] 사진 권한 거부, 이미지 decode 실패, export 취소/임시 파일 cleanup 경로 구현.
- [x] targetSdk 35, compileSdk 36 설정.

위 시뮬레이터 성능 수치는 공식 출시 성능 승인 자료가 아니다.

## Release Blocker

### 1. 소스·CI 재현

- [ ] 제품 코드, `pubspec.lock`, `ios/Podfile.lock`, 테스트, 문서, 승인된 runtime asset만 allowlist commit.
- [ ] clean checkout에서 analyze → full test → iOS build를 GitHub Actions로 통과.
- [ ] 36MB Direct MVP 모델의 Git/LFS 정책과 라이선스 기록 확정.
- [ ] CI runtime asset 검사에서 모델, 23개 브랜드 LUT, 24개 썸네일 확인.

### 2. iPhone 실기기 승인

- [ ] iPhone을 잠금 해제·USB 연결하거나 Memoria 로컬 네트워크 권한을 허용.
- [ ] profile `editor_performance_test` JSON과 `perf_gate` 통과.
- [ ] 12MP/24MP JPEG·PNG·TIFF·WebP complete export 시간과 peak RSS 기록.
- [ ] Photos 저장 완료와 실제 share sheet 수신 앱에서 파일 signature·해상도 확인.
- [ ] limited PhotoKit, iCloud 원본 다운로드, 권한 거부/재허용 확인.

### 3. Android 출시

- [ ] release keystore를 저장소 밖에서 생성하고 CI secret으로 연결.
- [ ] `android/app/build.gradle`의 debug signing fallback 제거.
- [ ] Android SDK runner에서 debug/release APK 또는 AAB 빌드.
- [ ] Android 13+ 사진 권한, 저장, 공유, TFLite arm64-v8a를 실기기 확인.

### 4. 개인정보·광고 정책

- [ ] `docs/privacy-policy.md`의 개발자명과 privacy contact email 입력.
- [ ] 개인정보처리방침을 HTTPS URL에 게시하고 설정 화면·스토어 제출 정보에 연결.
- [ ] 광고를 출시에서 완전히 끌지, 실제 AdMob ID로 켤지 결정.
- [ ] 광고를 켜면 Android/iOS App ID와 unit ID 교체, 동의·스토어 데이터 고지 검증.
- [ ] 광고를 끄면 모든 광고 flag OFF 유지 및 광고 SDK 포함 필요성 재검토.

### 5. 기능 품질 계약

- [x] 얼굴 피부 전용이 아닌 보정을 `인물 영역`으로 정확히 표시하고 모델 상태/재시도 안내.
- [x] synthetic radial blur를 `원형 초점 흐림`으로 표시.
- [x] linear blur를 `틸트 시프트`로 표시.
- [ ] 커스텀 필터 same-style, unseen hue, skin fixture와 blind preference 승인.
- [ ] profile iOS/Android cold/warm latency와 peak RSS 승인 전 BETA 유지.
- [ ] full export completion 성능 보고서와 `perf_gate --scope full` 측정 계약 통일.

## P1 안정화

- [ ] `EditorPage` 상태·renderer를 canonical `EditorRecipe` 경계로 분리.
- [x] production에서 import되지 않던 Crop/Rotate/Perspective/HDR/Brush standalone panel과 해당 허위 신뢰 테스트 제거.
- [ ] `EditorPage` 내부의 legacy `_ToolsPanel`/`_buildLocalPanel` 상태와 미사용 depth estimator·multiclass segmenter를 연결하거나 제거.
- [x] Flutter/platform global error boundary와 기기 내 최대 500줄 영구 diagnostic log 도입.
- [ ] 저장·모델·asset·권한 실패를 typed failure state로 통일하고 silent fallback을 사용자 메시지/진단 이벤트로 분류.
- [ ] export metadata 정책을 명시하고 보존 또는 제거를 일관되게 구현.
- [ ] accessibility label, Dynamic Type, contrast, iPad/작은 화면 검증.
- [ ] hardcoded 한국어/영어를 ARB localization으로 정리.

diagnostic log 변경을 포함한 현재 전체 Flutter suite는 460개가 통과했고, 로컬 fixture가 필요한 기존 neural predictor 테스트 1건은 조건부 skip됐다.

## 재검증 명령

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test --coverage --reporter compact
flutter test integration_test/editor_whitebox_device_test.dart -d <ios-simulator-id>
flutter drive --profile \
  --driver test_driver/editor_performance_driver.dart \
  --target integration_test/editor_performance_test.dart \
  -d <physical-ios-device-id> --publish-port
dart run tool/perf_gate.dart --report <profile-report.json> --scope preview
dart run tool/perf_gate.dart --report <profile-report.json> --scope export-cancel
git diff --check
```

`profile`/`release` 성능 빌드는 iOS 시뮬레이터에서 지원되지 않으므로 실기기가 필요하다.
