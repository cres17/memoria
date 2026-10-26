import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

// ── helpers ────────────────────────────────────────────────

/// Solid-colour 8×8 image.
img.Image _solidImage(int r, int g, int b) {
  final im = img.Image(width: 8, height: 8);
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      im.setPixelRgb(x, y, r, g, b);
    }
  }
  return im;
}

/// White-noise image seeded for reproducibility.
img.Image _noiseImage(int w, int h, {int seed = 42}) {
  final im = img.Image(width: w, height: h);
  var rng = seed;
  int lcg() {
    rng = (rng * 1664525 + 1013904223) & 0x7FFFFFFF;
    return rng & 0xFF;
  }

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgb(x, y, lcg(), lcg(), lcg());
    }
  }
  return im;
}

/// Average pixel brightness [0,255] across all pixels.
double _avgBrightness(img.Image im) {
  final nc = im.numChannels;
  final bytes = im.data!.buffer.asUint8List();
  double sum = 0;
  int count = 0;
  for (int i = 0; i < bytes.length; i += nc) {
    sum += bytes[i] + bytes[i + 1] + bytes[i + 2];
    count += 3;
  }
  return count > 0 ? sum / count : 0;
}

/// Per-channel standard deviation of a solid image run through NR.
double _channelStdDev(img.Image im, int ch) {
  final nc = im.numChannels;
  final bytes = im.data!.buffer.asUint8List();
  double sum = 0, sumSq = 0;
  int n = 0;
  for (int i = 0; i < bytes.length; i += nc) {
    final v = bytes[i + ch].toDouble();
    sum += v;
    sumSq += v * v;
    n++;
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return (sumSq / n - mean * mean > 0)
      ? (sumSq / n - mean * mean).toDouble()
      : 0.0; // return variance for comparison
}

void main() {
  // ── AdjustParams model ─────────────────────────────────────

  group('AdjustParams noise reduction', () {
    test('default values are zero / inactive', () {
      const p = AdjustParams.zero;
      expect(p.luminanceNR, 0.0);
      expect(p.colourNR, 0.0);
      expect(p.nrDetail, 0.0);
      expect(p.hasNoiseReduction, isFalse);
    });

    test('hasNoiseReduction when luminanceNR > 0', () {
      final p = AdjustParams.zero.copyWith(luminanceNR: 50.0);
      expect(p.hasNoiseReduction, isTrue);
    });

    test('hasNoiseReduction when colourNR > 0', () {
      final p = AdjustParams.zero.copyWith(colourNR: 30.0);
      expect(p.hasNoiseReduction, isTrue);
    });

    test('hasNoiseReduction false when only nrDetail > 0', () {
      // nrDetail alone does not trigger NR (no L-channel to sharpen if no filtering)
      final p = AdjustParams.zero.copyWith(nrDetail: 50.0);
      expect(p.hasNoiseReduction, isFalse);
    });

    test('JSON round-trip preserves all NR fields', () {
      final p = AdjustParams.zero.copyWith(
        luminanceNR: 42.0,
        colourNR: 28.0,
        nrDetail: 60.0,
      );
      final restored = AdjustParams.fromJson(p.toJson());
      expect(restored.luminanceNR, closeTo(42.0, 0.001));
      expect(restored.colourNR, closeTo(28.0, 0.001));
      expect(restored.nrDetail, closeTo(60.0, 0.001));
    });

    test('JSON defaults to 0 when NR keys absent', () {
      final p = AdjustParams.fromJson({});
      expect(p.luminanceNR, 0.0);
      expect(p.colourNR, 0.0);
      expect(p.nrDetail, 0.0);
    });

    test('cacheKey changes when luminanceNR changes', () {
      const p1 = AdjustParams.zero;
      final p2 = p1.copyWith(luminanceNR: 50.0);
      expect(p1.cacheKey, isNot(p2.cacheKey));
    });

    test('cacheKey changes when colourNR changes', () {
      const p1 = AdjustParams.zero;
      final p2 = p1.copyWith(colourNR: 40.0);
      expect(p1.cacheKey, isNot(p2.cacheKey));
    });

    test('cacheKey changes when nrDetail changes', () {
      const p1 = AdjustParams.zero;
      final p2 = p1.copyWith(nrDetail: 70.0);
      expect(p1.cacheKey, isNot(p2.cacheKey));
    });

    test('isZero false when hasNoiseReduction is true', () {
      final p = AdjustParams.zero.copyWith(luminanceNR: 10.0);
      expect(p.isZero, isFalse);
    });

    test('copyWith preserves unrelated fields', () {
      final p = AdjustParams.zero.copyWith(
        exposure: 0.5,
        luminanceNR: 20.0,
      );
      final p2 = p.copyWith(colourNR: 15.0);
      expect(p2.exposure, closeTo(0.5, 0.001));
      expect(p2.luminanceNR, closeTo(20.0, 0.001));
      expect(p2.colourNR, closeTo(15.0, 0.001));
    });
  });

  // ── CPU pipeline ────────────────────────────────────────────

  group('applyImagePipeline noise reduction', () {
    test('NR inactive: pipeline output equals non-NR output (solid image)', () {
      final im = _solidImage(128, 100, 80);
      final withoutNR =
          applyImagePipeline(image: im, params: AdjustParams.zero);
      final withNR = applyImagePipeline(
        image: im,
        params: AdjustParams.zero.copyWith(luminanceNR: 0.0, colourNR: 0.0),
      );
      // Solid images should produce identical output either way.
      final b1 = withoutNR.data!.buffer.asUint8List();
      final b2 = withNR.data!.buffer.asUint8List();
      expect(b1, equals(b2));
    });

    test('NR reduces variance in a noisy image', () {
      final noisy = _noiseImage(32, 32);
      // Measure variance of red channel before NR.
      final varBefore = _channelStdDev(noisy, 0);

      final denoised = applyImagePipeline(
        image: noisy,
        params: AdjustParams.zero.copyWith(luminanceNR: 80.0, colourNR: 60.0),
      );
      final varAfter = _channelStdDev(denoised, 0);
      // Bilateral filter should reduce variance (smoother output).
      expect(varAfter, lessThan(varBefore));
    });

    test('NR preserves average brightness within ±5 on solid image', () {
      final im = _solidImage(120, 90, 70);
      final result = applyImagePipeline(
        image: im,
        params: AdjustParams.zero.copyWith(luminanceNR: 60.0, colourNR: 50.0),
      );
      final avgBefore = _avgBrightness(im);
      final avgAfter = _avgBrightness(result);
      expect((avgAfter - avgBefore).abs(), lessThan(5.0));
    });

    test('NR output image has same dimensions as input', () {
      final im = _noiseImage(20, 24);
      final result = applyImagePipeline(
        image: im,
        params: AdjustParams.zero.copyWith(luminanceNR: 50.0),
      );
      expect(result.width, im.width);
      expect(result.height, im.height);
    });

    test('NR skipped on tiny (3×3) image without crash', () {
      final tiny = img.Image(width: 3, height: 3);
      tiny.setPixelRgb(0, 0, 200, 100, 50);
      expect(
        () => applyImagePipeline(
          image: tiny,
          params: AdjustParams.zero.copyWith(luminanceNR: 50.0),
        ),
        returnsNormally,
      );
    });

    test('detail recovery: higher detail → result closer to original luminance',
        () {
      final noisy = _noiseImage(16, 16, seed: 7);

      // With NR only (no detail recovery)
      final noDetail = applyImagePipeline(
        image: noisy,
        params: AdjustParams.zero.copyWith(luminanceNR: 80.0, nrDetail: 0.0),
      );
      // With NR + full detail recovery
      final withDetail = applyImagePipeline(
        image: noisy,
        params: AdjustParams.zero.copyWith(luminanceNR: 80.0, nrDetail: 100.0),
      );

      // Detail recovery brings back some luminance contrast — average pixel
      // difference vs. original should be lower with detail than without.
      double diffNoDetail = 0, diffWithDetail = 0;
      final srcBytes = noisy.data!.buffer.asUint8List();
      final ndBytes = noDetail.data!.buffer.asUint8List();
      final wdBytes = withDetail.data!.buffer.asUint8List();
      final nc = noisy.numChannels;
      for (int i = 0; i < srcBytes.length; i += nc) {
        diffNoDetail += (srcBytes[i] - ndBytes[i]).abs().toDouble();
        diffWithDetail += (srcBytes[i] - wdBytes[i]).abs().toDouble();
      }
      // Detail recovery should bring result closer to original (smaller diff).
      expect(diffWithDetail, lessThan(diffNoDetail));
    });
  });
}
