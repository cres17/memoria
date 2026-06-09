import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/models/edit_operation.dart';
import 'blend_modes.dart';
import 'lut_engine.dart';

Float32List createSoftBrushMask({
  required int width,
  required int height,
  required List<BrushStroke> strokes,
  double hardness = 0.5,
}) {
  final mask = Float32List(width * height);
  if (width <= 0 || height <= 0 || strokes.isEmpty) return mask;

  final minDim = math.min(width, height).toDouble();
  final hard = hardness.clamp(0.0, 1.0);
  final featherExp = 0.45 + hard * 5.55;

  for (final stroke in strokes) {
    final r = (stroke.radius * minDim).clamp(0.5, minDim);
    final cx = stroke.x.clamp(0.0, 1.0) * (width - 1);
    final cy = stroke.y.clamp(0.0, 1.0) * (height - 1);
    final isEraser = stroke.pressure < 0;
    final absPressure = stroke.pressure.abs().clamp(0.0, 1.0);
    if (absPressure <= 0) continue;

    final left = math.max(0, (cx - r).floor());
    final right = math.min(width - 1, (cx + r).ceil());
    final top = math.max(0, (cy - r).floor());
    final bottom = math.min(height - 1, (cy + r).ceil());
    final invR = 1.0 / r;

    for (var y = top; y <= bottom; y++) {
      final dy = y - cy;
      for (var x = left; x <= right; x++) {
        final dx = x - cx;
        final d = math.sqrt(dx * dx + dy * dy) * invR;
        if (d > 1) continue;
        final falloff = hard >= 0.999
            ? absPressure
            : math.pow(1.0 - d, featherExp).toDouble() * absPressure;
        final idx = y * width + x;
        if (isEraser) {
          mask[idx] = (mask[idx] - falloff).clamp(0.0, 1.0);
        } else {
          if (falloff > mask[idx]) {
            mask[idx] = falloff.clamp(0.0, 1.0);
          }
        }
      }
    }
  }

  return mask;
}

img.Image applyBrushCorrection({
  required img.Image image,
  required BrushMaskData brush,
  Uint8List? lutBytes,
  Float32List? decodedLutValues,
  int decodedLutDim = 65,
  BakedCurveLuts? bakedLuts,
}) {
  if (brush.strokes.isEmpty || brush.localParams.isZero) return image;

  final mask = brush.cachedMask != null &&
          brush.cachedMask!.length == image.width * image.height
      ? brush.cachedMask!
      : createSoftBrushMask(
          width: image.width,
          height: image.height,
          strokes: brush.strokes,
          hardness: brush.hardness,
        );

  final adjusted = applyImagePipeline(
    image: image,
    params: brush.localParams,
    lutBytes: lutBytes,
    decodedLutValues: decodedLutValues,
    decodedLutDim: decodedLutDim,
    bakedLuts: bakedLuts,
    intensity: 1.0,
  );

  return applyStacksMask(original: image, filtered: adjusted, mask: mask);
}
