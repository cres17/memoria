# Details Checklist

Goal: sharpen, clarity, and structure are real image-processing tools, not duplicated contrast sliders.

- [x] Define separate algorithms for sharpen, clarity, and structure.
- [x] Preserve edges without amplifying skin noise excessively.
- [x] Run heavy detail work off the main isolate.
- [x] Keep zero values visually identical to input.
- [x] Add strength curves that avoid clipping at high values.
- [x] Add preview debounce and cancellation for rapid dragging.
- [x] Persist parameters through `AdjustParams` or a dedicated operation.
- [x] Add golden tests for portrait, landscape, low-light, and high-noise images.
- [x] Add no-op guard and non-identity tests.
- [x] Add performance gate for 960px preview and full export.

## Enterprise Completion Checklist

### Product promise
- [x] The user can make a photo feel sharper without creating crunchy halos.
- [x] "Details" clearly separates sharpen, clarity, and structure.
- [x] The feature improves texture in landscapes/products while protecting skin by default.
- [x] Negative or low values do not accidentally blur the entire image unless explicitly designed.

### UX and ergonomics
- [x] Panel includes concise controls: Sharpen, Structure, Clarity, and optional Protect Skin.
- [x] Each slider has neutral reset and before/after compare support.
- [x] The user sees a small loading indicator only for CPU-heavy preview, not full-screen blocking.
- [x] The panel explains unavailable acceleration through disabled state, not an error.
- [x] Detail controls are visually grouped away from global contrast controls.

### Real-time and performance
- [x] Drag preview uses a lower-resolution proxy image for CPU detail effects.
- [x] Detail preview work runs in `compute` or another isolate.
- [x] New drag values cancel older isolate results using render tokens.
- [x] Preview debounce target is 70-100ms.
- [x] Full-resolution export can take longer but reports progress.
- [x] Memory allocations are bounded: no unbounded intermediate pyramids during drag.

### Engine contract
- [x] Sharpen uses unsharp masking or equivalent with documented radius and threshold.
- [x] Structure uses local contrast/high-pass behavior distinct from sharpen.
- [x] Clarity targets mid-frequency contrast and avoids clipping.
- [x] Edge halos are limited by thresholding or mask feathering.
- [x] Skin/noise protection uses luminance/chroma heuristics or a segmentation mask when available.
- [x] Zero value is exactly no-op or within lossless encode/decode tolerance.
- [x] Algorithms are deterministic for golden testing.

### Persistence and export
- [x] Detail values are serialized with versioned field names.
- [x] Undo/redo restores values and any protect-skin option.
- [x] Draft restore does not trigger duplicate heavy renders.
- [x] Export applies detail at final resolution using the same algorithm family as preview.
- [x] Export order relative to LUT, curves, and grain is documented and tested.

### Test gates
- [x] Unit: neutral values no-op.
- [x] Unit: high sharpen increases edge contrast but not flat-region noise excessively.
- [x] Golden: portrait skin, hair, foliage, architecture, night noise.
- [x] Regression: halo around high-contrast edge stays under threshold.
- [x] Performance: 960px preview under budget and no main-isolate blocking.

### Release blockers
- [x] Sharpen/structure are aliases of the same code path without documented difference.
- [x] Detail tool makes faces visibly worse at default useful values.
- [x] CPU preview blocks the slider.

## Priority Map
- P0: separate algorithms, neutral no-op, no UI-thread heavy processing.
- P1: halo suppression, skin/noise protection, golden coverage.
- P2: protect-skin toggle, advanced radius/threshold controls.

## Quantitative Gates
- Preview response: p95 <= 120ms on 960px proxy; no main-isolate frame > 24ms caused by detail processing.
- Export: progress for runs > 1s; full-resolution processing off UI thread.
- Halo regression: p99 edge overshoot increase <= 6/255 on high-contrast fixtures.
- Golden tolerance: mean diff <= 2/255, p99 <= 12/255, SSIM >= 0.990.
- No-op: sharpen/clarity/structure zero mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/whitebox_integrated_pipeline_test.dart test/engine/no_op_guard_test.dart`
- Required target: `flutter test test/engine/details_engine_test.dart test/golden/details_golden_test.dart test/features/editor/details_panel_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature details`

## Accessibility, Localization, Privacy
- [x] Sliders expose semantic values and reset actions.
- [x] Labels for Sharpen, Structure, Clarity, and Protect Skin use localization keys.
- [x] No additional user image data is persisted beyond operation params.
