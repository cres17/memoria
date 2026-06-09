import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/engine/raw_processor.dart';

void main() {
  group('Noise Reduction Engine Tests', () {
    // Generate a synthetic noisy image
    img.Image createNoisyImage() {
      final image = img.Image(width: 32, height: 32);
      final rand = math.Random(1234);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          // Base gray = 128, add Gaussian-like noise in range [-20, 20]
          final noise = rand.nextInt(41) - 20;
          final val = (128 + noise).clamp(0, 255);
          image.setPixelRgb(x, y, val, val, val);
        }
      }
      return image;
    }

    // Helper to calculate variance of an image channel
    double getVariance(img.Image image) {
      var sum = 0.0;
      var sumSq = 0.0;
      final n = image.width * image.height;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final val = image.getPixel(x, y).r.toDouble();
          sum += val;
          sumSq += val * val;
        }
      }
      final mean = sum / n;
      return (sumSq / n) - (mean * mean);
    }

    test('no-op when NR strength parameters are zero', () {
      final original = createNoisyImage();
      const params = AdjustParams(
        luminanceNR: 0.0,
        colourNR: 0.0,
        nrDetail: 50.0,
      );

      final out = applyImagePipeline(image: original, params: params);

      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          final pIn = original.getPixel(x, y);
          final pOut = out.getPixel(x, y);
          expect(pOut.r, equals(pIn.r));
          expect(pOut.g, equals(pIn.g));
          expect(pOut.b, equals(pIn.b));
        }
      }
    });

    test('luminance NR successfully reduces pixel variance (noise)', () {
      final original = createNoisyImage();
      final initialVar = getVariance(original);

      const params = AdjustParams(
        luminanceNR: 65.0,
        colourNR: 0.0,
        nrDetail: 0.0, // No detail recovery to maximize denoising
      );

      final out = applyImagePipeline(image: original, params: params);
      final finalVar = getVariance(out);

      // Variance should drop significantly after denoising
      expect(finalVar, lessThan(initialVar * 0.5));
    });

    test('nrDetail preserves edges and limits over-smoothing', () {
      final original = createNoisyImage();
      
      // Compare high detail recovery vs low detail recovery under same NR strength
      const paramsLowDetail = AdjustParams(
        luminanceNR: 80.0,
        colourNR: 0.0,
        nrDetail: 10.0,
      );

      const paramsHighDetail = AdjustParams(
        luminanceNR: 80.0,
        colourNR: 0.0,
        nrDetail: 90.0,
      );

      final outLow = applyImagePipeline(image: original, params: paramsLowDetail);
      final outHigh = applyImagePipeline(image: original, params: paramsHighDetail);

      final lowVar = getVariance(outLow);
      final highVar = getVariance(outHigh);

      // High detail recovery should retain more variance/texture from the noisy source
      expect(highVar, greaterThan(lowVar));
    });

    test('rawProcessor applyNoiseReduction functionality', () {
      final original = createNoisyImage();
      
      // Test no-op
      final outNoOp = applyNoiseReduction(original, 0);
      expect(getVariance(outNoOp), equals(getVariance(original)));

      // Test active reduction
      final outActive = applyNoiseReduction(original, 50);
      expect(getVariance(outActive), lessThan(getVariance(original)));
    });
  });
}
