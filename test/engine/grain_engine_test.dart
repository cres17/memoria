import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('Grain Engine Tests', () {
    img.Image createTestImage() {
      final image = img.Image(width: 32, height: 32);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(x, y, 128, 128, 128); // Mid gray
        }
      }
      return image;
    }

    test('no-op when strength is 0', () {
      final original = createTestImage();
      const params = AdjustParams(
        grainStrength: 0.0,
        grainSize: 1.5,
        grainSeed: 101,
      );

      final out = applyImagePipeline(image: original, params: params);

      // Verify that output is identical to input
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

    test('determinism: same params and seed produce byte-identical images', () {
      final original = createTestImage();
      const params = AdjustParams(
        grainStrength: 45.0,
        grainSize: 1.2,
        grainSeed: 42,
      );

      final out1 = applyImagePipeline(image: original, params: params);
      final out2 = applyImagePipeline(image: original, params: params);

      // Verify that out1 and out2 are byte-identical
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          final p1 = out1.getPixel(x, y);
          final p2 = out2.getPixel(x, y);
          expect(p1.r, equals(p2.r));
          expect(p1.g, equals(p2.g));
          expect(p1.b, equals(p2.b));
        }
      }
    });

    test(
        'pattern variation: different seeds produce different grain distributions',
        () {
      final original = createTestImage();
      const params1 = AdjustParams(
        grainStrength: 45.0,
        grainSize: 1.2,
        grainSeed: 42,
      );
      const params2 = AdjustParams(
        grainStrength: 45.0,
        grainSize: 1.2,
        grainSeed: 99,
      );

      final out1 = applyImagePipeline(image: original, params: params1);
      final out2 = applyImagePipeline(image: original, params: params2);

      var differenceCount = 0;
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          final p1 = out1.getPixel(x, y);
          final p2 = out2.getPixel(x, y);
          if (p1.r != p2.r || p1.g != p2.g || p1.b != p2.b) {
            differenceCount++;
          }
        }
      }

      // Most pixels should be different since the random distribution changes with seed
      expect(
          differenceCount, greaterThan(original.width * original.height * 0.8));
    });

    test('intensity: higher strength results in larger pixel deviations', () {
      final original = createTestImage();
      const lowParams = AdjustParams(
        grainStrength: 10.0,
        grainSize: 1.0,
        grainSeed: 123,
      );
      const highParams = AdjustParams(
        grainStrength: 80.0,
        grainSize: 1.0,
        grainSeed: 123,
      );

      final outLow = applyImagePipeline(image: original, params: lowParams);
      final outHigh = applyImagePipeline(image: original, params: highParams);

      double getMeanAbsoluteDeviation(img.Image src, img.Image dest) {
        var sum = 0.0;
        for (var y = 0; y < src.height; y++) {
          for (var x = 0; x < src.width; x++) {
            final pSrc = src.getPixel(x, y);
            final pDest = dest.getPixel(x, y);
            sum += (pSrc.r - pDest.r).abs();
          }
        }
        return sum / (src.width * src.height);
      }

      final lowDev = getMeanAbsoluteDeviation(original, outLow);
      final highDev = getMeanAbsoluteDeviation(original, outHigh);

      expect(highDev, greaterThan(lowDev * 3.0));
    });

    test('grain visibly changes pixels while preserving alpha', () {
      final original = img.Image(width: 32, height: 32, numChannels: 4);
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          original.setPixelRgba(x, y, 128, 128, 128, 111 + (x % 5));
        }
      }
      final output = applyImagePipeline(
        image: original,
        params: const AdjustParams(
          grainStrength: 60,
          grainSize: 1.4,
          grainSeed: 77,
        ),
      );
      var changed = 0;
      for (var y = 0; y < original.height; y++) {
        for (var x = 0; x < original.width; x++) {
          if (output.getPixel(x, y).r != original.getPixel(x, y).r) changed++;
          expect(output.getPixel(x, y).a, original.getPixel(x, y).a);
        }
      }
      expect(changed, greaterThan(original.width * original.height * 0.8));
    });
  });
}
