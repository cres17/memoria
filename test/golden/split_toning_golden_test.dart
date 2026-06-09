import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('split toning numeric goldens', () {
    final cases = <String, AdjustParams>{
      'teal_shadows': const AdjustParams(
        splitShadowHue: 180.0,
        splitShadowSat: 45.0,
      ),
      'warm_highlights': const AdjustParams(
        splitHighHue: 40.0,
        splitHighSat: 40.0,
      ),
      'low_sat_film': const AdjustParams(
        saturation: -20.0,
        splitShadowHue: 210.0,
        splitShadowSat: 25.0,
        splitHighHue: 45.0,
        splitHighSat: 20.0,
        splitBalance: -10.0,
      ),
    };

    final expected = <String, String>{
      'teal_shadows': '135588,139456,142868,1595164771',
      'warm_highlights': '145213,138905,133831,2314465103',
      'low_sat_film': '141632,139023,136602,3808442640',
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final source = _referenceImage();
        final out = applyImagePipeline(
          image: source,
          params: entry.value,
        );
        final signature = _signature(out);
        expect(
          signature,
          expected[entry.key],
          reason: 'Actual signature for ${entry.key}: "$signature"',
        );
      });
    }
  });
}

img.Image _referenceImage({int width = 24, int height = 18}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = x / (width - 1);
      final ny = y / (height - 1);
      final wave = ((x * 17 + y * 29) % 23) / 22.0;
      final skin = (1.0 - (nx - 0.32).abs() * 2.2).clamp(0.0, 1.0);
      final foliage = (1.0 - (nx - 0.74).abs() * 2.4).clamp(0.0, 1.0);
      image.setPixelRgb(
        x,
        y,
        (38 + nx * 124 + skin * 72 + wave * 18).round().clamp(0, 255),
        (44 + ny * 116 + foliage * 78 + wave * 12).round().clamp(0, 255),
        (58 + (1 - ny) * 134 + (1 - nx) * 22 + wave * 10).round().clamp(0, 255),
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
