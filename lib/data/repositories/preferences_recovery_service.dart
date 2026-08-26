import 'dart:convert';

import 'package:memoria/domain/models/custom_adjustment.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PreferenceRecoveryItem { favorites, customAdjustments }

/// A pending recovery decision for a preferences collection whose original
/// value could not be decoded. The raw source is deliberately not exposed to
/// widgets because it may contain user-created names or paths.
class PreferenceRecoveryEntry {
  final PreferenceRecoveryItem item;
  final int rawByteLength;

  const PreferenceRecoveryEntry({
    required this.item,
    required this.rawByteLength,
  });
}

class PreferenceRecoveryAttempt {
  final bool recovered;
  final int recoveredItemCount;

  const PreferenceRecoveryAttempt({
    required this.recovered,
    required this.recoveredItemCount,
  });
}

/// User-facing recovery boundary for corrupted SharedPreferences collections.
///
/// Recovered data replaces the live collection only after it has been parsed
/// successfully. Every reset that keeps the original moves it to an archive,
/// so a future app version or support workflow can still inspect it without
/// trapping the user in the same recovery prompt on every launch.
class PreferencesRecoveryService {
  static const _favoritesKey = 'filter_favorites_v1';
  static const _adjustmentsKey = 'custom_adjustments_v1';
  static const _backupSuffix = '_corrupt_backup';
  static const _archiveSuffix = '_recovery_archive';

  final Future<SharedPreferences> Function() _preferences;

  PreferencesRecoveryService({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<List<PreferenceRecoveryEntry>> pending() async {
    final prefs = await _preferences();
    final entries = <PreferenceRecoveryEntry>[];
    for (final item in PreferenceRecoveryItem.values) {
      final raw = prefs.getString(_backupKeyFor(item));
      if (raw != null) {
        entries.add(
          PreferenceRecoveryEntry(
            item: item,
            rawByteLength: utf8.encode(raw).length,
          ),
        );
      }
    }
    return entries;
  }

  Future<PreferenceRecoveryAttempt> tryRecover(
    PreferenceRecoveryItem item,
  ) async {
    final prefs = await _preferences();
    final raw = prefs.getString(_backupKeyFor(item));
    if (raw == null) {
      return const PreferenceRecoveryAttempt(
          recovered: false, recoveredItemCount: 0);
    }

    final recoveredJson = switch (item) {
      PreferenceRecoveryItem.favorites => _recoverFavoriteIds(raw),
      PreferenceRecoveryItem.customAdjustments =>
        _recoverCustomAdjustments(raw),
    };
    if (recoveredJson == null) {
      return const PreferenceRecoveryAttempt(
          recovered: false, recoveredItemCount: 0);
    }

    await prefs.setString(_liveKeyFor(item), jsonEncode(recoveredJson.values));
    await _archiveAndClearPending(prefs, item, raw);
    return PreferenceRecoveryAttempt(
      recovered: true,
      recoveredItemCount: recoveredJson.count,
    );
  }

  /// Clears the active collection while preserving the unreadable original in
  /// an archive. This is the safe reset default shown to users.
  Future<void> resetKeepingOriginal(PreferenceRecoveryItem item) async {
    final prefs = await _preferences();
    final raw = prefs.getString(_backupKeyFor(item));
    if (raw != null) await _archiveAndClearPending(prefs, item, raw);
    await prefs.remove(_liveKeyFor(item));
  }

  /// Removes both the current collection and its preserved raw original.
  /// Callers must obtain explicit confirmation before invoking this action.
  Future<void> discardOriginalAndReset(PreferenceRecoveryItem item) async {
    final prefs = await _preferences();
    await prefs.remove(_liveKeyFor(item));
    await prefs.remove(_backupKeyFor(item));
    await prefs.remove(_archiveKeyFor(item));
  }

  Future<void> _archiveAndClearPending(
    SharedPreferences prefs,
    PreferenceRecoveryItem item,
    String raw,
  ) async {
    await prefs.setString(_archiveKeyFor(item), raw);
    await prefs.remove(_backupKeyFor(item));
  }

  _RecoveredJson? _recoverFavoriteIds(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final ids = decoded.whereType<String>().toSet().toList()..sort();
      return _RecoveredJson(ids, ids.length);
    } on FormatException {
      return null;
    }
  }

  _RecoveredJson? _recoverCustomAdjustments(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final values = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final json = Map<String, dynamic>.from(item);
          CustomAdjustment.fromJson(json);
          values.add(json);
        } on FormatException {
          // One malformed item should not prevent valid saved adjustments
          // from being restored.
        } on TypeError {
          // See the FormatException case above.
        }
      }
      return _RecoveredJson(values, values.length);
    } on FormatException {
      return null;
    }
  }

  static String _liveKeyFor(PreferenceRecoveryItem item) => switch (item) {
        PreferenceRecoveryItem.favorites => _favoritesKey,
        PreferenceRecoveryItem.customAdjustments => _adjustmentsKey,
      };

  static String _backupKeyFor(PreferenceRecoveryItem item) =>
      '${_liveKeyFor(item)}$_backupSuffix';

  static String _archiveKeyFor(PreferenceRecoveryItem item) =>
      '${_liveKeyFor(item)}$_archiveSuffix';
}

class _RecoveredJson {
  final List<dynamic> values;
  final int count;

  const _RecoveredJson(this.values, this.count);
}
