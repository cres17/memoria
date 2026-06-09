import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/crop_engine.dart';

void main() {
  group('Crop Engine Tests', () {
    late img.Image testImage;

    setUp(() {
      testImage = img.Image(width: 800, height: 600); // 4:3 image
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 800; x++) {
          testImage.setPixel(x, y, img.ColorRgba8(x % 256, y % 256, 128, 255));
        }
      }
    });

    test('Identity crop (no-op)', () {
      const state = CropState(
        ratio: CropRatioPreset.free,
        cropLeft: 0.0,
        cropTop: 0.0,
        cropRight: 1.0,
        cropBottom: 1.0,
      );
      final cropped = cropImage(testImage, state);
      expect(cropped.width, 800);
      expect(cropped.height, 600);
    });

    test('Custom crop coordinates', () {
      const state = CropState(
        ratio: CropRatioPreset.free,
        cropLeft: 0.25,
        cropTop: 0.25,
        cropRight: 0.75,
        cropBottom: 0.75,
      );
      final cropped = cropImage(testImage, state);
      expect(cropped.width, 400); // 0.5 * 800
      expect(cropped.height, 300); // 0.5 * 600
    });

    test('Locked aspect ratio presets (Square 1:1 centering)', () {
      const state = CropState(
        ratio: CropRatioPreset.r1x1,
        centerX: 0.5,
        centerY: 0.5,
      );
      final cropped = cropImage(testImage, state);
      expect(cropped.width, 600); // 1:1 locks to height since width is larger
      expect(cropped.height, 600);
    });

    test('Legacy fallback centering path', () {
      const state = CropState(
        ratio: CropRatioPreset.r4x3,
        centerX: 0.5,
        centerY: 0.5,
        cropLeft: 0.0,
        cropTop: 0.0,
        cropRight: 1.0,
        cropBottom: 1.0,
      );
      final cropped = cropImage(testImage, state);
      expect(cropped.width, 800);
      expect(cropped.height, 600);
    });
  });
}
