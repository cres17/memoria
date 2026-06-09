# Brush Checklist

Goal: local brush edits are accurate, editable, real-time, and export-identical.

## Priority Map
- P0: coordinate correctness, overlay alignment, undo/redo, export parity.
- P1: compact mask storage, eraser, golden coverage, large-stroke performance.
- P2: stylus pressure, brush presets, mask view mode.

## Product And UX
- [ ] Brush supports exposure, saturation, temperature, clarity, and eraser.
- [ ] Active brush radius is visible before and during stroke.
- [ ] Size, hardness, opacity/strength controls are reachable with one hand.
- [ ] Zoom/pan mode and paint mode do not conflict.
- [ ] Clear and undo-last-stroke actions are available.

## Real-Time And Engine
- [ ] Touch overlay updates at touch rate without waiting for image processing.
- [ ] Brush coordinates are normalized to image space.
- [ ] Mask rasterization accounts for zoom, pan, crop, rotation, and export scale.
- [ ] Strokes flatten/tile when replay cost grows.
- [ ] Eraser subtracts deterministically from mask.

## Quantitative Gates
- Stroke overlay latency p95 <= 16ms.
- Preview recomposition p95 <= 120ms after stroke end on 960px proxy.
- 100 strokes replay p95 <= 250ms preview and does not exceed 128MB RSS delta.
- Export parity: mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: empty mask mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store tool, size, hardness, opacity, points, mask version, and schema version.
- [ ] Undo/redo restores stroke list and active tool.
- [ ] Draft restore rebuilds overlay before input.

## Test Commands
- Current: `flutter test test/features/editor/edit_session_controller_test.dart`
- Required target: `flutter test test/engine/brush_engine_test.dart test/features/editor/brush_toolbar_test.dart test/golden/brush_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature brush`

## Accessibility, Localization, Privacy
- [ ] Tool buttons expose semantic selected state and localized names.
- [ ] Brush-only gestures have keyboard/switch-access fallback actions where practical.
- [ ] Brush strokes persist as local numeric/mask data and can be deleted with session.

## Release Blockers
- [ ] Brush overlay misaligns after zoom, crop, rotation, or export.
- [ ] Touch input waits for image recomposition.
- [ ] Eraser or undo loses user work.
