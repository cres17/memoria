# Perspective Checklist

Goal: perspective correction uses real geometry, feels live, and does not misrepresent skew as premium perspective.

## Priority Map
- P0: documented transform, preview/export parity, no crash on extreme values.
- P1: real homography, touch handles, golden coverage.
- P2: auto-perspective suggestions.

## Product And UX
- [x] Horizontal and vertical perspective controls are clearly distinguished.
- [ ] Four-corner handles are required before calling the tool enterprise-grade perspective.
- [x] Reset returns to neutral instantly.
- [ ] Canvas shows clipped/fill areas clearly.

## Real-Time And Engine
- [x] Preview uses matrix/homography transform at interactive frame rate.
- [x] Final export uses full-resolution resampling.
- [x] If using shear approximation temporarily, UI and docs label it honestly.
- [x] Straight lines are preserved by the homography path.

## Quantitative Gates
- Drag p95 frame <= 16ms for matrix preview.
- Export transform alignment tolerance <= 1.5 pixels on synthetic grid.
- No-op: neutral perspective mean diff <= 0.25/255, max diff <= 2/255.
- Golden tolerance: grid SSIM >= 0.995 for deterministic perspective fixtures.

## Persistence
- [x] Store corner points or transform values with schema version.
- [x] Undo/redo restores handles and values.
- [x] Draft restore recovers future/legacy transform fields safely.

## Test Commands
- Current related: `flutter test test/engine/sprint5_test.dart`
- Required target: `flutter test test/engine/perspective_engine_test.dart test/features/editor/perspective_panel_test.dart test/golden/perspective_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature perspective`

## Accessibility, Localization, Privacy
- [ ] Handles expose semantic move actions where practical.
- [x] Direction labels and reset text use localization keys.
- [x] Only numeric geometry params persist.

## Release Blockers
- [x] Tool is marketed as perspective while only doing undocumented shear.
- [x] Straight lines bend or warp unexpectedly.
- [x] Export and preview use different transforms.
