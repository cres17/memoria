import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_media_export_coordinator.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_resource_preparer.dart';

void main() {
  test('publishes a validated output and removes non-shared temp files',
      () async {
    final directory = await Directory.systemTemp.createTemp('memoria_media_');
    addTearDown(() => directory.delete(recursive: true));
    var saved = false;
    String? savedPath;

    final coordinator = EditorMediaExportCoordinator(
      isIos: () => false,
      temporaryDirectory: () async => directory,
      loadSettings: (_) async =>
          const ExportSettings(format: ExportFormat.png, quality: 91),
      render: _writeValidOutput,
      saveToGallery: (path) async {
        saved = await File(path).exists();
        savedPath = path;
      },
      share: (_) async {},
    );

    final result = await coordinator.export(
      share: false,
      buildRequest: _requestFor,
      onProgress: (_) {},
    );

    expect(result.cancelled, isFalse);
    expect(result.format, ExportFormat.png);
    expect(saved, isTrue);
    expect(savedPath, isNotNull);
    expect(await File(savedPath!).exists(), isFalse);
  });

  test('normalizes a persisted WebP preference when native support is absent',
      () async {
    final directory = await Directory.systemTemp.createTemp('memoria_webp_');
    addTearDown(() => directory.delete(recursive: true));
    var allowWebp = true;
    var nativeEncoderCalled = false;
    ExportFormat? renderFormat;

    final coordinator = EditorMediaExportCoordinator(
      isIos: () => true,
      supportsWebp: () async => false,
      temporaryDirectory: () async => directory,
      loadSettings: (allow) async {
        allowWebp = allow;
        return const ExportSettings(format: ExportFormat.webp, quality: 92)
            .normalized(allowWebp: allow);
      },
      render: (request, {onProgress}) async {
        renderFormat = request.format;
        await _writeSignature(request.outputPath, request.format);
        return EditorExportJobResult.completed;
      },
      encodeWebp: (
          {required inputPath, required outputPath, required quality}) async {
        nativeEncoderCalled = true;
        return false;
      },
      saveToGallery: (_) async {},
      share: (_) async {},
    );

    final result = await coordinator.export(
      share: false,
      buildRequest: _requestFor,
      onProgress: (_) {},
    );

    expect(allowWebp, isFalse);
    expect(result.format, ExportFormat.jpeg);
    expect(renderFormat, ExportFormat.jpeg);
    expect(nativeEncoderCalled, isFalse);
  });

  test('retries memory pressure once at the next configured resolution',
      () async {
    final directory = await Directory.systemTemp.createTemp('memoria_retry_');
    addTearDown(() => directory.delete(recursive: true));
    final dimensions = <int?>[];
    final retriedAt = <int>[];

    final coordinator = EditorMediaExportCoordinator(
      isIos: () => false,
      temporaryDirectory: () async => directory,
      loadSettings: (_) async =>
          const ExportSettings(format: ExportFormat.jpeg, quality: 90),
      render: (request, {onProgress}) async {
        dimensions.add(request.maxDimension);
        if (dimensions.length == 1) {
          throw const EditorExportFailure(
            EditorExportFailureKind.memoryPressure,
            'test memory pressure',
          );
        }
        await _writeSignature(request.outputPath, request.format);
        return EditorExportJobResult.completed;
      },
      saveToGallery: (_) async {},
      share: (_) async {},
    );

    final result = await coordinator.export(
      share: false,
      buildRequest: _requestFor,
      onProgress: (_) {},
      onRetryAtLowerResolution: retriedAt.add,
    );

    expect(result.cancelled, isFalse);
    expect(dimensions, [null, 4096]);
    expect(retriedAt, [4096]);
  });

  test('removes final and intermediate files when native WebP encoding fails',
      () async {
    final directory = await Directory.systemTemp.createTemp('memoria_webp_');
    addTearDown(() => directory.delete(recursive: true));

    final coordinator = EditorMediaExportCoordinator(
      isIos: () => true,
      supportsWebp: () async => true,
      temporaryDirectory: () async => directory,
      loadSettings: (_) async =>
          const ExportSettings(format: ExportFormat.webp, quality: 92),
      render: _writeValidOutput,
      encodeWebp: (
              {required inputPath,
              required outputPath,
              required quality}) async =>
          false,
      saveToGallery: (_) async {},
      share: (_) async {},
    );

    await expectLater(
      () => coordinator.export(
        share: false,
        buildRequest: _requestFor,
        onProgress: (_) {},
      ),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.nativeEncoding,
        ),
      ),
    );

    expect(await directory.list().toList(), isEmpty);
  });

  test('cleans allocated output when typed resource preparation fails',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('memoria_resource_');
    addTearDown(() => directory.delete(recursive: true));
    final coordinator = EditorMediaExportCoordinator(
      isIos: () => false,
      temporaryDirectory: () async => directory,
      loadSettings: (_) async =>
          const ExportSettings(format: ExportFormat.png, quality: 91),
      saveToGallery: (_) async {},
      share: (_) async {},
    );

    await expectLater(
      () => coordinator.export(
        share: false,
        buildRequest: (attempt) async {
          await File(attempt.outputPath).writeAsBytes(const [1, 2, 3]);
          throw const EditorResourcePreparationFailure(
            EditorResourceFailureKind.textOverlay,
            'text resource unavailable',
          );
        },
        onProgress: (_) {},
      ),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.resourcePreparation,
        ),
      ),
    );

    expect(await directory.list().toList(), isEmpty);
  });
}

Future<EditorExportRequest> _requestFor(
    EditorMediaExportAttempt attempt) async {
  return EditorExportRequest(
    imagePath: 'unused-for-coordinator-test',
    outputPath: attempt.outputPath,
    format: attempt.renderFormat,
    quality: attempt.quality,
    maxDimension: attempt.maxDimension,
    recipe: _testRecipe,
  );
}

final _testRecipe = EditorRenderRecipe(
  adjustParams: AdjustParams.zero,
  lutBytes: null,
  intensity: 1,
  crop: const CropState(),
  cropAspectRatio: null,
  effect: ArtisticEffect.none,
  effectStrength: 1,
  grainVariant: 3,
  selectiveActive: false,
  selectiveX: 0.5,
  selectiveY: 0.5,
  selectiveBrightness: 0,
  selectiveContrast: 0,
  selectiveSaturation: 0,
  selectiveRadius: 0.3,
  dodgeBurnActive: false,
  dodgeStrength: 0,
  dodgeY: 0.25,
  dodgeRadius: 0.25,
  burnStrength: 0,
  burnY: 0.75,
  burnRadius: 0.25,
  tiltActive: false,
  tiltFocusCenter: 0.5,
  tiltBandWidth: 0.3,
  tiltMaxBlur: 8,
  lensActive: false,
  lensFocusDepth: 0,
  lensMaxRadius: 8,
  portrait: const PortraitParams(),
  creative: const CreativeParams(),
  brushStrokes: const [],
);

Future<EditorExportJobResult> _writeValidOutput(
  EditorExportRequest request, {
  void Function(double progress)? onProgress,
}) async {
  onProgress?.call(0.5);
  await _writeSignature(request.outputPath, request.format);
  return EditorExportJobResult.completed;
}

Future<void> _writeSignature(String path, ExportFormat format) {
  final bytes = switch (format) {
    ExportFormat.jpeg => const [0xFF, 0xD8, 0xFF],
    ExportFormat.png => const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    ExportFormat.webp => const [
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50
      ],
    ExportFormat.tiff => const [0x49, 0x49, 0x2A, 0x00],
  };
  return File(path).writeAsBytes(bytes);
}
