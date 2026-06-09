# Glow Checklist

Goal: create soft highlight bloom without clipping or muddying detail.

## Priority Map
- P0: neutral no-op, highlight-safe bloom, no UI-thread blur.
- P1: threshold/warmth controls, golden coverage, export progress.
- P2: glow presets and mask preview.

## Product And UX
- [ ] Controls include strength, threshold, warmth/tint, and softness.
- [ ] Loading state is non-blocking for blur preview.
- [ ] Reset returns to neutral.
- [ ] Effect is visibly different from simple exposure/contrast.

## Real-Time And Engine
- [ ] Highlight extraction uses smooth threshold.
- [ ] Blur preview uses preview-size buffers or pyramid.
- [ ] Export uses final-quality blur.
- [ ] Blend mode and order are documented.

## Quantitative Gates
- Preview p95 <= 120ms on 960px proxy.
- Main isolate frame p95 <= 16ms during slider drag.
- Highlight clipping increase <= 1% pixels at default useful values.
- Golden tolerance SSIM >= 0.990.
- No-op mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store strength, threshold, softness, tint/warmth, schema version.
- [ ] Undo/redo restores all controls.

## Test Commands
- Required target: `flutter test test/engine/glow_engine_test.dart test/features/editor/glow_panel_test.dart test/golden/glow_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature glow`

## Accessibility, Localization, Privacy
- [ ] Sliders expose semantic values.
- [ ] Labels use localization keys.
- [ ] Blur intermediates are temporary.

## Release Blockers
- [ ] Glow clips highlights instead of blooming them.
- [ ] Blur blocks UI.
- [ ] Preview/export glow radius differs materially.
