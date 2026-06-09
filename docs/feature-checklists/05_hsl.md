# HSL Checklist

Goal: hue, saturation, and luminance edits affect the intended color ranges only.

- [x] Define exact hue bands and feather widths.
- [x] Support H, S, and L controls per band.
- [x] Prevent hue wrap bugs around red.
- [x] Preserve neutrals unless saturation or luminance explicitly targets them.
- [x] Commit changes through `EditOperation.hslAdjust`.
- [x] Make preview and export use the same color conversion.
- [x] Add tests for red wraparound, skin tones, greens, blues, and neutrals.
- [x] Add no-op and non-identity tests.
- [x] Add golden tests for realistic photos.

## Enterprise Completion Checklist

### Product promise
- [x] Users can target a specific color range without damaging the whole photo.
- [x] Common edits are easy: greener foliage, bluer sky, warmer skin, muted reds.
- [x] The tool feels precise but not intimidating.

### UX and ergonomics
- [x] Color bands use swatches, not only text labels.
- [x] Selected color band is visually obvious.
- [x] Hue, saturation, and luminance controls are grouped per selected band.
- [x] A reset action exists per band and for all bands.
- [x] Skin-sensitive ranges have conservative defaults.
- [x] The panel remains compact enough for repeated use.
- [x] Band order follows the color wheel.

### Real-time and performance
- [x] HSL preview runs on GPU or optimized CPU without full export work.
- [x] Hue-band masks are computed procedurally, not stored per-pixel unless needed.
- [x] Dragging a slider updates within the same frame path as global color controls where possible.
- [x] Stale CPU previews are canceled.

### Engine contract
- [x] Hue wrap around red is explicitly handled.
- [x] Band center, width, and feather are defined in code and tests.
- [x] Saturation changes do not colorize true neutrals unless designed.
- [x] Luminance changes avoid clipping and posterization.
- [x] HSL conversion is consistent between preview and export.
- [x] Overlapping bands blend smoothly.

### Persistence and export
- [x] HSL data serializes as per-band H/S/L values.
- [x] Undo/redo restores selected band and all values.
- [x] Draft restore handles missing bands from older schema versions.
- [x] Export uses the same band definitions as preview.

### Test gates
- [x] Unit: red wrap, neutral preservation, band feather.
- [x] Golden: sky, foliage, skin, product red, mixed neon colors.
- [x] Widget: swatch selection, reset band, reset all.
- [x] No-op: all zero values no-op.
- [x] Performance: rapid per-band slider changes.

### Release blockers
- [x] Red hue edits break at 0/360 degrees.
- [x] Skin tones shift unexpectedly during unrelated color edits.
- [x] Preview and export use different HSL conversion.

## Priority Map
- P0: red wrap correctness, neutral no-op, preview/export same bands.
- P1: swatch UX, golden coverage for skin/sky/foliage, performance budget.
- P2: band presets, visual mask preview, advanced feather controls.

## Quantitative Gates
- Slider drag: p95 frame <= 16ms GPU or p95 <= 80ms CPU preview.
- Hue band feather: no hard boundary larger than 4/255 p99 diff at band edges in synthetic tests.
- Golden tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- No-op: all H/S/L zero mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/features/editor/parameter_panels_test.dart test/whitebox_color_utils_test.dart`
- Required target: `flutter test test/engine/hsl_engine_test.dart test/golden/hsl_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature hsl`

## Accessibility, Localization, Privacy
- [x] Color swatches expose localized color names and selected state.
- [x] H/S/L labels and band names use localization keys.
- [x] HSL stores only numeric operation params.
