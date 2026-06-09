import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/brush_engine.dart';

img.Image _solidImage(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, r, g, b);
    }
  }
  return im;
}

double _brightness(img.Pixel p) =>
    (p.rNormalized + p.gNormalized + p.bNormalized) / 3.0;

void main() {
  group('Brush Engine Tests', () {
    test('Soft mask generation with standard settings', () {
      final mask = createSoftBrushMask(
        width: 10,
        height: 10,
        hardness: 0.5,
        strokes: const [
          BrushStroke(x: 0.5, y: 0.5, radius: 0.3),
        ],
      );
      expect(mask.length, 100);
      // Center should have full or high strength
      expect(mask[5 * 10 + 5], greaterThan(0.4));
      // Outer border should be zero
      expect(mask[0], 0.0);
    });

    test('Dodge / Burn math applying brush corrections', () {
      final im = _solidImage(10, 10, 128, 128, 128);

      // Dodge (exposure+) should brighten the center
      final dodged = applyBrushCorrection(
        image: im,
        brush: const BrushMaskData(
          localParams: AdjustParams(exposure: 0.55),
          toolName: 'exposure+',
          hardness: 1.0,
          strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.3)],
        ),
      );
      expect(_brightness(dodged.getPixel(5, 5)),
          greaterThan(_brightness(im.getPixel(5, 5))));
      expect(dodged.getPixel(0, 0).r, im.getPixel(0, 0).r);

      // Burn (exposure-) should darken the center
      final burned = applyBrushCorrection(
        image: im,
        brush: const BrushMaskData(
          localParams: AdjustParams(exposure: -0.55),
          toolName: 'exposure-',
          hardness: 1.0,
          strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.3)],
        ),
      );
      expect(_brightness(burned.getPixel(5, 5)),
          lessThan(_brightness(im.getPixel(5, 5))));
      expect(burned.getPixel(0, 0).r, im.getPixel(0, 0).r);
    });

    test('Eraser subtraction math reduces mask value deterministically', () {
      const strokes = [
        BrushStroke(x: 0.5, y: 0.5, radius: 0.4, pressure: 1.0), // paint Dodge
        BrushStroke(x: 0.5, y: 0.5, radius: 0.2, pressure: -1.0), // erase center
      ];

      final mask = createSoftBrushMask(
        width: 10,
        height: 10,
        hardness: 1.0,
        strokes: strokes,
      );

      // The center (5, 5) is within the radius of both strokes, so it should be erased back to 0.0
      expect(mask[5 * 10 + 5], closeTo(0.0, 0.01));

      // The region outside the eraser radius but within the paint radius should still be painted
      expect(mask[5 * 10 + 2], greaterThan(0.9));
    });
  });
}
