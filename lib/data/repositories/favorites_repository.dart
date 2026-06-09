import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesRepository {
  static const _key = 'filter_favorites_v1';

  Future<Set<String>> getFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
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
