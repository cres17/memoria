# HDR Drama Checklist

Goal: add local depth and drama without halos, posterization, or frozen UI.

## Priority Map
- P0: neutral no-op, halo suppression, off-main-isolate processing.
- P1: strength/style controls, golden coverage, performance gate.
- P2: presets and auto scene detection.

## Product And UX
- [ ] Controls include strength and softness/style when supported.
- [ ] The feature is named honestly: HDR/Drama/local contrast.
- [ ] Reset returns to neutral.
- [ ] Preview loading state is non-blocking.

## Real-Time And Engine
- [ ] Multi-scale/local contrast work runs in isolate.
- [ ] Preview uses 960px proxy.
- [ ] Export uses final-resolution path with progress.
- [ ] Halo suppression is part of the algorithm contract.

## Quantitative Gates
- First preview p95 <= 250ms on 960px proxy.
- Main isolate frame p95 <= 16ms.
- Halo overshoot on synthetic edge <= 8/255 p99.
- Golden tolerance SSIM >= 0.985.
- No-op mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store strength, style/softness, schema version.
- [ ] Undo/redo restores controls and preview state.

## Test Commands
- Required target: `flutter test test/engine/hdr_drama_engine_test.dart test/features/editor/hdr_panel_test.dart test/golden/hdr_drama_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature hdr_drama`

## Accessibility, Localization, Privacy
- [ ] Controls expose semantic values and localized labels.
- [ ] Processing intermediates are temporary.
- [ ] No private image-derived data persists beyond params.

## Release Blockers
- [ ] HDR creates obvious halos at default values.
- [ ] Preview blocks UI.
- [ ] Export does not match preview intent.
