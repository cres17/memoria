import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/native.dart';
import 'package:image/image.dart' as img;

import '../../engine/sky_mask.dart';

/// 하늘 분할 모델(U²-Net, 변환 방법은 ml_pipeline/convert_skyseg.py).
///
/// 입력  : [1, 3, 320, 320] float32, RGB 0~1 (ImageNet 정규화는 모델 안에 포함)
/// 출력  : [1, 1, 320, 320] float32, 하늘 확률 0~1
///
/// 추론은 별도 isolate에서 하므로 화면이 멈추지 않는다. 사진 전체를 320×320으로 줄여 넣기 때문에
/// 결과 마스크도 정규화 좌표(0~1)로 쓴다([SkyMask.sample]).
typedef SkyInference = Future<Float32List> Function(Float32List chwInput);

class SkySegmenter {
  static const int size = 320;

  /// 하늘로 볼 확률의 절반 기준(0.5)을 넘는 면적이 이보다 작으면 하늘이 없는 사진으로 본다.
  static const double minSkyFraction = 0.005;

  final SkyInference _infer;

  const SkySegmenter(this._infer);

  /// 모델 파일을 별도 isolate에서 실행하는 분할기.
  factory SkySegmenter.fromModelFile(String modelPath) =>
      SkySegmenter((input) => Isolate.run(() => _runModel(modelPath, input)));

  /// [image] 전체의 하늘 마스크(320×320, 정규화 좌표)를 돌려준다.
  Future<SkyMask> segment(img.Image image) async {
    final output = await _infer(preprocess(image));
    return postprocess(output);
  }

  @visibleForTesting
  static Float32List preprocess(img.Image image) {
    final resized = img.copyResize(
      image,
      width: size,
      height: size,
      interpolation: img.Interpolation.linear,
    );
    final out = Float32List(3 * size * size);
    const plane = size * size;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = resized.getPixel(x, y);
        final i = y * size + x;
        out[i] = p.rNormalized.toDouble();
        out[plane + i] = p.gNormalized.toDouble();
        out[2 * plane + i] = p.bNormalized.toDouble();
      }
    }
    return out;
  }

  @visibleForTesting
  static SkyMask postprocess(Float32List probability) {
    if (probability.length != size * size) {
      throw ArgumentError('sky model output must be ${size * size} values, '
          'got ${probability.length}');
    }
    final out = Float32List(probability.length);
    var confident = 0;
    for (var i = 0; i < out.length; i++) {
      var v = probability[i];
      if (v.isNaN || v < 0) v = 0;
      if (v > 1) v = 1;
      if (v >= 0.5) confident++;
      // 경계가 계단지지 않도록 0.2~0.8 구간을 부드럽게 잇는다.
      final t = ((v - 0.2) / 0.6).clamp(0.0, 1.0);
      out[i] = t * t * (3 - 2 * t);
    }
    if (confident / out.length < minSkyFraction) {
      return SkyMask(Float32List(out.length), size, size);
    }
    return SkyMask(out, size, size);
  }
}

/// isolate 안에서 실행된다. 모델을 열고, 한 번 돌리고, 닫는다.
Float32List _runModel(String modelPath, Float32List input) {
  const n = SkySegmenter.size;
  const plane = n * n;
  final interpreter = Interpreter.fromFile(
    File(modelPath),
    options: InterpreterOptions()..threads = 2,
  );
  try {
    final nested = [
      List.generate(
        3,
        (c) => List.generate(
          n,
          (y) => List.generate(n, (x) => input[c * plane + y * n + x]),
        ),
      ),
    ];
    final output = [
      [
        List.generate(n, (_) => List.filled(n, 0.0)),
      ],
    ];
    interpreter.run(nested, output);
    final flat = Float32List(plane);
    for (var y = 0; y < n; y++) {
      final row = output[0][0][y];
      for (var x = 0; x < n; x++) {
        flat[y * n + x] = (row[x] as num).toDouble();
      }
    }
    return flat;
  } finally {
    interpreter.close();
  }
}
