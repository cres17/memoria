import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../ai_manager.dart';

enum _InputLayout { nhwc, nchw }

/// TFLite color-transfer wrapper.
///
/// The model contract is validated at load time instead of relying on a stale
/// hard-coded decoder dimension. Supported inputs are `[1, 256, 256, 3]`
/// (NHWC) and `[1, 3, 256, 256]` (NCHW); output must be `[1, D, D, D, 3]`.
class LutPredictor {
  static const int _inWH = 256;
  static const int _dstDim = 65;

  // Must match training and offline evaluation preprocessing.
  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  final Interpreter _interpreter;
  final _InputLayout _inputLayout;
  final int _srcDim;

  LutPredictor._(this._interpreter, this._inputLayout, this._srcDim);

  static LutPredictor? _instance;

  int get sourceDimension => _srcDim;

  static Future<LutPredictor> get instance async {
    if (_instance != null) return _instance!;
    final modelPath = await AiManager.instance.require(kModelColorTransfer);
    _instance = await _load(modelPath);
    return _instance!;
  }

  static Future<LutPredictor> fromPath(String modelPath) => _load(modelPath);

  static void resetForTesting() {
    _instance?._interpreter.close();
    _instance = null;
  }

  static Future<LutPredictor> _load(String modelPath) async {
    final options = InterpreterOptions()..threads = 2;
    if (Platform.isAndroid) {
      options.useNnApiForAndroid = true;
    }

    final interpreter = Interpreter.fromFile(File(modelPath), options: options);
    try {
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32) {
        throw StateError(
          'Color-transfer model must use float32 input and output tensors.',
        );
      }

      final layout = _inputLayoutFor(input.shape);
      final srcDim = _outputDimensionFor(output.shape);
      return LutPredictor._(interpreter, layout, srcDim);
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  static _InputLayout _inputLayoutFor(List<int> shape) {
    if (_matchesShape(shape, [1, _inWH, _inWH, 3])) {
      return _InputLayout.nhwc;
    }
    if (_matchesShape(shape, [1, 3, _inWH, _inWH])) {
      return _InputLayout.nchw;
    }
    throw StateError(
      'Unsupported color-transfer input shape $shape. Expected '
      '[1, 256, 256, 3] or [1, 3, 256, 256].',
    );
  }

  static int _outputDimensionFor(List<int> shape) {
    final valid = shape.length == 5 &&
        shape[0] == 1 &&
        shape[1] >= 2 &&
        shape[1] == shape[2] &&
        shape[2] == shape[3] &&
        shape[4] == 3;
    if (!valid) {
      throw StateError(
        'Unsupported color-transfer output shape $shape. Expected [1, D, D, D, 3].',
      );
    }
    return shape[1];
  }

  static bool _matchesShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  /// Flattened LUT contract used by storage, CPU sampling, and the GPU atlas:
  /// R is the fastest-changing axis, followed by G, then B.
  static int lutFlatIndex(int r, int g, int b, int c, int dim) =>
      (r + g * dim + b * dim * dim) * 3 + c;

  /// Style image → a 65³ LUT, stored with the shared R-fastest axis order.
  Future<Float32List> predict(String styleImagePath) async {
    final bytes = File(styleImagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Could not decode style image: $styleImagePath');
    }
    final image = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      image,
      width: _inWH,
      height: _inWH,
      interpolation: img.Interpolation.linear,
    );

    final input = _buildInput(resized);
    final output = _buildOutput();
    _interpreter.run(input, output);

    final lut = Float32List(_srcDim * _srcDim * _srcDim * 3);
    for (var b = 0; b < _srcDim; b++) {
      for (var g = 0; g < _srcDim; g++) {
        for (var r = 0; r < _srcDim; r++) {
          final values = output[0][r][g][b] as List;
          for (var c = 0; c < 3; c++) {
            lut[lutFlatIndex(r, g, b, c, _srcDim)] =
                (values[c] as double).clamp(0.0, 1.0);
          }
        }
      }
    }
    return _upsample(lut, _srcDim);
  }

  dynamic _buildInput(img.Image image) {
    if (_inputLayout == _InputLayout.nhwc) {
      return List.generate(
        1,
        (_) => List.generate(
          _inWH,
          (y) => List.generate(_inWH, (x) => _normalizedPixel(image, x, y)),
        ),
      );
    }
    return List.generate(
      1,
      (_) => List.generate(
        3,
        (c) => List.generate(
          _inWH,
          (y) => List.generate(_inWH, (x) => _normalizedPixel(image, x, y)[c]),
        ),
      ),
    );
  }

  List<double> _normalizedPixel(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    return [
      (pixel.rNormalized - _mean[0]) / _std[0],
      (pixel.gNormalized - _mean[1]) / _std[1],
      (pixel.bNormalized - _mean[2]) / _std[2],
    ];
  }

  dynamic _buildOutput() => List.generate(
        1,
        (_) => List.generate(
          _srcDim,
          (_) => List.generate(
            _srcDim,
            (_) => List.generate(_srcDim, (_) => List.filled(3, 0.0)),
          ),
        ),
      );

  Float32List _upsample(Float32List source, int srcDim) {
    final output = Float32List(_dstDim * _dstDim * _dstDim * 3);
    for (var db = 0; db < _dstDim; db++) {
      for (var dg = 0; dg < _dstDim; dg++) {
        for (var dr = 0; dr < _dstDim; dr++) {
          final sr = dr / (_dstDim - 1) * (srcDim - 1);
          final sg = dg / (_dstDim - 1) * (srcDim - 1);
          final sb = db / (_dstDim - 1) * (srcDim - 1);
          final r0 = sr.floor().clamp(0, srcDim - 2);
          final g0 = sg.floor().clamp(0, srcDim - 2);
          final b0 = sb.floor().clamp(0, srcDim - 2);
          final r1 = r0 + 1;
          final g1 = g0 + 1;
          final b1 = b0 + 1;
          final fr = sr - r0;
          final fg = sg - g0;
          final fb = sb - b0;

          for (var c = 0; c < 3; c++) {
            final v000 = source[lutFlatIndex(r0, g0, b0, c, srcDim)];
            final v100 = source[lutFlatIndex(r1, g0, b0, c, srcDim)];
            final v010 = source[lutFlatIndex(r0, g1, b0, c, srcDim)];
            final v110 = source[lutFlatIndex(r1, g1, b0, c, srcDim)];
            final v001 = source[lutFlatIndex(r0, g0, b1, c, srcDim)];
            final v101 = source[lutFlatIndex(r1, g0, b1, c, srcDim)];
            final v011 = source[lutFlatIndex(r0, g1, b1, c, srcDim)];
            final v111 = source[lutFlatIndex(r1, g1, b1, c, srcDim)];

            final value = v000 * (1 - fr) * (1 - fg) * (1 - fb) +
                v100 * fr * (1 - fg) * (1 - fb) +
                v010 * (1 - fr) * fg * (1 - fb) +
                v110 * fr * fg * (1 - fb) +
                v001 * (1 - fr) * (1 - fg) * fb +
                v101 * fr * (1 - fg) * fb +
                v011 * (1 - fr) * fg * fb +
                v111 * fr * fg * fb;
            output[lutFlatIndex(dr, dg, db, c, _dstDim)] =
                value.clamp(0.0, 1.0);
          }
        }
      }
    }
    return output;
  }

  void dispose() {
    _interpreter.close();
    _instance = null;
  }
}
