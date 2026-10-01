import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_litert/native.dart';

// ─── Result types ─────────────────────────────────────────────────────────────

/// Binary float32 mask aligned to [origW × origH], values 0.0–1.0.
class SegmentMask {
  final Float32List data; // row-major, index = y*width + x
  final int width;
  final int height;

  const SegmentMask(this.data, this.width, this.height);

  double at(int x, int y) => data[y * width + x];

  /// Resize mask to [targetW × targetH] via bilinear.
  SegmentMask resize(int targetW, int targetH) {
    if (targetW <= 0 || targetH <= 0) {
      throw ArgumentError('Mask target dimensions must be positive');
    }
    if (targetW == width && targetH == height) return this;
    final out = Float32List(targetW * targetH);
    for (int ty = 0; ty < targetH; ty++) {
      for (int tx = 0; tx < targetW; tx++) {
        // A one-pixel axis samples the source center instead of dividing by 0.
        final sx =
            targetW == 1 ? (width - 1) / 2 : tx * (width - 1) / (targetW - 1);
        final sy =
            targetH == 1 ? (height - 1) / 2 : ty * (height - 1) / (targetH - 1);
        final x0 = sx.floor();
        final x1 = (x0 + 1).clamp(0, width - 1);
        final y0 = sy.floor();
        final y1 = (y0 + 1).clamp(0, height - 1);
        final fx = sx - x0;
        final fy = sy - y0;
        final v = data[y0 * width + x0] * (1 - fx) * (1 - fy) +
            data[y0 * width + x1] * fx * (1 - fy) +
            data[y1 * width + x0] * (1 - fx) * fy +
            data[y1 * width + x1] * fx * fy;
        out[ty * targetW + tx] = v;
      }
    }
    return SegmentMask(out, targetW, targetH);
  }

  /// Feather edges with a Gaussian blur (radius in pixels of the resized mask).
  SegmentMask feather(int radius) {
    if (radius <= 0) return this;
    return _gaussianBlur(radius);
  }

  SegmentMask _gaussianBlur(int r) {
    final kernel = _gaussKernel(r);
    final tmp = Float32List(width * height);
    final out = Float32List(width * height);

    // Horizontal pass
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0, w = 0;
        for (int k = -r; k <= r; k++) {
          final xi = (x + k).clamp(0, width - 1);
          sum += data[y * width + xi] * kernel[k + r];
          w += kernel[k + r];
        }
        tmp[y * width + x] = sum / w;
      }
    }
    // Vertical pass
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double sum = 0, w = 0;
        for (int k = -r; k <= r; k++) {
          final yi = (y + k).clamp(0, height - 1);
          sum += tmp[yi * width + x] * kernel[k + r];
          w += kernel[k + r];
        }
        out[y * width + x] = sum / w;
      }
    }
    return SegmentMask(out, width, height);
  }

  static List<double> _gaussKernel(int r) {
    final sigma = r / 2.0;
    final k = List<double>.generate(
        2 * r + 1, (i) => _exp(-0.5 * ((i - r) / sigma) * ((i - r) / sigma)));
    return k;
  }

  static double _exp(double x) {
    if (x < -10) return 0.0;
    return _fastExp(x);
  }

  static double _fastExp(double x) {
    // Abramowitz & Stegun approximation (adequate for Gaussian kernel)
    if (x >= 0) return 1.0;
    final ax = -x;
    return 1.0 /
        (1.0 + ax + ax * ax / 2 + ax * ax * ax / 6 + ax * ax * ax * ax / 24);
  }
}

// ─── Selfie Segmenter (fast binary subject mask) ─────────────────────────────

class SelfieSegmenter {
  static const int _inW = 256;
  static const int _inH = 144;

  final Interpreter _interpreter;

  SelfieSegmenter._(this._interpreter);

  static Future<SelfieSegmenter> load(String modelPath) async {
    final options = InterpreterOptions()..threads = 2;
    try {
      options.addMediaPipeCustomOps();
      final interp = Interpreter.fromFile(File(modelPath), options: options);
      try {
        final input = interp.getInputTensor(0);
        final output = interp.getOutputTensor(0);
        if (input.type != TensorType.float32 ||
            output.type != TensorType.float32 ||
            !listEquals(input.shape, [1, _inH, _inW, 3]) ||
            !listEquals(output.shape, [1, _inH, _inW, 1])) {
          throw StateError('Unsupported selfie segmentation tensor contract');
        }
        return SelfieSegmenter._(interp);
      } catch (_) {
        interp.close();
        rethrow;
      }
    } finally {
      options.delete();
    }
  }

  /// Returns a subject probability mask (0 = background, 1 = subject).
  /// Output is resized to match [origW × origH].
  SegmentMask segment(img.Image image) {
    final origW = image.width;
    final origH = image.height;

    // Resize to model input
    final resized = img.copyResize(image,
        width: _inW, height: _inH, interpolation: img.Interpolation.linear);

    // Build input tensor [1, 144, 256, 3]
    final input = List.generate(
      1,
      (_) => List.generate(
        _inH,
        (y) => List.generate(
          _inW,
          (x) {
            final p = resized.getPixel(x, y);
            return [p.rNormalized, p.gNormalized, p.bNormalized];
          },
        ),
      ),
    );

    // Output tensor [1, 144, 256, 1]
    final output = List.generate(1,
        (_) => List.generate(_inH, (_) => List.generate(_inW, (_) => [0.0])));

    _interpreter.run(input, output);

    // The model already emits probabilities. A second sigmoid would turn
    // background values near zero into a mask near 0.5.
    final flat = Float32List(_inW * _inH);
    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final raw = output[0][y][x][0];
        flat[y * _inW + x] = raw.clamp(0.0, 1.0).toDouble();
      }
    }

    final mask = SegmentMask(flat, _inW, _inH);
    return mask.resize(origW, origH).feather(8); // soft edges
  }

  void dispose() => _interpreter.close();
}
