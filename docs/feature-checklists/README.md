# Memoria Feature Checklists

Purpose: each editor feature has its own implementation checklist so work can be shipped one feature at a time with objective quality gates.

Enterprise rule:
- Do not mark a feature complete until implementation, UX, persistence, export, undo/redo, golden output, performance, accessibility, localization, privacy/storage, and regression tests are all checked.
- Each feature must produce the same result in preview and export unless the file documents a deliberate quality split.
- Every visible non-zero operation must have a no-op guard test that fails if the output is identical to the input.
- P0 items block release. P1 items block enterprise-grade signoff. P2 items are polish and backlog candidates.

Global quantitative gates:
- GPU-compatible interactions: p95 frame build+raster <= 16ms during drag on the project baseline Android device.
- CPU preview interactions: p95 preview response <= 80ms after debounce for a 960px long-edge proxy.
- Heavy ML/heal/HDR/denoise preview: p95 <= 250ms for first reduced preview, with visible progress or non-blocking busy state.
- Export: no main-isolate blocking; progress updates at least every 500ms for operations expected to exceed 1s.
- Memory: p95 RSS delta <= 128MB for preview workflows and <= 512MB for full export unless the feature file sets a stricter budget.
- Golden tolerance: mean per-channel absolute diff <= 1.5/255, p99 diff <= 8/255, SSIM >= 0.995 for deterministic pixel tools. Generative/ML tools must define a feature-specific tolerance.
- Export parity: preview-rendered reference and export downsampled to preview size must satisfy mean diff <= 2.0/255, p99 diff <= 10/255, SSIM >= 0.992.
- No-op tolerance: neutral operation output must satisfy mean diff <= 0.25/255 and max diff <= 2/255 after equivalent encode/decode path.
- Accessibility: touch targets >= 44x44 logical px, semantic labels for icon-only controls, contrast ratio >= 4.5:1 for text and >= 3:1 for essential icons.
- Localization: all visible strings use localization keys unless explicitly marked debug-only; Korean and English labels fit at 320px width.
- Privacy/storage: user images, custom LUTs, masks, model outputs, and external paths remain local by default; persisted data has a clear owner, schema version, and delete path.

Feature files:
- [01_filters.md](01_filters.md)
- [02_global_adjust.md](02_global_adjust.md)
- [03_details.md](03_details.md)
- [04_curves.md](04_curves.md)
- [05_hsl.md](05_hsl.md)
- [06_split_toning.md](06_split_toning.md)
- [07_grain.md](07_grain.md)
- [08_noise_reduction.md](08_noise_reduction.md)
- [09_brush.md](09_brush.md)
- [10_crop.md](10_crop.md)
- [11_rotate_flip.md](11_rotate_flip.md)
- [12_perspective.md](12_perspective.md)
- [13_expand.md](13_expand.md)
- [14_portrait.md](14_portrait.md)
- [15_double_exposure.md](15_double_exposure.md)
- [16_frames.md](16_frames.md)
- [17_text_overlay.md](17_text_overlay.md)
- [18_vignette.md](18_vignette.md)
- [19_glow.md](19_glow.md)
- [20_hdr_drama.md](20_hdr_drama.md)
- [21_light_leak.md](21_light_leak.md)
- [22_halation.md](22_halation.md)
- [23_selective.md](23_selective.md)
- [24_healing.md](24_healing.md)
- [25_raw_develop.md](25_raw_develop.md)
- [26_custom_filter_creation.md](26_custom_filter_creation.md)
- [27_editor_tabs.md](27_editor_tabs.md)
- [28_quality_gates.md](28_quality_gates.md)
