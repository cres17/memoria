# Filters Checklist

Goal: built-in and custom LUT filters are reliable, fast, visually inspectable, and reversible.

- [x] Keep only approved default filter families visible by default.
- [x] Show fixed sample thumbnails or pre-rendered thumbnails, not unstable live thumbnails, when product direction requires it.
- [x] Replace long filter text with compact names or brand marks where applicable.
- [x] Validate LUT channel order, value range, identity behavior, and intensity blending.
- [x] Cache LUT bytes and decoded LUT data without leaking memory.
- [x] Make filter selection append an `EditOperation.filter`.
- [x] Ensure undo/redo restores preset, LUT bytes, intensity, and preview.
- [x] Ensure export output matches preview within golden tolerance.
- [x] Add golden tests for identity, Fuji, Leica, and custom LUT examples.
- [x] Add regression test for custom LUT inversion bugs.
- [x] Add performance budget for LUT preview and export.

## Enterprise Completion Checklist

### Product promise
- [ ] A user can understand the filter library without reading instructions.
- [ ] The first visible filters are high-quality, differentiated, and useful for common photos.
- [ ] Similar filters are grouped by style family, not dumped as a flat technical list.
- [x] Built-in, favorite, recent, and custom filters have clear visual separation.
- [x] The original/no-filter state is always available and visually obvious.

### UX and ergonomics
- [x] The strip shows at most one primary label per filter: short name or brand mark, not long LUT filenames.
- [x] Thumbnails use a consistent reference image unless product direction explicitly chooses live thumbnails.
- [x] Favorite state is reachable from the filter item without opening another page.
- [x] Intensity appears only after a filter is selected, keeping the default strip light.
- [x] Selecting a filter does not jump scroll position unexpectedly.
- [x] The selected filter remains centered or visible after selection.
- [x] Custom filters show delete/rename actions behind a long-press or menu, not as always-visible clutter.
- [x] Empty custom-filter state points to create-filter flow without marketing copy.

### Real-time and performance
- [ ] LUT preview path uses GPU shader when only LUT/global-compatible controls are active.
- [x] LUT bytes are loaded once per LUT and cached with a bounded LRU policy.
- [x] Decoded LUT data is reused across preview renders and export when possible.
- [x] Rapid filter tapping cancels stale preview work by token or equivalent request id.
- [ ] First filter preview appears within 150ms on a mid-range Android device after image load.
- [ ] Subsequent cached filter switches appear within 50ms for GPU path.
- [ ] Thumbnail generation does not happen on the main isolate during editor interaction.

### Engine contract
- [ ] LUT input and output ranges are documented: byte, normalized float, or cube value range.
- [x] RGB/BGR channel order is tested for every supported LUT source format.
- [x] Identity LUT output is pixel-identical or within documented rounding tolerance.
- [x] Intensity blending happens in a consistent color space and before/after other tools by design.
- [x] Filter params and LUT params do not overwrite unrelated global adjustment state accidentally.
- [x] Missing or corrupt LUT files fail gracefully and keep the image editable.

### Persistence and export
- [x] Filter selection appends or replaces the correct `EditOperation.filter` according to session policy.
- [x] Undo restores previous preset id, intensity, LUT bytes, and preview.
- [x] Redo restores the same visible filter selection.
- [x] Draft restore rehydrates selected filter and intensity before first preview render.
- [x] Export uses the same LUT bytes and intensity as preview.
- [x] Custom filter IDs remain stable after rename.

### Test gates
- [x] Unit: identity LUT, channel order, intensity 0/50/100, missing LUT.
- [ ] Widget: selected item, favorite toggle, custom filter actions, custom filter empty state, strip scroll retention.
- [x] Golden: original, representative Fuji/Leica/custom filters, high-saturation edge case.
- [x] Regression: custom LUT inversion, stale async preview, corrupt LUT fallback.
- [x] Performance: cold LUT load, cached switch, export application.

### Release blockers
- [x] Any visible filter returns the unmodified image at non-zero intensity.
- [x] Preview and export disagree beyond golden tolerance.
- [ ] Filter switching blocks touch input.
- [x] Custom filter output can invert colors without a failing test.

## Priority Map
- P0: no-op guard, preview/export parity, corrupt LUT fallback, undo/redo restore.
- P1: bounded LUT cache, thumbnail stability, golden coverage, performance budget.
- P2: advanced grouping, favorite polish, richer custom-filter management.

## Quantitative Gates
- Filter tap to first visual update: p95 <= 50ms cached, <= 150ms cold LUT.
- LUT preview: GPU path p95 frame <= 16ms; CPU fallback p95 <= 80ms on 960px proxy.
- Golden tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- Export parity: mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992 after downsample.
- No-op: identity LUT and intensity 0 output mean diff <= 0.25/255, max diff <= 2/255.

## Test Commands
- Current: `flutter test test/whitebox_lut_core_test.dart test/whitebox_lut_engine_test.dart test/whitebox_filter_preset_test.dart test/filter_apply_whitebox_test.dart`
- Current regression: `flutter test test/engine/no_op_guard_test.dart`
- Required target: `flutter test test/features/editor/filter_strip_test.dart test/golden/filters_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature filters`

## Accessibility, Localization, Privacy
- [x] Filter items expose semantic label, selected state, favorite state, and custom/built-in group.
- [ ] Every visible label uses localization keys; brand marks have localized fallback labels.
- [ ] Custom LUT files remain local, have delete paths, and do not persist original source photos unnecessarily.
