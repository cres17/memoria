import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/repositories/filter_repository.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';
import 'package:memoria/engine/reference_coverage_router.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('memoria-create-filter-tx-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<FilterPreset> makePreset(String id) async {
    final directory = Directory('${tempDirectory.path}/filters/$id');
    await directory.create(recursive: true);
    final lut = File('${directory.path}/lut.bin');
    final thumbnail = File('${directory.path}/thumbnail.jpg');
    await lut.writeAsBytes([1, 2, 3, 4]);
    await thumbnail.writeAsBytes([5, 6, 7, 8]);
    final now = DateTime(2026, 8, 19);
    return FilterPreset(
      id: id,
      name: 'Generated filter',
      type: FilterPresetType.custom,
      lutPath: lut.path,
      params: AdjustParams.zero,
      defaultIntensity: 0.8,
      thumbnailPath: thumbnail.path,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('CF-14 preview is validated before the preset is saved', () async {
    final events = <String>[];
    final repository = _RecordingRepository(events: events);
    final renderer = _RecordingPreviewRenderer(
      events: events,
      outputPath: '${tempDirectory.path}/preview.jpg',
    );
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: renderer,
    );
    final preset = await makePreset('success');

    final result = await transaction.commit(
      preset: preset,
      sourcePath: '${tempDirectory.path}/source.jpg',
    );

    expect(events, ['preview', 'save']);
    expect(repository.savedIds, ['success']);
    expect(await File(result.previewPath).exists(), isTrue);
    expect(await File(preset.lutPath).exists(), isTrue);
  });

  test('CF-14 preview failure leaves no preset or generated artifacts',
      () async {
    final events = <String>[];
    final repository = _RecordingRepository(events: events);
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: _RecordingPreviewRenderer(
        events: events,
        outputPath: null,
      ),
    );
    final preset = await makePreset('preview-failure');
    final generatedDirectory = File(preset.lutPath).parent;

    await expectLater(
      transaction.commit(preset: preset, sourcePath: 'source.jpg'),
      throwsA(isA<CreateFilterPreviewException>()),
    );

    expect(events, ['preview', 'delete']);
    expect(repository.savedIds, isEmpty);
    expect(await generatedDirectory.exists(), isFalse);
  });

  test('CF-14 save failure rolls back index, preview, and filter directory',
      () async {
    final events = <String>[];
    final repository = _RecordingRepository(
      events: events,
      failAfterSave: true,
    );
    final previewPath = '${tempDirectory.path}/save-failure-preview.jpg';
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: _RecordingPreviewRenderer(
        events: events,
        outputPath: previewPath,
      ),
    );
    final preset = await makePreset('save-failure');
    final generatedDirectory = File(preset.lutPath).parent;

    await expectLater(
      transaction.commit(preset: preset, sourcePath: 'source.jpg'),
      throwsA(isA<StateError>()),
    );

    expect(events, ['preview', 'save', 'delete']);
    expect(repository.savedIds, isEmpty);
    expect(await File(previewPath).exists(), isFalse);
    expect(await generatedDirectory.exists(), isFalse);
  });

  test('WB-CF-ROLLBACK-01 cancellation after preview rolls back without saving',
      () async {
    final events = <String>[];
    final repository = _RecordingRepository(events: events);
    final previewPath = '${tempDirectory.path}/cancelled-preview.jpg';
    final renderer = _ControlledPreviewRenderer(
      events: events,
      outputPath: previewPath,
    );
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: renderer,
    );
    final preset = await makePreset('cancel-before-save');
    final generatedDirectory = File(preset.lutPath).parent;
    var cancelled = false;

    final commit = transaction.commit(
      preset: preset,
      sourcePath: 'source.jpg',
      isCancelled: () => cancelled,
    );
    await renderer.started.future;
    cancelled = true;
    renderer.release.complete();

    await expectLater(commit, throwsA(isA<CreateFilterCancelledException>()));
    expect(events, ['preview', 'delete']);
    expect(repository.savedIds, isEmpty);
    expect(await File(previewPath).exists(), isFalse);
    expect(await generatedDirectory.exists(), isFalse);
  });

  test(
      'WB-CF-ROLLBACK-01 cancellation during save compensates repository write',
      () async {
    final events = <String>[];
    final repository = _ControlledSaveRepository(events: events);
    final previewPath = '${tempDirectory.path}/cancel-during-save-preview.jpg';
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: _RecordingPreviewRenderer(
        events: events,
        outputPath: previewPath,
      ),
    );
    final preset = await makePreset('cancel-during-save');
    final generatedDirectory = File(preset.lutPath).parent;
    var cancelled = false;

    final commit = transaction.commit(
      preset: preset,
      sourcePath: 'source.jpg',
      isCancelled: () => cancelled,
    );
    await repository.saveStarted.future;
    cancelled = true;
    repository.releaseSave.complete();

    await expectLater(commit, throwsA(isA<CreateFilterCancelledException>()));
    expect(events, ['preview', 'save', 'delete']);
    expect(repository.savedIds, isEmpty);
    expect(await File(previewPath).exists(), isFalse);
    expect(await generatedDirectory.exists(), isFalse);
  });

  test('CF-16 temporary preview cleanup is idempotent', () async {
    final preview = File('${tempDirectory.path}/temporary-preview.jpg');
    await preview.writeAsBytes([1, 2, 3]);

    await CreateFilterCommitTransaction.deleteFileIfPresent(preview.path);
    await CreateFilterCommitTransaction.deleteFileIfPresent(preview.path);

    expect(await preview.exists(), isFalse);
  });

  test('CF-14 worker error completes and removes only new artifacts', () async {
    final filters = Directory('${tempDirectory.path}/filters');
    final existing = Directory('${filters.path}/existing-filter');
    await existing.create(recursive: true);
    final generator = IsolateCreateFilterGenerator(
      timeout: const Duration(seconds: 5),
    );

    await expectLater(
      generator.generateStyle(
        ['${tempDirectory.path}/missing-reference.jpg'],
        basePath: tempDirectory.path,
        onProgress: (_, __) {},
      ),
      throwsA(isA<CreateFilterWorkerException>()),
    );

    final remaining = await filters
        .list()
        .where((entry) => entry is Directory)
        .map((entry) => entry.path)
        .toList();
    expect(remaining, [existing.path]);
  });

  test('low reference coverage stops before worker and creates no artifact',
      () async {
    final generator = IsolateCreateFilterGenerator(
      timeout: const Duration(seconds: 5),
    );
    const reference =
        'ml_pipeline/data/dataset_external_monochrome_calibration_001/graded/mono_000000.jpg';

    await expectLater(
      generator.generateStyle(
        const [reference],
        basePath: tempDirectory.path,
        onProgress: (_, __) {},
      ),
      throwsA(
        isA<LowReferenceCoverageException>().having(
          (error) => error.fraction,
          'fraction',
          lessThan(colorV3ReferenceCoverageThreshold),
        ),
      ),
    );

    final filters = Directory('${tempDirectory.path}/filters');
    expect(await filters.exists(), isFalse);
  });

  test('CF-14 cancel kills the worker and cleans its partial directory',
      () async {
    final source = File('${tempDirectory.path}/cancel-source.png');
    final image = img.Image(width: 64, height: 64);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 3, y * 3, 100);
      }
    }
    await source.writeAsBytes(img.encodePng(image));
    final generator = IsolateCreateFilterGenerator(
      timeout: const Duration(seconds: 5),
    );
    var requestedCancel = false;

    final generation = generator.generateStyle(
      [source.path],
      basePath: tempDirectory.path,
      onProgress: (stage, progress) {
        if (!requestedCancel) {
          requestedCancel = true;
          unawaited(generator.cancel());
        }
      },
    );

    await expectLater(
      generation,
      throwsA(isA<CreateFilterCancelledException>()),
    );
    final filters = Directory('${tempDirectory.path}/filters');
    final remaining = await filters.exists()
        ? await filters.list().where((entry) => entry is Directory).toList()
        : const <FileSystemEntity>[];
    expect(remaining, isEmpty);
  });

  test('Phase C worker receives the resolved Direct MVP model path', () async {
    const modelPath = 'assets/models/direct_mvp_color_transfer_fp16.tflite';
    final source = File('${tempDirectory.path}/neural-source.png');
    final image = img.Image(width: 64, height: 64);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x * 3, y * 3, 120);
      }
    }
    await source.writeAsBytes(img.encodePng(image));
    AiManager.instance.useLocalModelForTesting(
      kModelColorTransfer,
      modelPath,
    );
    final generator = IsolateCreateFilterGenerator(
      timeout: const Duration(seconds: 20),
    );

    try {
      final result = await generator.generateStyle(
        [source.path],
        basePath: tempDirectory.path,
        onProgress: (_, __) {},
      );
      final recipe = Map<String, dynamic>.from(result['filterRecipe'] as Map);

      expect(result['generatorType'], 'neural');
      expect(recipe['modelId'], kColorTransferModelId);
      expect(recipe['modelVersion'], kColorTransferModelVersion);
      expect(
        result['referenceCoverage'],
        greaterThanOrEqualTo(colorV3ReferenceCoverageThreshold),
      );
      expect(File(result['lutPath'] as String).existsSync(), isTrue);
    } finally {
      AiManager.instance.clearLocalModelForTesting(kModelColorTransfer);
    }
  });
}

class _RecordingPreviewRenderer implements CreateFilterPreviewRenderer {
  final List<String> events;
  final String? outputPath;

  const _RecordingPreviewRenderer({
    required this.events,
    required this.outputPath,
  });

  @override
  Future<String?> render(FilterPreset preset, String? sourcePath) async {
    events.add('preview');
    if (outputPath == null) return null;
    await File(outputPath!).writeAsBytes([9, 8, 7]);
    return outputPath;
  }
}

class _ControlledPreviewRenderer implements CreateFilterPreviewRenderer {
  final List<String> events;
  final String outputPath;
  final started = Completer<void>();
  final release = Completer<void>();

  _ControlledPreviewRenderer({
    required this.events,
    required this.outputPath,
  });

  @override
  Future<String?> render(FilterPreset preset, String? sourcePath) async {
    events.add('preview');
    started.complete();
    await release.future;
    await File(outputPath).writeAsBytes([9, 8, 7]);
    return outputPath;
  }
}

class _RecordingRepository implements FilterRepository {
  final List<String> events;
  final bool failAfterSave;
  final List<String> savedIds = [];

  _RecordingRepository({
    required this.events,
    this.failAfterSave = false,
  });

  @override
  Future<void> savePreset(FilterPreset preset) async {
    events.add('save');
    savedIds.add(preset.id);
    if (failAfterSave) throw StateError('simulated save failure');
  }

  @override
  Future<void> deletePreset(String id) async {
    events.add('delete');
    savedIds.remove(id);
  }

  @override
  Future<List<FilterPreset>> getCustomPresets() async => const [];

  @override
  Future<FilterPreset?> getPresetById(String id) async => null;

  @override
  Future<void> updatePreset(FilterPreset preset) async {}
}

class _ControlledSaveRepository extends _RecordingRepository {
  final saveStarted = Completer<void>();
  final releaseSave = Completer<void>();

  _ControlledSaveRepository({required super.events});

  @override
  Future<void> savePreset(FilterPreset preset) async {
    events.add('save');
    savedIds.add(preset.id);
    saveStarted.complete();
    await releaseSave.future;
  }
}
