import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Normalized depth map: 0.0 = closest, 1.0 = farthest.
class DepthMap {
  final Float32List data; // row-major, [0,1]
  final int width;
  final int height;

  const DepthMap(this.data, this.width, this.height);

  double at(int x, int y) => data[y * width + x];

  /// Resize to [targetW × targetH] via bilinear.
  DepthMap resize(int targetW, int targetH) {
    if (targetW == width && targetH == height) return this;
    final out = Float32List(targetW * targetH);
    for (int ty = 0; ty < targetH; ty++) {
      for (int tx = 0; tx < targetW; tx++) {
        final sx = tx * (width  - 1) / (targetW - 1);
        final sy = ty * (height - 1) / (targetH - 1);
        final x0 = sx.floor(); final x1 = (x0 + 1).clamp(0, width  - 1);
        final y0 = sy.floor(); final y1 = (y0 + 1).clamp(0, height - 1);
        final fx = sx - x0; final fy = sy - y0;
        out[ty * targetW + tx] =
            data[y0*width+x0]*(1-fx)*(1-fy) +
            data[y0*width+x1]*   fx *(1-fy) +
            data[y1*width+x0]*(1-fx)*   fy  +
            data[y1*width+x1]*   fx *   fy;
      }
    }
    return DepthMap(out, targetW, targetH);
  }

  /// Smooth the depth map to avoid blocking artifacts in bokeh.
  DepthMap smooth(int radius) {
    if (radius <= 0) return this;
    final tmp = Float32List(width * height);
    final out = Float32List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double s = 0, c = 0;
        for (int k = -radius; k <= radius; k++) {
          final xi = (x + k).clamp(0, width - 1);
          s += data[y * width + xi]; c++;
        }
        tmp[y * width + x] = s / c;
      }
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double s = 0, c = 0;
        for (int k = -radius; k <= radius; k++) {
          final yi = (y + k).clamp(0, height - 1);
          s += tmp[yi * width + x]; c++;
        }
        out[y * width + x] = s / c;
      }
    }
    return DepthMap(out, width, height);
  }
}

// ─── MiDaS Small depth estimator ─────────────────────────────────────────────

class DepthEstimator {
  static const int _inWH = 256;

  // MiDaS normalization constants (ImageNet mean/std)
  static const _mean = [0.485, 0.456, 0.406];
  static const _std  = [0.229, 0.224, 0.225];

  final Interpreter _interpreter;

  DepthEstimator._(this._interpreter);

  static Future<DepthEstimator> load(String modelPath) async {
    final options = InterpreterOptions()
      ..threads = 4
      ..useNnApiForAndroid = true;
    final interp = Interpreter.fromFile(File(modelPath), options: options);
    return DepthEstimator._(interp);
  }

  /// Returns a depth map normalized to [0, 1] where 0 = close, 1 = far.
  /// Output is resized to match the input image dimensions.
  DepthMap estimate(img.Image image) {
    final origW = image.width;
    final origH = image.height;

    final resized = img.copyResize(image,
        width: _inWH, height: _inWH,
        interpolation: img.Interpolation.linear);

    // Build input [1, 256, 256, 3] with ImageNet normalization
    final input = List.generate(
      1,
      (_) => List.generate(_inWH, (y) => List.generate(_inWH, (x) {
        final p = resized.getPixel(x, y);
        return [
          (p.rNormalized - _mean[0]) / _std[0],
          (p.gNormalized - _mean[1]) / _std[1],
          (p.bNormalized - _mean[2]) / _std[2],
        ];
      })),
    );

    // MiDaS Small output: [1, 256, 256] float32 (inverse depth)
    final raw = List.generate(1, (_) => List.generate(_inWH,
        (_) => List.filled(_inWH, 0.0)));

    _interpreter.run(input, raw);

    // Flatten + normalize to [0,1]
    final flat = Float32List(_inWH * _inWH);
    double minV = double.maxFinite, maxV = double.negativeInfinity;

    for (int y = 0; y < _inWH; y++) {
      for (int x = 0; x < _inWH; x++) {
        final v = (raw[0][y][x] as double);
        flat[y * _inWH + x] = v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }

    final range = (maxV - minV).abs();
    if (range > 1e-6) {
      for (int i = 0; i < flat.length; i++) {
        // MiDaS outputs inverse depth: larger = closer.
        // Invert so 0 = close, 1 = far (matches blur expectation).
        flat[i] = 1.0 - ((flat[i] - minV) / range);
      }
    }

    return DepthMap(flat, _inWH, _inWH)
        .resize(origW, origH)
        .smooth(2);
  }

  void dispose() => _interpreter.close();
}
