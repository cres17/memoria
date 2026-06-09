# Portrait Checklist

Goal: portrait edits improve people naturally, with ML acceleration when available and safe fallback when not.

## Priority Map
- P0: no crash without models/faces, conservative defaults, export parity.
- P1: cached segmentation/depth, golden coverage, model-load performance.
- P2: advanced face controls and per-person selection.

## Product And UX
- [ ] Controls include smoothing, spotlight, skin tone, bokeh, and head pose only when supported.
- [ ] Model loading/unavailable states are non-blocking and honest.
- [ ] No-face cases remain editable and do not show broken masks.
- [ ] Reset all portrait edits is available.
- [ ] Skin tone choices use swatches or short localized names.

## Real-Time And Engine
- [ ] Segmentation/depth loads asynchronously and is cached per source/geometry state.
- [ ] Slider drag reuses cached masks; ML does not rerun per drag tick.
- [ ] Fallback mask is deterministic.
- [ ] Bokeh uses edge-aware subject preservation.
- [ ] Export recomputes/resizes masks consistently after geometry transforms.

## Quantitative Gates
- Cached portrait slider p95 <= 80ms on 960px proxy.
- First model result p95 <= 1500ms or non-blocking unavailable state.
- Main isolate frame p95 <= 16ms during slider drag.
- Golden tolerance for ML/fallback paths: SSIM >= 0.985 with approved mask fixtures.
- No-op: all portrait values neutral mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store numeric portrait params independent of cached model outputs.
- [ ] Undo/redo restores sliders and selected skin tone.
- [ ] Draft/session restore can work without persisted masks.

## Test Commands
- Current: `flutter test test/whitebox_portrait_engine_test.dart test/neural_lut_predictor_test.dart`
- Required target: `flutter test test/features/editor/portrait_panel_test.dart test/golden/portrait_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature portrait`

## Accessibility, Localization, Privacy
- [ ] All controls expose semantic labels and values.
- [ ] Face/skin/bokeh labels use localization keys.
- [ ] Segmentation/depth maps remain local temporary data unless explicitly cached with deletion path.

## Release Blockers
- [ ] Missing ML model crashes or disables the editor.
- [ ] Default smoothing creates plastic skin.
- [ ] Bokeh visibly cuts into face/hair in common cases.
