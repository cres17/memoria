import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/ai/ai_manager.dart';
import 'package:memoria/ai/models/segmenter.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:path_provider/path_provider.dart';

import 'support/process_memory_sampler.dart';

// Run explicitly on a physical iOS device in profile mode. This is a bounded
// synthetic stress probe, not the complete release-quality/device matrix.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('physical iOS portrait masks and JPEG exports at 12/24MP',
      (tester) async {
    const physical = bool.fromEnvironment('MEMORIA_PHYSICAL_DEVICE');
    const deviceName = String.fromEnvironment('MEMORIA_PERF_DEVICE_NAME');
    const limitMiB =
        int.fromEnvironment('MEMORIA_RSS_DELTA_LIMIT_MIB', defaultValue: 500);
    if (!Platform.isIOS || !physical || !kProfileMode || deviceName.isEmpty) {
      throw StateError('Use a physical iOS device, --profile, '
          'MEMORIA_PHYSICAL_DEVICE=true and MEMORIA_PERF_DEVICE_NAME.');
    }
    if (limitMiB <= 0) throw StateError('RSS delta limit must be positive');

    final directory = await getTemporaryDirectory();
    final modelPath = await AiManager.instance.require(kModelSelfie);
    final segmenter = await SelfieSegmenter.load(modelPath);
    final reports = <Map<String, Object>>[];
    try {
      for (final dimensions in const [(4000, 3000), (6000, 4000)]) {
        final (width, height) = dimensions;
        final input =
            File('${directory.path}/portrait_probe_${width}x$height.jpg');
        final output = File('${directory.path}/portrait_probe_output.jpg');
        await Isolate.run(() {
          final image = img.Image(width: width, height: height);
          input.writeAsBytesSync(img.encodeJpg(image, quality: 95),
              flush: true);
        });
        final sampler = await ProcessMemorySampler.start();
        try {
          final watch = Stopwatch()..start();
          final source = img.decodeJpg(await input.readAsBytes())!;
          final mask = segmenter.segment(source);
          final maskMs = watch.elapsedMilliseconds;
          expect(mask.width, width);
          expect(mask.height, height);
          expect(mask.data.every((value) => value.isFinite), isTrue);
          // Empty background also guards against a second sigmoid.
          expect(mask.data.every((value) => value < 0.1), isTrue);
          final exportWatch = Stopwatch()..start();
          final result = await EditorExportService().render(
            EditorExportRequest(
              imagePath: input.path,
              outputPath: output.path,
              format: ExportFormat.jpeg,
              quality: 95,
              recipe: _portraitRecipe(),
              segmentMask: mask.data,
              segmentMaskWidth: width,
              segmentMaskHeight: height,
            ),
          );
          exportWatch.stop();
          watch.stop();
          expect(result, EditorExportJobResult.completed);
          final outputBytes = await output.readAsBytes();
          expect(ExportEncoder.matchesSignature(ExportFormat.jpeg, outputBytes),
              isTrue);
          final decoded = img.decodeJpg(outputBytes)!;
          expect((decoded.width, decoded.height), dimensions);
          final memory = await sampler.stop();
          final report = <String, Object>{
            'width': width,
            'height': height,
            'maskMs': maskMs,
            'exportMs': exportWatch.elapsedMilliseconds,
            'totalMs': watch.elapsedMilliseconds,
            'outputBytes': outputBytes.length,
            'rssBytes': memory,
            'rssDeltaLimitMiB': limitMiB,
          };
          reports.add(report);
          // Retain partial evidence even if the bound assertion fails.
          binding.reportData = {'portraitMemory': reports};
          // ignore: avoid_print
          print('IOS_PORTRAIT_MEMORY_CASE=${jsonEncode(report)}');
          expect(memory['peakDelta'], lessThanOrEqualTo(limitMiB * 1024 * 1024),
              reason: 'Predeclared process RSS delta limit exceeded');
        } finally {
          await sampler.stop();
          if (await input.exists()) await input.delete();
          if (await output.exists()) await output.delete();
        }
      }
      final report = <String, Object>{
        'schemaVersion': 1,
        'deviceName': deviceName,
        'osVersion': Platform.operatingSystemVersion,
        'buildMode': 'profile',
        'modelSha256': kModelSelfie.sha256,
        'cases': reports,
        'limitations': [
          'One synthetic black-background sample per resolution; no quality claim.',
          'RSS includes the test runner; it is not iOS physical footprint.',
          'Baseline includes the prepared model; output validation is sampled too.',
          'No OS memory-warning, external-pressure or jetsam-log collection.',
          'No Photos write or native share in this probe.',
          'A modern phone result does not validate a 2GB device.',
        ],
      };
      binding.reportData = {'portraitMemory': report};
      // ignore: avoid_print
      print('IOS_PORTRAIT_MEMORY_RESULT=${jsonEncode(report)}');
    } finally {
      segmenter.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

EditorRenderRecipe _portraitRecipe() => EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: CropState.identity,
      cropAspectRatio: null,
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
      portrait: const PortraitParams(spotlight: 20),
      creative: CreativeParams.zero,
      brushStrokes: const [],
    );
