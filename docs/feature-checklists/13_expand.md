# Expand Checklist

Goal: expand the canvas with predictable fill modes and non-blocking smart fill.

## Priority Map
- P0: black/white/simple fill correctness, preview/export parity, non-blocking smart fill.
- P1: smart fill quality, edge handling, golden coverage.
- P2: AI inpaint expand and content-aware presets.

## Product And UX
- [ ] User can expand top, bottom, left, and right independently.
- [ ] Fill modes include smart, black, and white.
- [ ] Affected edges are visually indicated.
- [ ] Reset all edges is available.
- [ ] Smart fill progress is visible if it takes longer than 500ms.

## Real-Time And Engine
- [ ] Simple fill preview is instant.
- [ ] Smart fill runs off UI thread.
- [ ] Export applies fill at final resolution.
- [ ] Fill algorithm and fallback behavior are documented.

## Quantitative Gates
- Simple fill preview p95 <= 50ms.
- Smart fill first preview p95 <= 250ms on 960px proxy.
- Export progress every <= 500ms if > 1s.
- Export parity: simple fill exact; smart fill SSIM >= 0.985 against deterministic golden.
- No-op: all expand values 0 mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store edge percentages/pixels, fill mode, seed/version if smart fill is stochastic.
- [ ] Undo/redo restores edges and mode.

## Test Commands
- Required target: `flutter test test/engine/expand_engine_test.dart test/features/editor/expand_panel_test.dart test/golden/expand_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature expand`

## Accessibility, Localization, Privacy
- [ ] Edge controls expose localized labels and numeric values.
- [ ] Fill modes use localization keys.
- [ ] Smart fill intermediates are temporary unless user exports.

## Release Blockers
- [ ] Smart fill freezes UI.
- [ ] Expanded dimensions differ between preview and export.
- [ ] Missing fill mode creates transparent/garbage pixels unexpectedly.
