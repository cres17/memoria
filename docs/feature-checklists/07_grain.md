# Grain Checklist

Goal: add intentional, deterministic film grain without making the image feel noisy or cheap.

## Priority Map
- P0: deterministic grain seed, neutral no-op, preview/export parity.
- P1: strength/size/roughness/color controls, golden coverage, bounded cache.
- P2: film stock presets, favorite grain profiles.

## Product And UX
- [x] Grain has clear controls for strength, size, roughness, and mono/color.
- [x] Default grain is off and one-tap resettable.
- [x] Grain remains visible enough in preview without requiring export.
- [x] Grain controls are separate from noise reduction controls.
- [x] User can compare before/after while grain is active.

## Real-Time And Engine
- [x] Grain generation uses a stable seed based on session/image and stored operation seed.
- [x] Preview uses shader/procedural texture or cached preview-size noise.
- [x] Grain scale is resolution-aware so export texture matches preview intent.
- [x] Mono grain affects luminance; color grain channel behavior is documented.
- [x] Operation order relative to LUT, details, and vignette is documented.

## Quantitative Gates
- Preview drag p95 <= 16ms GPU path or <= 80ms CPU path.
- Export parity after downsample: mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: strength 0 mean diff <= 0.25/255, max diff <= 2/255.
- Determinism: same session params produce byte-identical generated grain texture.
- Memory: preview grain cache RSS delta <= 32MB.

## Persistence
- [x] Store strength, size, roughness, mono/color, seed, and schema version.
- [x] Undo/redo restores grain pattern and controls.
- [x] Draft restore does not regenerate a different pattern.

## Test Commands
- Required target: `flutter test test/engine/grain_engine_test.dart test/golden/grain_golden_test.dart`
- Required no-op: `flutter test test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature grain`

## Accessibility, Localization, Privacy
- [x] Sliders expose semantic value, min, max, and reset.
- [x] Labels and preset names use localization keys.
- [x] Grain persists only numeric params and seed, no source image data.

## Release Blockers
- [x] Grain changes randomly after restart, undo/redo, or export.
- [x] Grain strength 0 changes the image.
- [x] Grain drag blocks the UI.
