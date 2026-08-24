import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/local_adjust.dart';

img.Image _solidImage(int width, int height, int value) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _twoToneImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = x < width ~/ 2 ? 80 : 220;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

void main() {
  group('Local adjustment spatial-mask contracts', () {
    test('empty or neutral selective input is an exact no-op', () {
      final image = _solidImage(64, 64, 80);

      expect(identical(applySelectiveAdjust(image, const []), image), isTrue);
      expect(
        identical(
          applySelectiveAdjust(image, const [
            LocalSelectivePoint(x: 0.5, y: 0.5),
          ]),
          image,
        ),
        isTrue,
      );
    });

    test('selective adjustment is strongest at the touched point', () {
      final image = _solidImage(101, 101, 80);
      final result = applySelectiveAdjust(image, const [
        LocalSelectivePoint(
          x: 0.5,
          y: 0.5,
          radius: 0.15,
          brightness: 60,
        ),
      ]);

      final center = result.getPixel(50, 50).r;
      final nearby = result.getPixel(60, 50).r;
      final far = result.getPixel(0, 0).r;

      expect(center, greaterThan(80));
      expect(center, greaterThan(nearby));
      expect(nearby, greaterThan(far));
      expect(far, closeTo(80, 1));
    });

    test('colour boundary resists local-adjustment bleed', () {
      final image = _twoToneImage(100, 40);
      final result = applySelectiveAdjust(image, const [
        LocalSelectivePoint(
          x: 0.25,
          y: 0.5,
          radius: 0.65,
          brightness: 60,
        ),
      ]);

      final selectedSide = result.getPixel(25, 20).r;
      final otherColour = result.getPixel(75, 20).r;
      expect(selectedSide, greaterThan(100));
      expect(otherColour, closeTo(220, 2));
    });

    test('zero-radius selective point and dodge-burn stroke fail closed', () {
      final image = _solidImage(32, 32, 100);
      final selective = applySelectiveAdjust(image, const [
        LocalSelectivePoint(x: 0.5, y: 0.5, radius: 0, brightness: 50),
      ]);
      final dodgeBurn = applyDodgeBurn(image, const [
        DodgeBurnStroke(
          x: 0.5,
          y: 0.5,
          radius: 0,
          strength: 1,
          isDodge: true,
        ),
      ]);

      expect(identical(selective, image), isTrue);
      expect(identical(dodgeBurn, image), isTrue);
    });
  });
}
