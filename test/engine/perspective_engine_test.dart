import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/geometry_transforms.dart';

void main() {
  group('Perspective Engine Tests', () {
    late img.Image testImage;

    setUp(() {
      // Create a simple test image (100x100) with a gradient
      testImage = img.Image(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          testImage.setPixelRgb(x, y, x * 2, y * 2, 128);
        }
      }
    });

    test('Identity perspective skew (hDeg = 0, vDeg = 0) is no-op', () {
      final processed = applyPerspectiveSkewInverse(testImage, 0, 0);
      expect(processed.width, testImage.width);
      expect(processed.height, testImage.height);
      
      // Pixels should remain identical
      expect(processed.getPixel(10, 10).r, testImage.getPixel(10, 10).r);
      expect(processed.getPixel(50, 50).r, testImage.getPixel(50, 50).r);
    });

    test('Horizontal perspective skew transformation changes pixels', () {
      final processed = applyPerspectiveSkewInverse(testImage, 15, 0);
      expect(processed.width, testImage.width);
      expect(processed.height, testImage.height);

      // Verify that at least some pixels have changed due to skewing
      var changedCount = 0;
      for (var y = 10; y < 90; y += 10) {
        for (var x = 10; x < 90; x += 10) {
          final orig = testImage.getPixel(x, y);
          final proc = processed.getPixel(x, y);
          if (orig.r != proc.r || orig.g != proc.g) {
            changedCount++;
          }
        }
      }
      expect(changedCount, greaterThan(0), reason: 'Image pixels should warp and change');
    });

    test('Vertical perspective skew transformation changes pixels', () {
      final processed = applyPerspectiveSkewInverse(testImage, 0, 15);
      expect(processed.width, testImage.width);
      expect(processed.height, testImage.height);

      var changedCount = 0;
      for (var y = 10; y < 90; y += 10) {
        for (var x = 10; x < 90; x += 10) {
          final orig = testImage.getPixel(x, y);
          final proc = processed.getPixel(x, y);
          if (orig.r != proc.r || orig.g != proc.g) {
            changedCount++;
          }
        }
      }
      expect(changedCount, greaterThan(0), reason: 'Image pixels should warp and change');
    });

    test('Extreme values do not crash and clamp/warp correctly', () {
      // 45 degrees skew
      final processed = applyPerspectiveSkewInverse(testImage, 45, 45);
      expect(processed.width, testImage.width);
      expect(processed.height, testImage.height);
      
      // Extreme negative skew
      final processedNeg = applyPerspectiveSkewInverse(testImage, -45, -45);
      expect(processedNeg.width, testImage.width);
      expect(processedNeg.height, testImage.height);
    });

    test('Out-of-bounds pixels are filled with black', () {
      // Apply a strong skew which leaves corners out of bounds
      final processed = applyPerspectiveSkewInverse(testImage, 30, 30);
      
      // Skewing compresses along bottom-left (0, 99) and top-right (99, 0)
      final bottomLeftPixel = processed.getPixel(0, 99);
      final topRightPixel = processed.getPixel(99, 0);
      
      expect(bottomLeftPixel.r, 0);
      expect(bottomLeftPixel.g, 0);
      expect(topRightPixel.r, 0);
      expect(topRightPixel.g, 0);
    });
  });
}
