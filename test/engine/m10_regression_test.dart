import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';

void main() {
  group('M10 regression gate', () {
    test(
        'production renderer applies the M6-M9 visual stack without blank output',
        () async {
      final original = _gradientImage(96, 64);
      final blend = _solidImage(96, 64, 32, 96, 220);
      final out = await EditorRenderer.renderExport(
        source: original,
        recipe: _integratedRecipe(),
        resources: EditorRenderResources(
          segmentMask: _centerMask(original.width, original.height),
          segmentMaskWidth: original.width,
          segmentMaskHeight: original.height,
          blendImageBytes: Uint8List.fromList(img.encodePng(blend)),
        ),
      );

      expect(out.width, original.width);
      expect(out.height, original.height);
      expect(_meanAbsoluteDelta(original, out), greaterThan(2.0));
      expect(_lumaVariance(out), greaterThan(10.0));
    });

    test('perf baseline contains all M10 tracked metrics', () {
      final file = File('tool/perf_baseline.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      for (final key in [
        'rawHealKernelMedianMs',
        'healMedianMs',
        'portraitKernelMedianMs',
        'integratedKernelMedianMs',
        'rssDeltaMb',
      ]) {
        expect(json[key], isA<num>(), reason: 'missing metric $key');
      }
    });

    test('editor disposes long-lived native/GPU resources', () {
      final source =
          File('lib/features/editor/editor_page.dart').readAsStringSync();
      for (final call in [
        '_segmenter?.dispose()',
        '_depthEstimator?.dispose()',
        '_gpuSourceImage?.dispose()',
        '_gpuLutAtlas?.dispose()',
        '_gpuCurve1D?.dispose()',
        '_gpuLumCurve?.dispose()',
        '_transformCtrl.dispose()',
      ]) {
        expect(source, contains(call), reason: 'missing dispose call: $call');
      }
    });
  });
}

EditorRenderRecipe _integratedRecipe() => EditorRenderRecipe(
      adjustParams: const AdjustParams(
        exposure: 0.12,
        contrast: 12,
        saturation: 8,
        structure: 10,
        glowStrength: 12,
        hdrStrength: 14,
        lightLeakStrength: 16,
        lightLeakAngle: 28,
        halationStrength: 18,
        halationThreshold: 58,
      ),
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
      lensActive: true,
      lensFocusDepth: 0.35,
      lensMaxRadius: 2,
      portrait: const PortraitParams(
        smooth: 16,
        spotlight: 18,
        skinTone: SkinTone.medium,
        skinToneStrength: 18,
      ),
      creative: const CreativeParams(
        blendImagePath: 'memory://blend',
        blendMode: bm.BlendMode.overlay,
        blendOpacity: 0.20,
      ),
      brushStrokes: const [],
    );

img.Image _gradientImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (48 + x * 144 / (width - 1)).round(),
        (64 + y * 120 / (height - 1)).round(),
        (96 + (x + y) * 72 / (width + height - 2)).round(),
      );
    }
  }
  return image;
}

img.Image _solidImage(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

Float32List _centerMask(int width, int height) {
  final mask = Float32List(width * height);
  final cx = (width - 1) / 2;
  final cy = (height - 1) / 2;
  final rx = width * 0.30;
  final ry = height * 0.36;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = (x - cx) / rx;
      final dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) {
        mask[y * width + x] = 1;
      }
    }
  }
  return mask;
}

double _meanAbsoluteDelta(img.Image a, img.Image b) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final ap = a.getPixel(x, y);
      final bp = b.getPixel(x, y);
      sum += (ap.r - bp.r).abs();
      sum += (ap.g - bp.g).abs();
      sum += (ap.b - bp.b).abs();
      count += 3;
    }
  }
  return sum / count;
}

double _lumaVariance(img.Image image) {
  final values = <double>[];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      values.add(p.r * 0.299 + p.g * 0.587 + p.b * 0.114);
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  var variance = 0.0;
  for (final value in values) {
    final d = value - mean;
    variance += d * d;
  }
  return variance / values.length;
}
