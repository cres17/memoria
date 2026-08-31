import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_export_failure.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';

void main() {
  test('renders a real fixture through the production export boundary',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final output = File('${directory.path}/fixture-export.png');
    final progress = <double>[];

    final result = await EditorExportService().render(
      EditorExportRequest(
        imagePath: 'assets/images/summer_sapporo.jpg',
        outputPath: output.path,
        format: ExportFormat.png,
        quality: 92,
        maxDimension: 640,
        recipe: _fixtureRecipe(),
      ),
      onProgress: progress.add,
    );

    expect(result, EditorExportJobResult.completed);
    expect(output.existsSync(), isTrue);
    final bytes = output.readAsBytesSync();
    expect(ExportEncoder.matchesSignature(ExportFormat.png, bytes), isTrue);
    expect(progress, isNotEmpty);
    expect(progress.last, 0.95);
  });

  test('production export isolate stays on the real-photo pixel baseline',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_golden_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final output = File('${directory.path}/fixture-export-golden.png');

    final result = await EditorExportService().render(
      EditorExportRequest(
        imagePath: 'assets/images/summer_sapporo.jpg',
        outputPath: output.path,
        format: ExportFormat.png,
        quality: 92,
        maxDimension: 360,
        recipe: _fixtureRecipe(),
      ),
    );

    final decoded = img.decodeImage(await output.readAsBytes());
    expect(result, EditorExportJobResult.completed);
    expect(decoded, isNotNull);
    expect(_rgbaHash(decoded!), 'ce381fec');
  });

  test('production export isolate writes every Dart-encoded format faithfully',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_formats_',
    );
    addTearDown(() => directory.delete(recursive: true));

    for (final format in const <ExportFormat>[
      ExportFormat.jpeg,
      ExportFormat.png,
      ExportFormat.tiff,
    ]) {
      final output = File('${directory.path}/fixture.${format.extension}');
      final result = await EditorExportService().render(
        EditorExportRequest(
          imagePath: 'assets/images/summer_sapporo.jpg',
          outputPath: output.path,
          format: format,
          quality: 92,
          maxDimension: 360,
          recipe: _fixtureRecipe(),
        ),
      );
      final bytes = await output.readAsBytes();
      final decoded = img.decodeImage(bytes);

      expect(result, EditorExportJobResult.completed);
      expect(ExportEncoder.matchesSignature(format, bytes), isTrue);
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
    }
  });

  test('production export bakes JPEG EXIF orientation before rendering',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_orientation_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/rotated.jpg');
    final output = File('${directory.path}/rendered.png');
    final source = img.Image(width: 80, height: 40)
      ..clear(img.ColorRgba8(80, 120, 180, 255));
    source.exif.imageIfd.orientation = 6;
    await input.writeAsBytes(img.encodeJpg(source));

    final result = await EditorExportService().render(
      EditorExportRequest(
        imagePath: input.path,
        outputPath: output.path,
        format: ExportFormat.png,
        quality: 92,
        recipe: _request().recipe,
      ),
    );
    final decoded = img.decodeImage(await output.readAsBytes());

    expect(result, EditorExportJobResult.completed);
    expect(decoded, isNotNull);
    expect(decoded!.width, 40);
    // The shared 4:3 recipe crops the baked 40×80 portrait source to 40×30.
    // Without EXIF baking this would instead be a 53×40 landscape result.
    expect(decoded.height, 30);
  });

  test('transports a typed decode failure from the export worker', () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_failure_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final invalidInput = File('${directory.path}/invalid.jpg');
    await invalidInput.writeAsBytes(const [0, 1, 2, 3]);

    await expectLater(
      EditorExportService().render(
        EditorExportRequest(
          imagePath: invalidInput.path,
          outputPath: '${directory.path}/unused.png',
          format: ExportFormat.png,
          quality: 92,
          recipe: _fixtureRecipe(),
        ),
      ),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.inputDecode,
        ),
      ),
    );
  });

  test('transports an output write failure from the export worker', () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_write_failure_',
    );
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      EditorExportService().render(
        EditorExportRequest(
          imagePath: 'assets/images/summer_sapporo.jpg',
          outputPath: directory.path,
          format: ExportFormat.png,
          quality: 92,
          recipe: _fixtureRecipe(),
        ),
      ),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.outputWrite,
        ),
      ),
    );
  });

  test(
      'fails instead of hanging when a worker exits without a terminal message',
      () async {
    await expectLater(
      EditorExportService(worker: _exitWithoutTerminal).render(_request()),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.workerTerminated,
        ),
      ),
    );
  });

  test('times out a non-terminal worker and releases the service', () async {
    final service = EditorExportService(
      timeout: const Duration(milliseconds: 25),
      worker: _neverFinishes,
    );

    await expectLater(
      service.render(_request()),
      throwsA(
        isA<EditorExportFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorExportFailureKind.timeout,
        ),
      ),
    );
    expect(
      await service.render(_request(quality: 2)),
      EditorExportJobResult.completed,
    );
  });

  test('cancel waits for cleanup before allowing another export', () async {
    final directory = await Directory.systemTemp.createTemp(
      'memoria_editor_export_cancel_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final partialOutput = File('${directory.path}/partial.png');
    final progressSeen = Completer<void>();
    final service = EditorExportService(worker: _cancelThenFinish);
    final running = service.render(
      _request(outputPath: partialOutput.path),
      onProgress: (_) {
        if (!progressSeen.isCompleted) progressSeen.complete();
      },
    );
    await progressSeen.future;

    final cleanup = service.cancel();
    await expectLater(
      service.render(_request(quality: 2)),
      throwsA(isA<StateError>()),
    );
    await cleanup;
    expect(await running, EditorExportJobResult.cancelled);
    expect(await partialOutput.exists(), isFalse);
    expect(
      await service.render(_request(quality: 2)),
      EditorExportJobResult.completed,
    );
  });

  test('forwards only monotonic, bounded progress before terminal success',
      () async {
    final progress = <double>[];

    final result = await EditorExportService(worker: _progressNoise).render(
      _request(),
      onProgress: progress.add,
    );

    expect(result, EditorExportJobResult.completed);
    expect(progress, <double>[0.01, 0.6, 0.99]);
  });

  test('keeps progress callbacks alive during a long worker stage', () async {
    final elapsed = <Duration>[];
    final stopwatch = Stopwatch()..start();

    final result = await EditorExportService(
      worker: _slowProgressStage,
      progressPulseInterval: const Duration(milliseconds: 20),
    ).render(
      _request(),
      onProgress: (_) => elapsed.add(stopwatch.elapsed),
    );

    expect(result, EditorExportJobResult.completed);
    expect(elapsed.length, greaterThanOrEqualTo(5));
    for (var index = 1; index < elapsed.length; index++) {
      expect(
        elapsed[index] - elapsed[index - 1],
        lessThan(const Duration(milliseconds: 80)),
      );
    }
  });
}

EditorExportRequest _request({
  String imagePath = 'assets/images/summer_sapporo.jpg',
  String outputPath = 'unused.png',
  int quality = 1,
}) =>
    EditorExportRequest(
      imagePath: imagePath,
      outputPath: outputPath,
      format: ExportFormat.png,
      quality: quality,
      recipe: _fixtureRecipe(),
    );

Future<void> _exitWithoutTerminal(EditorExportWorkerContext _) async {}

Future<void> _neverFinishes(EditorExportWorkerContext context) async {
  if (context.request.quality == 2) {
    context.sendPort.send('done');
    return;
  }
  await Future<void>.delayed(const Duration(seconds: 10));
}

Future<void> _cancelThenFinish(EditorExportWorkerContext context) async {
  if (context.request.quality == 2) {
    context.sendPort.send('done');
    return;
  }
  await File(context.request.outputPath).writeAsBytes(const [1, 2, 3]);
  context.sendPort.send(0.2);
  await Future<void>.delayed(const Duration(seconds: 10));
}

Future<void> _progressNoise(EditorExportWorkerContext context) async {
  context.sendPort.send(0.6);
  context.sendPort.send(0.2);
  context.sendPort.send(3.0);
  context.sendPort.send('done');
}

Future<void> _slowProgressStage(EditorExportWorkerContext context) async {
  context.sendPort.send(0.4);
  await Future<void>.delayed(const Duration(milliseconds: 140));
  context.sendPort.send(0.95);
  context.sendPort.send('done');
}

String _rgbaHash(img.Image image) {
  var hash = 0x811c9dc5;
  for (final byte in image.getBytes(order: img.ChannelOrder.rgba)) {
    hash = (hash ^ byte) * 0x01000193 & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

EditorRenderRecipe _fixtureRecipe() => EditorRenderRecipe(
      adjustParams: const AdjustParams(
        exposure: 0.15,
        contrast: 12,
        saturation: 8,
        highlights: -10,
      ),
      lutBytes: null,
      intensity: 1,
      crop: const CropState(centerX: 0.5, centerY: 0.5, flipV: true),
      cropAspectRatio: 4 / 3,
      effect: ArtisticEffect.none,
      effectStrength: 1,
      grainVariant: 0,
      selectiveActive: false,
      selectiveX: 0.5,
      selectiveY: 0.5,
      selectiveBrightness: 0,
      selectiveContrast: 0,
      selectiveSaturation: 0,
      selectiveRadius: 0.3,
      dodgeBurnActive: false,
      dodgeStrength: 0,
      dodgeY: 0.5,
      dodgeRadius: 0.3,
      burnStrength: 0,
      burnY: 0.5,
      burnRadius: 0.3,
      tiltActive: false,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.3,
      tiltMaxBlur: 0,
      lensActive: false,
      lensFocusDepth: 0,
      lensMaxRadius: 0,
      portrait: PortraitParams.zero,
      creative: CreativeParams.zero,
      brushStrokes: const [],
    );
