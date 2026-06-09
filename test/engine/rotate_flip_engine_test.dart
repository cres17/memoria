import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/edit_operation.dart';

void main() {
  group('Rotate and Flip Engine Tests', () {
    late img.Image testImage;

    setUp(() {
      // Create a 4x3 image where pixel colors indicate coordinates:
      // Red = x coordinate, Green = y coordinate
      testImage = img.Image(width: 4, height: 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          testImage.setPixelRgb(x, y, x * 50, y * 50, 100);
        }
      }
    });

    test('Horizontal flip', () {
      // Let's manually apply horizontal flip
      const dir = img.FlipDirection.horizontal;
      final flipped = img.copyFlip(testImage, direction: dir);

      expect(flipped.width, 4);
      expect(flipped.height, 3);

      // Leftmost pixel of flipped should be rightmost of original
      expect(flipped.getPixel(0, 0).r, testImage.getPixel(3, 0).r);
      expect(flipped.getPixel(1, 0).r, testImage.getPixel(2, 0).r);
    });

    test('Vertical flip', () {
      const dir = img.FlipDirection.vertical;
      final flipped = img.copyFlip(testImage, direction: dir);

      expect(flipped.width, 4);
      expect(flipped.height, 3);

      // Topmost pixel of flipped should be bottommost of original
      expect(flipped.getPixel(0, 0).g, testImage.getPixel(0, 2).g);
      expect(flipped.getPixel(0, 1).g, testImage.getPixel(0, 1).g);
    });

    test('Rotate 90 degrees clockwise', () {
      final rotated = img.copyRotate(testImage, angle: 90);

      // 4x3 becomes 3x4
      expect(rotated.width, 3);
      expect(rotated.height, 4);

      // (0,0) of rotated is bottom-left of original (0, 2)
      expect(rotated.getPixel(0, 0).r, testImage.getPixel(0, 2).r);
      expect(rotated.getPixel(0, 0).g, testImage.getPixel(0, 2).g);
    });

    test('Rotate 180 degrees', () {
      final rotated = img.copyRotate(testImage, angle: 180);

      expect(rotated.width, 4);
      expect(rotated.height, 3);

      // (0,0) of rotated is bottom-right of original (3, 2)
      expect(rotated.getPixel(0, 0).r, testImage.getPixel(3, 2).r);
      expect(rotated.getPixel(0, 0).g, testImage.getPixel(3, 2).g);
    });

    test('No-op: rotation 0 and no flip', () {
      const state = CropState(
        ratio: CropRatioPreset.free,
        rotation: 0.0,
        flipH: false,
        flipV: false,
      );

      expect(state.rotation, 0.0);
      expect(state.flipH, false);
      expect(state.flipV, false);

      final duplicate = img.Image.from(testImage);
      // Verify no-op check
      expect(duplicate.width, testImage.width);
      expect(duplicate.height, testImage.height);
      expect(duplicate.getPixel(0, 0).r, testImage.getPixel(0, 0).r);
    });
  });
}
