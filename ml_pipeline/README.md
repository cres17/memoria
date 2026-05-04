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
# 중립 이미지 + LUT → (neutral, graded, lut) 학습 쌍 생성
python 2_generate_dataset.py

# 모델 학습 (GPU 필요)
python 3_train.py
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
