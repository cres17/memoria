# ml_pipeline 개발 진행 정리

기준일: 2026-07-21

이 문서는 `memoria/ml_pipeline` 기준으로 현재까지의 작업물, 판단, 검증 상태를 한 번에 이어볼 수 있게 정리한 개발용 메모다.

---

## 1. 현재 결론

- 기존 `3_train.py` 직접 3D LUT 회귀는 목표 품질에 충분하지 않았다.
- `11_train_basis_v2.py`는 direct LUT 회귀보다 구조적으로 낫지만, 개인 보정 사진을 일반화해서 만들기에는 한계가 있다.
- `12_train_basis_v3.py`는 group weight sweep까지 해봤지만, V2 대비 큰 개선이 없었다.
- 그래서 현재는 "비슷한 LUT를 찾는 모델"이 아니라 "before/after 편집 페어를 직접 적합하는 개인화 필터 생성기"를 추가했다.

즉, 방향은 다음 두 축으로 분리됐다.

1. 공용/분포형 LUT 학습 실험
2. 개인 편집 페어 기반 필터 적합

---

## 2. 실험 파이프라인 상태

### 2.1 기존 LUT 학습 계열

- `3_train.py`
  - 직접 3D LUT 회귀
  - 데이터셋 균형 manifest 검증 포함
  - 현재는 목표 품질 미달로 판단

- `11_train_basis_v2.py`
  - 17^3 mean LUT + 12 PCA residual bases
  - group-balanced sampler
  - LUT 단위 holdout split
  - checkpoint:
    - `ml_pipeline/checkpoints/basis_v2_lut.npz`
    - `ml_pipeline/checkpoints/basis_v2_color.pt`

- `12_train_basis_v3.py`
  - V2 basis를 그대로 쓰고, crawled/app/canon loss weight와 reconstruction weight를 자동 탐색
  - sweep 결과 best score가 V2 대비 유의미한 개선이 아니었음
  - checkpoint / sweep artifact:
    - `ml_pipeline/checkpoints/basis_v3_sweep.json`
    - `ml_pipeline/checkpoints/basis_v3_params.json`

### 2.2 새 개인화 필터 경로

- `13_fit_personal_filter.py`
  - before/after 이미지 페어를 입력받아 필터를 직접 적합
  - global affine color transform + coarse residual LUT
  - 출력:
    - `lut.bin`
    - `thumbnail.jpg`
    - `recipe.json`
    - `fit_report.json`
  - `FilterRecipe` 계약과 맞는 메타데이터를 생성
  - 안전 게이트를 통과하는 65^3 float16 LUT로 내보냄

---

## 3. 현재 파일별 역할

### Python / ML

- `1_download_luts.py`
  - LUT 수집

- `2_generate_dataset.py`
  - sRGB / Canon 합성 포함 dataset 생성
  - manifest에 `inputDomain`, `samplingGroup`, `samplingMode` 포함

- `3_train.py`
  - direct regression baseline

- `4_generate_synthetic_luts.py`
  - synthetic LUT 생성

- `5_download_neutral_images.py`
  - neutral image 수집

- `6_evaluate.py`
  - direct regression 평가

- `7_export_model.py`
  - direct regression export

- `8_train_basis.py`
  - V1 basis-residual experiment

- `9_benchmark_basis.py`
  - basis benchmark

- `10_export_basis.py`
  - V1 export

- `11_train_basis_v2.py`
  - balanced basis-residual training

- `12_train_basis_v3.py`
  - auto-tuned group weights sweep

- `13_fit_personal_filter.py`
  - 개인 편집 페어 기반 필터 적합

### 앱 / Dart

- `lib/engine/personal_filter_core.dart`
  - before/after pair fit 엔진
  - 안전 LUT 생성 및 recipe/report 저장

- `lib/features/create_filter/create_filter_page.dart`
  - `Style Mode` / `Before / After` 모드 추가
  - pair 입력 UI 및 생성 경로 연결

- `lib/domain/models/filter_recipe.dart`
  - `modelId`, `modelVersion`, `referenceFusion` 등 확장된 메타데이터 지원

- `lib/domain/models/filter_preset.dart`
  - recipe 포함 preset 저장/복원

- `lib/engine/custom_lut_core.dart`
  - LUT safety gate, identity LUT, constraint 로직

---

## 4. 검증 상태

### ML / Python smoke

- `13_fit_personal_filter.py --demo`
  - 동작 확인 완료
  - demo 결과에서 safe LUT 생성 확인

### Dart / Flutter

- `flutter analyze`
  - 대상:
    - `lib/features/create_filter/create_filter_page.dart`
    - `lib/engine/personal_filter_core.dart`
    - `test/filter_recipe_test.dart`
    - `test/engine/personal_filter_core_test.dart`
  - 결과: `No issues found`

- `flutter test`
  - 대상:
    - `test/filter_recipe_test.dart`
    - `test/engine/personal_filter_core_test.dart`
  - 결과: `All tests passed`

---

## 5. 최근 얻은 수치 / 판단

### V2 / V3 쪽

- V2 baseline report에서 small LUT RMSE는 전체적으로는 괜찮았지만, crawled 계열 holdout이 상대적으로 약했다.
- V3 sweep을 돌려도 group weight를 조정하는 것만으로는 큰 폭의 개선이 없었다.
- 결론:
  - group weighting 자체는 보정에 도움은 되지만
  - "개인이 직접 편집한 결과를 필터로 복원"하는 문제를 해결하기에는 표현력이 부족하다

### 개인화 pair-fit 쪽

- 개인이 직접 고른 before/after에서 바로 적합하는 방법은
  - 유사 LUT 검색이 필요 없고
  - 같은 LUT 분포가 없어도 되고
  - 개인 보정 습관을 그대로 필터로 압축할 수 있다
- 단, pair가 거칠면 LUT가 보수적으로 수축될 수 있으므로
  - 더 가까운 구도
  - 더 적은 로컬 보정
  - 비슷한 노출
  - 잘 정렬된 before/after
  가 품질에 중요하다

---

## 6. 새 개인화 필터 사용법

### Python

```bash
.venv-ml/bin/python ml_pipeline/13_fit_personal_filter.py \
  --pair before.jpg after.jpg \
  --output-dir ml_pipeline/exports/personalized_filters/my_filter
```

또는 manifest:

```bash
.venv-ml/bin/python ml_pipeline/13_fit_personal_filter.py \
  --manifest pairs.jsonl \
  --output-dir ml_pipeline/exports/personalized_filters/my_filter
```

### 앱

- Create Filter 화면에서 `Before / After` 모드 선택
- BEFORE 이미지 선택
- AFTER 이미지 선택
- 필터 이름 입력
- 생성

---

## 7. 산출물 구조

개인화 필터 결과 디렉토리에는 보통 다음 파일이 생성된다.

- `lut.bin`
  - 65^3 float16 LUT

- `thumbnail.jpg`
  - 대표 썸네일

- `recipe.json`
  - `FilterRecipe` 호환 메타데이터

- `fit_report.json`
  - 적합 품질, 안전 메트릭, 경고 정보

---

## 8. 앞으로 할 수 있는 일

1. pair-fit을 여러 before/after 샘플에 대한 batch 모드로 확장
2. UI에서 before/after pair 품질이 낮을 때 경고 문구를 더 구체화
3. `fit_report.json`을 기준으로 자동 reject / soft-fit 기준을 더 정교하게 조정
4. 개인화 필터를 editor preset 목록에 더 명확히 노출
5. pair-fit 결과를 저장소/공유 흐름과 더 자연스럽게 연결

---

## 9. 참고

- V2 checkpoint: `ml_pipeline/checkpoints/basis_v2_color.pt`
- V3 sweep: `ml_pipeline/checkpoints/basis_v3_sweep.json`
- V3 params: `ml_pipeline/checkpoints/basis_v3_params.json`
- pair-fit engine: `lib/engine/personal_filter_core.dart`
- pair-fit UI: `lib/features/create_filter/create_filter_page.dart`
