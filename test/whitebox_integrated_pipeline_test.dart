import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/engine/portrait_engine.dart';

void main() {
  group('integrated edit pipeline', () {
    test('global adjustments, curves, B&W, and intensity are applied together',
        () {
      final src = _gradientImage(12, 12);
      const params = AdjustParams(
        exposure: 0.35,
        contrast: 28,
        saturation: 35,
        temperature: 20,
        tint: -10,
        shadows: 25,
        highlights: -15,
        bnwEnabled: true,
        bnwRed: 20,
        tonalMidtones: 35,
        rgbCurve: CurveData(
          channel: CurveChannel.rgb,
          points: [
            CurvePoint(0, 0),
            CurvePoint(0.45, 0.55),
            CurvePoint(1, 1),
          ],
        ),
      );

      final full = applyImagePipeline(
        image: src,
        params: params,
        lutBytes: null,
        intensity: 1,
      );
      final half = applyImagePipeline(
        image: src,
        params: params,
        lutBytes: null,
        intensity: 0.5,
      );

      expect(_imageDiff(src, full), greaterThan(0));
      expect(_imageDiff(src, half), greaterThan(0));
      expect(_imageDiff(src, half), lessThan(_imageDiff(src, full)));

      final px = full.getPixel(6, 6);
      expect((px.r - px.g).abs(), lessThanOrEqualTo(1),
          reason: 'B&W must be preserved after all tonal operations');
      expect((px.g - px.b).abs(), lessThanOrEqualTo(1),
          reason: 'B&W must be preserved after all tonal operations');
    });

    test('portrait effects can be combined with a blend layer', () {
      final src = _solidImage(12, 12, 150, 110, 90);
      final mask = Float32List(src.width * src.height)..fillRange(0, 144, 1);

      final smooth = applySkinSmoothing(src, mask, 70);
      final spotlight = applyFaceSpotlight(smooth, mask, 60);
      final toned = applySkinToning(spotlight, mask, SkinTone.fair, 80);
      final overlay = _solidImage(12, 12, 40, 120, 220);
      final blended = bm.blendImages(
        dst: toned,
        src: overlay,
        mode: bm.BlendMode.overlay,
        opacity: 0.35,
      );

      expect(blended.width, src.width);
      expect(blended.height, src.height);
      expect(_imageDiff(src, blended), greaterThan(0));
    });
  });
}

img.Image _solidImage(int w, int h, int r, int g, int b) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

img.Image _gradientImage(int w, int h) {
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.setPixelRgb(
        x,
        y,
        (40 + x * 160 / (w - 1)).round(),
        (50 + y * 150 / (h - 1)).round(),
        (80 + (x + y) * 80 / (w + h - 2)).round(),
      );
    }
  }
  return out;
}

int _imageDiff(img.Image a, img.Image b) {
  var diff = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final ap = a.getPixel(x, y);
      final bp = b.getPixel(x, y);
      diff += (ap.r - bp.r).abs().round();
      diff += (ap.g - bp.g).abs().round();
      diff += (ap.b - bp.b).abs().round();
    }
  }
  return diff;
}
