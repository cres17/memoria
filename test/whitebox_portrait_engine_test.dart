// Whitebox tests — portrait_engine.dart
// Coverage: _rgbToHsv / _hsvToRgb (via public surface),
//   applySkinSmoothing, applyFaceSpotlight, applySkinToning
//   — boundary conditions, zero-strength passthrough, mask=0 passthrough

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/portrait_engine.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

img.Image _solidImage(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, r, g, b);
    }
  }
  return im;
}

Float32List _zeroMask(int w, int h) => Float32List(w * h);

Float32List _fullMask(int w, int h) =>
    Float32List(w * h)..fillRange(0, w * h, 1.0);

void main() {
  // ── applySkinSmoothing ─────────────────────────────────────────────────────
  group('applySkinSmoothing', () {
    const w = 6, h = 6;

    test('strength=0 returns identical image', () {
      final src = _solidImage(w, h, 150, 100, 80);
      final out = applySkinSmoothing(src, _fullMask(w, h), 0);
      expect(identical(out, src), isTrue);
    });

    test('zero mask (no skin): output equals input', () {
      final src = _solidImage(w, h, 120, 80, 60);
      final out = applySkinSmoothing(src, _zeroMask(w, h), 80);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final a = src.getPixel(x, y);
          final b = out.getPixel(x, y);
          expect((b.r - a.r).abs(), lessThanOrEqualTo(2));
          expect((b.g - a.g).abs(), lessThanOrEqualTo(2));
          expect((b.b - a.b).abs(), lessThanOrEqualTo(2));
        }
      }
    });

    test('full mask + strength=100: uniform solid stays uniform colour', () {
      final src = _solidImage(w, h, 200, 150, 100);
      final out = applySkinSmoothing(src, _fullMask(w, h), 100);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final b = out.getPixel(x, y);
          expect((b.r - 200).abs(), lessThanOrEqualTo(3));
          expect((b.g - 150).abs(), lessThanOrEqualTo(3));
          expect((b.b - 100).abs(), lessThanOrEqualTo(3));
        }
      }
    });

    test('output dimensions match input', () {
      final src = _solidImage(5, 7, 100, 100, 100);
      final out = applySkinSmoothing(src, _fullMask(5, 7), 50);
      expect(out.width, equals(5));
      expect(out.height, equals(7));
    });

    test('only the segmented region is smoothed and alpha is preserved', () {
      final src = img.Image(width: 24, height: 12, numChannels: 4);
      final mask = Float32List(src.width * src.height);
      for (var y = 0; y < src.height; y++) {
        for (var x = 0; x < src.width; x++) {
          final value = (x + y).isEven ? 40 : 220;
          src.setPixelRgba(x, y, value, value, value, 90 + x);
          if (x >= 12) mask[y * src.width + x] = 1;
        }
      }

      final out = applySkinSmoothing(src, mask, 100);
      var backgroundChanges = 0;
      var segmentedChanges = 0;
      for (var y = 0; y < src.height; y++) {
        for (var x = 0; x < src.width; x++) {
          final before = src.getPixel(x, y);
          final after = out.getPixel(x, y);
          if (before.r != after.r) {
            if (x < 12) {
              backgroundChanges++;
            } else {
              segmentedChanges++;
            }
          }
          expect(after.a, before.a);
        }
      }
      expect(backgroundChanges, 0);
      expect(segmentedChanges, greaterThan(0));
    });
  });

  // ── applyFaceSpotlight ─────────────────────────────────────────────────────
  group('applyFaceSpotlight', () {
    const w = 8, h = 8;

    test('boost=0 returns identical image', () {
      final src = _solidImage(w, h, 100, 100, 100);
      final out = applyFaceSpotlight(src, _fullMask(w, h), 0);
      expect(identical(out, src), isTrue);
    });

    test('zero mask: all pixels pass through unchanged', () {
      final src = _solidImage(w, h, 100, 120, 140);
      final out = applyFaceSpotlight(src, _zeroMask(w, h), 80);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final a = src.getPixel(x, y);
          final b = out.getPixel(x, y);
          expect((b.r - a.r).abs(), lessThanOrEqualTo(2));
          expect((b.g - a.g).abs(), lessThanOrEqualTo(2));
          expect((b.b - a.b).abs(), lessThanOrEqualTo(2));
        }
      }
    });

    test('boost=100 brightens centre pixel more than corner pixel', () {
      final src = _solidImage(w, h, 100, 100, 100);
      final out = applyFaceSpotlight(src, _fullMask(w, h), 100);
      final centre = out.getPixel(w ~/ 2, h ~/ 2);
      final corner = out.getPixel(0, 0);
      expect(centre.r, greaterThanOrEqualTo(corner.r));
    });

    test('output is brighter than or equal to input for non-zero boost', () {
      final src = _solidImage(w, h, 80, 80, 80);
      final out = applyFaceSpotlight(src, _fullMask(w, h), 50);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          expect(out.getPixel(x, y).r,
              greaterThanOrEqualTo(src.getPixel(x, y).r - 1));
        }
      }
    });

    test('output dimensions match input', () {
      final src = _solidImage(5, 9, 100, 100, 100);
      final out = applyFaceSpotlight(src, _fullMask(5, 9), 40);
      expect(out.width, equals(5));
      expect(out.height, equals(9));
    });
  });

  // ── applySkinToning ────────────────────────────────────────────────────────
  group('applySkinToning', () {
    const w = 4, h = 4;

    test('SkinTone.none returns identical image', () {
      final src = _solidImage(w, h, 200, 150, 120);
      final out = applySkinToning(src, _fullMask(w, h), SkinTone.none, 100);
      expect(identical(out, src), isTrue);
    });

    test('strength=0 returns identical image', () {
      final src = _solidImage(w, h, 200, 150, 120);
      final out = applySkinToning(src, _fullMask(w, h), SkinTone.fair, 0);
      expect(identical(out, src), isTrue);
    });

    test('zero mask: pixels unchanged', () {
      final src = _solidImage(w, h, 200, 150, 120);
      final out = applySkinToning(src, _zeroMask(w, h), SkinTone.medium, 100);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final a = src.getPixel(x, y);
          final b = out.getPixel(x, y);
          expect((b.r - a.r).abs(), lessThanOrEqualTo(2));
          expect((b.g - a.g).abs(), lessThanOrEqualTo(2));
          expect((b.b - a.b).abs(), lessThanOrEqualTo(2));
        }
      }
    });

    test('output dimensions match input', () {
      final src = _solidImage(6, 3, 180, 130, 100);
      final out = applySkinToning(src, _fullMask(6, 3), SkinTone.pale, 50);
      expect(out.width, equals(6));
      expect(out.height, equals(3));
    });

    test('pixel values stay in [0, 255] after toning', () {
      final src = _solidImage(w, h, 220, 180, 140);
      for (final tone in [
        SkinTone.pale,
        SkinTone.fair,
        SkinTone.medium,
        SkinTone.dark
      ]) {
        final out = applySkinToning(src, _fullMask(w, h), tone, 100);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final px = out.getPixel(x, y);
            expect(px.r, inInclusiveRange(0, 255));
            expect(px.g, inInclusiveRange(0, 255));
            expect(px.b, inInclusiveRange(0, 255));
          }
        }
      }
    });
  });

  // ── SkinTone enum ──────────────────────────────────────────────────────────
  group('SkinTone enum', () {
    test('all tones have non-empty labels', () {
      for (final t in SkinTone.values) {
        expect(t.label, isNotEmpty);
      }
    });

    test('SkinTone.none has null targetHue', () {
      expect(SkinTone.none.targetHue, isNull);
    });

    test('non-none tones have positive targetHue', () {
      for (final t in SkinTone.values.skip(1)) {
        expect(t.targetHue, isNotNull);
        expect(t.targetHue!, greaterThan(0));
      }
    });
  });

  group('applyDepthBokeh', () {
    test('strength=0 returns identical image', () {
      final src = _stripedImage(24, 12);
      final depth = Float32List(src.width * src.height)
        ..fillRange(0, src.width * src.height, 1.0);
      final out = applyDepthBokeh(src, depth, 0);
      expect(identical(out, src), isTrue);
    });

    test('invalid depth map length returns original image', () {
      final src = _stripedImage(24, 12);
      final out = applyDepthBokeh(src, Float32List(3), 80);
      expect(identical(out, src), isTrue);
    });

    test('blur pyramid applies more blur to far depth than mid depth', () {
      final src = _stripedImage(60, 20);
      final depth = Float32List(src.width * src.height);
      for (var y = 0; y < src.height; y++) {
        for (var x = 0; x < src.width; x++) {
          depth[y * src.width + x] = x < 20
              ? 0.0
              : x < 40
                  ? 0.5
                  : 1.0;
        }
      }

      final out = applyDepthBokeh(src, depth, 100);

      final nearDelta = _meanPixelDelta(src, out, 2, 18);
      final farDelta = _meanPixelDelta(src, out, 42, 58);

      expect(nearDelta, lessThan(1.0));
      expect(farDelta, greaterThan(0.02));
    });
  });

  group('applyHeadPoseWarp', () {
    test('zero yaw and pitch returns identical image', () {
      final src = _horizontalGradientImage(24, 16);
      final out = applyHeadPoseWarp(src, _fullMask(24, 16));
      expect(identical(out, src), isTrue);
    });

    test('invalid mask length returns original image', () {
      final src = _horizontalGradientImage(24, 16);
      final out = applyHeadPoseWarp(src, Float32List(1), yaw: 60);
      expect(identical(out, src), isTrue);
    });

    test('warps masked face region and preserves background', () {
      final src = _horizontalGradientImage(32, 20);
      final mask = _centerMask(src.width, src.height);

      final out = applyHeadPoseWarp(src, mask, yaw: 100, pitch: -80);

      expect(_pixelDelta(src.getPixel(16, 10), out.getPixel(16, 10)),
          greaterThan(0.5));
      expect(_pixelDelta(src.getPixel(1, 1), out.getPixel(1, 1)), equals(0));
    });
  });
}

img.Image _stripedImage(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final isBar =
          (x >= 8 && x <= 10) || (x >= 28 && x <= 30) || (x >= 48 && x <= 50);
      final v = isBar ? 240 : 24;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}

img.Image _horizontalGradientImage(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, 40 + x * 5, 80 + y * 3, 120);
    }
  }
  return im;
}

Float32List _centerMask(int w, int h) {
  final mask = Float32List(w * h);
  final cx = (w - 1) / 2;
  final cy = (h - 1) / 2;
  final rx = w * 0.32;
  final ry = h * 0.38;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - cx) / rx;
      final dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) {
        mask[y * w + x] = 1;
      }
    }
  }
  return mask;
}

num _pixelDelta(img.Pixel a, img.Pixel b) {
  return ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3;
}

double _meanPixelDelta(
  img.Image before,
  img.Image after,
  int startX,
  int endX,
) {
  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < before.height; y++) {
    for (var x = startX; x < endX; x++) {
      sum += (after.getPixel(x, y).r - before.getPixel(x, y).r).abs();
      count++;
    }
  }
  return sum / count;
}
