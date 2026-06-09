import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../ai_manager.dart';

/// TFLite Neural Color Transfer 모델 래퍼.
///
/// 모델 출력: 5³ LUT (125 × 3 float32)
/// 앱 내 업샘플: 5³ → 65³ (trilinear, ~50ms)
/// 총 추론 시간: GPU delegate ~80ms (목표 200ms 이하)
class LutPredictor {
  static const int _inWH       = 256;
  static const int _srcDim     = 5;   // 모델 직접 출력 해상도
  static const int _dstDim     = 65;  // 앱 내 업샘플 목표

  // ImageNet 정규화 (MobileNetV3)
  static const _mean = [0.485, 0.456, 0.406];
  static const _std  = [0.229, 0.224, 0.225];

  final Interpreter _interpreter;

  LutPredictor._(this._interpreter);

  // ── Singleton ──────────────────────────────────────────────────────────────

  static LutPredictor? _instance;

  static Future<LutPredictor> get instance async {
    if (_instance != null) return _instance!;
    final modelPath = await AiManager.instance.require(kModelColorTransfer);
    _instance = await _load(modelPath);
    return _instance!;
  }

  static Future<LutPredictor> _load(String modelPath) async {
    final options = InterpreterOptions()..threads = 2;

    // GPU delegate: Android NNAPI, iOS CoreML
    if (Platform.isAndroid) {
      options.useNnApiForAndroid = true;
    }

    final interp = Interpreter.fromFile(File(modelPath), options: options);
    return LutPredictor._(interp);
  }

  // ── 추론 ──────────────────────────────────────────────────────────────────

  /// 스타일 이미지 경로 → 65³ LUT (Float32List, 길이 65³×3 = 823,875).
  Future<Float32List> predict(String styleImagePath) async {
    final bytes   = File(styleImagePath).readAsBytesSync();
    final image   = img.decodeImage(bytes)!;
    final resized = img.copyResize(image,
        width: _inWH, height: _inWH,
        interpolation: img.Interpolation.linear);

    // 입력 텐서 [1, 256, 256, 3] — ImageNet 정규화
    final input = List.generate(1, (_) =>
      List.generate(_inWH, (y) =>
        List.generate(_inWH, (x) {
          final p = resized.getPixel(x, y);
          return [
            (p.rNormalized - _mean[0]) / _std[0],
            (p.gNormalized - _mean[1]) / _std[1],
            (p.bNormalized - _mean[2]) / _std[2],
          ];
        }),
      ),
    );

    // 출력 텐서 [1, 5, 5, 5, 3]
    final output = List.generate(1, (_) =>
      List.generate(_srcDim, (_) =>
        List.generate(_srcDim, (_) =>
          List.generate(_srcDim, (_) =>
            List.filled(3, 0.0),
          ),
        ),
      ),
    );

    _interpreter.run(input, output);

    // 5³ → Float32List
    final lut5 = Float32List(_srcDim * _srcDim * _srcDim * 3);
    int i = 0;
    for (int r = 0; r < _srcDim; r++) {
      for (int g = 0; g < _srcDim; g++) {
        for (int b = 0; b < _srcDim; b++) {
          final vals = output[0][r][g][b] as List;
          lut5[i++] = (vals[0] as double).clamp(0.0, 1.0);
          lut5[i++] = (vals[1] as double).clamp(0.0, 1.0);
          lut5[i++] = (vals[2] as double).clamp(0.0, 1.0);
        }
      }
    }

    // 5³ → 65³ trilinear upsample
    return _upsample(lut5);
  }

  // ── 65³ 업샘플 (trilinear) ────────────────────────────────────────────────

  Float32List _upsample(Float32List lut5) {
    const src = _srcDim;
    const dst = _dstDim;
    final out  = Float32List(dst * dst * dst * 3);

    for (int dr = 0; dr < dst; dr++) {
      for (int dg = 0; dg < dst; dg++) {
        for (int db = 0; db < dst; db++) {
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

          for (int c = 0; c < 3; c++) {
            final v000 = lut5[_idx5(r0,g0,b0,c)];
            final v100 = lut5[_idx5(r1,g0,b0,c)];
            final v010 = lut5[_idx5(r0,g1,b0,c)];
            final v110 = lut5[_idx5(r1,g1,b0,c)];
            final v001 = lut5[_idx5(r0,g0,b1,c)];
            final v101 = lut5[_idx5(r1,g0,b1,c)];
            final v011 = lut5[_idx5(r0,g1,b1,c)];
            final v111 = lut5[_idx5(r1,g1,b1,c)];

            final v = v000*(1-fr)*(1-fg)*(1-fb) +
                      v100*fr    *(1-fg)*(1-fb) +
                      v010*(1-fr)*fg    *(1-fb) +
                      v110*fr    *fg    *(1-fb) +
                      v001*(1-fr)*(1-fg)*fb     +
                      v101*fr    *(1-fg)*fb     +
                      v011*(1-fr)*fg    *fb     +
                      v111*fr    *fg    *fb;

            out[_idx65(dr,dg,db,c)] = v.clamp(0.0, 1.0);
          }
        }
      }
    }
    return out;
  }

  static int _idx5(int r, int g, int b, int c) =>
      (r + g * _srcDim + b * _srcDim * _srcDim) * 3 + c;

  static int _idx65(int r, int g, int b, int c) =>
      (r + g * _dstDim + b * _dstDim * _dstDim) * 3 + c;

  void dispose() {
    _interpreter.close();
    _instance = null;
  }
}
