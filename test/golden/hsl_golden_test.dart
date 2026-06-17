import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('HSL numeric goldens', () {
    final cases = <String, AdjustParams>{
      'sky': const AdjustParams(
        hsl: {
          HslBand.blue: HslBandParams(saturation: 50.0, luminance: 20.0),
        },
      ),
      'foliage': const AdjustParams(
        hsl: {
          HslBand.green: HslBandParams(hue: 15.0, saturation: 40.0),
          HslBand.yellow: HslBandParams(hue: 5.0, saturation: 30.0),
        },
      ),
      'skin': const AdjustParams(
        hsl: {
          HslBand.orange: HslBandParams(saturation: -15.0, luminance: 15.0),
        },
      ),
      'product_red': const AdjustParams(
        hsl: {
          HslBand.red: HslBandParams(saturation: 60.0),
        },
      ),
      'mixed_neon': const AdjustParams(
        hsl: {
          HslBand.cyan: HslBandParams(hue: -10.0, saturation: 50.0),
          HslBand.magenta: HslBandParams(hue: 10.0, saturation: 40.0),
          HslBand.purple: HslBandParams(saturation: -30.0),
        },
      ),
    };

    final expected = <String, String>{
      'sky': '145255,141736,153991,3951109951',
      'foliage': '133220,149053,130146,3951270562',
      'skin': '141410,139176,146440,795369182',
      'product_red': '141766,136086,139132,2549850420',
      'mixed_neon': '138069,140472,138949,3953773217',
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
