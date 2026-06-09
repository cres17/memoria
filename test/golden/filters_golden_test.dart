import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/custom_lut_core.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('filter numeric goldens', () {
    final cases = <String, _GoldenCase>{
      'original': const _GoldenCase(lutBytes: null, intensity: 1),
      'fuji_provia': _GoldenCase(
        lutBytes: File('assets/luts/fuji_provia.bin').readAsBytesSync(),
        intensity: 0.9,
      ),
      'leica_m8': _GoldenCase(
        lutBytes: File('assets/luts/leica_m8.bin').readAsBytesSync(),
        intensity: 0.9,
      ),
      'custom_warm': _GoldenCase(
        lutBytes: _warmCustomLutBytes(),
        intensity: 0.85,
      ),
      'high_saturation_velvia': _GoldenCase(
        source: _highSaturationImage(),
        lutBytes: File('assets/luts/fuji_velvia.bin').readAsBytesSync(),
        intensity: 1,
      ),
    };

    const expected = <String, String>{
      'original': '139359,137574,140986,2956847176',
      'fuji_provia': '158053,159655,157641,3415134026',
      'leica_m8': '211567,194933,204331,1607978388',
      'custom_warm': '150530,141301,128046,2746582522',
      'high_saturation_velvia': '149667,142333,134167,2981388573',
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final source = entry.value.source ?? _referenceImage();
        final out = applyImagePipeline(
          image: source,
          params: AdjustParams.zero,
          lutBytes: entry.value.lutBytes,
          intensity: entry.value.intensity,
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

  test('preview and export LUT application stay within parity tolerance', () {
    final exportSource = _referenceImage(width: 64, height: 48);
    final previewSource = img.copyResize(
      exportSource,
      width: 32,
      height: 24,
      interpolation: img.Interpolation.linear,
    );
    final lutBytes =
        File('assets/luts/fuji_classic_chrome.bin').readAsBytesSync();

    final preview = applyImagePipeline(
      image: previewSource,
      params: AdjustParams.zero,
      lutBytes: lutBytes,
      intensity: 0.9,
    );
    final export = applyImagePipeline(
      image: exportSource,
      params: AdjustParams.zero,
      lutBytes: lutBytes,
      intensity: 0.9,
    );
    final exportDownsampled = img.copyResize(
      export,
      width: preview.width,
      height: preview.height,
      interpolation: img.Interpolation.linear,
    );

    final diff = _diff(preview, exportDownsampled);
    expect(diff.mean, lessThanOrEqualTo(2.0), reason: diff.toString());
    expect(diff.p99, lessThanOrEqualTo(10.0), reason: diff.toString());
  });
}

class _GoldenCase {
  final img.Image? source;
  final Uint8List? lutBytes;
  final double intensity;

  const _GoldenCase({
    this.source,
    required this.lutBytes,
    required this.intensity,
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

img.Image _highSaturationImage() {
  final image = img.Image(width: 24, height: 18);
  const colors = [
    [255, 0, 0],
    [0, 255, 0],
    [0, 0, 255],
    [255, 255, 0],
    [255, 0, 255],
    [0, 255, 255],
  ];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final c = colors[(x ~/ 4 + y ~/ 3) % colors.length];
      image.setPixelRgb(x, y, c[0], c[1], c[2]);
    }
  }
  return image;
}

Uint8List _warmCustomLutBytes() {
  final values = Uint16List(customLutDim * customLutDim * customLutDim * 3);
  final max = (customLutDim - 1).toDouble();
  var i = 0;
  for (var b = 0; b < customLutDim; b++) {
    for (var g = 0; g < customLutDim; g++) {
      for (var r = 0; r < customLutDim; r++) {
        final rn = r / max;
        final gn = g / max;
        final bn = b / max;
        final lum = 0.2126 * rn + 0.7152 * gn + 0.0722 * bn;
        values[i++] = floatToHalf((rn * 1.06 + 0.035 * lum).clamp(0.0, 1.0));
        values[i++] = floatToHalf((gn * 1.01 + 0.012).clamp(0.0, 1.0));
        values[i++] = floatToHalf((bn * 0.91 - 0.018 * lum).clamp(0.0, 1.0));
      }
    }
  }
  return values.buffer.asUint8List();
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

({double mean, double p99}) _diff(img.Image a, img.Image b) {
  final values = <double>[];
  var sum = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final ap = a.getPixel(x, y);
      final bp = b.getPixel(x, y);
      final d =
          ((ap.r - bp.r).abs() + (ap.g - bp.g).abs() + (ap.b - bp.b).abs()) /
              3.0;
      values.add(d);
      sum += d;
    }
  }
  values.sort();
  final p99Index = (values.length * 0.99).floor().clamp(0, values.length - 1);
  return (mean: sum / values.length, p99: values[p99Index]);
}
