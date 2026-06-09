import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/engine/edit_operation_player.dart';

void main() {
  group('Details Engine Tests', () {
    test('sharpen increases details contrast', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.details,
          params: const AdjustParams(sharpen: 50),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.1));
    });

    test('structure modifies edge contrast', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.details,
          params: const AdjustParams(structure: 50),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.1));
    });

    test('clarity changes mid-frequency contrast', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.details,
          params: const AdjustParams(clarity: 50),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.1));
    });

    test('details parameters are no-op when zero', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.details,
          params: AdjustParams.zero,
        ),
      );

      expect(_meanAbsoluteDelta(original, out), closeTo(0.0, 0.001));
    });
  });
}

img.Image _play(img.Image original, EditOperation op) {
  final session = EditSession.forImage('memory://sample').pushOp(op);
  return const EditOperationPlayer().play(
    EditOperationPlayerArgs(original: original, session: session),
  );
}

EditOperation _op(EditToolType tool, {AdjustParams? params}) => EditOperation(
      id: 'op-${tool.name}',
      tool: tool,
      appliedAt: DateTime(2026, 6, 2),
      params: params,
    );

img.Image _sampleImage() {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 90 + x * 3, 96 + y * 3, 120);
    }
  }
  for (var y = 12; y < 20; y++) {
    for (var x = 12; x < 20; x++) {
      image.setPixelRgb(x, y, 235, 30, 34);
    }
  }
  return image;
}

double _meanAbsoluteDelta(img.Image a, img.Image b) {
  var sum = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      sum += _pixelDelta(a.getPixel(x, y), b.getPixel(x, y));
    }
  }
  return sum / (a.width * a.height);
}

double _pixelDelta(img.Pixel a, img.Pixel b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3.0;
