# Editor Tabs Checklist

Goal: the editor shows four user-selected feature tabs by default while keeping all features accessible.

Status: deferred from v1. The unconnected preference-only scaffold was removed;
this checklist describes the contract required before the feature is reintroduced.

## Priority Map
- P0: four visible feature tabs, all-features left, tab-edit right, persisted selection.
- P1: tests, localization, accessibility, invalid preference recovery.
- P2: drag reorder, per-device layouts, usage-based suggestions.

## Product And UX
- [ ] Show only four user-facing feature tabs by default.
- [ ] Add all-features entry on the left.
- [ ] Add tab-edit entry on the right.
- [ ] Persist the user's four selected tabs.
- [ ] Enforce exactly four selected tabs in edit sheet.
- [ ] Hidden active feature marks all-features entry active.
- [ ] Layout remains usable at 320px width.

## Real-Time And Engine/UI
- [ ] Opening sheets is instant and does not trigger image recomputation.
- [ ] Preference load does not block image load.
- [ ] Invalid stored tab names recover to four valid tabs.
- [ ] Preferences are separate from image edit session state.

## Quantitative Gates
- Open all-features/edit-tabs sheet p95 <= 50ms.
- Save preferences p95 <= 100ms async and non-blocking.
- Tab switch p95 <= 50ms excluding feature-specific preview work.
- Layout: no overflow at 320x640 and landscape 640x320.

## Persistence
- [ ] Store selected tab names under versioned key.
- [ ] Future removed tabs recover safely.
- [ ] User can reset to defaults if needed.

## Test Commands
- Current: `flutter analyze lib/features/editor/editor_page.dart`
- Required target: add a production-path preference test when the feature is reintroduced.
- Required layout: `flutter test test/features/editor/editor_tabs_layout_test.dart`

## Accessibility, Localization, Privacy
- [ ] All/edit/icon controls have semantic labels and tooltips.
- [ ] `전체 기능`, `탭 편집`, `저장` use localization keys.
- [ ] Tab preferences store only UI choices, no image data.

## Release Blockers
- [ ] Users see all feature tabs by default.
- [ ] Tab edit can save fewer/more than four tabs.
- [ ] Preference corruption breaks editor open.
