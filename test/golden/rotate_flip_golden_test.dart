import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Rotate Flip Golden Signatures', () {
    final image = _referenceImage();

    final expectedSignatures = {
      'flipH': '127500,127500,128000,3130117342',
      'flipV': '127500,127500,128000,48746004',
      'rotate90': '127500,127500,128000,2737724636',
      'rotate180': '127500,127500,128000,1854121734',
      'rotate270': '127500,127500,128000,811715866',
    };

    for (final entry in expectedSignatures.entries) {
      test('Verify signature for ${entry.key}', () {
        img.Image processed;
        if (entry.key == 'flipH') {
          processed = img.copyFlip(image, direction: img.FlipDirection.horizontal);
        } else if (entry.key == 'flipV') {
          processed = img.copyFlip(image, direction: img.FlipDirection.vertical);
        } else if (entry.key == 'rotate90') {
          processed = img.copyRotate(image, angle: 90);
        } else if (entry.key == 'rotate180') {
          processed = img.copyRotate(image, angle: 180);
        } else if (entry.key == 'rotate270') {
          processed = img.copyRotate(image, angle: 270);
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
