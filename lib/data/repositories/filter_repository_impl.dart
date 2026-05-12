import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/filter_preset.dart';
import '../../domain/repositories/filter_repository.dart';

class FilterRepositoryImpl implements FilterRepository {
  static const _indexFile = 'filters_index.json';

  Future<Directory> get _filtersDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/filters');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get _indexFilePath async {
    final dir = await _filtersDir;
    return File('${dir.path}/$_indexFile');
  }

  Future<List<String>> _readIndex() async {
    final file = await _indexFilePath;
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<String> ids) async {
    final file = await _indexFilePath;
    await file.writeAsString(jsonEncode(ids));
  }

  @override
  Future<List<FilterPreset>> getCustomPresets() async {
    final ids = await _readIndex();
    final results = <FilterPreset>[];
    final validIds = <String>[];
    for (final id in ids) {
      final preset = await getPresetById(id);
      if (preset != null) {
        results.add(preset);
        validIds.add(id);
      }
    }
    if (validIds.length != ids.length) {
      await _writeIndex(validIds);
    }
    return results;
  }

  @override
  Future<FilterPreset?> getPresetById(String id) async {
    final dir = await _filtersDir;
    final metaFile = File('${dir.path}/$id/meta.json');
    if (!await metaFile.exists()) return null;
    try {
      final raw = await metaFile.readAsString();
      return FilterPreset.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePreset(FilterPreset preset) async {
    final dir = await _filtersDir;
    final presetDir = Directory('${dir.path}/${preset.id}');
    await presetDir.create(recursive: true);

    final metaFile = File('${presetDir.path}/meta.json');
    await metaFile.writeAsString(preset.toJsonString());

    final ids = await _readIndex();
    if (!ids.contains(preset.id)) {
      ids.add(preset.id);
      await _writeIndex(ids);
    }
  }

  @override
  Future<void> deletePreset(String id) async {
    final dir = await _filtersDir;
    final presetDir = Directory('${dir.path}/$id');
    if (await presetDir.exists()) await presetDir.delete(recursive: true);

    final ids = await _readIndex();
    ids.remove(id);
    await _writeIndex(ids);
  }

  @override
  Future<void> updatePreset(FilterPreset preset) async {
    final updated = preset.copyWith(updatedAt: DateTime.now());
    await savePreset(updated);
  }
}
