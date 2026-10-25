import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:memoria/core/remote_config/remote_config.dart';
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/fast_blur.dart';
import 'package:memoria/engine/gpu_ops.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/features/editor/editor_export_service.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/gpu_recipe.dart';
import '../test/visual/reference_image_test.dart' as visual;
import 'gpu_test_photos.g.dart';

Map<String, Object> difference(img.Image a, img.Image b) {
  expect(a.width, b.width);
  expect(a.height, b.height);
  final aa = a.getBytes(order: img.ChannelOrder.rgba);
  final bb = b.getBytes(order: img.ChannelOrder.rgba);
  var max = 0, sum = 0, changed = 0, gt1 = 0;
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < aa.length; i++) {
    final d = (aa[i] - bb[i]).abs();
    hist[d]++;
    if (d > max) max = d;
    sum += d;
    if (d > 0) changed++;
    if (d > 1) gt1++;
  }
  var acc = 0, p99 = 0;
  for (var d = 0; d < 256; d++) {
    acc += hist[d];
    if (acc >= aa.length * .99) {
      p99 = d;
      break;
    }
  }
  return {
    'max_abs': max,
    'mean_abs': sum / aa.length,
    'p99': p99,
    'frac_nonzero': changed / aa.length,
    'frac_gt1': gt1 / aa.length
  };
}

Future<img.Image> backgroundPreview(EditorPreviewRenderRequest request) async {
  // Pass a root token explicitly, just like the production preview worker.
  final token = RootIsolateToken.instance!;
  final bytes = await compute((RootIsolateToken root) async {
    GpuOps.initializeBackground(root);
    final image = img.Image.fromBytes(
        width: request.width,
        height: request.height,
        bytes: request.imageBytes.buffer,
        numChannels: 4);
    if (await const GpuOps(enabled: true).gpuGaussianBlur(image, 1) == null) {
      throw StateError('Background isolate did not reach native Metal');
    }
    return EditorRenderer.renderPreviewBytes(request);
  }, token);
  return img.decodePng(bytes)!;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'iOS Metal parity, background channels, and complete export timing',
      (tester) async {
    expect(Platform.isIOS, isTrue);
    final measurements = <Map<String, Object?>>[];
    final gpu = GpuOps(enabled: true, onTiming: measurements.add);
    for (var photo = 0; photo < gpuTestPhotos.length; photo++) {
      final decoded = img.decodeJpg(base64Decode(gpuTestPhotos[photo]))!;
      final source =
          img.copyResize(decoded, width: 320).convert(numChannels: 4);
      // Exercise RGBA and tile boundaries with non-opaque alpha.
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.getPixel(x, y).a = (x * 17 + y * 31) % 256;
        }
      }
      for (final config in [
        [25.0, 25.0, 0.0],
        [100.0, 100.0, 0.0],
        [35.0, 0.0, 40.0],
        [0.0, 70.0, 50.0],
        [75.0, 65.0, 75.0]
      ]) {
        final params = AdjustParams(
            luminanceNR: config[0], colourNR: config[1], nrDetail: config[2]);
        final expected = applyImagePipeline(image: source, params: params);
        final actual = await applyImagePipelineAsync(
            image: source, params: params, gpu: gpu);
        final d = difference(expected, actual);
        debugPrint('GPU_DIFF ${jsonEncode({
              'photo': photo,
              'op': 'noise',
              'config': config,
              ...d
            })}');
        expect(d['max_abs'], lessThanOrEqualTo(1));
        for (var y = 0; y < source.height; y++) {
          for (var x = 0; x < source.width; x++) {
            expect(actual.getPixel(x, y).a, source.getPixel(x, y).a);
          }
        }
      }
      for (final radius in [1, 5, 20]) {
        final expected =
            fastGaussianBlur(img.Image.from(source), radius: radius);
        final actual = await gpu.gpuGaussianBlur(source, radius);
        expect(actual, isNotNull,
            reason: 'A CPU fallback cannot pass native parity');
        final d = difference(expected, actual!);
        debugPrint('GPU_DIFF ${jsonEncode({
              'photo': photo,
              'op': 'blur',
              'radius': radius,
              ...d
            })}');
        expect(d['max_abs'], lessThanOrEqualTo(2));
      }
      final recipe =
          gpuRecipe(const AdjustParams(luminanceNR: 25, colourNR: 25));
      final preview = await backgroundPreview(EditorPreviewRenderRequest(
          width: source.width,
          height: source.height,
          imageBytes: source.getBytes(order: img.ChannelOrder.rgba),
          recipe: recipe,
          resources: const EditorRenderResources(),
          gpuOpsEnabled: true));
      final expected = await EditorRenderer.applyVisual(
          source, recipe, const EditorRenderResources());
      expect(difference(expected, preview)['max_abs'], lessThanOrEqualTo(1));
    }
    expect(measurements.length, greaterThanOrEqualTo(16));

    // Production has bundled textures. Legacy PNGs were produced by a plain
    // `test` binding where optional rootBundle texture loads were unavailable.
    // Validate real app CPU/GPU parity first, then the unchanged legacy contract.
    expect(
        (await rootBundle.load('assets/overlays/curves/film_curves_def.png'))
            .lengthInBytes,
        greaterThan(0));
    for (final entry in visual.gpuVisualReferenceCases.entries) {
      final photo = entry.value.photo == 'p1' ? 0 : 1;
      final source = visual.prepareVisualReferenceImage(
          img.decodeJpg(base64Decode(gpuTestPhotos[photo]))!);
      final actual = await EditorRenderer.renderExport(
          source: source.clone(), recipe: entry.value.recipe, gpu: gpu);
      final appCpu = await EditorRenderer.renderExport(
          source: source.clone(), recipe: entry.value.recipe);
      final appDiff = visual.compareVisualReference(actual, appCpu);
      debugPrint('GPU_REFERENCE_APP ${entry.key} $appDiff');
      expect(appDiff.ok, isTrue, reason: 'App CPU/GPU ${entry.key}: $appDiff');
      var legacyOutput = actual;
      if (entry.key == 'film_look') {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler('flutter/assets', (_) async => null);
        try {
          legacyOutput = await EditorRenderer.renderExport(
              source: source.clone(), recipe: entry.value.recipe, gpu: gpu);
        } finally {
          messenger.setMockMessageHandler('flutter/assets', null);
        }
      }
      final reference =
          img.decodePng(base64Decode(gpuVisualReferences[entry.key]!))!;
      final diff = visual.compareVisualReference(legacyOutput, reference);
      debugPrint('GPU_REFERENCE ${entry.key} $diff');
      expect(diff.ok, isTrue, reason: '${entry.key}: $diff');
    }

    // Use the actual export service: spawn, file read/decode, native round trips,
    // remaining Dart stages, encode, write, terminal worker message.
    final dir = await getTemporaryDirectory();
    final input = File('${dir.path}/gpu-bench-input.jpg');
    await input.writeAsBytes(base64Decode(gpuTestPhotos.first));
    for (final enabled in [false, true]) {
      RemoteConfigService.instance
          .resetForTest(RemoteConfig(gpuOpsIosEnabled: enabled));
      final timings = <Map<String, dynamic>>[];
      final output = File('${dir.path}/gpu-bench-$enabled.jpg');
      final watch = Stopwatch()..start();
      await EditorExportService(timeout: const Duration(minutes: 10)).render(
        EditorExportRequest(
            imagePath: input.path,
            outputPath: output.path,
            format: ExportFormat.jpeg,
            quality: 90,
            recipe: gpuRecipe(const AdjustParams(
                luminanceNR: 100, colourNR: 100, sharpen: 20))),
        onTiming: timings.add,
      );
      expect(await output.length(), greaterThan(0));
      if (enabled) {
        expect(timings.any((t) => t['op'] == 'noise'), isTrue);
        expect(timings.any((t) => t['op'] == 'blur'), isTrue);
        expect(timings.any((t) => t['phase'] == 'gpu_fallback'), isFalse);
      }
      debugPrint('GPU_EXPORT ${jsonEncode({
            'gpu': enabled,
            'total_ms': watch.elapsedMicroseconds / 1000,
            'timings': timings
          })}');
    }
    RemoteConfigService.instance.resetForTest();
  }, skip: !Platform.isIOS, timeout: const Timeout(Duration(minutes: 20)));
}
