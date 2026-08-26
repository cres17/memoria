import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter_litert/native.dart';

import '../ai_manager.dart';

/// TFLite neural color-transfer model wrapper.
///
/// v2 model (color_transfer_v2.tflite):
///   Input : [1, 3, 256, 256] float32, ImageNet-normalized NCHW.
///   Output: [1, 33, 33, 33, 3] float32 LUT, upsampled to 65³ in Dart.
///   LUT Prototype conditioning (Fuji/Leica bank) is folded into model weights.
///
/// v1 legacy: same interface, output [1, 17, 17, 17, 3].
/// srcDim is detected automatically from the model output shape.
class LutPredictor {
  static const int _inWH = 256;
  static const int _dstDim = 65;

  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  final Interpreter _interpreter;
  final int _srcDim; // 17 (v1) or 33 (v2), detected at load time

  LutPredictor._(this._interpreter, this._srcDim);

  static LutPredictor? _instance;

  static Future<LutPredictor> get instance async {
    if (_instance != null) return _instance!;
    final modelPath = await AiManager.instance.require(kModelColorTransfer);
    _instance = await _load(modelPath);
    return _instance!;
  }

  static Future<LutPredictor> fromPath(String modelPath) => _load(modelPath);

  static Future<LutPredictor> _load(String modelPath) async {
    final options = InterpreterOptions()..threads = 4;
    final interp = Interpreter.fromFile(File(modelPath), options: options);
    // output shape: [1, D, D, D, 3] — read D from tensor
    final outShape = interp.getOutputTensor(0).shape;
    final srcDim = (outShape.length >= 4) ? outShape[1] : 17;
    return LutPredictor._(interp, srcDim);
  }

  Future<Float32List> predict(String styleImagePath) async {
    final bytes = File(styleImagePath).readAsBytesSync();
    final image = img.bakeOrientation(img.decodeImage(bytes)!);
    final resized = img.copyResize(
      image,
      width: _inWH,
      height: _inWH,
      interpolation: img.Interpolation.linear,
    );

    final input = List.generate(
      1,
      (_) => List.generate(
        3,
        (c) => List.generate(
          _inWH,
          (y) => List.generate(_inWH, (x) {
            final p = resized.getPixel(x, y);
            final values = [
              (p.rNormalized - _mean[0]) / _std[0],
              (p.gNormalized - _mean[1]) / _std[1],
              (p.bNormalized - _mean[2]) / _std[2],
            ];
            return values[c];
          }),
        ),
      ),
    );

    final d = _srcDim;
    final output = List.generate(
      1,
      (_) => List.generate(
        d,
        (_) => List.generate(
          d,
          (_) => List.generate(d, (_) => List.filled(3, 0.0)),
        ),
      ),
    );

    _interpreter.run(input, output);

    final lutFlat = Float32List(d * d * d * 3);
    for (var b = 0; b < d; b++) {
      for (var g = 0; g < d; g++) {
        for (var r = 0; r < d; r++) {
          final vals = output[0][r][g][b] as List;
          final i = _idx(r, g, b, 0, d);
          lutFlat[i] = (vals[0] as double).clamp(0.0, 1.0);
          lutFlat[i + 1] = (vals[1] as double).clamp(0.0, 1.0);
          lutFlat[i + 2] = (vals[2] as double).clamp(0.0, 1.0);
        }
      }
    }

    return _upsample(lutFlat, _srcDim);
  }

  Float32List _upsample(Float32List lut, int src) {
    const dst = _dstDim;
    final out = Float32List(dst * dst * dst * 3);

    for (var dr = 0; dr < dst; dr++) {
      for (var dg = 0; dg < dst; dg++) {
        for (var db = 0; db < dst; db++) {
          final sr = dr / (dst - 1) * (src - 1);
          final sg = dg / (dst - 1) * (src - 1);
          final sb = db / (dst - 1) * (src - 1);

          final r0 = sr.floor().clamp(0, src - 2);
          final g0 = sg.floor().clamp(0, src - 2);
          final b0 = sb.floor().clamp(0, src - 2);
          final r1 = r0 + 1;
          final g1 = g0 + 1;
          final b1 = b0 + 1;

          final fr = sr - r0;
          final fg = sg - g0;
          final fb = sb - b0;

          for (var c = 0; c < 3; c++) {
            final v000 = lut[_idx(r0, g0, b0, c, src)];
            final v100 = lut[_idx(r1, g0, b0, c, src)];
            final v010 = lut[_idx(r0, g1, b0, c, src)];
            final v110 = lut[_idx(r1, g1, b0, c, src)];
            final v001 = lut[_idx(r0, g0, b1, c, src)];
            final v101 = lut[_idx(r1, g0, b1, c, src)];
            final v011 = lut[_idx(r0, g1, b1, c, src)];
            final v111 = lut[_idx(r1, g1, b1, c, src)];

            final v = v000 * (1 - fr) * (1 - fg) * (1 - fb) +
                v100 * fr * (1 - fg) * (1 - fb) +
                v010 * (1 - fr) * fg * (1 - fb) +
                v110 * fr * fg * (1 - fb) +
                v001 * (1 - fr) * (1 - fg) * fb +
                v101 * fr * (1 - fg) * fb +
                v011 * (1 - fr) * fg * fb +
                v111 * fr * fg * fb;

            out[_idx(dr, dg, db, c, dst)] = v.clamp(0.0, 1.0);
          }
        }
      }
    }

    return out;
  }

  static int _idx(int r, int g, int b, int c, int dim) =>
      (r + g * dim + b * dim * dim) * 3 + c;

  void dispose() {
    _interpreter.close();
    _instance = null;
  }
}
