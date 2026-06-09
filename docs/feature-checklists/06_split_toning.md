# Split Toning Checklist

Goal: shadows and highlights can be toned independently without damaging midtones.

- [x] Define shadow, midtone, and highlight masks.
- [x] Support hue, saturation, balance, and strength.
- [x] Keep zero strength identical.
- [x] Avoid hue shifts in neutral midtones unless balance requires it.
- [x] Persist through `EditOperation.splitTone`.
- [x] Match preview and export.
- [x] Add golden tests for warm highlights, cool shadows, and balanced looks.
- [x] Add no-op guard tests.
- [x] Add performance coverage with global adjust and LUT stacked together.

## Enterprise Completion Checklist

### Product promise
- [x] Users can create cinematic color separation quickly.
- [x] Shadows and highlights feel independent, with a controllable balance point.
- [x] The feature improves mood without making neutral photos look broken.

### UX and ergonomics
- [x] Shadow and highlight color controls use hue rings or swatches.
- [x] Strength and balance controls are easy to find.
- [x] Neutral state is obvious and one-tap resettable.
- [x] Color selection gives live preview.
- [x] The panel avoids showing too many numeric controls at once.
- [x] Presets can be added later without changing the operation model.

### Real-time and performance
- [x] Split toning runs in the fast color pipeline.
- [x] Dragging hue or strength is immediate.
- [x] Balance mask is computed cheaply from luminance.
- [x] CPU preview fallback stays under the global color budget.

### Engine contract
- [x] Shadow/highlight masks are based on documented luminance curves.
- [x] Balance shifts the crossover without hard edges.
- [x] Hue application respects saturation and strength separately.
- [x] Zero strength is no-op.
- [x] Toning order relative to LUT and curves is fixed.
- [x] Highlight toning avoids clipping bright whites.

### Persistence and export
- [x] Operation stores shadow hue/saturation, highlight hue/saturation, balance, and strength.
- [x] Undo/redo restores all color choices and sliders.
- [x] Export uses identical mask curves.
- [x] Old drafts with missing fields fall back to neutral.

### Test gates
- [x] Unit: zero strength no-op, mask smoothness, balance extremes.
- [x] Golden: teal shadows, warm highlights, low-saturation film look.
- [x] Widget: color selection, strength drag, reset.
- [x] Performance: stacked with LUT, curves, and global adjust.

### Release blockers
- [x] Midtones show abrupt color boundaries.
- [x] Highlights clip or posterize.
- [x] Export tone split differs from preview.

## Priority Map
- P0: zero no-op, smooth mask, preview/export same mask curve.
- P1: clear shadow/highlight color UX, golden coverage, performance.
- P2: split-toning presets and favorite looks.

## Quantitative Gates
- Hue/strength drag: p95 frame <= 16ms GPU or p95 <= 80ms CPU preview.
- Mask smoothness: adjacent synthetic luminance steps produce p99 output jump <= 6/255.
- Golden tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- No-op: zero strength mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/features/editor/parameter_panels_test.dart`
- Required target: `flutter test test/engine/split_toning_engine_test.dart test/golden/split_toning_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature split_toning`

## Accessibility, Localization, Privacy
- [x] Shadow/highlight color controls expose semantic role, value, and selected hue.
- [x] All labels and preset names use localization keys.
- [x] Split-toning stores only numeric operation params.
