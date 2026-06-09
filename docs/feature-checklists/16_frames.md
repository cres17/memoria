# Frames Checklist

Goal: frame overlays are selectable, lightweight, visually stable, and export-identical.

## Priority Map
- P0: none state, asset fallback, export parity.
- P1: thumbnail selection, cache, golden coverage.
- P2: frame color/scale variants and favorites.

## Product And UX
- [ ] Frame picker shows visible none state.
- [ ] Frame thumbnails are fixed-size and scannable.
- [ ] Selected frame is obvious.
- [ ] Missing frame asset falls back to none with no crash.
- [ ] Frame selection does not obscure the photo.

## Real-Time And Engine
- [ ] Frame assets are cached and decoded once.
- [ ] Preview composites at preview resolution.
- [ ] Export composites at final resolution.
- [ ] Aspect-ratio stretch/fit behavior is documented.

## Quantitative Gates
- Frame switch cached p95 <= 50ms.
- Cold frame decode p95 <= 150ms.
- Export parity mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: none frame mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store frame id/index and schema version.
- [ ] Undo/redo restores selected frame.
- [ ] Draft restore does not block editor while asset loads.

## Test Commands
- Required target: `flutter test test/features/editor/frame_panel_test.dart test/golden/frames_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature frames`

## Accessibility, Localization, Privacy
- [ ] Frame thumbnails expose localized labels and selected state.
- [ ] Asset names are not shown as raw filenames.
- [ ] Frame choice persists only local numeric/string id.

## Release Blockers
- [ ] Missing asset crashes.
- [ ] None state is unclear.
- [ ] Export frame alignment differs from preview.
