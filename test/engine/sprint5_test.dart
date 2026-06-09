import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/engine/brush_engine.dart';
import 'package:memoria/engine/edit_operation_player.dart';

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

    test('EditOperationPlayer applies brush operations in sequence', () {
      final im = _solidImage(16, 16, 80, 80, 80);
      final session = EditSession(
        imageUri: 'test.jpg',
        ops: [
          EditOperation(
            id: 'brush-1',
            tool: EditToolType.brush,
            appliedAt: DateTime.utc(2026, 1, 1),
            brushMask: const BrushMaskData(
              localParams: AdjustParams(exposure: 1.0),
              toolName: 'exposure+',
              hardness: 1,
              strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.3)],
            ),
          ),
        ],
        undoCursor: 1,
      );

      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(original: im, session: session),
      );
      expect(_brightness(out.getPixel(8, 8)),
          greaterThan(_brightness(im.getPixel(8, 8))));
      expect(out.getPixel(0, 0).r, im.getPixel(0, 0).r);
    });
  });

  group('Canvas Expansion', () {
    test('expands bounds correctly with black/white/smart modes', () {
      final im = _solidImage(10, 10, 100, 100, 100);
      final session = EditSession(
        imageUri: 'test.jpg',
        ops: [
          EditOperation(
            id: 'expand-1',
            tool: EditToolType.crop,
            appliedAt: DateTime.utc(2026, 1, 1),
            cropState: const CropState(
              expandLeft: 0.2,
              expandRight: 0.3,
              expandTop: 0.1,
              expandBottom: 0.4,
              expandMode: 'black',
            ),
          ),
        ],
        undoCursor: 1,
      );

      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(original: im, session: session),
      );

      // Expected new width: 10 + 2 (left) + 3 (right) = 15
      // Expected new height: 10 + 1 (top) + 4 (bottom) = 15
      expect(out.width, 15);
      expect(out.height, 15);

      // Center should retain original color
      expect(out.getPixel(4, 2).r, 100);
      // Border should be black (expanded area)
      expect(out.getPixel(0, 0).r, 0);
    });

    test('smart mode mirrors the border correctly', () {
      final im = img.Image(width: 4, height: 4);
      // Create a gradient so we can verify mirroring
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          im.setPixelRgb(x, y, 10 + x * 20, 20 + y * 20, 30);
        }
      }

      final session = EditSession(
        imageUri: 'test.jpg',
        ops: [
          EditOperation(
            id: 'expand-smart',
            tool: EditToolType.crop,
            appliedAt: DateTime.utc(2026, 1, 1),
            cropState: const CropState(
              expandLeft: 0.5, // 2 pixels left
              expandMode: 'smart',
            ),
          ),
        ],
        undoCursor: 1,
      );

      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(original: im, session: session),
      );

      // Expected width: 4 + 2 (left) = 6
      expect(out.width, 6);
      expect(out.height, 4);

      // Verify mirrored columns:
      // Original x=0 was 10. x=1 was 30.
      // Mirrored left:
      // x=1 (dist=0) -> maps to original x=0 (value 10)
      // x=0 (dist=1) -> maps to original x=1 (value 30)
      expect(out.getPixel(1, 0).r, 10);
      expect(out.getPixel(0, 0).r, 30);
    });
  });
}

