# V3 Requirements

V3는 아직 완료본이 아니다. 이 문서는 `12_train_basis_v3.py`를 더 밀어붙이기 전에
무엇을 V3의 성공으로 볼지, 무엇을 저장해야 하는지, 무엇을 건드리지 말아야 하는지를
먼저 고정하는 계약 문서다.

---

## 1. V3의 목적

V3의 목적은 에폭을 늘리는 것이 아니라, basis-residual 파이프라인에서 더 나은
학습 목적함수와 가중치 설계를 찾는 것이다.

핵심 질문은 다음 네 가지다.

- `crawled`, `app`, `canon` 그룹을 어떻게 균형 있게 다룰 것인가
- reconstruction loss와 group-level validation loss를 어떻게 묶을 것인가
- holdout LUT 기준 일반화를 어떻게 확인하고 억제할 것인가
- 한 그룹만 좋아지고 나머지가 무너지는 현상을 어떻게 막을 것인가

---

## 2. 문제 정의

현재 V2/V3 계열의 핵심 리스크는 다음과 같다.

- 전체 score가 좋아 보여도 group별 오차가 고르게 줄지 않을 수 있다
- `crawled` 쪽을 과하게 보정하면 `app`/`canon` 일반화가 흔들릴 수 있다
- sweep best가 좋아도 holdout LUT별 오차 분포는 나쁠 수 있다
- 단순 weight tuning만으로는 구조적 한계를 넘지 못할 수 있다

따라서 V3는 “같은 모델을 조금 더 오래 학습하는 버전”이 아니라, 평가 방식과
손실 설계를 더 엄격하게 검증하는 버전이어야 한다.

---

## 3. 기준선

V3는 다음 사실을 기준선으로 삼는다.

- V2 basis는 이미 존재해야 한다
- train/validation은 LUT 단위로 분리되어야 한다
- V3 sweep 결과가 이미 있어도, 그 결과만으로 완결이라고 보지 않는다
- V3의 목표는 단일 score 개선이 아니라 group 안정성과 holdout 안정성을 함께
  확인하는 것이다

현재 판단 기준은 “best score 숫자 하나”가 아니라 다음 묶음이다.

- `score`
- `val_loss`
- `crawled` / `app` / `canon` group metric
- coefficient MSE
- small LUT RMSE
- holdout LUT별 오차 분포

---

## 4. 범위

### 포함

- `ml_pipeline/12_train_basis_v3.py`
- V3 학습/평가 로직
- V3 sweep 정책
- V3 checkpoint / params / report 저장
- V3 결과 해석용 JSON
- V3 전용 smoke test

### 제외

- `ml_pipeline/2_generate_dataset.py` 재설계
- `ml_pipeline/3_train.py` 직접 회귀 경로의 대수술
- 검증된 V2 artifact의 무분별한 변경
- 장시간 재학습을 무계획으로 반복하는 것

---

## 5. V3 score contract

V3의 model selection score는 실제 validation loss와 별개로, 다음 원칙을 만족해야 한다.

1. 그룹 평균 오차를 기본축으로 둔다.
2. 그룹 간 편차를 억제하는 항을 포함한다.
3. 가장 나쁜 holdout LUT 쪽 꼬리를 벌점으로 포함한다.
4. baseline report가 있으면 `app` / `canon` 악화를 추가 벌점으로 반영한다.

현재 코드의 권장 score 구성은 다음이다.

- `group_mean`: `crawled`, `app`, `canon` small LUT RMSE의 평균
- `group_std`: 그룹 간 편차
- `tail_source_mean`: worst holdout source LUT 상위 몇 개의 small LUT RMSE 평균
- `baseline_penalty`: baseline 대비 `app` / `canon` 초과분 벌점

이 score는 “한 그룹만 잘 맞춘 모델”을 밀어주는 방식이 아니라,
그룹 균형과 outlier 억제를 같이 보는 선택 기준이어야 한다.

---

## 6. 성공 기준

V3가 의미 있으려면 다음 조건을 만족해야 한다.

1. V2 대비 balanced score가 개선되거나 최소한 동등해야 한다.
2. `crawled`, `app`, `canon` 중 하나만 좋아지고 나머지가 크게 악화되면 실패다.
3. holdout LUT별 오차가 일부 소수 LUT에만 몰리지 않아야 한다.
4. coefficient MSE와 reconstruction 품질을 함께 설명할 수 있어야 한다.
5. 재실행 가능한 best config와 checkpoint가 함께 남아야 한다.

---

## 7. 필수 산출물

V3가 진전되면 최소한 다음이 남아야 한다.

- 최종 또는 후보 checkpoint
- best config JSON
- sweep 결과 JSON
- validation report JSON
- group별 / source LUT별 요약
- 다음 단계 판단용 짧은 결론

---

## 8. 필수 로그 필드

`basis_v3_color.report.json` 또는 동등한 report에는 최소한 다음이 있어야 한다.

- `overall`
- `by_group`
- `by_source_lut`
- `top_sources_by_small_lut_rmse`
- `score`
- `score_components`
- `baseline_group_metrics`

`score_components`에는 최소한 다음이 있어야 한다.

- `group_mean`
- `group_std`
- `tail_source_mean`
- `baseline_penalty`
- `tail_source_luts`

---

## 9. 학습 요구사항

### 데이터 분할

- train/validation은 LUT 단위로 분리되어야 한다
- 같은 source LUT가 train과 validation에 섞이면 안 된다
- basis fit과 train split 계약이 어긋나면 안 된다

### 그룹 균형

- `crawled`, `app`, `canon` 노출이 의도한 비율을 유지해야 한다
- 특정 그룹을 과하게 밀어 올려 다른 그룹을 희생시키면 안 된다
- group weight는 수동 한 번 찍기가 아니라 비교 가능한 탐색 대상이어야 한다

### 파라미터 탐색

- sweep은 비교 가능한 후보군을 남겨야 한다
- best config는 재실행 가능해야 한다
- sweep 결과는 파일로 보존해야 한다

---

## 10. 구현 요구사항

### 파일 정책

- V3의 핵심 수정은 `12_train_basis_v3.py` 중심으로 진행한다
- V2 기준선과 충돌하는 변경은 최소화한다
- 필요하면 새 파일을 추가하되, 기존 파일을 덮어쓰지 않는다

### 저장 정책

- checkpoint
- params JSON
- sweep JSON
- evaluation log

이 네 가지는 최소한 남아야 한다.

### 안전 정책

- 데이터셋을 삭제하거나 재생성하기 전에 왜 필요한지 먼저 적는다
- 장시간 학습 전에 짧은 smoke test를 먼저 통과시킨다
- 기존 검증 결과를 덮어쓰지 않는다

---

## 11. 비목표

V3에서 지금 당장 하지 않을 일은 다음과 같다.

- 에폭만 늘리는 방식으로 해결하려는 접근
- sweep 결과만 보고 결론을 내리는 것
- 데이터셋을 다시 크게 뒤집는 것
- 구조적 한계가 의심되는데도 같은 방향의 튜닝만 반복하는 것

---

## 12. 위험 요소

- `crawled`를 너무 강하게 보정하면 `app` / `canon` 일반화가 깨질 수 있다
- reconstruction weight가 지나치면 group metric이 가려질 수 있다
- sweep score가 좋아도 실제 holdout 품질은 나쁠 수 있다
- basis split contract가 틀어지면 V2/V3 비교가 무의미해질 수 있다

---

## 13. 현재 의사결정 원칙

V3는 “현재 방식의 미세 조정”에 머물지 말고, 아래 순서로 판단한다.

1. 지금 구조에서 더 나은 가중치/손실 설계가 있는지 본다
2. 없으면 구조를 바꾸는 방향을 검토한다
3. 그래도 한계가 보이면 새로운 방법으로 전환한다

즉, V3의 목표는 정답을 끝까지 우기는 것이 아니라, 현 구조의 한계를 사실 기반으로 판별하는 것이다.
