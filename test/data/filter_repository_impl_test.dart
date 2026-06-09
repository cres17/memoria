import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/data/repositories/filter_repository_impl.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/filter_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memoria_filters_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('renaming a custom preset preserves its id and index entry', () async {
    final repo = FilterRepositoryImpl();
    final createdAt = DateTime(2026, 6, 4);
    final preset = FilterPreset(
      id: 'custom_stable_id',
      name: 'Warm Walk',
      type: FilterPresetType.custom,
      lutPath: '${tempDir.path}/filters/custom_stable_id/lut.bin',
      params: const AdjustParams(exposure: 0.1),
      defaultIntensity: 0.8,
      thumbnailPath: '${tempDir.path}/filters/custom_stable_id/thumb.jpg',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await repo.savePreset(preset);
    await repo.updatePreset(preset.copyWith(name: 'Golden Walk'));

    final renamed = await repo.getPresetById('custom_stable_id');
    expect(renamed, isNotNull);
    expect(renamed!.id, equals('custom_stable_id'));
    expect(renamed.name, equals('Golden Walk'));

    final filtersDir = Directory('${tempDir.path}/filters');
    final metaFile = File('${filtersDir.path}/custom_stable_id/meta.json');
    final indexFile = File('${filtersDir.path}/filters_index.json');
    final metaJson = jsonDecode(await metaFile.readAsString()) as Map;
    final indexJson = jsonDecode(await indexFile.readAsString()) as List;

    expect(metaJson['id'], equals('custom_stable_id'));
    expect(indexJson, equals(['custom_stable_id']));
    expect(Directory('${filtersDir.path}/Golden Walk').existsSync(), isFalse);
  });
}
