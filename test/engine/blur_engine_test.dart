import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/blur_engine.dart';

img.Image _checkerboard(int size) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final value = (x + y).isEven ? 0 : 255;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _rgbaCheckerboard(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = (x + y).isEven ? 20 : 235;
      image.setPixelRgba(x, y, value, value, value, 120 + (x % 3));
    }
  }
  return image;
}

void _expectSamePixels(img.Image actual, img.Image expected) {
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  for (var y = 0; y < actual.height; y++) {
    for (var x = 0; x < actual.width; x++) {
      final a = actual.getPixel(x, y);
      final e = expected.getPixel(x, y);
      expect(a.r, e.r, reason: 'red differs at ($x, $y)');
      expect(a.g, e.g, reason: 'green differs at ($x, $y)');
      expect(a.b, e.b, reason: 'blue differs at ($x, $y)');
    }
  }
}

void main() {
  group('Blur engine no-op and focus-plane contracts', () {
    late img.Image image;

    setUp(() => image = _checkerboard(32));

    test('linear tilt shift with zero radius is a true no-op', () {
      final result = applyLinearTiltShift(
        image: image,
        focusCenter: 0.5,
        focusBandWidth: 0.3,
        maxBlur: 0,
      );

      _expectSamePixels(result, image);
    });

    test('elliptical tilt shift with zero radius is a true no-op', () {
      final result = applyEllipticalTiltShift(
        image: image,
        centerX: 0.5,
        centerY: 0.5,
        radiusX: 0.3,
        radiusY: 0.3,
        maxBlur: 0,
      );

      _expectSamePixels(result, image);
    });

    test('lens blur with zero radius is a true no-op', () {
      final result = applyLensBlur(
        image: image,
        depthMap: Float32List(32 * 32)..fillRange(0, 32 * 32, 0.5),
        focusDepth: 0.5,
        maxBlurRadius: 0,
      );

      _expectSamePixels(result, image);
    });

    test('lens blur preserves pixels that are exactly at focus depth', () {
      final result = applyLensBlur(
        image: image,
        depthMap: Float32List(32 * 32)..fillRange(0, 32 * 32, 0.5),
        focusDepth: 0.5,
        maxBlurRadius: 12,
      );

      _expectSamePixels(result, image);
    });

    test('lens blur fails closed for an invalid depth map', () {
      final result = applyLensBlur(
        image: image,
        depthMap: Float32List(3),
        focusDepth: 0.5,
        maxBlurRadius: 12,
      );

      _expectSamePixels(result, image);
    });

    test('outfocus changes the outer area but preserves the focus band', () {
      final result = applyLinearTiltShift(
        image: image,
        focusCenter: 0.5,
        focusBandWidth: 0.25,
        maxBlur: 12,
      );

      expect(result.getPixel(16, 16).r, image.getPixel(16, 16).r);
      expect(result.getPixel(16, 1).r, isNot(image.getPixel(16, 1).r));
    });

    test('zero-width focus band is clamped and does not throw', () {
      expect(
        () => applyLinearTiltShift(
          image: image,
          focusCenter: 0.5,
          focusBandWidth: 0,
          maxBlur: 8,
        ),
        returnsNormally,
      );
    });

    test('RGBA blur paths preserve per-pixel alpha on small previews', () {
      final source = _rgbaCheckerboard(64, 32);
      final depth = Float32List(source.width * source.height);
      for (var index = 0; index < depth.length; index++) {
        depth[index] = index / (depth.length - 1);
      }
      final lens = applyLensBlur(
        image: source,
        depthMap: depth,
        focusDepth: 0.5,
        maxBlurRadius: 20,
      );
      final tilt = applyLinearTiltShift(
        image: source,
        focusCenter: 0.5,
        focusBandWidth: 0.25,
        maxBlur: 20,
      );

      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final alpha = source.getPixel(x, y).a;
          expect(lens.getPixel(x, y).a, alpha);
          expect(tilt.getPixel(x, y).a, alpha);
        }
      }
    });

    test('lens blur interpolates continuously across depth levels', () {
      final source = _checkerboard(48);
      final depth = Float32List(source.width * source.height);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          depth[y * source.width + x] = x / (source.width - 1);
        }
      }
      final result = applyLensBlur(
        image: source,
        depthMap: depth,
        focusDepth: 0,
        maxBlurRadius: 16,
      );
      final rowValues = <int>{
        for (var x = 0; x < result.width; x++)
          result.getPixel(x, result.height ~/ 2).r.toInt(),
      };
      expect(rowValues.length, greaterThan(6));
    });
  });
}
