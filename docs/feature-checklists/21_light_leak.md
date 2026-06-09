# Light Leak Checklist

Goal: add controllable film light leaks that are subtle by default and deterministic after save.

## Priority Map
- P0: deterministic saved output, neutral no-op, missing asset fallback.
- P1: texture thumbnails, transform controls, golden coverage.
- P2: randomized variants and favorite leak packs.

## Product And UX
- [ ] Texture/style selection uses thumbnails.
- [ ] Position, rotation, scale, tint, and strength are controllable.
- [ ] Randomize is explicit and seeded only after user applies it.
- [ ] Reset returns to neutral.
- [ ] Default strength is subtle.

## Real-Time And Engine
- [ ] Leak overlays are cached and preview-sized.
- [ ] Transform preview uses GPU-friendly path when possible.
- [ ] Blend mode is documented, typically screen/additive.
- [ ] Export uses high-quality sampling.

## Quantitative Gates
- Transform drag p95 frame <= 16ms.
- Texture switch cached p95 <= 50ms, cold p95 <= 150ms.
- Export parity mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op strength 0 mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store texture id, transform, strength, tint, seed, schema version.
- [ ] Undo/redo and draft restore keep the same randomized variant.

## Test Commands
- Required target: `flutter test test/engine/light_leak_engine_test.dart test/features/editor/light_leak_panel_test.dart test/golden/light_leak_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature light_leak`

## Accessibility, Localization, Privacy
- [ ] Texture choices expose localized labels and selected state.
- [ ] UI labels use localization keys.
- [ ] Only selected asset id and transform params persist.

## Release Blockers
- [ ] Saved leak changes after app restart.
- [ ] Missing texture crashes.
- [ ] Default leak covers the entire image.
