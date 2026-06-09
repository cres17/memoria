# Selective Checklist

Goal: local point-based edits target spatial/color regions without manual brushing.

## Priority Map
- P0: visible active op changes output, mask correctness, undo/redo.
- P1: LAB/color-similarity mask, point editing UX, golden coverage.
- P2: auto-subject selection and mask preview.

## Product And UX
- [ ] User can add, move, resize, duplicate, and delete selective points.
- [ ] Active point is visually clear.
- [ ] Local controls include brightness, contrast, saturation, and optional structure.
- [ ] Radius/feather adjustment gives immediate visual feedback.
- [ ] Unsupported state is hidden or disabled honestly.

## Real-Time And Engine
- [ ] Mask uses spatial distance and color similarity, preferably CIELAB.
- [ ] Mask feather avoids hard circular edges.
- [ ] Multiple points blend predictably.
- [ ] Moving radius updates preview interactively.
- [ ] Mask computation is optimized or isolated when expensive.

## Quantitative Gates
- Point move/radius drag p95 <= 80ms preview.
- Mask edge smoothness p99 adjacent jump <= 6/255 on synthetic fixtures.
- Active non-zero op must produce mean diff >= 0.5/255 within mask area.
- Export parity mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: zero local params mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store points, radius, feather/mode, adjustments, schema version.
- [ ] Undo/redo restores point list and selected point.

## Test Commands
- Required target: `flutter test test/engine/selective_engine_test.dart test/features/editor/selective_panel_test.dart test/golden/selective_golden_test.dart`
- Required no-op: `flutter test test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature selective`

## Accessibility, Localization, Privacy
- [ ] Point controls expose semantic selected/move/delete actions where practical.
- [ ] Labels use localization keys.
- [ ] Selective stores local numeric point data only.

## Release Blockers
- [ ] Visible selective control does nothing.
- [ ] Mask has hard, obvious circular edges.
- [ ] Export ignores selective points.
