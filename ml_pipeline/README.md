# ml_pipeline — Neural Color Transfer 학습 파이프라인

스타일 이미지 → 65³ LUT 자동 생성 모델 (MobileNetV3 + Progressive LUT Decoder).
목표 정확도: ΔE < 2.0 (98%+, Lightroom/Capture One 수준).

## 환경 설정

```bash
pip install -r requirements.txt
```

GPU(CUDA) 권장. GTX 1650 Max-Q(4GB) 기준 학습 시간 ~8~12시간.

---

## 실행 순서

### Stage 1 — 데이터 준비

```bash
# GitHub 등에서 실제 .cube LUT 파일 수집 (인터넷 필요)
python 1_download_luts.py

# 수학적으로 2000개 LUT 즉시 생성 (인터넷 불필요, ~5분)
python 4_generate_synthetic_luts.py

# 중립 이미지 다운로드 (인터넷 필요, Unsplash/COCO)
python 5_download_neutral_images.py
```

### Stage 2 — 학습

```bash
# 크롤링 CUBE + 기존 앱 BIN 30개 + Canon CLog2/CLog3 LUT를 각각 같은 수로 샘플링해 학습
# 기존 dataset은 섞지 않고 삭제한다. data/luts에 크롤링 CUBE가 있어야 시작된다.
python 3_train.py --prepare-dataset --clean-dataset
```

학습기는 `manifest.jsonl`로 각 쌍의 LUT 출처를 검증한다. 공개 CUBE, 앱 BIN,
Canon CLog2, Canon CLog3 중 하나라도 빠지면 기본적으로 중단하며, 검증 세트는 LUT
단위로 분리해 같은 LUT가 학습과 검증에 동시에 들어가지 않게 한다. Canon LUT는
생성 시 `sRGB → CLog → Canon LUT`로 합성해 앱과 동일한 sRGB 입력 도메인으로 저장한다.
기본 3,000쌍은 크롤링·앱·Canon에 각각 1,000쌍씩 배정한다.

데이터셋만 다시 만들려면 다음을 실행한다.

```bash
python 2_generate_dataset.py --clean --require-all-sources
```

### Stage 3 — 평가 및 배포

```bash
# 정확도 측정 (ΔE, capture rate)
python 6_evaluate.py

# TFLite / ONNX 내보내기
python 7_export_model.py
# → exports/color_transfer.tflite  (~18MB, Android)
# → exports/color_transfer.onnx    (CoreML 변환용)
```

TFLite 변환은 TensorFlow/onnx-tf 호환성 때문에 Python 3.11 환경에서 실행한다.

```bash
python3.11 -m venv ../.venv-ml-tflite
../.venv-ml-tflite/bin/python -m pip install -r requirements-tflite.txt
../.venv-ml-tflite/bin/python 10_export_basis.py
```

### P4 — Basis-residual LUT 실험

P4는 전체 3D LUT 대신 평균 LUT와 8개 residual basis의 가중치를 예측한다.
모델 출력은 `[-2, 2]`의 정규화 coefficient이며, basis에 scale을 적용해
앱의 안전 계약을 유지하면서 원래 LUT 공간을 재구성한다.

```bash
# Python 3.14 학습/benchmark 환경
../.venv-ml/bin/python 8_train_basis.py --fit-basis
../.venv-ml/bin/python 8_train_basis.py --train
../.venv-ml/bin/python 9_benchmark_basis.py

# Python 3.11 TFLite export 환경
../.venv-ml-tflite/bin/python 10_export_basis.py
```

현재 로컬 smoke dataset(앱 LUT 30개 × 샘플 이미지, 300쌍)에서 40 epoch 학습한 결과:

| 항목 | 결과 |
|------|------|
| 최저 validation normalized-coefficient MSE | 0.372717 |
| Normalized coefficient RMSE | 0.4081 |
| 17³ small-LUT RMSE | 0.07585 |
| Python CPU latency p50 / p95 | 31.1ms / 33.0ms |
| TFLite 출력 | `[1, 8]`, coefficient 절대값 ≤ 2 |

생성물은 `exports/basis_weights.tflite`, `exports/basis_weights.onnx`,
`exports/basis_lut.bin`, `exports/basis_lut_metadata.json`에 저장된다.
`basis_lut.bin`의 basis는 `normalized_scaled_bases` coefficient 공간용이므로,
모델 출력에 별도 scale을 곱하지 않고 그대로 LUT 재구성에 사용한다.

이 결과는 제품 품질 판정이 아닌 실행 검증이다. 제품 적용 전 다음 작업이 필요하다.

1. Dart에서 TFLite predictor와 `MBLT` basis binary loader를 구현하고, 공통 LUT safety gate에 연결한다.
2. LUT 단위로 분리된 holdout set과 실제 사진 데이터에서 시각 품질·LUT 오차를 평가한다.
3. iOS/Android 실기기에서 TFLite latency, 메모리, dynamic-shape 동작을 측정한다.

### V2 — Balanced Basis-residual Training

기존 `8_train_basis.py`는 보존한다. V2는 균형 manifest를 요구하고, 전체 LUT를
무작위로 나누지 않는다. PCA basis는 train LUT에만 적합하며, 크롤링·앱·Canon 그룹을
각 학습 epoch에서 균등하게 샘플링한다.

```bash
../.venv-ml/bin/python 11_train_basis_v2.py --fit-basis --train
```

V2 생성물은 `checkpoints/basis_v2_lut.npz`와 `checkpoints/basis_v2_color.pt`다.
기존 `10_export_basis.py`는 V1 artifact만 내보내므로, V2 결과를 제품에 연결하지 않는다.

### V3 — Auto-tuned Group Weights

V3는 V2 basis를 그대로 사용하지만, crawled/app/canon 손실 가중치와
reconstruction weight를 자동 탐색한 뒤 가장 좋은 조합으로 본학습한다.
V3의 요구사항과 판정 기준은 `V3_REQUIREMENTS.md`에 정리되어 있으며,
결과 JSON에는 `score_components`와 holdout LUT 요약이 함께 저장된다.

```bash
../.venv-ml/bin/python 12_train_basis_v3.py --sweep
../.venv-ml/bin/python 12_train_basis_v3.py --train
# 또는
../.venv-ml/bin/python 12_train_basis_v3.py --sweep --train
```

탐색 결과는 `checkpoints/basis_v3_sweep.json`, 선택된 파라미터는
`checkpoints/basis_v3_params.json`, 최종 체크포인트는
`checkpoints/basis_v3_color.pt`에 저장된다.

---

### Personal Filter Fit — Before/After Pair Personalization

V2/V3는 기존 LUT 분포 안에서 잘 맞는 필터를 찾는 방식이지만, 이 스크립트는
개인이 직접 보정한 before/after 페어에서 바로 새 필터를 적합한다. 먼저 전역
affine color transform을 맞추고, 그 잔차를 coarse residual LUT로 보강한 뒤
안전 게이트를 통과하는 65³ LUT로 내보낸다.

```bash
# 반복 가능한 before/after 페어
../.venv-ml/bin/python 13_fit_personal_filter.py \
  --pair before.jpg after.jpg \
  --output-dir exports/personalized_filters/my_filter

# JSONL manifest
../.venv-ml/bin/python 13_fit_personal_filter.py \
  --manifest pairs.jsonl \
  --output-dir exports/personalized_filters/my_filter

# 자체 smoke demo
../.venv-ml/bin/python 13_fit_personal_filter.py --demo
```

출력은 `lut.bin`, `thumbnail.jpg`, `recipe.json`, `fit_report.json`이다.
`recipe.json`은 기존 `FilterRecipe` 계약과 같은 핵심 필드를 가진다.

---

## 디렉토리 구조

```
ml_pipeline/
├── data/
│   ├── luts/             # 수집된 .cube 파일
│   ├── synthetic_luts/   # 수학 생성 .bin 파일 (65³ float16)
│   ├── neutral_images/   # 학습용 중립 이미지
│   └── dataset/          # 생성된 학습 쌍
│       ├── neutral/
│       ├── graded/
│       └── luts/
├── checkpoints/          # 학습 체크포인트
└── exports/              # TFLite / ONNX 출력
```

---

## 정확도 기준

| 지표 | 목표 |
|------|------|
| 평균 ΔE (CIE76) | < 2.0 |
| ΔE < 5.0 픽셀 비율 | ≥ 90% |
| ΔE < 2.0 픽셀 비율 | ≥ 98% |

---

## 환경변수 (선택)

```bash
export GITHUB_TOKEN=ghp_...        # GitHub API (1_download_luts.py)
export UNSPLASH_ACCESS_KEY=...     # Unsplash (5_download_neutral_images.py)
export PEXELS_API_KEY=...          # Pexels   (5_download_neutral_images.py)
```
