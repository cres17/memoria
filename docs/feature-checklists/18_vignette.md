# Vignette Checklist

Goal: guide attention with controllable, center-aware edge darkening/brightening.

## Priority Map
- P0: neutral no-op, center/strength correctness, export parity.
- P1: feather/inner brightness controls, GPU path, golden coverage.
- P2: custom center drag and vignette presets.

## Product And UX
- [ ] Controls include strength, feather, inner brightness, and center when supported.
- [ ] Reset returns to neutral.
- [ ] Effect remains subtle at default useful values.
- [ ] Center control does not obscure the subject.

## Real-Time And Engine
- [ ] Vignette runs in shader/GPU path where possible.
- [ ] Mask formula is center-aware and documented.
- [ ] Zero strength is no-op.
- [ ] Order relative to LUT/curves is fixed.

## Quantitative Gates
- Slider drag p95 frame <= 16ms GPU path.
- Golden tolerance mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- No-op mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store strength, feather, inner brightness, center, schema version.
- [ ] Undo/redo restores center and sliders.

## Test Commands
- Required target: `flutter test test/engine/vignette_engine_test.dart test/features/editor/vignette_panel_test.dart test/golden/vignette_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature vignette`

## Accessibility, Localization, Privacy
- [ ] Sliders and center control expose semantic labels.
- [ ] Labels use localization keys.
- [ ] Only numeric params persist.

## Release Blockers
- [ ] Vignette cannot be reset to true neutral.
- [ ] Center or strength differs in export.
- [ ] Default useful value looks cheap or overly dark.
