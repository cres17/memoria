# Memoria — 퍼블리시 전 체크리스트

> 마지막 감사: 2026-05-03  
> 전체 상태: ❌ 출시 불가 (크리티컬 이슈 해결 필요)

---

## 🔴 CRITICAL — 스토어 제출 차단 (반드시 해결)

- [ ] **AdMob 테스트 ID → 실제 ID 교체** ← TODO 마킹 완료, 실제 ID는 AdMob 콘솔에서 직접 교체 필요
  - `lib/monetization/banner_ad_widget.dart` — 배너 유닛 ID
  - `lib/monetization/fullscreen_ad_service.dart` — 전면/리워드 유닛 ID
  - `android/app/src/main/AndroidManifest.xml` — App ID
  - `ios/Runner/Info.plist` — App ID
  - 현재 전부 Google 공식 테스트 ID(`ca-app-pub-3940256099942544~...`) → 정책 위반으로 즉시 거절

- [ ] **Android 릴리즈 서명 키 설정**
  - `android/app/build.gradle` line 36: `signingConfig signingConfigs.debug` → production keystore로 교체
  - 프로덕션 keystore 생성 후 `signingConfigs.release` 블록 추가

- [ ] **ML 모델 파일 번들 확인** ← Phase 2 완료 후 처리
  - `assets/models/color_transfer.tflite` 실제 존재 여부 확인
  - `assets/models/color_transfer.mlmodel` 실제 존재 여부 확인
  - 모델 없으면 LUT 생성 기능 전체가 작동 안 함 (Phase 2 미완)

- [x] **create_filter mock 데이터 제거**
  - `lib/features/create_filter/create_filter_page.dart` — style_analyzer 실제 결과로 교체 완료

---

## 🟠 HIGH — 출시 전 필수

- [x] **Dev Panel 릴리즈 빌드에서 비활성화**
  - `kDebugMode` 게이트 + 라우터 조건부 등록 완료

- [x] **Settings 미구현 항목 처리**
  - 캐시 지우기: 실제 구현 완료
  - 오픈소스 라이선스: `showLicensePage` 연결 완료
  - 필터 저장 위치 / 내보내기 품질: 정보 표시 전용으로 변경 (chevron 제거)

- [x] **app.dart 다크모드 버그 수정**
  - `lib/app.dart` — `darkTheme: AppTheme.dark` 수정 완료

- [x] **LUT 생성 실패 시 사용자 피드백**
  - `lib/features/create_filter/create_filter_page.dart` — 에러 메시지 표시 완료

- [x] **export 결과 검증**
  - `lib/features/editor/editor_page.dart` — 파일 존재 확인 + catch 블록 추가 완료

---

## 🟡 MEDIUM — 품질 개선

- [x] **비동기 함수 예외처리 보강**
  - `filters_page._load()`, `home_page._loadFlags()` try/catch 추가 완료

- [ ] **Android 릴리즈 서명 keystore 생성 및 설정**
  - `android/app/build.gradle` — TODO 주석과 keytool 명령어 추가 완료, 실제 keystore 생성 필요

- [ ] **Android ProGuard / 코드 축소 활성화 검토**
  - `android/app/build.gradle` — `shrinkResources false`, `minifyEnabled false`
  - 활성화 시 APK 크기 감소, `proguard-rules.pro`에 TFLite/AdMob 규칙 추가 필요

- [ ] **LUT 차원 불일치 확인**
  - `lib/engine/lut_engine.dart` — `_dim = 65` 와 33 지원 코드 혼재
  - 65³ 고정인지 확인하고 불필요한 33 분기 제거

- [ ] **패키지명 Google Play 등록명과 일치 확인**
  - `android/app/build.gradle` — `applicationId "com.memoria.photofilter"`
  - Play Console에 등록된 패키지명과 반드시 동일해야 함

- [ ] **iOS 배포 프로비저닝 프로파일 설정**
  - Xcode에서 Production 인증서 + 프로파일 선택
  - App Store Connect에 앱 등록

---

## 🔵 LOW — 출시 후 개선 가능

- [ ] **버전/빌드번호 관리 체계화**
  - `pubspec.yaml` — 릴리즈마다 `version: 1.0.0+N` 빌드번호 증가

- [ ] **한국어 전용 UI 처리 결정**
  - 현재 전체 UI가 하드코딩 한국어
  - 한국 전용 앱이면 현재 유지 가능
  - 글로벌 출시 계획 시 `flutter_localizations` + `.arb` 파일 체계 도입

- [ ] **내보내기 진행률 표시 정확도**
  - `lib/features/editor/editor_page.dart` — 항상 1.0으로 표시됨, 실제 진행률 반영

- [ ] **`_flags` null 상태 UI 처리**
  - `lib/features/home/home_page.dart` — 비동기 로드 전 null일 때 기본값 또는 로딩 상태 표시

---

## ✅ 통과 항목 (확인 완료)

- [x] `print()` / `debugPrint()` 없음
- [x] 메모리 누수 없음 (Controller dispose 정상)
- [x] Android 권한 선언 적절 (카메라, 미디어, 인터넷)
- [x] iOS Privacy 문자열 선언 완료
- [x] Asset 파일 선언 구조 정상
- [x] 광고 실패 bypass 로직 구현됨
- [x] 풀스크린 광고 기본 OFF

---

## 출시 준비 단계 요약

| 단계 | 내용 | 예상 소요 |
|------|------|----------|
| Phase 2 완료 | ML 모델 학습 + TFLite/CoreML 번들 | 별도 일정 |
| Critical 해결 | AdMob ID 교체 + 서명 설정 + mock 제거 | 1~2일 |
| High 해결 | Dev panel 보안 + settings 구현 + 버그픽스 | 2~3일 |
| QA | 실기기 테스트 (Android + iOS) | 1~2일 |
| **스토어 제출** | | **총 Phase 2 이후 ~1주** |
