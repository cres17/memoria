import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
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
    if (targetW == width && targetH == height) return this;
    final out = Float32List(targetW * targetH);
    for (int ty = 0; ty < targetH; ty++) {
      for (int tx = 0; tx < targetW; tx++) {
        final sx = tx * (width - 1) / (targetW - 1);
        final sy = ty * (height - 1) / (targetH - 1);
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
    final interp = Interpreter.fromFile(File(modelPath), options: options);
    return SelfieSegmenter._(interp);
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

    // Flatten to Float32List and sigmoid
    final flat = Float32List(_inW * _inH);
    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final raw = output[0][y][x][0];
        flat[y * _inW + x] = _sigmoid(raw);
      }
    }

    final mask = SegmentMask(flat, _inW, _inH);
    return mask.resize(origW, origH).feather(8); // soft edges
  }

  void dispose() => _interpreter.close();

  static double _sigmoid(double x) => 1.0 / (1.0 + _safeExp(-x));
  static double _safeExp(double x) {
    if (x > 88) return double.maxFinite;
    if (x < -88) return 0.0;
    return _expApprox(x);
  }

  static double _expApprox(double x) {
    // Reasonable approximation for sigmoid range
    double r = 1, term = 1;
    for (int i = 1; i <= 5; i++) {
      term *= x / i;
      r += term;
    }
    return r.clamp(0.0, double.maxFinite);
  }
}
