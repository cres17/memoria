import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/geometry_transforms.dart';

void main() {
  group('Perspective Golden Signatures', () {
    final image = _referenceImage();

    final expectedSignatures = {
      'hSkew15': '133591,124141,119927,600761840',
      'vSkew15': '124162,133463,119925,1151933860',
      'bothSkew15': '131243,131182,112354,671301980',
      'negBothSkew15': '112051,112010,131805,2718936925',
    };

    for (final entry in expectedSignatures.entries) {
      test('Verify signature for ${entry.key}', () {
        img.Image processed;
        if (entry.key == 'hSkew15') {
          processed = applyPerspectiveSkewInverse(image, 15, 0);
        } else if (entry.key == 'vSkew15') {
          processed = applyPerspectiveSkewInverse(image, 0, 15);
        } else if (entry.key == 'bothSkew15') {
          processed = applyPerspectiveSkewInverse(image, 15, 15);
        } else if (entry.key == 'negBothSkew15') {
          processed = applyPerspectiveSkewInverse(image, -15, -15);
        } else {
          processed = image;
        }

        final sig = _signature(processed);
        expect(sig, entry.value, reason: 'Mismatch for: ${entry.key}');
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
