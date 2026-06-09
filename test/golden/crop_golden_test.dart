import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/crop_engine.dart';

void main() {
  group('Crop Golden Signatures', () {
    final image = _referenceImage();

    final expectedSignatures = {
      CropRatioPreset.r1x1: '127500,127500,128000,915754685',
      CropRatioPreset.r16x9: '127500,127500,128000,8661173',
      CropRatioPreset.r4x5: '127500,127500,128000,3152915997',
      CropRatioPreset.r5x7: '127660,127500,127920,475584230',
    };

    for (final entry in expectedSignatures.entries) {
      test('Verify signature for preset ${entry.key.name}', () {
        final state = CropState(
          ratio: entry.key,
          centerX: 0.5,
          centerY: 0.5,
        );
        final cropped = cropImage(image, state);
        final sig = _signature(cropped);
        expect(sig, entry.value, reason: 'Mismatch for preset: ${entry.key.name}');
      });
    }
  });
}

img.Image _referenceImage() {
  final image = img.Image(width: 800, height: 600);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 800; x++) {
      final nx = x / 799.0;
      final ny = y / 599.0;
      image.setPixelRgb(
        x,
        y,
        (nx * 255).round(),
        (ny * 255).round(),
        ((1 - nx) * 128 + (1 - ny) * 128).round().clamp(0, 255),
      );
    }
  }
  return image;
}

String _signature(img.Image image) {
  var sumR = 0;
  var sumG = 0;
  var sumB = 0;
  var hash = 0x811c9dc5;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      sumR += r;
      sumG += g;
      sumB += b;
      hash = _fnv(hash, r);
      hash = _fnv(hash, g);
      hash = _fnv(hash, b);
    }
  }
  final n = image.width * image.height;
  final meanR = (sumR * 1000 / n).round();
  final meanG = (sumG * 1000 / n).round();
  final meanB = (sumB * 1000 / n).round();
  return '$meanR,$meanG,$meanB,${hash.toUnsigned(32)}';
}

int _fnv(int hash, int value) {
  hash ^= value;
  return (hash * 0x01000193).toUnsigned(32);
}
