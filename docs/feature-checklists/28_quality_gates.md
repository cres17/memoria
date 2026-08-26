# Quality Gates Checklist

Goal: every feature reaches enterprise-grade quality through repeatable, measurable gates.

## Priority Map
- P0: analyze clean, no visible no-op tools, no UI freezes, undo/redo safe.
- P1: golden/export/performance coverage, accessibility/localization/privacy complete.
- P2: broader device matrix and automated visual dashboards.

## Test Commands
- Static analysis: `flutter analyze`
- Core editor tests: `flutter test test/features/editor/adjust_slider_test.dart test/features/editor/parameter_panels_test.dart test/features/editor/editor_render_recipe_test.dart`
- Engine regression: `flutter test test/engine/no_op_guard_test.dart test/engine/edit_operation_roundtrip_test.dart`
- Integrated pipeline: `flutter test test/whitebox_integrated_pipeline_test.dart test/filter_apply_whitebox_test.dart`
- Performance: `dart run tool/perf_gate.dart`

## Product Gates
- [ ] Every visible feature has a clear user promise and done criteria.
- [ ] No placeholder feature is visible in production unless behind an experimental flag.
- [ ] Every feature has neutral/default behavior that is safe and reversible.
- [ ] Every long-running operation has progress or non-blocking busy state.

## Architecture Gates
- [ ] Image edit state uses `EditSession`/`EditOperation` or documented equivalent.
- [ ] UI draft state is separated from committed operation state.
- [ ] Every operation has JSON round-trip tests and schema version where needed.
- [ ] Preview and export share engine code or a tested contract.
- [ ] Stale async results cannot overwrite newer preview state.

## Quantitative Gates
- GPU interaction p95 frame <= 16ms.
- CPU preview p95 <= 80ms after debounce unless feature-specific budget says otherwise.
- Heavy preview p95 <= 250ms first reduced result with non-blocking UI.
- Export progress interval <= 500ms for operations > 1s.
- Golden deterministic tolerance: mean diff <= 1.5/255, p99 <= 8/255, SSIM >= 0.995.
- Export parity: mean diff <= 2/255, p99 <= 10/255, SSIM >= 0.992.
- No-op: mean diff <= 0.25/255, max diff <= 2/255.

## Accessibility, Localization, Privacy
- [ ] Touch targets >= 44x44 logical px or equivalent hit slop.
- [ ] Icon-only controls have semantic labels and tooltips.
- [ ] Text contrast >= 4.5:1 and essential icon contrast >= 3:1.
- [ ] All visible strings use localization keys.
- [ ] Korean and English text fit at 320px width.
- [ ] User images, masks, LUTs, and model outputs remain local by default.
- [ ] Persisted data has owner, schema version, retention policy, and delete path.

## Manual QA Matrix
- [ ] Small phone portrait.
- [ ] Large phone portrait.
- [ ] Landscape phone.
- [ ] Tablet.
- [ ] Low-memory Android.
- [ ] Offline/no-model/no-asset fallback.

## Release Blockers
- [ ] Any visible tool silently does nothing.
- [ ] Any tool can crash on missing assets/models/files.
- [ ] Main UI freezes during common editing.
- [ ] Preview/export mismatch is undocumented or untested.
- [ ] Undo/redo loses user work.
