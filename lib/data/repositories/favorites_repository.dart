import 'dart:convert';
import 'package:memoria/core/error/error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesRepository {
  static const _key = 'filter_favorites_v1';
  static const _corruptBackupKey = '${_key}_corrupt_backup';

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (error, stackTrace) {
      await _quarantine(raw, prefs);
      ErrorLogger.log(
        'Favorite filter storage was corrupt; original was quarantined',
        error.runtimeType,
        stackTrace,
      );
      return {};
    }
  }

  Future<void> _quarantine(String raw, SharedPreferences prefs) async {
    if (prefs.getString(_corruptBackupKey) == null) {
      await prefs.setString(_corruptBackupKey, raw);
    }
  }

  Future<void> toggle(String presetId) async {
    final ids = await getFavoriteIds();
    if (ids.contains(presetId)) {
      ids.remove(presetId);
    } else {
      ids.add(presetId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ids.toList()));
  }

  Future<void> add(String presetId) async {
    final ids = await getFavoriteIds();
    ids.add(presetId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ids.toList()));
  }

  Future<void> remove(String presetId) async {
    final ids = await getFavoriteIds();
    ids.remove(presetId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ids.toList()));
  }
}
