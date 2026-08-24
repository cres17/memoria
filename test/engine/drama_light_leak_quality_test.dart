import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/lut_engine.dart';

img.Image _grayGradient(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = (x * 255 / (width - 1)).round();
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _blackImage(int width, int height) =>
    img.Image(width: width, height: height, numChannels: 4);

img.Image _shadowNoise(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = 28 + ((x * 17 + y * 11) % 7) - 3;
      image.setPixelRgba(x, y, value, value, value, 137);
    }
  }
  return image;
}

double _meanHorizontalDelta(img.Image image) {
  var total = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 1; x < image.width; x++) {
      total += (image.getPixel(x, y).r - image.getPixel(x - 1, y).r).abs();
      count++;
    }
  }
  return total / count;
}

img.Image _stepEdge(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = x < width ~/ 2 ? 64 : 192;
      image.setPixelRgba(x, y, value, value, value, 149);
    }
  }
  return image;
}

double _ssim(img.Image a, img.Image b) {
  expect(a.width, b.width);
  expect(a.height, b.height);
  final count = a.width * a.height;
  var meanA = 0.0;
  var meanB = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      meanA += _luminance(a.getPixel(x, y)) / 255.0;
      meanB += _luminance(b.getPixel(x, y)) / 255.0;
    }
  }
  meanA /= count;
  meanB /= count;
  var varianceA = 0.0;
  var varianceB = 0.0;
  var covariance = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final da = _luminance(a.getPixel(x, y)) / 255.0 - meanA;
      final db = _luminance(b.getPixel(x, y)) / 255.0 - meanB;
      varianceA += da * da;
      varianceB += db * db;
      covariance += da * db;
    }
  }
  varianceA /= count - 1;
  varianceB /= count - 1;
  covariance /= count - 1;
  const c1 = 0.0001;
  const c2 = 0.0009;
  return ((2 * meanA * meanB + c1) * (2 * covariance + c2)) /
      ((meanA * meanA + meanB * meanB + c1) * (varianceA + varianceB + c2));
}

double _luminance(img.Color pixel) =>
    0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;

({double x, double y, double energy}) _energyCentroid(img.Image image) {
  var sum = 0.0;
  var sumX = 0.0;
  var sumY = 0.0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final energy = _luminance(image.getPixel(x, y));
      sum += energy;
      sumX += energy * x / (image.width - 1);
      sumY += energy * y / (image.height - 1);
    }
  }
  return (x: sumX / sum, y: sumY / sum, energy: sum);
}

void main() {
  group('Drama and light-leak quality contracts', () {
    test('bright drama preserves high-key gradient detail and is deterministic',
        () async {
      final source = _grayGradient(256, 8);
      final first = await applyArtisticEffect(
        source,
        ArtisticEffect.dramaBright2,
        strength: 1,
      );
      final second = await applyArtisticEffect(
        source,
        ArtisticEffect.dramaBright2,
        strength: 1,
      );

      final sourceClipped = [
        for (var x = 0; x < source.width; x++) source.getPixel(x, 0).r.toInt(),
      ].where((value) => value == 255).length;
      final outputClipped = [
        for (var x = 0; x < first.width; x++) first.getPixel(x, 0).r.toInt(),
      ].where((value) => value == 255).length;
      final highKeyValues = <int>{
        for (var x = 224; x < first.width; x++) first.getPixel(x, 0).r.toInt(),
      };

      expect(outputClipped, lessThanOrEqualTo(sourceClipped));
      expect(highKeyValues.length, greaterThan(12));
      expect(
        Uint8List.fromList(first.getBytes()),
        Uint8List.fromList(second.getBytes()),
      );
    });

    test('drama keeps alpha, gradient steps, and hard edges halo-free',
        () async {
      final gradient = img.Image(width: 256, height: 8, numChannels: 4);
      for (var y = 0; y < gradient.height; y++) {
        for (var x = 0; x < gradient.width; x++) {
          gradient.setPixelRgba(x, y, x, x, x, 141);
        }
      }
      final drama = await applyArtisticEffect(
        gradient,
        ArtisticEffect.dramaBright2,
        strength: 1,
      );
      final levels = <int>{
        for (var x = 0; x < drama.width; x++) drama.getPixel(x, 0).r.toInt(),
      };
      // An 8-bit tone curve cannot remain bijective while changing contrast;
      // this guard instead rejects long flat plateaus that are visibly banded.
      expect(levels.length, greaterThanOrEqualTo(175));
      var longestPlateau = 1;
      var currentPlateau = 1;
      for (var x = 1; x < drama.width; x++) {
        if (drama.getPixel(x, 0).r == drama.getPixel(x - 1, 0).r) {
          currentPlateau++;
          longestPlateau = math.max(longestPlateau, currentPlateau);
        } else {
          currentPlateau = 1;
        }
      }
      expect(longestPlateau, lessThanOrEqualTo(4));
      expect(drama.getPixel(128, 0).a.toInt(), 141);

      final edge = await applyArtisticEffect(
        _stepEdge(64, 32),
        ArtisticEffect.drama2,
        strength: 1,
      );
      final farLeft = edge.getPixel(8, 16).r.toInt();
      final nearLeft = edge.getPixel(30, 16).r.toInt();
      final farRight = edge.getPixel(55, 16).r.toInt();
      final nearRight = edge.getPixel(33, 16).r.toInt();
      expect((nearLeft - farLeft).abs(), lessThanOrEqualTo(3));
      expect((nearRight - farRight).abs(), lessThanOrEqualTo(3));
      expect(edge.getPixel(32, 16).a.toInt(), 149);
    });

    test('HDR preview proxy remains visually equivalent to full render',
        () async {
      final fullSource =
          img.copyResize(_grayGradient(256, 64), width: 256, height: 128);
      final full = await applyArtisticEffect(
        fullSource,
        ArtisticEffect.hdrNature,
        strength: 0.75,
      );
      final downsampledFull = img.copyResize(full, width: 128, height: 64);
      final proxySource = img.copyResize(fullSource, width: 128, height: 64);
      final proxy = await applyArtisticEffect(
        proxySource,
        ArtisticEffect.hdrNature,
        strength: 0.75,
      );
      expect(_ssim(downsampledFull, proxy), greaterThanOrEqualTo(0.992));
    });

    test('strength zero is byte-identical for drama and HDR', () async {
      final source = _shadowNoise(48, 32);
      for (final effect in const [
        ArtisticEffect.drama2,
        ArtisticEffect.hdrStrong,
      ]) {
        final output = await applyArtisticEffect(source, effect, strength: 0);
        expect(output.getBytes(), source.getBytes());
      }
    });

    test('HDR preserves highlight detail, alpha, and shadow-noise restraint',
        () async {
      final gradient = img.Image(width: 256, height: 4, numChannels: 4);
      for (var y = 0; y < gradient.height; y++) {
        for (var x = 0; x < gradient.width; x++) {
          final value = (x * 255 / (gradient.width - 1)).round();
          gradient.setPixelRgba(x, y, value, value, value, 173);
        }
      }
      final hdr = await applyArtisticEffect(
        gradient,
        ArtisticEffect.hdrStrong,
        strength: 1,
      );
      final highKeyValues = <int>{
        for (var x = 224; x < hdr.width; x++) hdr.getPixel(x, 0).r.toInt(),
      };

      expect(highKeyValues.length, greaterThan(12));
      for (var y = 0; y < hdr.height; y++) {
        for (var x = 0; x < hdr.width; x++) {
          expect(hdr.getPixel(x, y).a.toInt(), 173);
        }
      }

      final noisySource = _shadowNoise(64, 32);
      final noisyHdr = await applyArtisticEffect(
        noisySource,
        ArtisticEffect.hdrStrong,
        strength: 1,
      );
      expect(
        _meanHorizontalDelta(noisyHdr),
        lessThanOrEqualTo(_meanHorizontalDelta(noisySource) * 1.4),
      );
    });

    test('light leak strength and angle control energy location', () {
      final source = _blackImage(101, 101);
      final none = applyImagePipeline(
        image: source,
        params: const AdjustParams(lightLeakStrength: 0),
      );
      final right = applyImagePipeline(
        image: source,
        params: const AdjustParams(
          lightLeakStrength: 100,
          lightLeakAngle: 0,
        ),
      );
      final left = applyImagePipeline(
        image: source,
        params: const AdjustParams(
          lightLeakStrength: 100,
          lightLeakAngle: 180,
        ),
      );
      final down = applyImagePipeline(
        image: source,
        params: const AdjustParams(
          lightLeakStrength: 100,
          lightLeakAngle: 90,
        ),
      );

      final rightCenter = _energyCentroid(right);
      final leftCenter = _energyCentroid(left);
      final downCenter = _energyCentroid(down);
      expect(_energyCentroid(none).energy, 0);
      expect(rightCenter.energy, greaterThan(0));
      expect(rightCenter.x, greaterThan(0.5));
      expect(leftCenter.x, lessThan(0.5));
      expect(downCenter.y, greaterThan(0.5));
    });

    test('warmth changes the light leak toward warm or cool channels', () {
      final source = _blackImage(61, 61);
      final warm = applyImagePipeline(
        image: source,
        params: const AdjustParams(
          lightLeakStrength: 100,
          lightLeakWarmth: 100,
        ),
      );
      final cool = applyImagePipeline(
        image: source,
        params: const AdjustParams(
          lightLeakStrength: 100,
          lightLeakWarmth: -100,
        ),
      );
      final warmPixel = warm.getPixel(60, 30);
      final coolPixel = cool.getPixel(60, 30);

      expect(warmPixel.r, greaterThan(warmPixel.b));
      expect(coolPixel.b, greaterThan(coolPixel.r));
    });
  });
}
