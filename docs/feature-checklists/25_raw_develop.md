# RAW Develop Checklist

Goal: expose RAW controls only when real RAW/DNG decoding and color management exist.

## Priority Map
- P0: unsupported files hidden/disabled, real RAW decode path, no placeholder no-op.
- P1: white balance/exposure/noise controls, export parity, golden coverage.
- P2: lens profiles, highlight recovery, camera profiles.

## Product And UX
- [ ] RAW controls appear only for supported RAW inputs.
- [ ] Unsupported JPEG/PNG shows no dead RAW controls.
- [ ] Controls include exposure, white balance, tint, highlights, shadows, and noise when supported.
- [ ] Loading/progress state is non-blocking.
- [ ] User understands RAW edits happen before normal editor pipeline.

## Real-Time And Engine
- [ ] RAW decode/demosaic runs off UI thread.
- [ ] Color transform/profile handling is documented.
- [ ] Preview uses downsampled RAW pipeline.
- [ ] Export uses full-resolution RAW processing.
- [ ] Pipeline order relative to global adjust is fixed.

## Quantitative Gates
- Unsupported file detection p95 <= 50ms.
- RAW preview first result p95 <= 1500ms with non-blocking progress.
- Main isolate frame p95 <= 16ms.
- Active RAW non-zero op must change output mean diff >= 0.5/255.
- No-op RAW params mean diff <= 0.5/255 after RAW decode baseline tolerance.

## Persistence
- [ ] Store RAW params separately from JPEG/global adjust params.
- [ ] Store schema version and supported decoder/profile metadata.
- [ ] Undo/redo restores RAW params.

## Test Commands
- Required target: `flutter test test/engine/raw_develop_engine_test.dart test/features/editor/raw_develop_panel_test.dart test/golden/raw_develop_golden_test.dart`
- Required no-op: `flutter test test/engine/no_op_guard_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature raw_develop`

## Accessibility, Localization, Privacy
- [ ] Controls expose semantic values and localized labels.
- [ ] RAW file paths remain local; no upload by default.
- [ ] Temporary decoded buffers are deleted/released after use.

## Release Blockers
- [ ] RAW UI exists without real RAW decode.
- [ ] RAW operation silently returns original for active params.
- [ ] Decoder crash takes down editor.
