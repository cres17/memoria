# Memoria 필터 생성 실험 인벤토리

기준일: 2026-08-31

근거: `ml_pipeline/TRAINING_PROGRESS.md`, 로컬 checkpoint·report, 앱 번들 모델 SHA-256

## 결론

현재 채택 후보는 **color-v3 smoothness 0.01, seed 20260830**에서 출발한 G5다.

- PyTorch checkpoint: `conditional_lut_color-v3-smooth010-seed-20260830.pt`
- checkpoint SHA-256: `3674a5a79bc68235bf80c99f8592933d3f83f92f84e016fc189a84bf8385cf47`
- 앱 FP16 TFLite SHA-256: `a1b8ecf00632ba359b2d4dec603de6e35fc031aed9af978b14658422e02241a6`
- 제품 정책: 단일 reference coverage `<0.03`은 생성 차단
- 판정: iOS 실기기 생성·차단·저장 통과, Android 실기기는 미검증

이 문서의 `성공`은 해당 실험의 지엽적 목표를 달성했다는 뜻이다. 제품 품질을 통과했다는
뜻으로 확장해 해석하지 않는다.

## 1. 초기 모델과 데이터 기반

| ID | 시도 | 결과 | 현재 처리 |
| --- | --- | --- | --- |
| `LEGACY-DIRECT-001` | 초기 direct LUT 학습 | 실패, Val ΔE 약 14.12 | 폐기 |
| `LEGACY-PCA-V2-001` | PCA basis V2 | 제한적 baseline | 비교 기록만 유지 |
| `LEGACY-PCA-V3-001` | PCA basis V3 | 실패/불확정 | 폐기 |
| `DATA-AUDIT-001` | conditional dataset 무결성 감사 | 성공 | 스크립트 유지 |
| `DATA-SPLIT-001` | 초기 split | family leakage로 실패 | 폐기 |
| `SPLIT-CONTRACT-001` | family-aware split 계약 | 부분 완료 | color-v3 split으로 대체 |
| `HUE-MASK-001` | 17³ hue coverage mask | 성공 | color-v3 mask만 보존 |
| `EVAL-CORE-001` | LUT 평가 코어 | 부분 완료 | 코드 유지 |
| `BASELINE-DUAL-001` | identity·interpolation baseline | 성공 | 평가 기준으로 유지 |
| `LUT-OOG-AUDIT-001` | out-of-gamut 안정성 | 성공 | 감사 기록 유지 |
| `MVP-SKELETON-001` | 1-batch end-to-end smoke | 기계적 성공 | 코드 유지 |
| `STYLE-CONSISTENCY-SMOKE-001~004` | 스타일 일관성 초기 검증 | 실패 | 산출물 폐기 |
| `STYLE-CONSISTENCY-SMOKE-005~006` | smoke 보정 | 005 실패, 006 성공 | 기록만 유지 |
| `RETRIEVAL-BASELINE-001` | 유사 LUT retrieval | 성공 | 비교 기준으로 유지 |

## 2. Direct MVP 학습·파라미터 탐색

| ID | 시도 | 결과 | 현재 처리 |
| --- | --- | --- | --- |
| `MVP-TRAIN-001` | 초기 17³ conditional LUT | pipeline 성공, 성능 실패 | checkpoint 폐기 |
| `MVP-BOTTLENECK-ANALYSIS-001` | output collapse 진단 | 성공 | report 요약만 유지 |
| `MVP-INSTRUMENTED-CONTROL-001` | 계측 가능 control | 성능 실패 재확인 | checkpoint 폐기 |
| `MVP-BOUNDED-RESIDUAL-001` | bounded residual | 실패 | checkpoint 폐기 |
| `MVP-DYNAMICS-COMPARISON-001` | control/ablation dynamics | 진단 성공 | report 요약만 유지 |
| `LUT-FAMILY-HOLDOUT-001` | LUT family holdout | 성공 | color-v3 split으로 대체 |
| `COMPARISON-REPORT-001~005` | baseline/MVP 연속 비교 | 보고서 생성 성공 | 요약 기록만 유지 |
| `MVP-TRAJECTORY-CONTROL-001` | trajectory control | 측정 성공, 품질 미달 | checkpoint 폐기 |
| `MVP-DECODER-CAPACITY-001` | decoder capacity 확대 | 개선, baseline 미달 | checkpoint 폐기 |
| `MVP-ENCODER-LR-001` | encoder LR 조정 | 개선, baseline 미달 | checkpoint 폐기 |
| `MVP-COSINE-SCHEDULE-001` | cosine schedule | 실패 | checkpoint 폐기 |
| `MVP-FIXED-LR-4EPOCH-001` | fixed LR 4 epoch | 개선, baseline 미달 | checkpoint 폐기 |
| `PROTOCOL-AUDIT-001` | sample/LUT macro 평가 계약 감사 | 기존 해석 오류 확정 | 교정 계약 유지 |
| `MVP-PROTOCOL-CORRECTED-CONTROL-001` | 교정 protocol control | 완료 | checkpoint 폐기 |
| `MVP-PROTOCOL-STYLE-WEIGHT-010-001` | style loss 0.10 | 실패 | checkpoint 폐기 |
| `MVP-PROTOCOL-DECODER-CAPACITY-2048-001` | decoder 2048 | 실패 | 139MB checkpoint 폐기 |
| `MVP-PROTOCOL-LONG-TRAJECTORY-8EPOCH-001` | 8 epoch | 당시 best | G5로 대체, checkpoint 폐기 |
| `MVP-PROTOCOL-IMAGE-WEIGHT-010-001` | image weight 0.10 | 당시 best | G5로 대체, checkpoint 폐기 |
| `MVP-PROTOCOL-IMAGE-WEIGHT-000-001` | image weight 0 | 당시 best | G5로 대체, checkpoint 폐기 |
| `MVP-PROTOCOL-SMOOTHNESS-WEIGHT-020-001` | smoothness 0.02 | 당시 best | checkpoint 폐기 |
| `MVP-PROTOCOL-SMOOTHNESS-WEIGHT-040-001` | smoothness 0.04 | single-seed best | replication 후 폐기 |
| `MVP-SMOOTHNESS-MULTISEED-REPLICATION-001` | 0.01/0.04 multi-seed | practical tie, 0.01 선택 | color-v3 0.01로 승계 |

## 3. 구조화 decoder·평가 계약 탐색

| ID | 시도 | 결과 | 현재 처리 |
| --- | --- | --- | --- |
| `MVP-FAMILY-HOLDOUT-SMOOTH-010-001` | family holdout smooth 0.01 | 유효한 비교 완료 | G5로 대체 |
| `V2-FAMILY-HOLDOUT-001` | PCA V2 family baseline | 비교 완료 | checkpoint 폐기 |
| `TONE-CURVE-TARGET-AUDIT-001` | luminance tone target | 채택 가능성 확인 | 감사 코드 유지 |
| `MVP-FAMILY-TONE-CURVE-001` | Tone Curve-only | 품질 실패 | checkpoint 폐기 |
| `HUE-ANCHOR-RESIDUAL-TARGET-AUDIT-001` | hue residual anchor | 6-anchor 최소안 확인 | 감사 코드 유지 |
| `MVP-FAMILY-TONE-HUE-ANCHOR-006-001` | unsupervised 6-anchor | 실패 | checkpoint 폐기 |
| `MVP-FAMILY-TONE-HUE-ANCHOR-006-SUP-001` | supervised 6-anchor | 부분 개선, 최종 거부 | checkpoint 폐기 |
| `PROTOCOL-FIX-001` | family macro·paired bootstrap 교정 | 완료 | 현재 평가 계약으로 유지 |
| `COMPARISON-PROTOCOL-001` | pre-fix 참조 비교 | 성공 | 요약 기록만 유지 |

## 4. 축·색공간 계약 교정과 color-v3

| ID | 시도 | 결과 | 현재 처리 |
| --- | --- | --- | --- |
| `AXIS-V2-DATASET-001` | R-fastest 축 교정 dataset | G1/G2/G3 통과, G4 실패 | dataset/checkpoint 폐기 |
| `AXIS-V2-MULTISEED-001` | axis-v2 3 seed | G3 통과, G4 실패 | checkpoint 폐기 |
| `AXIS-V2-FAILURE-DIAGNOSIS-001` | validation-only 원인 분석 | Canon 계약 문제 확정 | 요약 유지 |
| `CANON-COLOR-CONTRACT-AUDIT-001` | Canon Log/Cinema Gamut 교정 | 원인 확정·교정 | 코드 유지 |
| `COLOR-V3-DATASET-001` | 교정 색공간 3,000쌍 | G1 통과 | **로컬 보존** |
| `COLOR-V3-PILOT-001` | smooth 0.01 대 style 0.10 | Canon 개선, G4 전체 실패 | smooth 0.01만 승계 |
| `COLOR-V3-CANDIDATE-SELECTION-002` | 10분 제한 후보 2개 | 후보 B 선발 | A checkpoint 폐기 |
| `COLOR-V3-FALLBACK-READINESS-003` | coverage 0.03 routing | 독립 calibration 부재로 보류 | 후속 검증으로 승계 |
| `EXTERNAL-CALIBRATION-HIGH-COVERAGE-004` | 독립 high-coverage 10 LUT | high branch 통과 | **로컬 보존** |
| `EXTERNAL-MONOCHROME-CALIBRATION-005` | 독립 low-coverage 31 LUT | low branch·결합 gate 통과 | **로컬 보존** |
| `COLOR-V3-FALLBACK-ONE-TIME-TEST-006` | 고정 test 12 LUT | G4 통과, 재튜닝 금지 | 고정 report만 보존 |
| `COLOR-V3-FALLBACK-G5-PARITY-007` | PyTorch→ONNX→FP16 TFLite | G5 통과 | **현재 채택** |

## 5. 제품 연결·실기기

| ID | 시도 | 결과 | 현재 처리 |
| --- | --- | --- | --- |
| `COLOR-V3-FALLBACK-G6-SIM-PROXY-008` | iOS Simulator 성능 proxy | 선행 통과 | 실기기 결과로 대체 |
| `COLOR-V3-BUNDLE-SWAP-BRANCH-009` | G5 앱 bundle 교체 | 기능 통과, fallback 부재로 일시 보류 | coverage 차단과 함께 채택 |
| `COLOR-V3-RUNTIME-FALLBACK-REJECTION-010` | algorithmic/identity fallback | 모두 품질 실패 | 코드 제거 |
| `G6 iPhone physical` | cold/warm, 4K, 권한, 메모리 | iOS 주요 항목 통과 | Android 실기기 남음 |
| `G5 create-filter black box` | low coverage 차단→정상 생성→저장 | iOS 실기기 통과 | 현재 회귀 gate |

## 6. 로컬 G5 재현 세트

Git에 올리지 않고 로컬에만 보존한다.

| 경로 | 용도 |
| --- | --- |
| `ml_pipeline/checkpoints/conditional_lut_color-v3-smooth010-seed-20260830.pt` | G5 원본 checkpoint |
| `ml_pipeline/data/dataset_color_v3_001/` | 학습·평가 입력 |
| `ml_pipeline/data/dataset_external_calibration_001/` | high-coverage 독립 calibration |
| `ml_pipeline/data/dataset_external_monochrome_calibration_001/` | low-coverage 독립 calibration |
| `LUT/` | color-v3 manifest가 참조하는 원본 LUT·Canon look source |
| `.venv-ml-tflite/` | 고정 Python 3.11 TFLite 변환·parity 환경 |
| `ml_pipeline/reports/splits/color_v3_001/` | 고정 family split |
| `ml_pipeline/reports/hue_masks/color_v3_001/` | 고정 coverage mask |
| `ml_pipeline/reports/validation/color_v3*` | G4·routing 평가 결과 |
| `ml_pipeline/reports/validation/external*` | 독립 calibration 결과 |
| `ml_pipeline/reports/deployment/color_v3_fallback_003_*` | G5 parity 요약·fixture·FP16 산출물 |

앱 실행에 필요한 최종 FP16 TFLite는 `assets/models/` 아래에 Git으로 배포된다. 위 로컬 세트는
재학습·평가·변환 재현을 위한 것이며 앱 runtime에서 읽지 않는다.

## 7. 정리 정책

- 삭제: legacy, axis-v2, 실패 ablation, 이전 best checkpoint와 training state
- 삭제: 이전 dataset, 중간 ONNX/SavedModel/export, 구형 report와 cache
- 보존: G5 checkpoint, color-v3·독립 calibration data, 고정 split/mask, G4/G5 핵심 report
- Git 보존: 재현 스크립트, 실험 요약, 소형 실기기 증거, 최종 앱 TFLite
- Git 제외: dataset, PyTorch checkpoint, training state, ONNX, SavedModel, 대용량 중간 report
