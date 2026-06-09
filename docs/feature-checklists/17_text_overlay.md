# Text Overlay Checklist

Goal: text overlays are editable, legible, localized, and export-identical.

## Priority Map
- P0: text input safety, export parity, missing-font fallback.
- P1: multiline, color/size/position controls, golden coverage.
- P2: font library, alignment presets, text styles.

## Product And UX
- [ ] Text input supports multiline and clear action.
- [ ] Size, color, opacity, position, and alignment are controllable.
- [ ] Text remains inside visible canvas unless user intentionally moves it.
- [ ] Color choices use swatches and custom color path if needed.
- [ ] Editing text does not trigger expensive recomposition per keystroke without debounce.

## Real-Time And Engine
- [ ] Text preview is debounced and cached.
- [ ] Export uses same font metrics or documented high-quality renderer.
- [ ] Missing font falls back deterministically.
- [ ] Text bounds and wrapping are documented.

## Quantitative Gates
- Text edit preview p95 <= 120ms after debounce.
- Position/size drag p95 frame <= 16ms if transform-only.
- Export parity text bounding box difference <= 2px after downsample.
- No-op: empty text mean diff <= 0.25/255, max diff <= 2/255.

## Persistence
- [ ] Store text, font id, size, color, opacity, position, alignment, schema version.
- [ ] Undo/redo restores text content and style.
- [ ] Draft restore handles missing fonts.

## Test Commands
- Required target: `flutter test test/features/editor/text_overlay_panel_test.dart test/golden/text_overlay_golden_test.dart`
- Required perf: `dart run tool/perf_gate.dart --feature text_overlay`

## Accessibility, Localization, Privacy
- [ ] Text input has semantic label and respects platform text editing.
- [ ] UI labels use localization keys; user-entered text is never localized or modified.
- [ ] User text stays local and is deleted with session/export draft deletion.

## Release Blockers
- [ ] Exported text position/size differs materially from preview.
- [ ] Long text overflows UI controls.
- [ ] Missing font crashes export.
