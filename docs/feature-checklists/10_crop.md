# Crop Checklist

Goal: crop framing is precise, touch-friendly, reversible, and export-safe.

## Priority Map
- P0: correct crop rect math, touch handles, preview/export same framing.
- P1: ratio presets, reset/cancel/apply flow, golden coverage.
- P2: composition grid variants and saved crop presets.

## Product And UX
- [ ] Support free, original, square, common social, and print-like ratios.
- [ ] Crop handles have >= 44px hit targets or equivalent hit slop.
- [ ] Crop box remains visible and centered on small screens.
- [ ] Reset restores full image.
- [ ] User can cancel temporary crop mode without committing.

## Real-Time And Engine
- [ ] Dragging crop handles uses matrix/clip preview at 60fps.
- [ ] Final resampling happens on commit/export, not every drag tick.
- [ ] Crop rect stores normalized bounds and ratio.
- [ ] Crop applies before color/effect operations.

## Quantitative Gates
- Handle drag p95 frame <= 16ms.
- Commit preview update p95 <= 80ms.
- Export parity framing: crop rect difference <= 1 output pixel per edge after scaling.
- No-op: full-image crop mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store ratio, normalized rect/center, schema version.
- [ ] Undo/redo restores crop box and selected ratio.
- [ ] Draft restore shows crop overlay before first input.

## Test Commands
- Required target: `flutter test test/engine/crop_engine_test.dart test/features/editor/crop_panel_test.dart test/golden/crop_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature crop`

## Accessibility, Localization, Privacy
- [ ] Ratio buttons expose localized labels and selected state.
- [ ] Handles have semantic increase/decrease/move actions where practical.
- [ ] Crop persists only numeric geometry params.

## Release Blockers
- [ ] Preview and export crop different pixels.
- [ ] Handles are unusable at 320px width.
- [ ] Crop can permanently lose image data before export/session commit.
