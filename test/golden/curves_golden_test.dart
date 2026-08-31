import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('curves numeric goldens', () {
    final cases = <String, AdjustParams>{
      's_curve': const AdjustParams(
        rgbCurve: CurveData(
          channel: CurveChannel.rgb,
          points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.25, 0.15),
            CurvePoint(0.5, 0.5),
            CurvePoint(0.75, 0.85),
            CurvePoint(1.0, 1.0),
          ],
        ),
      ),
      'matte_fade': const AdjustParams(
        rgbCurve: CurveData(
          channel: CurveChannel.rgb,
          points: [
            CurvePoint(0.0, 0.10),
            CurvePoint(1.0, 0.90),
          ],
        ),
      ),
      'red_lift': const AdjustParams(
        redCurve: CurveData(
          channel: CurveChannel.red,
          points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.65),
            CurvePoint(1.0, 1.0),
          ],
        ),
      ),
      'blue_shadows': const AdjustParams(
        blueCurve: CurveData(
          channel: CurveChannel.blue,
          points: [
            CurvePoint(0.0, 0.18),
            CurvePoint(0.4, 0.28),
            CurvePoint(1.0, 1.0),
          ],
        ),
      ),
    };

    // Note: These expected signatures will be filled with the actual signatures generated during first run.
    final expected = <String, String>{
      's_curve': '146396,140567,145588,2936641823',
      'matte_fade': '137079,135681,138389,1715047585',
      'red_lift': '174831,137574,140986,1173856222',
      'blue_shadows': '139359,137574,110840,2319880887',
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final source = _referenceImage();
        final out = applyImagePipeline(
          image: source,
          params: entry.value,
        );
        final signature = _signature(out);

        // Assert matching signature (or print to make updating them easy if parameters change)
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
