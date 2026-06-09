import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('global adjust numeric goldens', () {
    final cases = <String, AdjustParams>{
      'identity': AdjustParams.zero,
      'exposure_contrast': const AdjustParams(exposure: 0.5, contrast: 15),
      'saturation_temp_tint': const AdjustParams(saturation: 25, temperature: -30, tint: 20),
      'highlights_shadows_ambiance': const AdjustParams(highlights: 30, shadows: -20, ambiance: 40),
      'tonal_contrast': const AdjustParams(tonalShadows: 40, tonalMidtones: -30, tonalHighlights: 20),
      'mixed_realistic': const AdjustParams(
        exposure: 0.25,
        contrast: 10,
        saturation: 15,
        temperature: 15,
        tint: -5,
        highlights: -15,
        shadows: 20,
        ambiance: 35,
      ),
    };

    // Placeholders to be updated after first run
    final expected = <String, String>{
      'identity': '139359,137574,140986,2956847176', // Should match filter original
      'exposure_contrast': '205521,192736,198384,2055240490',
      'saturation_temp_tint': '129463,142498,149275,4277879165',
      'highlights_shadows_ambiance': '143632,141211,145847,74467781',
      'tonal_contrast': '131407,129623,133035,162592809',
      'mixed_realistic': '166414,156042,155681,636270874',
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
          reason: 'Actual signature for ${entry.key}: $signature',
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
