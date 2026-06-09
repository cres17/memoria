# Halation Checklist

Goal: add highlight halation using thresholded bloom without contaminating non-highlight areas.

## Priority Map
- P0: threshold mask correctness, neutral no-op, export parity.
- P1: spread/tint controls, golden coverage, blur performance.
- P2: film stock halation presets.

## Product And UX
- [ ] Controls include threshold, spread, tint, and strength.
- [ ] Tint uses swatches or compact color picker.
- [ ] Reset returns to neutral.
- [ ] Low strength affects only highlights.

## Real-Time And Engine
- [ ] Mask comes from luminance/highlight threshold with smooth feather.
- [ ] Spread radius scales with image size.
- [ ] Blur preview uses preview-size buffers.
- [ ] Export uses final-quality blur.
- [ ] Order relative to LUT/grain is documented.

## Quantitative Gates
- Preview p95 <= 120ms on 960px proxy.
- Main isolate frame p95 <= 16ms during controls.
- Non-highlight contamination at low strength: mean diff <= 1/255 for pixels below threshold margin.
- Golden tolerance SSIM >= 0.990.
- No-op mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store threshold, spread, tint, strength, schema version.
- [ ] Undo/redo restores all controls.

## Test Commands
- Required target: `flutter test test/engine/halation_engine_test.dart test/features/editor/halation_panel_test.dart test/golden/halation_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature halation`

## Accessibility, Localization, Privacy
- [ ] Controls expose semantic values and localized labels.
- [ ] Tint swatches have localized color names.
- [ ] Processing intermediates are temporary.

## Release Blockers
- [ ] Halation changes shadows heavily at low strength.
- [ ] Blur freezes UI.
- [ ] Export spread differs from preview.
