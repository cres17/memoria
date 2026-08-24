# V3 Development Checklist

기준: `V3_REQUIREMENTS.md`를 먼저 읽고, 그 계약을 지키면서 `basis_v3`를 계속 개발할 때 매번 다시 찾지 말고 이 파일만 보면 되도록 만든 작업 체크리스트.

---

## 1. 현재 상태 한 줄 요약

- V3는 `11_train_basis_v2.py`의 basis를 유지한 채, group weight와 reconstruction weight를 자동 탐색하고 score contract를 고도화하는 실험이다.
- 현재까지 확인된 사실:
  - `basis_v3_sweep.json` 생성됨
  - `basis_v3_params.json` 생성됨
  - 이전 full sweep은 V2보다 아주 작은 폭만 앞서거나 비슷한 수준이었음
  - 현재 코드의 score는 group mean, group std, tail source penalty, baseline penalty를 함께 본다

---

## 2. V3 작업 범위

### 건드릴 수 있는 것

- `ml_pipeline/12_train_basis_v3.py`
- 필요할 때만 `ml_pipeline/11_train_basis_v2.py`
- V3 결과 해석용 문서
- V3 전용 테스트나 smoke script

### 되도록 건드리지 않을 것

- `ml_pipeline/3_train.py`
- `ml_pipeline/2_generate_dataset.py`
- `ml_pipeline/11_train_basis_v2.py`의 basis split contract
- 기존 V2/V1 artifact

---

## 3. 작업 시작 전 확인 순서

1. `ml_pipeline/checkpoints/basis_v3_sweep.json` 확인
2. `ml_pipeline/checkpoints/basis_v3_params.json` 확인
3. V3 로그에서 아래를 비교
   - overall score
   - crawled/app/canon group metric
   - coefficient MSE
   - small LUT RMSE
   - top holdout source LUT 오차
   - reconstruction weight
   - val loss
4. 현재 코드가 V2 basis split seed와 맞는지 확인
5. 어떤 파일을 수정할지 최소 범위로 정하기

---

## 4. V3에서 매번 봐야 하는 지표

### 필수

- `score`
- `val_loss`
- `crawled` / `app` / `canon` group metric
- `reconstruction_weight`
- train/validation split이 LUT 단위로 유지되는지
- `score_components`
- `baseline_group_metrics`

### 있으면 같이 볼 것

- coefficient MSE
- small LUT RMSE
- holdout LUT별 RMSE
- best trial 대비 worst trial 격차

---

## 5. V3 디버깅 루틴

### A. sweep 관련 문제

- `--sweep`가 도는지 확인
- split seed가 V2 basis split과 일치하는지 확인
- 같은 source LUT가 train/val에 섞이지 않는지 확인
- group sampling이 intended balance를 유지하는지 확인

### B. 성능이 안 오를 때

- weight 탐색 범위를 확인
- reconstruction weight가 너무 세거나 약하지 않은지 확인
- crawled만 끌어올리다가 app/canon을 죽이고 있지 않은지 확인
- best score만 보지 말고 group metric 분산도 확인
- `score_components`가 실제로 group mean, group std, tail source penalty를 담고 있는지 확인

### C. checkpoint가 안 생길 때

- sweep만 돌고 train을 안 했는지 확인
- best config 저장 경로 확인
- `basis_v3_color.pt` 저장 조건 확인
- `basis_v3_color.report.json`이 같이 저장되는지 확인

---

## 6. V3 개발 루프

1. 현재 sweep 결과 읽기
2. 병목을 한 줄로 적기
3. `12_train_basis_v3.py`만 우선 수정
4. 문법 검사
5. 작은 smoke test
6. 필요하면 sweep trial 수를 줄여 빠르게 재확인
7. 결과가 좋아지면 checkpoint와 params 저장

---

## 7. 테스트 순서

### 최소

```bash
.venv-ml/bin/python -m py_compile ml_pipeline/12_train_basis_v3.py
```

### 가능하면

```bash
.venv-ml/bin/python ml_pipeline/12_train_basis_v3.py --sweep-only
```

### 본학습 확인이 필요할 때

```bash
.venv-ml/bin/python ml_pipeline/12_train_basis_v3.py --train
```

### 결과 비교가 필요할 때

- `basis_v3_sweep.json`
- `basis_v3_params.json`
- `basis_v3_color.pt`
- `basis_v3_color.report.json`

---

## 8. V3 작업 중 자주 놓치는 것

- dataset을 다시 지우기 전에 왜 필요한지 먼저 적기
- basis split이 바뀌면 `load_basis()` 계약이 깨질 수 있음
- sweep 결과가 좋아 보여도 group 하나가 무너졌는지 꼭 보기
- epoch만 늘리는 방식은 우선순위가 낮음
- 기존 V2 artifact를 덮어쓰지 않기

---

## 9. V3에서 바꾸는 파일 우선순위

1. `ml_pipeline/12_train_basis_v3.py`
2. `ml_pipeline/checkpoints/*.json` 결과 확인
3. 필요할 때만 `ml_pipeline/11_train_basis_v2.py`
4. 그 다음 문서 업데이트

---

## 10. 현재 개발자가 기억해야 할 핵심

- V3의 목적은 "더 오래 학습"이 아니라 "가중치/손실 설계를 더 잘 찾기"다.
- V3의 품질 판단은 전체 score 하나로 끝내면 안 되고, group별 오차와 holdout LUT별 오차를 같이 봐야 한다.
- V3가 답이 아니면, 그때는 새로운 방법으로 넘어가야 한다.
