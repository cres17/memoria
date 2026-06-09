# Curves Checklist

Goal: RGB, luminance, and channel curves are editable, stable, and export-identical.

- [x] Support luminance, RGB, red, green, and blue channels.
- [x] Make selected channel visually obvious.
- [x] Prevent control points from crossing in invalid ways.
- [x] Bake curve lookup tables once per edit state.
- [x] Use the same baked curve tables in preview and export.
- [x] Commit one curve operation when editing ends.
- [x] Round-trip curves through JSON.
- [x] Add identity curve tests.
- [x] Add channel-isolation tests.
- [x] Add golden tests for S-curve and per-channel color casts.

## Enterprise Completion Checklist

### Product promise
- [x] Advanced users can shape tones precisely without fighting the editor.
- [x] Casual users can apply simple contrast curves through presets or safe defaults.
- [x] Luminance, RGB, red, green, and blue channels are understandable at a glance.

### UX and ergonomics
- [x] Channel buttons have strong selected/unselected contrast.
- [x] The graph has visible grid lines and a diagonal identity reference.
- [x] Control points are large enough to drag on touch screens.
- [x] Dragging a point clamps to valid x/y bounds.
- [x] Points cannot cross in ways that produce invalid lookup tables.
- [x] Double-tap point resets/removes it where appropriate.
- [x] Reset channel and reset all actions are available.
- [x] The panel does not require text instructions to be usable.

### Real-time and performance
- [x] Dragging a point updates a baked 1D LUT, not a per-pixel spline calculation.
- [x] GPU preview samples curve textures for compatible paths.
- [x] CPU preview receives pre-baked lookup tables.
- [x] Curve texture rebuilds happen only when a curve changes.
- [x] Dragging remains live on mid-range devices.

### Engine contract
- [x] Curve interpolation algorithm is fixed and documented.
- [x] Lookup table resolution is defined, ideally 1024 samples or enough to avoid banding.
- [x] Luminance curve behavior relative to RGB curve is documented.
- [x] Channel curves preserve alpha and do not corrupt non-color channels.
- [x] Identity curve produces no change.
- [x] Curves are applied in a defined order relative to LUT and global adjust.

### Persistence and export
- [x] Curve control points serialize with channel names and schema version.
- [x] Undo/redo restores selected channel and point positions.
- [x] Draft restore rebuilds baked LUTs before first preview.
- [x] Export uses the same baked curve logic as preview.

### Test gates
- [x] Unit: identity, monotonic point order, interpolation samples.
- [x] Unit: red channel curve changes red more than green/blue.
- [x] Widget: channel selection, point drag, reset.
- [x] Golden: S-curve, matte fade, red lift, blue shadows.
- [x] Performance: continuous point drag.

### Release blockers
- [x] Channel selection is visually ambiguous.
- [x] Export uses different curve math than preview.
- [x] Invalid point order can crash or produce NaN.

## Priority Map
- P0: identity no-op, valid point constraints, preview/export same baked LUT.
- P1: channel visibility, JSON round-trip, golden coverage.
- P2: curve presets, multi-point gestures, advanced grid options.

## Quantitative Gates
- Point drag: p95 frame <= 16ms when using baked LUT/GPU path.
- Bake time: p95 <= 8ms for 1024-sample LUT.
- Golden tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- Export parity: same baked LUT hash or equivalent serialized curve state.
- No-op: identity curves mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/whitebox_curve_data_test.dart test/features/editor/parameter_panels_test.dart`
- Required target: `flutter test test/features/editor/curve_editor_test.dart test/golden/curves_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature curves`

## Accessibility, Localization, Privacy
- [x] Channel buttons expose semantic selected state and localized labels.
- [x] Graph control points are reachable with touch targets >= 44px or equivalent hit slop.
- [x] Curve data persists only as numeric operation params, not image-derived private data.
