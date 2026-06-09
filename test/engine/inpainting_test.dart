import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/inpainting.dart';

void main() {
  group('applyHealing', () {
    test('returns original image when mask dimensions are invalid', () {
      final source = _gradientImage(16, 12);

      final out = applyHealing(source, [
        [true]
      ]);

      expect(identical(out, source), isTrue);
    });

    test('preserves unmasked pixels exactly', () {
      final source = _gradientImage(24, 16);
      final mask = _rectMask(source.width, source.height, 9, 5, 14, 10);

      final out = applyHealing(source, mask);

      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          if (mask[y][x]) continue;
          expect(
            _pixelDelta(source.getPixel(x, y), out.getPixel(x, y)),
            equals(0),
            reason: 'unmasked pixel changed at ($x, $y)',
          );
        }
      }
    });

    test('reconstructs a masked blemish from surrounding gradient', () {
      final clean = _gradientImage(40, 24);
      final damaged = img.Image.from(clean);
      final mask = _rectMask(clean.width, clean.height, 15, 8, 24, 15);

      for (var y = 8; y <= 15; y++) {
        for (var x = 15; x <= 24; x++) {
          damaged.setPixelRgb(x, y, 0, 0, 0);
        }
      }

      final out = applyHealing(damaged, mask);
      final center = out.getPixel(20, 12);
      final expected = clean.getPixel(20, 12);
      final damagedCenter = damaged.getPixel(20, 12);

      expect(_pixelDelta(center, damagedCenter), greaterThan(40));
      expect(_pixelDelta(center, expected), lessThan(24));
    });

    test('createBrushMask clamps stroke geometry to image bounds', () {
      final mask = createBrushMask(
        width: 10,
        height: 10,
        strokes: const [(x: 1.2, y: -0.2, radius: 0.3)],
      );

      expect(mask, hasLength(10));
      expect(mask.every((row) => row.length == 10), isTrue);
      expect(mask.expand((row) => row).where((v) => v), isNotEmpty);
    });
  });
}

img.Image _gradientImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        (32 + x * 4).clamp(0, 255),
        (48 + y * 5).clamp(0, 255),
        (72 + x * 2 + y * 2).clamp(0, 255),
      );
    }
  }
  return image;
}

List<List<bool>> _rectMask(
  int width,
  int height,
  int left,
  int top,
  int right,
  int bottom,
) {
  final mask = List.generate(height, (_) => List.filled(width, false));
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      mask[y][x] = true;
    }
  }
  return mask;
}

num _pixelDelta(img.Pixel a, img.Pixel b) {
  return ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3;
}
