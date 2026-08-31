# Healing Checklist

Goal: remove small distractions using texture-aware fill without visible blur patches.

## Priority Map
- P0: active healing changes output, off-main-isolate fill, no crash.
- P1: texture-aware algorithm, stroke UX, golden coverage.
- P2: source selection and advanced inpaint models.

## Product And UX
- [ ] Healing brush shows size and affected mask.
- [ ] Undo-last-stroke is immediate.
- [ ] User sees mask quickly while final fill computes.
- [ ] Result can be reset or stroke removed.
- [ ] Placeholder blur healing is hidden from production or clearly experimental.

## Real-Time And Engine
- [ ] Stroke capture never waits for fill computation.
- [ ] Fill runs in isolate.
- [ ] Production algorithm respects texture and structure: Telea/FMM, PatchMatch, or validated alternative.
- [ ] Export recomputes fill at final resolution.
- [ ] Algorithm version is stored for reproducibility.

## Quantitative Gates
- Stroke mask feedback p95 <= 16ms.
- First reduced healing preview p95 <= 250ms for small strokes.
- Main isolate frame p95 <= 16ms.
- Active non-zero heal stroke must change output in mask area mean diff >= 0.5/255.
- Golden/ML tolerance: SSIM >= 0.985 and no visible blur patch above approved threshold.

## Persistence
- [ ] Store strokes, brush size, mask data/points, algorithm version, schema version.
- [ ] Undo/redo restores strokes and computed/fallback state.

## Test Commands
- Current: 제품 경로와 품질 기준을 충족하지 못한 placeholder inpainting 구현은 제거됨.
- Required target: `flutter test test/features/editor/healing_panel_test.dart test/golden/healing_golden_test.dart`
- Required no-op: `flutter test test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature healing`

## Accessibility, Localization, Privacy
- [ ] Brush controls expose semantic labels and values.
- [ ] Labels use localization keys.
- [ ] Healing intermediates are temporary and deleted with session/cache cleanup.

## Release Blockers
- [ ] Visible healing returns original image for active strokes.
- [ ] Fill freezes UI.
- [ ] Common spot removal produces obvious blur smears.
