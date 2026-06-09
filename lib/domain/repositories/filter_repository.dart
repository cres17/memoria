import '../models/filter_preset.dart';

abstract class FilterRepository {
  Future<List<FilterPreset>> getCustomPresets();
  Future<FilterPreset?> getPresetById(String id);
  Future<void> savePreset(FilterPreset preset);
  Future<void> deletePreset(String id);
  Future<void> updatePreset(FilterPreset preset);
}
