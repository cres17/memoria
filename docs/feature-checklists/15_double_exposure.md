# Double Exposure Checklist

Goal: blend a second image with predictable modes, opacity, alignment, and export parity.

## Priority Map
- P0: missing-file safety, blend formula correctness, export parity.
- P1: compact picker UX, preview cache, golden coverage.
- P2: transform controls for blend image and blend presets.

## Product And UX
- [ ] Blend image picker is compact and recoverable.
- [ ] Selected blend image shows thumbnail/name and remove action.
- [ ] Blend mode picker uses readable localized names.
- [ ] Opacity is visible when a blend image is selected.
- [ ] Missing external file shows recoverable state.

## Real-Time And Engine
- [ ] Blend image bytes are cached by path.
- [ ] Preview uses preview-sized blend image.
- [ ] Export loads final asset once.
- [ ] Scaling/crop/fit mode is documented.
- [ ] Blend formulas are tested.

## Quantitative Gates
- Blend mode/opacity change p95 <= 80ms on 960px proxy.
- Cached blend preview p95 <= 50ms for opacity-only updates.
- Export parity mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: opacity 0 or no image mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store external path, mode, opacity, fit/transform, schema version.
- [ ] Undo/redo restores blend state.
- [ ] Missing path fallback is deterministic.

## Test Commands
- Required target: `flutter test test/engine/blend_modes_test.dart test/features/editor/double_exposure_panel_test.dart test/golden/double_exposure_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature double_exposure`

## Accessibility, Localization, Privacy
- [ ] Picker, remove, mode, and opacity controls have semantic labels.
- [ ] Blend mode names use localization keys.
- [ ] External image path stays local and is removable with session/custom data.

## Release Blockers
- [ ] Missing blend image crashes preview or export.
- [ ] Preview and export use different scaling/blend formula.
- [ ] Picker dominates panel layout.
