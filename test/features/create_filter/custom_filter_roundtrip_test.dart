import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/data/repositories/filter_repository_impl.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/models/filter_recipe.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/features/create_filter/create_filter_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp
        .createTemp('memoria-custom-filter-roundtrip-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    AiManager.instance.clearLocalModelForTesting(kModelColorTransfer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('CF-12 neural generate save reload and apply are byte-stable', () async {
    // Use the repository candidate path because worker isolates cannot resolve
    // Flutter asset keys as ordinary files. Production passes the installed
    // documents-directory path through the same generator contract.
    AiManager.instance.useLocalModelForTesting(
      kModelColorTransfer,
      'ml_pipeline/reports/deployment/'
      'direct_mvp_family_holdout_smooth_010_001_fp16.tflite',
    );
    const sourcePath = 'test/원본_1.jpg';
    final generator = IsolateCreateFilterGenerator(
      timeout: const Duration(seconds: 30),
    );
    final result = await generator.generateStyle(
      const [sourcePath],
      basePath: tempDirectory.path,
      onProgress: (_, __) {},
    );
    final now = DateTime(2026, 8, 19);
    final preset = FilterPreset(
      id: result['presetId'] as String,
      name: 'Round-trip Direct MVP',
      type: FilterPresetType.custom,
      lutPath: result['lutPath'] as String,
      params: AdjustParams.fromJson(
        Map<String, dynamic>.from(result['defaultParams'] as Map),
      ),
      defaultIntensity: 0.8,
      thumbnailPath: result['thumbnailPath'] as String,
      createdAt: now,
      updatedAt: now,
      recipe: FilterRecipe.fromJson(
        Map<String, dynamic>.from(result['filterRecipe'] as Map),
      ),
    );
    final repository = FilterRepositoryImpl();
    final transaction = CreateFilterCommitTransaction(
      repository: repository,
      previewRenderer: FileCreateFilterPreviewRenderer(),
    );
    final committed = await transaction.commit(
      preset: preset,
      sourcePath: sourcePath,
    );

    final reloaded = await FilterRepositoryImpl().getPresetById(preset.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.effectiveRecipe.generatorType, 'neural');
    expect(reloaded.effectiveRecipe.modelId, kColorTransferModelId);
    expect(reloaded.effectiveRecipe.modelVersion, kColorTransferModelVersion);
    expect(File(committed.previewPath).existsSync(), isTrue);

    final source = img.bakeOrientation(
      img.decodeImage(await File(sourcePath).readAsBytes())!,
    );
    final beforeReload = applyImagePipeline(
      image: source,
      params: preset.params,
      lutBytes: await loadLutBytes(preset.lutPath),
      intensity: preset.defaultIntensity,
    );
    final afterReload = applyImagePipeline(
      image: source,
      params: reloaded.params,
      lutBytes: await loadLutBytes(reloaded.lutPath),
      intensity: reloaded.defaultIntensity,
    );
    final beforeHash = sha256.convert(img.encodePng(beforeReload)).toString();
    final afterHash = sha256.convert(img.encodePng(afterReload)).toString();

    expect(afterHash, beforeHash);
    expect(await repository.getCustomPresets(), hasLength(1));
  });
}
