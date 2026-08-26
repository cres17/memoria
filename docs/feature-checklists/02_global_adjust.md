# Global Adjust Checklist

Goal: base tuning controls behave predictably across GPU preview, CPU preview, export, and sessions.

- [x] Cover exposure, contrast, saturation, temperature, tint, highlights, shadows, ambiance, tonal shadows, tonal midtones, and tonal highlights.
- [x] Define exact min, max, default, and display unit for every slider.
- [x] Use GPU preview for shader-compatible controls.
- [x] Use CPU fallback only for controls that require pixel-level processing.
- [x] Commit one operation on slider end, not on every drag tick.
- [x] Keep draft values, `EditSession`, undo/redo, and export in sync.
- [x] Add no-op tests for zero values.
- [x] Add non-zero output-difference tests for every slider.
- [x] Add golden tests for mixed slider combinations.
- [x] Add performance gate for rapid slider dragging.

## Enterprise Completion Checklist

### Product promise
- [x] The user can make a photo brighter, richer, cooler/warmer, and more balanced without opening advanced tools.
- [x] The default control order matches user intent: light, contrast, color, detail, tone.
- [x] Every slider name maps to a visible photographic concept, not engine terminology.
- [x] The tool works well on portraits, food, landscapes, indoor shots, and screenshots.

### UX and ergonomics
- [x] Sliders show current value, neutral marker, and reset affordance.
- [x] Dragging a slider updates the image continuously.
- [x] Releasing a slider commits exactly one undo step.
- [x] Double-tap or reset returns a slider to neutral without affecting others.
- [x] Numeric ranges are consistent: either percentage-like or photographic units, not mixed without labels.
- [x] Advanced controls can be collapsed if the panel becomes too dense.
- [x] Controls never overflow on 320px-wide devices.
- [x] The user can compare before/after while holding or tapping compare.

### Real-time and performance
- [x] Exposure, contrast, saturation, temperature, tint, highlights, shadows, tonal zones, and curves run through GPU preview when possible.
- [x] CPU-only controls are debounced with a target of 70-80ms.
- [x] Slider drag never calls final export-quality processing on the main isolate.
- [x] Pending preview work is canceled when a newer slider value arrives.
- [x] GPU texture rebuilds happen only when curves/LUTs actually change.
- [x] Main isolate frame time remains under 16ms during GPU-compatible slider drag.

### Engine contract
- [x] Exposure uses a documented EV mapping.
- [x] Contrast preserves mid-gray according to a defined pivot.
- [x] Saturation handles near-gray pixels without color speckling.
- [x] Temperature/tint avoids clipping by using a bounded color adaptation curve.
- [x] Highlights/shadows protect already-clipped regions from harsh halos.
- [x] Ambiance/local tone behavior is defined separately from contrast.
- [x] All operations document whether they run in sRGB or linearized space.
- [x] Operation order is fixed and tested.

### Persistence and export
- [x] Adjustment state lives in `AdjustParams` and/or a single `EditOperation.globalAdjust`.
- [x] Draft save includes every slider value.
- [x] Undo/redo restores panel slider positions and preview.
- [x] Export receives the same `AdjustParams.cacheKey` equivalent as preview.
- [x] A new image starts from neutral values unless an initial preset is explicitly passed.

### Test gates
- [x] Unit: each slider neutral is no-op.
- [x] Unit: each non-zero slider changes expected pixel statistics.
- [x] Widget: drag preview callback and commit callback are separate.
- [x] Golden: mixed realistic edits on portrait, landscape, low-light, and high-key images.
- [x] Performance: 100 rapid slider updates without dropped async state.

### Release blockers
- [x] Slider drag feels delayed or freezes the UI.
- [x] Undo stack gets one entry per drag tick.
- [x] Export result differs materially from preview.
- [x] Any slider has a label the user cannot map to a visible result.

## Priority Map
- P0: neutral no-op, one undo entry per committed drag, preview/export parity.
- P1: GPU fast path, all slider ranges documented, golden coverage.
- P2: collapsible advanced group, richer presets, extra display units.

## Quantitative Gates
- GPU-compatible slider drag: p95 frame <= 16ms.
- CPU fallback response: p95 <= 80ms after debounce on 960px proxy.
- Commit policy: one `EditOperation.globalAdjust` per completed drag.
- Golden tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- No-op: all neutral sliders mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/features/editor/adjust_slider_test.dart test/features/editor/editor_render_recipe_test.dart`
- Current engine: `flutter test test/whitebox_integrated_pipeline_test.dart test/whitebox_color_utils_test.dart`
- Required target: `flutter test test/golden/global_adjust_golden_test.dart test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature global_adjust`

## Accessibility, Localization, Privacy
- [x] Every slider has semantic label, value, min, max, and reset action.
- [x] All visible slider names and units use localization keys and fit at 320px width.
- [x] Drafted adjustment values are local-only and removable with editor draft/session deletion.
