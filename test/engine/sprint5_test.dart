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
  group('Sprint 5 brush masks', () {
    test('empty strokes create a zero mask', () {
      final mask = createSoftBrushMask(
        width: 8,
        height: 8,
        strokes: const [],
      );
      expect(mask.length, 64);
      expect(mask.every((v) => v == 0), isTrue);
    });

    test('center stroke reaches full strength near center', () {
      final mask = createSoftBrushMask(
        width: 20,
        height: 20,
        hardness: 1,
        strokes: const [
          BrushStroke(x: 0.5, y: 0.5, radius: 0.25),
        ],
      );
      expect(mask[10 * 20 + 10], greaterThan(0.85));
      expect(mask[0], 0);
    });

    test('soft hardness feathers the edge more than hard hardness', () {
      const strokes = [
        BrushStroke(x: 0.5, y: 0.5, radius: 0.35),
      ];
      final soft = createSoftBrushMask(
        width: 40,
        height: 40,
        hardness: 0,
        strokes: strokes,
      );
      final hard = createSoftBrushMask(
        width: 40,
        height: 40,
        hardness: 0.8,
        strokes: strokes,
      );
      const edgeIndex = 20 * 40 + 30;
      expect(soft[edgeIndex], greaterThan(hard[edgeIndex]));
    });
  });

  group('Sprint 5 brush correction', () {
    test('zero local params pass image through', () {
      final im = _solidImage(8, 8, 90, 90, 90);
      final out = applyBrushCorrection(
        image: im,
        brush: const BrushMaskData(
          localParams: AdjustParams.zero,
          toolName: 'exposure+',
          strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.5)],
        ),
      );
      expect(identical(out, im), isTrue);
    });

    test('brightens inside the brush and preserves outside pixels', () {
      final im = _solidImage(20, 20, 90, 90, 90);
      final out = applyBrushCorrection(
        image: im,
        brush: const BrushMaskData(
          localParams: AdjustParams(exposure: 1.0),
          toolName: 'exposure+',
          hardness: 1,
          strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.25)],
        ),
      );
      expect(_brightness(out.getPixel(10, 10)),
          greaterThan(_brightness(im.getPixel(10, 10))));
      expect(out.getPixel(0, 0).r, im.getPixel(0, 0).r);
      expect(out.getPixel(0, 0).g, im.getPixel(0, 0).g);
      expect(out.getPixel(0, 0).b, im.getPixel(0, 0).b);
    });
  });
}
