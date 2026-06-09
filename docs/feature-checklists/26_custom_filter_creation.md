# Custom Filter Creation Checklist

Goal: users can create accurate reusable filters without saving broken or inverted LUTs.

## Priority Map
- P0: generated LUT validation, preview before save, saved filter applies later.
- P1: before/after and style-only modes, golden reference sets, fitting performance.
- P2: rename/delete/reorder/favorite polish and cloud backup later if explicitly designed.

## Product And UX
- [ ] Flow is task-based: choose inputs, preview, name, save.
- [ ] Before/after pair and style-only modes are visually distinct.
- [ ] User can inspect original, generated result, and reference.
- [ ] Save failure is recoverable.
- [ ] Created filter appears immediately in filter strip.

## Real-Time And Engine
- [ ] Preview fitting uses downsampled images.
- [ ] Full fitting runs async with progress.
- [ ] LUT dimension, interpolation, gamut handling, and clamp policy are documented.
- [ ] Identity pair produces identity-like LUT.
- [ ] Channel order/range validation runs before save.

## Quantitative Gates
- Small preview fit p95 <= 1500ms.
- UI remains responsive: main isolate p95 <= 16ms during fitting.
- Generated LUT validation: all values finite and in documented range.
- Identity pair: mean diff <= 1/255 against identity application.
- Reference golden: SSIM >= 0.985 or documented style metric threshold.

## Persistence
- [ ] Store id, name, LUT bytes/path, thumbnail, metadata, schema version.
- [ ] Duplicate names are handled safely.
- [ ] Deleting custom filter has documented fallback for old sessions.

## Test Commands
- Current: `flutter test test/custom_adjustment_test.dart test/whitebox_lut_core_test.dart`
- Required target: `flutter test test/features/create_filter/create_filter_flow_test.dart test/golden/custom_filter_creation_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature custom_filter_creation`

## Accessibility, Localization, Privacy
- [ ] Pickers, preview, name, save, delete controls expose semantic labels.
- [ ] All visible strings use localization keys.
- [ ] Source/reference photos are not retained after LUT creation unless user explicitly saves them.

## Release Blockers
- [ ] User can save a filter that cannot apply later.
- [ ] Generated LUT frequently inverts or posterizes colors.
- [ ] Fitting blocks the UI.
