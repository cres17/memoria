# Noise Reduction Checklist

Goal: reduce noise while preserving real detail, skin texture, and edges.

## Priority Map
- P0: off-main-isolate processing, neutral no-op, no plastic skin defaults.
- P1: detail preservation, golden coverage, export progress.
- P2: chroma/luma split controls, auto noise estimation.

## Product And UX
- [x] Noise reduction is visually separate from artistic grain.
- [x] Controls include strength and detail preservation.
- [x] Loading state is subtle and non-blocking.
- [x] User can cancel or continue editing while preview updates.
- [x] Default useful value protects faces and fine edges.

## Real-Time And Engine
- [x] Preview runs on 960px long-edge proxy in isolate.
- [x] Full export runs higher-quality denoise off UI thread.
- [x] Algorithm preserves edges using bilateral, guided, NL-means, or documented alternative.
- [x] New slider values cancel stale preview results.
- [x] Operation order relative to sharpen/details is documented.

## Quantitative Gates
- Reduced preview p95 <= 250ms for denoise first result; slider debounce <= 100ms.
- Main isolate frame caused by denoise <= 16ms p95.
- Edge preservation: synthetic edge contrast loss <= 8%.
- Golden tolerance for denoise: SSIM >= 0.985, no flat-region color shift mean > 2/255.
- No-op: strength 0 mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [x] Store strength, detail preservation, mode, and schema version.
- [x] Undo/redo restores controls and current preview state.
- [x] Draft restore schedules preview lazily.

## Test Commands
- Required target: `flutter test test/engine/noise_reduction_engine_test.dart test/golden/noise_reduction_golden_test.dart`
- Required no-op: `flutter test test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature noise_reduction`

## Accessibility, Localization, Privacy
- [x] Sliders expose semantic values and reset actions.
- [x] Labels use localization keys and fit on 320px width.
- [x] No denoised intermediate image is persisted unless explicitly saved by export.

## Release Blockers
- [x] Denoise blocks slider input.
- [x] Moderate values destroy skin texture.
- [x] Preview and export use unrelated algorithms without documented parity.
