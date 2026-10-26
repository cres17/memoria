# Color-v3 fallback integration — 2026-10-26

## Integration inputs

- Current main: `8acaf3770`.
- Test branch: `b93d6968a` (`test/color-v3-fallback-routing`).
- Common ancestor: `ea477cd7d7e4e1e2acd1dcc5091270bfc872e068`.
- Integration uses both parents, preserving the test branch's ancestry.

## Resolution decisions

The test branch's editor and filter-creation modules remain the structural basis. Main's editor changes were compared at declaration/member level against the common ancestor and transferred into those modules: Metal preview work and interruption recovery, sky masks and model download, healing strokes, multiple selective points, look copy/paste, split comparison, categorized tools and small-screen sizing. The tool catalog now includes healing and sky, with history classifications and reset handling; the remote sky kill switch also controls favorites.

`inpainting.dart` and `raw_processor.dart` remain because current render/import paths still use them. The inpainting regression suite is retained. Obsolete unused engine wrappers and their tests follow the test branch's removals. Main's newer documentation deletions are retained rather than resurrecting old checklists.

Main's dependency lockfile, AGP 9.4.1, Kotlin 2.4.21 and current Actions SHA pins are preserved. The application uses upstream `flutter_litert` 3.9.4; the test branch's 3.8.0 fork is not substituted for the already merged update. Both SwiftPM resolution files reflect the installed `google_mobile_ads` 9.2.0 requirement (native SDK 13.11.0). Historical device reports describing the old vendored runtime do not validate this dependency combination.

Model handling combines the test branch's landscape-selfie contract and timeout/atomic-download checks with main's sky model and streaming size ceiling. Startup isolates task failures while retaining crash consent, cached remote configuration, GPU fallback setup and model preparation. Sharing uses current SharePlus APIs with iPad popover origin; gallery writes request add-only access, while system pickers do not request whole-library access.

The iOS 15 and arm64 SwiftPM settings from the test branch are retained and applied to the iOS CI simulator jobs. Main's direct certificate import and keychain cleanup remain alongside the test branch's verified profile installation and release-configuration checks. Release ad flags remain disabled, with the remote kill switch retained. The GPU feature flag remains off by default.

## Local validation

- Flutter 3.44.6 / Dart 3.12.2.
- `flutter pub get --offline --enforce-lockfile`: passed, preserving main's pub lockfile.
- `flutter analyze --no-pub --no-fatal-infos`: no errors or warnings; 3 existing info diagnostics.
- Full Flutter unit/widget suite with the CI-pinned macOS inference library: **716 passed, 2 skipped**.
- `scripts/check_coverage.py coverage/lcov.info --min 58`: **69.8% (10,432/14,952)**. This measures only source files included in lcov, not all repository code.
- Provisioning-profile tests: **4 passed**.
- GPU CI startup/watchdog tests: **4 passed**.
- iOS arm64 simulator debug build with `SimulatorCI.xcconfig`: passed. An initial build without that CI configuration failed to link Flutter symbols; the supported configuration was then verified.

Native runtime/integration checks, unsigned device release compilation and remote CI are recorded below as they complete. Signed IPA creation, physical-device operation, memory/thermal measurements and GPU rollout are separate from this integration.
