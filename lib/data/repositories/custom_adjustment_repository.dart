import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/custom_adjustment.dart';

class CustomAdjustmentRepository {
  static const _key = 'custom_adjustments_v1';

  Future<List<CustomAdjustment>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(CustomAdjustment.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(CustomAdjustment adjustment) async {
    final all = await getAll();
    final idx = all.indexWhere((a) => a.id == adjustment.id);
    if (idx >= 0) {
      all[idx] = adjustment;
    } else {
      all.add(adjustment);
    }
    await _write(all);
  }

  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((a) => a.id == id);
    await _write(all);
  }

  Future<void> _write(List<CustomAdjustment> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((a) => a.toJson()).toList()));
  }
}
