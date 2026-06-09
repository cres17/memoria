# Rotate And Flip Checklist

Goal: straighten, rotate, and flip are instant, precise, and reversible.

## Priority Map
- P0: correct orientation, preview/export parity, undo/redo.
- P1: fine straighten control, active flip state, golden coverage.
- P2: auto-straighten and horizon detection.

## Product And UX
- [x] Rotate slider supports fine control and neutral reset.
- [x] 90-degree rotate and horizontal/vertical flip use icons with clear active state.
- [x] Canvas remains centered and does not jump during adjustment.
- [x] Background fill behavior is predictable.

## Real-Time And Engine
- [x] Preview uses GPU transform or matrix transform where possible.
- [x] Final resampling happens on commit/export.
- [x] EXIF orientation is baked or normalized before operations.
- [x] Transform order relative to crop and perspective is documented.

## Quantitative Gates
- Rotation drag p95 frame <= 16ms.
- 90-degree rotate/flip response p95 <= 50ms preview.
- Export parity: transformed reference differs by <= 1 pixel alignment tolerance.
- No-op: rotation 0 and no flip mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [x] Store rotation degrees, flipH, flipV, schema version.
- [x] Undo/redo restores slider and active flip buttons.

## Test Commands
- Required target: `flutter test test/engine/rotate_flip_engine_test.dart test/features/editor/rotate_flip_panel_test.dart test/golden/rotate_flip_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature rotate_flip`

## Accessibility, Localization, Privacy
- [x] Icon-only buttons have semantic labels and tooltips.
- [x] Degree values are localized/formatted.
- [x] Only numeric transform params persist locally.

## Release Blockers
- [x] EXIF orientation causes double rotation.
- [x] Flip state is visually ambiguous.
- [x] Export transform differs from preview.
