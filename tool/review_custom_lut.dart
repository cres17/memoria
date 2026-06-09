// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/custom_lut_core.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run tool/review_custom_lut.dart <original> <target_style> <out_dir>');
    exit(64);
  }

  final original = img.decodeImage(File(args[0]).readAsBytesSync());
  final targetRaw = img.decodeImage(File(args[1]).readAsBytesSync());
  if (original == null || targetRaw == null) {
    throw StateError('Unable to decode input images.');
  }

  final outDir = Directory(args[2])..createSync(recursive: true);
  final diagnostics = inspectCustomLutStyle(targetRaw);
  final lut = buildCustomLutFromStyleImage(targetRaw);
  final result = _applyLutToImage(original, lut);
  final target = targetRaw.width == result.width && targetRaw.height == result.height
      ? targetRaw
      : img.copyResize(targetRaw, width: result.width, height: result.height);

  File('${outDir.path}/result_custom.jpg').writeAsBytesSync(img.encodeJpg(result, quality: 95));

  final before = _deltaE(original, target);
  final after = _deltaE(result, target);
  final gain = before.mean <= 0 ? 0.0 : (1.0 - after.mean / before.mean) * 100.0;

  print('Baseline original -> target: mean=${before.mean.toStringAsFixed(2)} '
      'p95=${before.p95.toStringAsFixed(2)} max=${before.max.toStringAsFixed(2)}');
  print('Custom LUT -> target:       mean=${after.mean.toStringAsFixed(2)} '
      'p95=${after.p95.toStringAsFixed(2)} max=${after.max.toStringAsFixed(2)}');
  print('Improvement vs original:    ${gain.toStringAsFixed(1)}%');
  print('Diagnostics:                ${diagnostics.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(2)}').join(', ')}');
  print('Saved: ${outDir.path}/result_custom.jpg');
}

img.Image _applyLutToImage(img.Image src, Uint8List lutBytes) {
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final px = src.getPixel(x, y);
      final rgb = applyCustomLut(
        lutBytes,
        RgbColor(
          px.rNormalized.toDouble(),
          px.gNormalized.toDouble(),
          px.bNormalized.toDouble(),
        ),
      );
      out.setPixelRgb(
        x,
        y,
        (rgb.r * 255).round(),
        (rgb.g * 255).round(),
        (rgb.b * 255).round(),
      );
    }
  }
  return out;
}

({double mean, double p95, double max}) _deltaE(img.Image a, img.Image b) {
  final values = <double>[];
  for (int y = 0; y < a.height; y++) {
    for (int x = 0; x < a.width; x++) {
      final ap = a.getPixel(x, y);
      final bp = b.getPixel(x, y);
      final al = rgbToLab(RgbColor(
        ap.rNormalized.toDouble(),
        ap.gNormalized.toDouble(),
        ap.bNormalized.toDouble(),
      ));
      final bl = rgbToLab(RgbColor(
        bp.rNormalized.toDouble(),
        bp.gNormalized.toDouble(),
        bp.bNormalized.toDouble(),
      ));
      final dl = al.l - bl.l;
      final da = al.a - bl.a;
      final db = al.b - bl.b;
      values.add(math.sqrt(dl * dl + da * da + db * db));
    }
  }

  values.sort();
  return (
    mean: values.fold(0.0, (sum, value) => sum + value) / values.length,
    p95: values[(values.length * 0.95).floor().clamp(0, values.length - 1)],
    max: values.last,
  );
}
