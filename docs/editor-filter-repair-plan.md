# 사진 편집기·필터 생성 복구 및 화이트박스 검증 계획

- 작성일: 2026-08-18
- 상태: 구현 전 작업 명세
- 대상: Flutter 사진 편집기, 렌더 파이프라인, 사용자 필터 생성
- 상세 화이트박스·성능 검증: [editor-whitebox-validation-plan.md](editor-whitebox-validation-plan.md)
- 기준 파일:
  - `lib/features/editor/editor_page.dart`
  - `lib/features/editor/widgets/crop_panel.dart`
  - `lib/features/editor/widgets/crop_overlay_widget.dart`
  - `lib/features/editor/widgets/filter_strip.dart`
  - `lib/features/create_filter/create_filter_page.dart`
  - `lib/engine/`

## 1. 목표

1. 모든 편집 도구를 **미리보기 → 확인(✓) → 반영** 흐름으로 통일한다.
2. 활성 도구에서 뒤로 가면 해당 도구의 임시 변경만 취소하고, 편집기 자체를 나갈 때는 편집 폐기 여부를 확인한다.
3. 크롭, 반전, 필터, 부분 보정, 아웃포커스, 그레인, 렌즈 흐림, 텍스트, 프레임 등 현재 느리거나 작동하지 않는 기능을 실제 preview/export 파이프라인에 연결한다.
4. 얼굴·영역 기반 효과는 유효한 mask가 있을 때만 적용한다.
5. 모든 수치 조절 도구에 현재 도구만 중립값으로 되돌리는 초기화 버튼을 제공한다.
6. 사용자 필터 생성에서 실제 최근 사진을 보여 주고, 생성 완료 결과도 실제 사진의 Before/After로 검증 가능하게 한다.

## 2. 공통 UX 및 상태 계약

### 2.1 도구 편집 트랜잭션

도구를 열 때 현재 확정 상태를 `toolEntrySnapshot`으로 보관한다. 도구 안에서 발생하는 변경은 임시 상태에만 반영하고 history나 draft의 확정 상태를 바꾸지 않는다.

| 사용자 동작 | 활성 도구 있음 | 활성 도구 없음 |
| --- | --- | --- |
| 왼쪽 위 뒤로 가기 | 임시 변경을 snapshot으로 복구하고 도구 닫기 | 편집 폐기 확인 다이얼로그 표시 |
| 시스템 뒤로 가기/제스처 | 왼쪽 위 뒤로 가기와 동일 | 편집 폐기 확인 다이얼로그 표시 |
| 오른쪽 위 ✓ | 현재 도구 변경을 history에 한 번 저장하고 도구 닫기 | 표시하지 않음 |
| 오른쪽 위 원본 보기 | 누르는 동안 원본 표시, 떼면 현재 미리보기 복구 | 편집기 공통 동작 유지 |
| 오른쪽 아래 초기화 | 현재 도구의 임시 값만 중립값으로 변경 | 표시하지 않음 |
| 다른 도구 선택 | 현재 도구를 자동 적용하지 않음. 먼저 취소한 뒤 새 도구 진입 | 새 도구 진입 |

필수 규칙:

- 필터 항목을 누르거나 슬라이더를 움직이는 것만으로 edit history에 확정 operation을 추가하지 않는다.
- ✓ 한 번당 history entry는 정확히 한 개만 생성한다.
- 취소 후에는 픽셀 결과와 모든 파라미터가 도구 진입 전과 같아야 한다.
- 초기화는 이전에 확정한 다른 도구의 결과를 지우지 않는다.
- 비동기 preview가 늦게 완료되더라도 취소/다른 도구 진입 이후 화면을 덮어쓰지 않도록 request token으로 stale result를 폐기한다.

### 2.2 공통 버튼 배치

- 상단 오른쪽: `원본 보기`, `✓ 적용`
- 하단 오른쪽: `초기화`
- 상단 왼쪽: 활성 도구 취소 또는 편집기 나가기
- 아이콘 전용 버튼은 최소 44×44 logical px, semantic label과 tooltip을 제공한다.
- `초기화`는 모든 수치 조절 도구에 동일한 위치와 형태로 표시한다.

### 2.3 편집기 나가기

- 활성 도구가 있으면 나가기 다이얼로그를 띄우지 않고 해당 도구만 취소한다.
- 활성 도구가 없고 편집 변경이 있으면 `편집을 취소하고 나갈까요?` 확인 다이얼로그를 표시한다.
- `계속 편집`은 화면과 history를 그대로 유지한다.
- `나가기`는 저장하지 않은 편집을 폐기하고 이전 화면으로 이동한다.
- 변경이 전혀 없으면 다이얼로그 없이 나갈 수 있다.

## 3. 기능별 수정 명세

### P0-1. 크롭

현재 문제: 비율 도구를 바꾸면 곧바로 적용되거나, 선택한 비율에서 crop 영역을 자유롭게 작게/크게 조절하기 어렵다.

수정 요구:

- `자유`, `원본`, `1:1`, `4:3`, `3:4`, `16:9`, `9:16` 등 비율 선택은 **비율 잠금만 변경**하고 확정하지 않는다.
- 고정 비율에서는 네 모서리 handle을 드래그해 비율을 유지한 채 crop box를 확대/축소할 수 있어야 한다.
- crop box 내부 드래그로 영역을 이동할 수 있어야 한다.
- crop box는 사진 bounds 밖으로 나가거나 최소 크기보다 작아지지 않는다.
- 비율을 바꿀 때 현재 crop 중심을 최대한 유지하며, 가능한 최대 영역으로만 재계산한다.
- 자유 비율에서는 각 edge/corner를 독립적으로 조절한다.
- 드래그 중에는 matrix/clip 기반 미리보기만 사용하고 실제 resample은 ✓ 또는 export에서 수행한다.
- 초기화는 전체 사진 영역과 `자유` 또는 제품에서 정한 기본 비율로 복구한다.
- 뒤로 가기는 도구 진입 전 crop 상태로 복구한다.

완료 기준:

- 비율 선택만으로 history가 변하지 않는다.
- 어떤 고정 비율에서도 crop box를 작게 만든 뒤 이동하고 다시 크게 만들 수 있다.
- ✓ 후 preview/export crop 경계 오차가 edge별 1px 이하다.
- 드래그 중 p95 frame time은 16ms 이하다.

### P0-2. 좌우·상하 반전

현재 문제: 반응이 매우 느리거나 화면에서 실제 반전이 보이지 않는다.

수정 요구:

- 탭 즉시 canvas transform으로 반전 상태를 보여 준다.
- 탭마다 원본 decode, 전체 CPU 재렌더, JPEG 재인코딩을 수행하지 않는다.
- 반전 상태는 `flipH`, `flipV` boolean으로만 관리하고 crop/rotation과 transform 순서를 고정한다.
- 연속 탭 시 최신 상태만 렌더하며 stale preview 결과를 폐기한다.
- ✓에서만 history에 반영하고 export에서는 동일한 transform을 최종 해상도에 적용한다.
- 초기화는 회전 0°, `flipH=false`, `flipV=false`로 복구한다.

완료 기준:

- 반전 탭 후 첫 시각 변화 p95 50ms 이하.
- 좌우 두 번 또는 상하 두 번 누르면 no-op 기준으로 원본과 같다.
- EXIF orientation이 있는 입력에서도 이중 회전/반전이 없다.
- preview/export의 방향과 crop 위치가 일치한다.

### P0-3. 필터 확인·취소

현재 문제: 필터 선택만으로 적용되며, 별도의 확인 없이 화면을 나가도 결과가 남을 수 있다.

수정 요구:

- 필터 도구 진입 시 현재 preset, LUT, intensity를 snapshot으로 보관한다.
- 필터 카드를 누르면 임시 preview만 바뀐다.
- 필터 도구 상단 오른쪽에 ✓를 표시한다.
- ✓를 눌러야 선택한 필터와 강도가 확정되고 필터 도구에서 빠져나간다.
- 뒤로 가기, 시스템 back, 다른 도구 이동은 임시 필터를 폐기한다.
- `원본` 필터도 같은 트랜잭션 규칙을 따른다.
- 빠르게 여러 필터를 누를 때 마지막 선택만 화면에 반영한다.

완료 기준:

- 필터 선택 후 취소하면 preset/LUT/intensity와 픽셀이 진입 전 상태로 돌아간다.
- ✓ 전에는 history count가 증가하지 않고, ✓ 후 정확히 1 증가한다.
- cached filter switch p95 50ms, cold switch p95 150ms 이하.

### P0-4. 부분 보정

현재 문제: 부분 보정이 전역 조정 도구를 한 화면에 다시 모아 둔 것처럼 동작하며, 터치한 영역만 수정되지 않는다.

수정 요구:

- 사진 탭으로 selective point를 추가한다.
- point를 드래그해 위치를 이동하고, 반경과 feather를 조절할 수 있게 한다.
- 밝기, 대비, 채도, 구조 등 local parameter는 선택된 point의 mask 안에만 적용한다.
- mask는 최소한 `화면상 거리 × 원본 색상 유사도`를 사용하고 feather로 경계를 부드럽게 만든다.
- 여러 point가 겹칠 때 합성 규칙을 고정하고 과도한 중복 증폭을 방지한다.
- 필요 시 `마스크 보기`로 실제 영향 영역을 확인할 수 있게 한다.
- point가 없으면 local slider를 비활성화하거나 안내 문구를 표시한다.
- 초기화는 현재 도구의 point와 local parameter를 모두 제거한다.

완료 기준:

- synthetic 2-color fixture에서 한쪽을 터치했을 때 반대쪽 평균 변화는 허용 오차 이하다.
- mask 내부에는 유의미한 변화가 있고, mask 외부는 no-op에 가깝다.
- point 추가/이동/삭제와 undo/redo가 동일한 결과를 재현한다.
- preview와 export가 동일한 normalized point 좌표를 사용한다.

### P0-5. 아웃포커스·렌즈 흐림

현재 문제: 아웃포커스가 작동하지 않으며 오류가 발생하고, 렌즈 흐림도 가시적 효과가 없을 수 있다.

수정 요구:

- 아웃포커스는 subject/portrait mask의 바깥쪽에 blur를 적용한다.
- lens blur는 사용자가 지정한 center/radius/feather mask에 실제 blur kernel을 적용한다.
- mask 크기와 preview 이미지 크기가 항상 일치하도록 resize contract를 둔다.
- 모델 미설치, mask 생성 실패, 빈 mask, decode 실패는 crash 대신 원본 보존과 사용자 안내로 처리한다.
- blur radius 0은 정확한 no-op, 양수는 측정 가능한 blur가 되어야 한다.
- slider drag 중 960px proxy를 사용하고, 늦은 결과를 취소할 수 있게 한다.
- 초기화는 blur 0과 기본 mask geometry로 복구한다.

완료 기준:

- 오류 fixture에서도 crash 없이 편집을 계속할 수 있다.
- checkerboard fixture에서 blur 0 대비 blur 양수의 edge energy가 감소한다.
- subject mask 내부 선명도는 유지되고 배경 edge energy만 감소한다.
- 첫 reduced preview p95 250ms 이하, UI isolate frame p95 16ms 이하.

### P0-6. 그레인

현재 문제: 강도를 올려도 보이지 않거나 렌더/export 경로가 누락될 수 있다.

수정 요구:

- 강도 0은 no-op, 양수는 실제 preview와 export에 grain을 합성한다.
- 동일 seed/parameter는 preview 재진입, undo/redo, export에서 같은 패턴을 만든다.
- 해상도에 따른 grain 크기를 보정해 preview와 export의 질감 크기가 일치해야 한다.
- 초기화는 strength 0, 기본 size/roughness/color mode로 복구한다.

완료 기준:

- non-zero grain은 원본 대비 유의미한 pixel variance 증가를 만든다.
- 동일 seed의 결과는 deterministic하다.
- preview/export downsample 비교가 공통 golden 허용치 안에 든다.

### P0-7. 텍스트

현재 문제: 텍스트 입력 또는 canvas 합성이 작동하지 않는다.

수정 요구:

- 입력한 문자열이 preview canvas에 즉시 보이고 export에도 같은 위치/크기/색상으로 합성된다.
- multiline, 크기, 색상, opacity, 정렬, 위치 이동을 지원한다.
- 키 입력은 debounce하고 위치 이동은 transform 기반으로 즉시 반응한다.
- 빈 문자열은 no-op이며, 폰트 누락 시 deterministic fallback font를 사용한다.
- 텍스트가 사진 뒤나 frame 뒤에 의도치 않게 묻히지 않도록 layer order를 명시한다.
- 초기화는 현재 텍스트 overlay를 제거하고 style/position을 기본값으로 되돌린다.

완료 기준:

- 한글·영문·숫자·multiline fixture가 preview/export 모두 보인다.
- preview/export text bounding box 차이가 downsample 기준 2px 이하다.
- 빈 텍스트와 폰트 누락이 crash를 만들지 않는다.

### P0-8. 프레임 합성 순서

현재 문제: 사진이 프레임 아래에 완전히 묻혀 보이지 않는다.

수정 요구:

- 사진을 먼저 그리고 프레임의 테두리/투명 영역을 그 위에 overlay한다.
- 불투명 JPG 프레임은 중앙 사진 영역을 가리는 asset인지 감사하고, alpha PNG 또는 명시적 cutout mask를 사용한다.
- layer order를 `편집된 사진 → 프레임 → 텍스트/의도된 최상위 overlay`로 고정한다.
- preview와 export에서 동일한 fit/scale/alignment 규칙을 사용한다.
- 초기화는 frame none 상태로 복구한다.

완료 기준:

- 모든 frame asset에서 중앙 사진 영역이 보인다.
- none frame은 no-op이다.
- border fixture에서는 중앙 pixel은 원본과 같고 테두리 pixel만 프레임으로 바뀐다.

### P1-1. 피부 스무딩

현재 문제: 얼굴/피부 영역을 인식하지 않고 사진 전체를 임의로 보정한다.

수정 요구:

- face detection과 skin/portrait mask가 유효할 때만 smoothing을 적용한다.
- 머리카락, 눈, 눈썹, 입술, 배경의 세부 정보는 가능한 한 보호한다.
- 얼굴이 없거나 confidence가 threshold 미만이면 no-op 처리하고 기능 상태를 안내한다.
- smoothing은 피부 mask 내부에서도 edge-aware 방식으로 동작해야 한다.
- 강도 0과 mask 없음은 no-op이다.
- 초기화는 모든 portrait parameter를 중립값으로 복구한다.

완료 기준:

- 비인물 fixture의 결과는 no-op 허용치 안에 든다.
- 인물 fixture에서 피부 영역의 high-frequency noise는 줄고 눈/머리카락 edge 손실은 제한된다.
- mask가 전체 화면으로 fallback되어 전역 blur가 되는 경로가 없어야 한다.

### P1-2. 드라마 화질

현재 문제: 밝은 드라마 preset/강도에서 화질이 깨지거나 하이라이트가 손상된다.

수정 요구:

- 8-bit 중간 buffer에서 반복적으로 contrast를 누적하지 않고 float 기반 또는 충분한 정밀도의 pipeline을 사용한다.
- highlight roll-off/soft clip으로 밝은 영역 clipping을 억제한다.
- local contrast 경계에서 halo, banding, posterization을 줄인다.
- 강도 0은 no-op이며 밝은 fixture에서 25/50/100 강도를 비교한다.
- 초기화는 drama strength와 관련 보조 파라미터를 0으로 복구한다.

완료 기준:

- 기본 유효 강도에서 clipping pixel 증가율 1%p 이하를 목표로 한다.
- synthetic edge halo overshoot p99 8/255 이하.
- gradient fixture에서 새 band가 발생하지 않는다.

### P1-3. 광학 유출

현재 문제: 실제 효과 연결과 방향/강도 동작이 검증되지 않았다.

수정 요구:

- 강도, 위치, 방향, scale, tint가 실제 overlay transform과 연결되어야 한다.
- blend mode는 screen/additive 중 하나로 명시하고 기본 효과는 사진을 덮지 않게 한다.
- random variant가 있다면 seed를 저장해 재실행과 export 결과를 결정적으로 만든다.
- texture 누락은 no-op과 안내로 처리한다.
- 초기화는 strength 0과 기본 transform/tint로 복구한다.

완료 기준:

- strength 0은 no-op이고 100은 위치별로 측정 가능한 변화가 있다.
- 좌/우/상/하 방향 변경 시 에너지 중심이 기대 방향으로 이동한다.
- 저장/재실행/export 결과가 동일하다.

## 4. 사용자 필터 생성 수정

### 4.1 최근 사진 선택 화면

- 필터 만들기 화면 진입 시 권한 범위 안에서 최신 사진을 최근순으로 조회한다.
- 최근 사진을 회색 placeholder가 아닌 실제 thumbnail로 가로 strip/grid 첫 화면에 표시한다.
- 기본 목표 수는 최근 30장이고 pagination으로 추가 로드할 수 있게 한다.
- thumbnail decode는 화면 크기에 맞는 캐시 이미지를 사용하며 원본을 메인 isolate에서 decode하지 않는다.
- 선택 상태, 선택 순서, 최대 선택 수를 시각적으로 표시한다.
- limited permission, 권한 거부, 빈 라이브러리, cloud-only asset을 각각 안전하게 처리한다.

### 4.2 생성 완료 화면

- 생성 완료 sheet의 Before는 사용자가 선택한 실제 source/reference 사진이어야 한다.
- After는 **동일한 사진에 새로 생성된 필터를 실제 적용한 결과**여야 한다.
- 회색 placeholder를 성공 결과로 사용하지 않는다.
- Before/After slider 또는 두 장 비교로 색 변화와 손상을 확인할 수 있게 한다.
- 결과 적용, 이름 지정/저장, 다시 선택을 제공한다.
- preview 생성 실패 시 성공처럼 보이는 회색 화면을 띄우지 말고 오류와 재시도 동작을 제공한다.

### 4.3 생성 필터 안전 계약

- LUT node는 finite여야 하며 채널 순서, dimension, range가 유효해야 한다.
- intensity 0은 원본, 1은 생성 LUT 결과여야 한다.
- identity-like input은 identity-like LUT를 생성해야 한다.
- 생성 직후 preview에 사용한 LUT bytes와 저장 후 다시 불러온 LUT bytes가 같아야 한다.
- source/reference 사진은 사용자가 명시적으로 저장하지 않는 한 필터 생성 후 영구 보관하지 않는다.

## 5. 화이트박스 테스트 계획

이 절은 핵심 회귀 사례의 요약이다. 전체 기능 인벤토리, 모든 도구에 공통 적용할 12개 검증축, 기능별 고유 test ID, 실기기 성능 측정과 완료 판정은 [editor-whitebox-validation-plan.md](editor-whitebox-validation-plan.md)를 단일 기준으로 사용한다.

### 5.1 편집 트랜잭션 및 공통 UI

| ID | 입력/조작 | 내부 확인 지점 | 기대 결과 |
| --- | --- | --- | --- |
| ED-TX-01 | 도구 진입 → 값 변경 → 뒤로 | snapshot, draft state, history length | 모든 값과 preview가 진입 전으로 복구되고 history가 늘지 않는다. |
| ED-TX-02 | 도구 진입 → 값 변경 → ✓ | active tool state, history | 값이 유지되고 history가 정확히 1 증가하며 도구가 닫힌다. |
| ED-TX-03 | 값 변경 → 초기화 | tool-local neutral params | 현재 도구만 중립값이 되고 다른 확정 편집은 유지된다. |
| ED-TX-04 | 활성 도구에서 시스템 back | `PopScope`, active tool | 도구만 취소하고 editor route는 유지한다. |
| ED-TX-05 | 도구 없는 dirty editor에서 back | route pop guard | 폐기 확인창이 뜨며 `계속 편집`은 상태를 보존한다. |
| ED-TX-06 | 비동기 preview 중 취소 | request token | 늦게 끝난 preview가 복구된 화면을 덮지 않는다. |
| ED-TX-07 | 모든 조절 도구 렌더 | action layout | 상단 오른쪽에 원본/✓, 하단 오른쪽에 초기화가 있다. |

### 5.2 크롭·반전·필터

| ID | 입력/조작 | 내부 확인 지점 | 기대 결과 |
| --- | --- | --- | --- |
| CR-01 | 1:1 선택 후 corner drag | normalized crop rect, ratio | rect 크기가 변하고 비율 오차는 epsilon 이하다. |
| CR-02 | crop box 내부 drag | bounds clamp | 비율/크기는 유지되고 사진 밖으로 나가지 않는다. |
| CR-03 | 4:3 → 16:9 전환 | crop center | 즉시 확정되지 않고 중심을 최대한 유지한다. |
| CR-04 | crop 변경 후 취소/적용 | snapshot/history | 취소는 완전 복구, 적용은 1회 저장이다. |
| FL-01 | 좌우/상하 각각 1회 | transform matrix, flags | 기대 방향으로 즉시 반전된다. |
| FL-02 | 동일 반전 2회 | output diff | 원본과 no-op 허용치 안에 든다. |
| FL-03 | 빠른 연속 반전 | preview token | 마지막 boolean 상태만 반영된다. |
| FT-01 | 필터 선택 후 뒤로 | preset/LUT/intensity/history | 필터가 남지 않고 history가 변하지 않는다. |
| FT-02 | 필터 선택 후 ✓ | history operation | 선택 preset과 intensity가 한 번만 저장된다. |
| FT-03 | 필터 연속 탭 | async request id | 마지막 선택의 LUT만 화면에 표시된다. |

### 5.3 효과·영역·합성

| ID | 입력/조작 | 내부 확인 지점 | 기대 결과 |
| --- | --- | --- | --- |
| SE-01 | 2-color 이미지 한쪽에 point 추가 | selective mask | 선택한 쪽 mask가 높고 반대쪽은 낮다. |
| SE-02 | point brightness 증가 | inside/outside mean diff | mask 내부만 바뀌고 외부는 no-op에 가깝다. |
| BL-01 | blur 0/양수 | edge energy | 0은 no-op, 양수는 mask 영역 edge energy를 낮춘다. |
| BL-02 | segmenter 실패/빈 mask | error path | crash 없이 no-op과 안내 상태를 반환한다. |
| GR-01 | grain 0/양수/동일 seed | variance, output hash | 0은 no-op, 양수는 variance 증가, 동일 seed hash는 같다. |
| TX-01 | 한글·영문 multiline 입력 | overlay layout/output | 문자열이 보이고 preview/export 위치가 일치한다. |
| TX-02 | 빈 텍스트/폰트 누락 | fallback path | no-op 또는 fallback으로 완료되며 crash가 없다. |
| FR-01 | frame 적용 | center/border pixels, layer order | 중앙 사진은 보존되고 border만 변경된다. |
| FR-02 | frame none/asset 누락 | fallback path | no-op이며 crash가 없다. |
| SK-01 | 비인물 이미지 smoothing | face/skin mask | 원본과 no-op 허용치 안에 든다. |
| SK-02 | 인물 이미지 smoothing | skin/non-skin metrics | 피부만 완화되고 눈·머리카락·배경은 보호된다. |
| DR-01 | 밝은 gradient에 drama 0/50/100 | clipping/banding/halo | 0은 no-op이고 유효 강도에서 품질 gate를 만족한다. |
| LL-01 | light leak 0/100, 네 방향 | overlay energy centroid | 0은 no-op이고 에너지 중심이 선택 방향과 일치한다. |

### 5.4 사용자 필터 생성

| ID | 입력/조작 | 내부 확인 지점 | 기대 결과 |
| --- | --- | --- | --- |
| CF-01 | 사진 권한 허용 후 진입 | recent asset query/order | 최신 실제 사진 thumbnail이 최근순으로 표시된다. |
| CF-02 | 사진 1·3·5장 선택 | selected paths/IDs, isolate input | 실제 collage가 표시되고 같은 선택 목록이 생성기에 전달된다. |
| CF-03 | 필터 생성 완료 | `_buildSampleFilterPreview` input/output | Before와 After가 같은 실제 사진이며 After에는 새 필터가 적용된다. |
| CF-04 | 성공 sheet 렌더 | source path, after path | 회색 placeholder 없이 두 이미지가 정상 decode된다. |
| CF-05 | intensity 0/1 | pipeline blend | 0은 원본이고 1은 생성 LUT 결과다. |
| CF-06 | identity pair 생성 | generated LUT/output diff | identity 기준 허용치 안에 든다. |
| CF-07 | 저장 후 reload | LUT bytes/hash, recipe | 생성 직후와 재로드 결과가 같다. |
| CF-08 | LUT range/channel 검사 | validator | NaN/Inf/range/channel 오류는 저장 전에 차단된다. |
| CF-09 | 권한 거부/limited/빈 앨범 | media permission state | 적절한 안내와 선택 대안이 있고 crash가 없다. |
| CF-10 | 깨진 사진/생성 취소/preview 실패 | isolate cleanup, repository | 성공 preset이 저장되지 않고 임시 자원이 정리된다. |

## 6. 테스트 파일 및 실행 명령

기존 테스트는 유지하고, 없는 target은 아래 이름으로 추가한다.

- 공통 상태/UI:
  - `test/features/editor/editor_tool_transaction_test.dart`
  - `test/features/editor/editor_back_navigation_test.dart`
- 크롭/반전/필터:
  - `test/features/editor/editor_spatial_renderer_test.dart`
  - `test/features/editor/crop_panel_test.dart`
  - `test/engine/rotate_flip_engine_test.dart`
  - `test/features/editor/rotate_flip_panel_test.dart`
  - `test/features/editor/filter_strip_test.dart`
- 부분 보정/효과:
  - `test/engine/selective_engine_test.dart`
  - `test/engine/lens_blur_engine_test.dart`
  - `test/engine/grain_engine_test.dart`
  - `test/features/editor/text_overlay_panel_test.dart`
  - `test/features/editor/frame_panel_test.dart`
  - `test/whitebox_portrait_engine_test.dart`
  - `test/engine/hdr_drama_engine_test.dart`
  - `test/engine/light_leak_engine_test.dart`
- 필터 생성:
  - `test/features/create_filter/create_filter_flow_test.dart`
  - `test/engine/personal_filter_core_test.dart`
  - `test/whitebox_lut_core_test.dart`
  - `test/filter_recipe_test.dart`

단계별 테스트 예시:

```bash
flutter test test/features/editor/editor_spatial_renderer_test.dart test/features/editor/crop_panel_test.dart
flutter test test/engine/rotate_flip_engine_test.dart test/features/editor/rotate_flip_panel_test.dart
flutter test test/features/editor/editor_tool_transaction_test.dart test/features/editor/editor_back_navigation_test.dart
flutter test test/engine/selective_engine_test.dart test/engine/lens_blur_engine_test.dart
flutter test test/engine/grain_engine_test.dart test/features/editor/text_overlay_panel_test.dart test/features/editor/frame_panel_test.dart
flutter test test/whitebox_portrait_engine_test.dart test/engine/hdr_drama_engine_test.dart test/engine/light_leak_engine_test.dart
flutter test test/features/create_filter/create_filter_flow_test.dart test/engine/personal_filter_core_test.dart test/whitebox_lut_core_test.dart test/filter_recipe_test.dart
flutter test
git diff --check
```

## 7. 구현 순서

### Phase 1: 공통 적용·취소·초기화 상태 머신

- `backup/restore/apply/reset` 책임을 한 경로로 통합한다.
- back navigation과 dirty editor confirmation을 고정한다.
- 공통 상단/하단 action UI를 적용한다.
- stale preview cancellation을 추가한다.

### Phase 2: 직접 조작 P0 도구

- 크롭 비율 잠금/resize/move
- 좌우·상하 반전 즉시 preview
- 필터 임시 선택과 ✓ 확정
- 부분 보정 point/mask

### Phase 3: 현재 미작동 렌더 기능

- 아웃포커스·렌즈 흐림
- 그레인
- 텍스트
- 프레임 layer/asset

### Phase 4: 품질 및 인식 기반 기능

- 얼굴/피부 mask 기반 smoothing
- 밝은 드라마 highlight/halo 품질
- 광학 유출 transform/determinism

### Phase 5: 필터 생성 UX 및 화이트박스 검증

- 최신 사진 thumbnail
- 실제 사진 Before/After 성공 sheet
- 생성 LUT validation 및 저장/reload parity

각 phase는 해당 target test, 전체 관련 regression, `flutter analyze`, `git diff --check`가 통과한 뒤 다음 phase로 이동한다.

## 8. 정량 품질 게이트

- GPU 직접 조작: drag 중 p95 frame build+raster 16ms 이하.
- CPU preview: 960px proxy 기준 debounce 후 p95 80ms 이하.
- ML/blur/HDR 첫 reduced preview: p95 250ms 이하, UI block 없음.
- preview/export parity: downsample 기준 mean diff 2/255 이하, p99 10/255 이하, SSIM 0.992 이상.
- deterministic pixel golden: mean diff 1.5/255 이하, p99 8/255 이하, SSIM 0.995 이상.
- neutral no-op: mean diff 0.25/255 이하, max diff 2/255 이하.
- export는 main isolate를 막지 않고 1초 초과 작업은 progress/cancel을 제공한다.

## 9. 실기기 점검

- iPhone에서 고해상도 JPEG/HEIC를 열고 좌우·상하 반전 탭 반응과 preview/export 방향을 확인한다.
- 모든 crop ratio에서 영역을 작게/크게 만들고 이동한 뒤 export 결과를 비교한다.
- 필터 선택 후 뒤로 가기와 ✓를 각각 실행해 취소/확정이 구분되는지 확인한다.
- 부분 보정 point를 피부, 하늘, 배경에 각각 놓고 영향 영역을 육안 확인한다.
- 아웃포커스와 lens blur를 인물/비인물/모델 미설치 상태에서 확인한다.
- 프레임 전체 asset을 순회해 사진 중앙이 보이고 border만 위에 합성되는지 확인한다.
- 텍스트를 한글·영문·여러 줄로 입력하고 이동/크기/색상/내보내기를 확인한다.
- 밝은 드라마 0/25/50/100에서 clipping, banding, block noise, halo를 확인한다.
- 광학 유출 0/100과 네 방향에서 위치와 강도 변화를 확인한다.
- 필터 생성에서 최신 사진 목록, 실제 collage, 실제 Before/After, 저장 후 재적용을 확인한다.

## 10. 완료 정의

다음 조건을 모두 만족해야 이 계획을 완료로 표시한다.

- 요청된 모든 도구가 공통 미리보기/✓/취소/초기화 계약을 따른다.
- 현재 미작동으로 보고된 그레인, 렌즈 흐림, 텍스트가 preview와 export에서 실제로 작동한다.
- 아웃포커스 오류가 제거되고 실패 상태가 안전하게 처리된다.
- 부분 보정이 실제 공간 mask 기반으로 동작한다.
- 피부 스무딩이 얼굴/피부가 없는 사진 전체를 임의로 보정하지 않는다.
- 프레임이 사진을 가리지 않는다.
- 드라마와 광학 유출이 정량/실기기 품질 검증을 통과한다.
- 필터 생성 시작/완료 화면에 실제 사용자 사진이 표시된다.
- 관련 white-box, widget, golden, regression test와 전체 `flutter test`, `flutter analyze`, `git diff --check`가 통과한다.

## 11. 작업 시 주의사항

- 현재 worktree의 기존 변경은 사용자 작업이므로 관련 없는 파일을 되돌리거나 삭제하지 않는다.
- 체크리스트의 기존 `[x]` 표시는 실제 재검증 전 신뢰하지 않는다. 이번 회귀 테스트 결과로 다시 판단한다.
- 모델/권한/asset이 필요한 기능은 준비되지 않은 상태에서 전역 보정으로 fallback하지 않고 안전한 no-op과 안내를 사용한다.
- preview와 export가 다른 구현을 쓰더라도 파라미터, mask 좌표, layer order, 결과 의도는 같아야 한다.
- 각 phase 완료 시 수정 파일, 테스트 명령, 결과, 남은 blocker를 이 문서 또는 별도 진행 로그에 기록한다.

## 12. 진행 로그

### 2026-08-18 — Wave 1 시작: 공통 transaction·크롭·반전·필터 기반

완료한 변경:

- 활성 도구의 초기화가 진입 전 snapshot 복원이 아니라 도구별 중립값 복원이 되도록 변경했다.
- 취소 snapshot에 텍스트 font와 브러시 mode를 추가해 취소 시 누락 없이 되돌린다.
- 도구를 바꿀 때 기존 도구를 자동 적용하지 않고 취소하도록 고정했다.
- 취소 시 진행 중인 LUT 선택 결과가 늦게 도착해 복구된 화면을 덮지 않도록 selection token을 무효화했다.
- ✓ 적용 history를 filter/crop/portrait/creative 타입으로 기록하도록 바로잡고, undo/redo 시 preset/LUT·crop·portrait·creative 상태를 함께 복원하도록 보강했다.
- `원본` crop preset의 legacy `-1` sentinel이 계산에 들어가 음수 crop size가 되는 경로를 제거했다. 원본 사진 비율을 실제 aspect-ratio lock으로 해석하며, 선택 후에도 사용자가 crop box를 이동·확대·축소할 수 있다.
- crop box 드래그 시 normalized center도 갱신하도록 수정했다.

검증:

```bash
flutter analyze lib/features/editor/editor_page.dart lib/features/editor/editor_spatial_renderer.dart test/features/editor/editor_spatial_renderer_test.dart
flutter test test/features/editor/editor_spatial_renderer_test.dart test/engine/rotate_flip_engine_test.dart test/features/editor/crop_panel_test.dart test/features/editor/rotate_flip_panel_test.dart test/features/editor/edit_session_controller_test.dart test/filter_apply_whitebox_test.dart
git diff --check
```

- 분석 결과: 컴파일 오류 없음. 기존 코드의 deprecated API/lint info는 남아 있다.
- 테스트 결과: 30개 통과.

다음 작업:

- `editor_tool_transaction_test.dart`와 `editor_back_navigation_test.dart`를 추가해 ✓/취소/reset/history를 widget 수준에서 고정한다.
- crop overlay의 실제 화면 좌표/ratio-lock drag를 widget test로 검증한다.
- 부분 보정 mask와 아웃포커스/렌즈 흐림 오류 경로를 P0 순서로 구현·검증한다.

### 2026-08-18 — Wave 1 보강: 부분 보정·블러의 안전 계약

완료한 변경:

- 선택 보정은 도구를 열기만 해도 전역 보정되는 상태를 제거했다. 사진을 탭하거나 드래그해 지점을 먼저 지정해야 활성화되고, 선택 지점과 조절값을 화면에 명확히 표시한다.
- 브러시·틸트 시프트도 실제 제스처 또는 유효한 값 변경 전에는 활성 처리하지 않는다.
- 부분 보정과 Dodge/Burn 엔진은 중립값·0 반경 입력을 원본 그대로 반환하도록 해 0 나누기/의도치 않은 전역 변경을 차단했다.
- 부분 보정은 터치 지점에서 가장 강하고 멀어질수록 감쇠하며, 지점과 색상이 크게 다른 가까운 영역도 보호하는 `공간 거리 × 색상 유사도` 마스크임을 엔진 테스트로 고정했다.
- 렌즈 흐림과 틸트 시프트는 0 반경에서 완전 no-op이며, 렌즈 흐림의 정확한 초점면은 원본 픽셀을 보존한다. 깊이 맵 크기가 잘못된 경우에도 안전하게 no-op 처리한다.

검증:

```bash
flutter analyze lib/features/editor/editor_page.dart lib/engine/blur_engine.dart test/engine/blur_engine_test.dart
flutter test test/engine/local_adjust_test.dart test/engine/blur_engine_test.dart test/features/editor/editor_spatial_renderer_test.dart test/engine/rotate_flip_engine_test.dart test/features/editor/crop_panel_test.dart test/features/editor/rotate_flip_panel_test.dart test/features/editor/edit_session_controller_test.dart test/filter_apply_whitebox_test.dart
git diff --check
```

- 분석 결과: 컴파일 error 없음. 기존 deprecated API 및 lint info 46개는 이번 범위 밖의 기존 정리 항목이다.
- 테스트 결과: 38개 통과.

다음 작업:

- text/frame/grain의 preview·export pixel test를 추가해 “도구가 실제로 보이는 결과를 내는지”를 고정한다.
- portrait segmentation 미준비 상태의 사용자 안내와 아웃포커스 실패 경로를 점검한다.

### 2026-08-18 — Wave 2: 프레임·텍스트·인물 효과의 export 계약

완료한 변경:

- 세션 재생/export 경로의 프레임도 미리보기와 똑같이 중앙을 투명화한 border overlay로 합성하게 맞췄다. 따라서 불투명 프레임 asset도 사진 중앙을 가리지 않는다.
- 프레임 경계는 실제로 덮이고 중앙 사진은 그대로 남는 픽셀 테스트를 추가했다.
- 폰트 raster layer를 사용할 수 없는 경로에서도 fallback 텍스트 렌더러가 결과 이미지에 텍스트 픽셀을 합성하는지 테스트로 확인했다.
- `EditOperationPlayer`의 중앙 타원 얼굴 fallback을 제거했다. 인물/피부 조정은 현재 이미지의 유효한 segmentation mask 없이는 원본을 유지하며, bokeh는 유효한 depth map 또는 segmentation mask가 있을 때만 적용된다.

검증 명령: `flutter analyze lib/engine/edit_operation_player.dart test/engine/no_op_guard_test.dart`, `flutter test test/engine/no_op_guard_test.dart test/engine/creative_rendering_test.dart test/engine/local_adjust_test.dart test/engine/blur_engine_test.dart`, `git diff --check`.

- 분석 결과: 오류/경고 없음.
- 테스트 결과: 31개 통과.

다음 작업:

- `editor_tool_transaction_test.dart`와 editor-level back/reset widget test를 추가한다.
- iOS 실기기에서 TextRasterizer의 한글 폰트 fallback과 프레임 asset별 보기를 확인한다.

### 2026-08-18 — 통합 회귀 확인

- `flutter test` 전체 실행: 428개 통과.
- 로컬 모델 또는 이미지 fixture가 없는 neural LUT 테스트 1개는 의도적으로 skip되었다.
- `git diff --check` 통과.

### 2026-08-18 — Wave 3: 밝은 드라마·광학 유출 품질

완료한 변경:

- 밝은 드라마의 contrast를 endpoint를 고정하는 bounded curve로 바꾸고, 양의 exposure는 하이라이트 headroom을 보존하는 roll-off로 바꿨다. 고조도 gradient에서 불필요한 255 clipping과 banding을 줄인다.
- 밝은 드라마 preset의 contrast를 재조정해 detail enhancement는 유지하면서 하이라이트 단계를 보존한다.
- 광학 유출의 warmth가 실제로 warm(적색 우세)/cool(청색 우세)로 움직이도록 색상 계수를 명시했다.
- 광학 유출의 0 no-op, 강도, 0/90/180도 방향별 energy centroid, warm/cool 색상 및 밝은 드라마의 고조도·결정성 테스트를 추가했다.

검증 명령: `flutter analyze lib/engine/artistic_effects.dart lib/engine/lut_engine.dart test/engine/drama_light_leak_quality_test.dart`, `flutter test test/engine/drama_light_leak_quality_test.dart test/engine/sprint5_style_tools_test.dart test/engine/no_op_guard_test.dart`, `git diff --check`.

- 분석 결과: 오류/경고 없음.
- 테스트 결과: 29개 통과.

다음 작업:

- 필터 생성 화면에서 최신 사진 thumbnail과 실제 Before/After 결과가 항상 보이는지 검증·보강한다.
- editor-level 취소/back/reset widget test와 iOS 실기기 성능 측정을 진행한다.

### 2026-08-18 — Wave 4: 필터 생성 실제 사진·결과 미리보기

완료한 변경:

- 필터 생성은 PhotoKit 최근 30장으로 구성한 실제 파일 경로 thumbnail strip을 사용하며, 선택된 스타일 사진 또는 pair의 Before 사진을 새 LUT 결과의 기준 source로 유지한다는 경로를 재확인했다.
- 성공 preview의 source/after 중 하나라도 생성되지 않으면 회색 Before/After 성공 카드를 띄우지 않는다. 저장은 유지하되 오류 sheet에서 미리보기 재시도를 제공한다.
- LUT 생성 후 success sheet의 After는 동일 source에 저장된 preset의 LUT/params/intensity를 실제 적용해 만든 파일이다.
- 필터 생성 화면 정적 분석을 통과했고 LUT 생성·안전성·재적용 white-box 테스트를 다시 실행했다.

검증 명령: `flutter analyze lib/features/create_filter/create_filter_page.dart`, `flutter test test/engine/personal_filter_core_test.dart test/filter_recipe_test.dart test/whitebox_lut_core_test.dart test/filter_apply_whitebox_test.dart`, `git diff --check`.

- 분석 결과: 오류/경고 없음.
- 테스트 결과: 44개 통과.
- 통합 회귀: `flutter test` 전체 431개 통과 (로컬 모델/fixture 부재 LUT 테스트 1개 skip).

다음 작업:

- PhotoKit 권한 허용/limited/빈 앨범과 실제 최근 사진 정렬은 iOS 실기기에서 확인한다.
- editor-level 취소/back/reset widget test와 preview/export parity 성능 측정을 진행한다.

### 2026-08-18 — Wave 5: 편집 화면 적용·취소·초기화 계약

완료한 변경:

- `EditorPage` 경로 위젯 테스트를 추가해 도구를 열면 상단에 `적용`, 하단에 `초기화`가 노출되고 `적용` 후 도구가 닫히는 계약을 고정했다.
- 시스템 뒤로 가기는 활성 도구를 먼저 취소하고, 활성 도구가 없을 때에만 `편집을 취소할까요?` 확인 대화상자를 보여 주는지 검증했다.
- 기본 보정의 노출값을 실제로 변경한 뒤 `초기화`를 누르면 slider 값이 정확히 중립값 `0`으로 복원되는지 검증했다.

검증 명령: `flutter test test/features/editor/editor_route_contract_test.dart`.

- 테스트 결과: 3개 통과.

### 2026-08-18 — Wave 5 통합 회귀

- `flutter test` 전체 실행: 434개 통과.
- 로컬 모델 또는 이미지 fixture가 없는 neural LUT 테스트 1개는 의도적으로 skip되었다.

다음 작업:

- 전체 Flutter 회귀 테스트와 iOS 연결 기기 탐색을 실행한다.
- 기기가 연결되어 있으면 PhotoKit 권한 상태, 텍스트/프레임 렌더링, preview/export 성능을 실기기에서 측정한다.

### 2026-08-18 — Wave 6 시작: profile 성능 harness

- `integration_test/editor_performance_test.dart`는 1920×1440 fixture에서 기본 보정 slider warm-up 5회와 30회 측정을 수행하고, device frame timing 및 원시 sample을 JSON report로 보낸다.
- `test_driver/editor_performance_driver.dart`는 host의 `PERF_OUTPUT` 경로(기본 `build/perf/editor_performance_report.json`)에 해당 report를 저장한다.
- `tool/perf_gate.dart`는 profile/release build, 기기 정보, 30개 이상의 frame/preview sample, preview cold/warm 및 export progress gate를 검사하고 실패 시 non-zero exit code를 반환한다.

실기기 실행 명령:

```bash
PERF_OUTPUT=build/perf/editor_perf_iphone.json flutter drive \
  --driver=test_driver/editor_performance_driver.dart \
  --target=integration_test/editor_performance_test.dart \
  --profile -d 00008150-000949D436F8401C \
  --dart-define=MEMORIA_PERF_BUILD_MODE=profile \
  --dart-define=MEMORIA_PERF_DEVICE_NAME='junseok의 iPhone'
dart run tool/perf_gate.dart --report build/perf/editor_perf_iphone.json --scope preview
```

이 harness는 아직 gallery 권한을 우회하지 않고 export/memory를 실제로 측정하지 않는다. 따라서 `--scope preview` 통과는 preview·frame gate만 의미하며 full release gate 통과가 아니다.

### 2026-08-18 — Wave 6 결과: iPhone profile preview 성능

- 기기: `junseok의 iPhone`, iOS 26.6 (23G71), Flutter profile mode.
- fixture: harness가 기기 임시 저장소에 생성한 1920×1440 deterministic gradient JPEG.
- warm-up 5회 후 기본 보정 노출 slider를 36회 교차 변경해 측정했다.
- 편집 steady-state frame (`build + raster`) 31개: p50 **0.601ms**, p95 **0.862ms**, p99 **0.893ms** — 16ms gate 통과.
- warm preview 36개: p50 **8.354ms**, p95 **43.599ms**, p99 **50.286ms** — 80ms gate 통과.
- cold preview: **8.776ms** — 250ms gate 통과.
- `dart run tool/perf_gate.dart --report build/perf/editor_perf_iphone.json --scope preview` 통과. `git diff --check` 통과.

남은 release blocker:

- gallery 권한이 필요한 실제 고해상도 export의 progress interval/cancel과 export memory delta는 아직 측정하지 않았다. 따라서 full performance gate 및 배포 가능성 승인을 선언하지 않는다.
- PhotoKit 권한 상태별 최근 사진, 한글 텍스트·전체 frame asset·아웃포커스/렌즈 흐림의 L5 실기기 시각 QA도 남아 있다.

### 2026-08-18 — Wave 6 보강: iPhone export 진행·취소

- 별도 3072×2304 합성 JPEG에서 노출값을 적용하고 `다른 앱으로 공유` export를 시작했다. gallery 저장 경로를 사용하지 않아 사진 라이브러리에 테스트 이미지를 남기지 않았다.
- 첫 non-zero progress 표시까지 **457.719ms**, 취소 탭 후 export overlay 해제까지 **266.456ms**였다. 두 값 모두 500ms 목표 안이다.
- `PERF-EXPORT-001`은 progress가 표시되지 않거나 cancel 후 overlay가 남으면 실패한다. 결과 JSON의 `exportCompleted: false`는 공유·저장을 완료하지 않고 안전하게 취소됐음을 뜻한다.
- `dart run tool/perf_gate.dart --report build/perf/editor_perf_iphone.json --scope export-cancel`로 이 좁은 범위를 판정한다.

남은 release blocker:

- 완료된 고해상도 export의 progress interval, 결과 checksum/parity, RSS delta는 아직 측정하지 않았다. cancel 측정 통과만으로 full export gate를 통과 처리하지 않는다.

### 2026-08-18 — L5 시각 QA 상태

- `junseok의 iPhone`에 profile 앱을 정상 빌드·설치·실행했다.
- 이 작업 환경에는 iPhone 화면 조작/캡처를 위한 Computer Use 권한이 없어, PhotoKit 권한 상태, 한글 텍스트, 전체 frame asset, 아웃포커스·렌즈 흐림의 실제 화면 QA는 자동으로 수행하지 못했다.
- 해당 권한이 허용되면 이 문서의 실기기 점검 목록 순서대로 캡처와 pass/fail evidence를 추가한다. 권한 부재를 pass로 간주하지 않는다.

### 2026-08-18 — Simulator 보강: 첫 실행 권한 UX

- iPhone 17 Pro Simulator에서 앱 기동과 홈 화면 렌더링은 확인됐지만, 수정 전 native app이 남긴 카메라 permission dialog 때문에 편집 QA를 진행할 수 없었다.
- 원인은 `AppDelegate`가 앱 활성화 때마다 camera와 Photo Library 권한을 선행 요청하는 것이었다. 이 중복 native 요청을 제거했다. 실제 카메라/사진 접근은 해당 기능이 선택될 때의 Dart permission service 및 PhotoKit 경로가 담당한다.
- 초기 상태 iPad Pro 11-inch (M5) Simulator에서 재빌드·실행해, 권한 팝업 없이 홈 화면과 태블릿 레이아웃이 정상 표시되는 것을 확인했다.
- Simulator/Xcode build는 통과했다.

### 2026-08-18 — Simulator 보강 결과: iPhone 첫 실행 재검증

- 이전 iPhone 17 Pro의 dialog state를 재사용하지 않고, 별도 초기 상태인 **iPhone 17 Pro Max Simulator**에 수정된 앱을 새로 빌드·설치했다.
- 첫 실행 홈 화면에서 카메라·사진 library 권한 dialog가 나타나지 않았다. iPhone과 iPad 양쪽 form factor에서 initial permission UX가 깨지지 않음을 확인했다.
- 이 검증은 앱 시작 시의 강제 권한 요청 제거 범위만 판정한다. 카메라 촬영/사진 선택 시의 기능별 권한 허용·거부 경로는 실기기 white-box matrix로 계속 검증한다.

### 2026-08-18 — 실기기 white-box 자동화 착수

- `integration_test/editor_whitebox_device_test.dart`를 추가했다. 앱 임시 저장소의 640×480 합성 JPEG만 사용하고, photo library 저장·공유 완료는 수행하지 않는다.
- 현재 실기기 자동 검증 대상은 `WB-ED-01` (도구 활성 중 첫 back은 취소, 두 번째 back만 exit confirmation), `WB-ED-02/06` (조정값 변경 → 초기화는 neutral → 적용은 transaction 종료), `WB-CR-01` (crop ratio 선택 및 reset의 자유 비율 복귀)이다.
- 실행 결과는 `WHITEBOX_OUTPUT`으로 지정한 JSON artifact에 pass한 white-box ID를 기록한다. 이는 전체 235개 matrix 완료를 의미하지 않으며, 다음 wave에서 필터 draft transaction, 텍스트·frame compositing, selective touch map, blur/portrait 및 PhotoKit 권한 상태를 같은 방식으로 추가한다.

### 2026-08-18 — 실기기 white-box 실행 상태

- 위 3개 시나리오는 iOS Simulator에서 production `EditorPage`와 실제 파일 fixture로 모두 통과했다.
- 연결된 `junseok의 iPhone`에 profile build의 설치·기동은 성공했다. 단, 무선 Flutter test runner의 Dart VM service 연결은 iOS **Local Network** 권한 dialog의 허용을 기다리다 중단했다. 따라서 실기기 pass artifact는 아직 생성되지 않았고, simulator 통과를 실기기 통과로 대체하지 않는다.
- 다음 실행 전 기기에서 `Memoria`의 **설정 → 개인정보 보호 및 보안 → 로컬 네트워크**를 허용하거나, 표시된 “기기 찾기 및 연결” dialog에서 **허용**한다. 가능하면 USB 연결을 사용한다. 이후 아래 명령으로 같은 test를 재개한다.

```bash
WHITEBOX_OUTPUT=build/test-results/editor/whitebox_device_iphone.json flutter drive \
  --driver=test_driver/editor_whitebox_device_driver.dart \
  --target=integration_test/editor_whitebox_device_test.dart \
  --profile -d 00008150-000949D436F8401C
```

### 2026-08-19 — iPhone Simulator white-box 결과

- 대상: **iPhone 17 Pro Max Simulator**, iOS 26.5 (23F77), Xcode simulator runtime.
- iOS Simulator는 Flutter의 profile/release AOT build를 지원하지 않으므로, UI state-contract suite는 simulator가 지원하는 **debug** mode로 실행했다. 이는 성능 수치를 실기기와 동등하게 취급하지 않는다는 뜻이며, functional white-box 판정에는 영향이 없다.
- 결과 artifact: `build/test-results/editor/whitebox_device_iphone17promax_simulator.json`.
- 통과: `WB-ED-01`, `WB-ED-02`, `WB-ED-06`, `WB-CR-01` (4/4). 즉, back/cancel exit 분기, 조정 transaction의 reset/apply, crop ratio의 reset 동작은 iPhone Simulator의 production editor 구성에서 통과했다.
- 이 결과는 카메라/PhotoKit 실제 권한, device GPU/RSS, 실제 사진 library write 또는 share completion을 포함하지 않는다. 이 항목들은 여전히 실기기 validation 범위다.
