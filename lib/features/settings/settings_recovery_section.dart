import 'package:flutter/material.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/filter_index_recovery_service.dart';
import '../../data/repositories/preferences_recovery_service.dart';

enum SettingsRecoveryKind {
  favorites,
  customAdjustments,
  filterIndex,
}

class SettingsRecoveryCandidate {
  final String id;
  final SettingsRecoveryKind kind;
  final int rawByteLength;

  const SettingsRecoveryCandidate({
    required this.id,
    required this.kind,
    required this.rawByteLength,
  });
}

class SettingsRecoveryResult {
  final bool recovered;
  final int recoveredItemCount;

  const SettingsRecoveryResult({
    required this.recovered,
    required this.recoveredItemCount,
  });
}

/// Presentation-facing boundary for storage recovery.
///
/// The settings widget deliberately receives opaque candidate ids rather than
/// repository paths or preference keys. This keeps local paths and corrupt raw
/// values out of the widget tree and makes the complete user flow testable
/// without platform plugins.
abstract interface class SettingsRecoveryController {
  Future<List<SettingsRecoveryCandidate>> pending();

  Future<SettingsRecoveryResult> recover(SettingsRecoveryCandidate candidate);

  Future<void> resetKeepingOriginal(SettingsRecoveryCandidate candidate);

  Future<void> discardOriginal(SettingsRecoveryCandidate candidate);
}

class ServiceSettingsRecoveryController implements SettingsRecoveryController {
  final PreferencesRecoveryService preferences;
  final FilterIndexRecoveryService filterIndex;
  final Map<String, PreferenceRecoveryItem> _preferenceItems = {};
  final Map<String, FilterIndexRecoveryEntry> _filterIndexEntries = {};

  ServiceSettingsRecoveryController({
    required this.preferences,
    required this.filterIndex,
  });

  @override
  Future<List<SettingsRecoveryCandidate>> pending() async {
    final results = await Future.wait([
      preferences.pending(),
      filterIndex.pending(),
    ]);
    final preferenceEntries = results[0] as List<PreferenceRecoveryEntry>;
    final filterEntries = results[1] as List<FilterIndexRecoveryEntry>;
    _preferenceItems.clear();
    _filterIndexEntries.clear();

    final candidates = <SettingsRecoveryCandidate>[];
    for (final entry in preferenceEntries) {
      final id = 'preference:${entry.item.name}';
      _preferenceItems[id] = entry.item;
      candidates.add(
        SettingsRecoveryCandidate(
          id: id,
          kind: switch (entry.item) {
            PreferenceRecoveryItem.favorites => SettingsRecoveryKind.favorites,
            PreferenceRecoveryItem.customAdjustments =>
              SettingsRecoveryKind.customAdjustments,
          },
          rawByteLength: entry.rawByteLength,
        ),
      );
    }
    for (var index = 0; index < filterEntries.length; index++) {
      final id = 'filter-index:$index';
      _filterIndexEntries[id] = filterEntries[index];
      candidates.add(
        SettingsRecoveryCandidate(
          id: id,
          kind: SettingsRecoveryKind.filterIndex,
          rawByteLength: filterEntries[index].rawByteLength,
        ),
      );
    }
    return candidates;
  }

  @override
  Future<SettingsRecoveryResult> recover(
    SettingsRecoveryCandidate candidate,
  ) async {
    if (candidate.kind == SettingsRecoveryKind.filterIndex) {
      final result = await filterIndex.tryRecover(_filterEntry(candidate));
      return SettingsRecoveryResult(
        recovered: result.recovered,
        recoveredItemCount: result.recoveredItemCount,
      );
    }
    final result = await preferences.tryRecover(_preferenceItem(candidate));
    return SettingsRecoveryResult(
      recovered: result.recovered,
      recoveredItemCount: result.recoveredItemCount,
    );
  }

  @override
  Future<void> resetKeepingOriginal(
    SettingsRecoveryCandidate candidate,
  ) {
    if (candidate.kind == SettingsRecoveryKind.filterIndex) {
      return filterIndex.resetKeepingOriginal(_filterEntry(candidate));
    }
    return preferences.resetKeepingOriginal(_preferenceItem(candidate));
  }

  @override
  Future<void> discardOriginal(SettingsRecoveryCandidate candidate) {
    if (candidate.kind == SettingsRecoveryKind.filterIndex) {
      return filterIndex.discardOriginal(_filterEntry(candidate));
    }
    return preferences.discardOriginalAndReset(_preferenceItem(candidate));
  }

  PreferenceRecoveryItem _preferenceItem(
    SettingsRecoveryCandidate candidate,
  ) {
    final item = _preferenceItems[candidate.id];
    if (item == null) {
      throw StateError('Preference recovery candidate is no longer pending');
    }
    return item;
  }

  FilterIndexRecoveryEntry _filterEntry(
    SettingsRecoveryCandidate candidate,
  ) {
    final entry = _filterIndexEntries[candidate.id];
    if (entry == null) {
      throw StateError('Filter index recovery candidate is no longer pending');
    }
    return entry;
  }
}

class SettingsRecoverySection extends StatefulWidget {
  final SettingsRecoveryController controller;

  const SettingsRecoverySection({
    super.key,
    required this.controller,
  });

  @override
  State<SettingsRecoverySection> createState() =>
      _SettingsRecoverySectionState();
}

class _SettingsRecoverySectionState extends State<SettingsRecoverySection> {
  List<SettingsRecoveryCandidate> _pending = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pending = await widget.controller.pending();
    if (mounted) setState(() => _pending = pending);
  }

  String _label(SettingsRecoveryKind kind) => switch (kind) {
        SettingsRecoveryKind.favorites => S.get('settings.recovery_favorites'),
        SettingsRecoveryKind.customAdjustments =>
          S.get('settings.recovery_adjustments'),
        SettingsRecoveryKind.filterIndex =>
          S.get('settings.recovery_filter_index'),
      };

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 66),
          child: Divider(height: 1, color: AppColors.oceanNavy),
        ),
        InkWell(
          key: const Key('settings-recovery-row'),
          onTap: _showRecoveryPicker,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.oceanNavy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.restore_page_outlined,
                    color: AppColors.textOnDarkSub,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.get('settings.recovery'),
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textOnDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        S
                            .get('settings.recovery_sub')
                            .replaceAll('{n}', '${_pending.length}'),
                        style: const TextStyle(
                          fontFamily: 'NotoSerif',
                          fontSize: 13,
                          color: AppColors.textOnDarkTert,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textOnDarkTert,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showRecoveryPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.oceanMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.oceanNavy,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  S.get('settings.recovery_body'),
                  style: const TextStyle(color: AppColors.textOnDarkSub),
                ),
              ),
              const SizedBox(height: 8),
              for (final candidate in _pending)
                ListTile(
                  key: Key('settings-recovery-candidate-${candidate.id}'),
                  leading: Icon(
                    candidate.kind == SettingsRecoveryKind.filterIndex
                        ? Icons.auto_fix_high_rounded
                        : Icons.restore_page_outlined,
                    color: AppColors.oceanFoam,
                  ),
                  title: Text(
                    _label(candidate.kind),
                    style: const TextStyle(color: AppColors.textOnDark),
                  ),
                  subtitle: Text(
                    S
                        .get('settings.recovery_size')
                        .replaceAll('{n}', '${candidate.rawByteLength}'),
                    style: const TextStyle(color: AppColors.textOnDarkSub),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textOnDarkTert,
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.microtask(() => _showActions(candidate));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(SettingsRecoveryCandidate candidate) {
    final isFilterIndex = candidate.kind == SettingsRecoveryKind.filterIndex;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.oceanMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              _label(candidate.kind),
              style: const TextStyle(
                color: AppColors.textOnDark,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isFilterIndex)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(
                  S.get('settings.recovery_filter_index_body'),
                  style: const TextStyle(color: AppColors.textOnDarkSub),
                ),
              ),
            ListTile(
              key: const Key('settings-recovery-attempt'),
              leading: const Icon(
                Icons.auto_fix_high_rounded,
                color: AppColors.oceanFoam,
              ),
              title: Text(
                S.get('settings.recovery_attempt'),
                style: const TextStyle(color: AppColors.textOnDark),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _recover(candidate);
              },
            ),
            ListTile(
              key: const Key('settings-recovery-safe-reset'),
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.textOnDarkSub,
              ),
              title: Text(
                S.get(isFilterIndex
                    ? 'settings.recovery_index_safe_reset'
                    : 'settings.recovery_safe_reset'),
                style: const TextStyle(color: AppColors.textOnDark),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _safeReset(candidate);
              },
            ),
            ListTile(
              key: const Key('settings-recovery-discard'),
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: AppColors.accentError,
              ),
              title: Text(
                S.get(isFilterIndex
                    ? 'settings.recovery_discard_original'
                    : 'settings.recovery_discard_reset'),
                style: const TextStyle(color: AppColors.accentError),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Future<void>.microtask(() => _confirmDiscard(candidate));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _recover(SettingsRecoveryCandidate candidate) async {
    final result = await widget.controller.recover(candidate);
    await _refresh();
    if (!mounted) return;
    final message = result.recovered
        ? S
            .get(candidate.kind == SettingsRecoveryKind.filterIndex
                ? 'settings.recovery_filter_index_done'
                : 'settings.recovery_partial')
            .replaceAll('{n}', '${result.recoveredItemCount}')
        : S.get('settings.recovery_unavailable');
    _showMessage(message);
  }

  Future<void> _safeReset(SettingsRecoveryCandidate candidate) async {
    await widget.controller.resetKeepingOriginal(candidate);
    await _refresh();
    if (!mounted) return;
    _showMessage(
      S.get(candidate.kind == SettingsRecoveryKind.filterIndex
          ? 'settings.recovery_index_safe_reset_done'
          : 'settings.recovery_safe_reset_done'),
    );
  }

  Future<void> _confirmDiscard(SettingsRecoveryCandidate candidate) async {
    if (!mounted) return;
    final isFilterIndex = candidate.kind == SettingsRecoveryKind.filterIndex;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.oceanMid,
        title: Text(
          S.get('settings.recovery_discard_title'),
          style: const TextStyle(color: AppColors.textOnDark),
        ),
        content: Text(
          S.get(isFilterIndex
              ? 'settings.recovery_index_discard_body'
              : 'settings.recovery_discard_body'),
          style: const TextStyle(color: AppColors.textOnDarkSub),
        ),
        actions: [
          TextButton(
            key: const Key('settings-recovery-discard-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              S.get('settings.clear_cache_cancel'),
              style: const TextStyle(color: AppColors.textOnDarkTert),
            ),
          ),
          TextButton(
            key: const Key('settings-recovery-discard-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              S.get(isFilterIndex
                  ? 'settings.recovery_discard_original'
                  : 'settings.recovery_discard_reset'),
              style: const TextStyle(color: AppColors.accentError),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.controller.discardOriginal(candidate);
    await _refresh();
    if (!mounted) return;
    _showMessage(
      S.get(isFilterIndex
          ? 'settings.recovery_index_discard_done'
          : 'settings.recovery_discard_done'),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
