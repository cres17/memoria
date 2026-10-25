import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// `img.gaussianBlur`와 같은 결과(바이트 단위로 동일)를 내는 빠른 구현.
///
/// 라이브러리 구현은 모든 탭마다 픽셀 객체의 위치를 옮기고 채널을 읽어서 12MP 사진에서 수 초가 걸린다.
/// 이 구현은 같은 계수·같은 합산 순서·같은 반사 규칙·같은 버림(toInt)을 쓰면서 바이트 배열을 직접 읽는다.
/// 그래서 선명도·구조·샤픈 등 기존 결과(골든 테스트)가 바뀌지 않는다.
///
/// 8비트 이미지(채널 3 또는 4, 팔레트 없음)이고 반지름이 작아 반사가 한 번만 일어나는 경우에만 쓰고,
/// 그 밖에는 라이브러리 구현으로 넘긴다. [src]를 제자리에서 바꾸고 돌려주는 점도 라이브러리와 같다.
img.Image fastGaussianBlur(img.Image src, {required int radius}) {
  if (radius <= 0) return src;
  final supported = src.format == img.Format.uint8 &&
      !src.hasPalette &&
      (src.numChannels == 3 || src.numChannels == 4) &&
      src.width > radius &&
      src.height > radius;
  if (!supported) return img.gaussianBlur(src, radius: radius);

  final kernel = _kernel(radius);
  final width = src.width;
  final height = src.height;
  final nc = src.numChannels;
  final bytes = src.toUint8List();
  final temp = Uint8List.fromList(bytes);

  // 가로: bytes → temp
  _pass(bytes, temp, kernel, radius, lines: height, length: width, nc: nc, lineStride: width * nc, step: nc);
  // 세로: temp → bytes
  _pass(temp, bytes, kernel, radius, lines: width, length: height, nc: nc, lineStride: nc, step: width * nc);
  return src;
}

final Map<int, Float64List> _kernels = {};

Float64List _kernel(int radius) => _kernels.putIfAbsent(radius, () {
      // package:image의 gaussianBlur와 같은 식과 같은 계산 순서
      final sigma = radius * (2.0 / 3.0);
      final s = 2.0 * sigma * sigma;
      final k = Float64List(2 * radius + 1);
      double sum = 0.0;
      for (var x = -radius; x <= radius; ++x) {
        final c = math.exp(-(x * x) / s);
        sum += c;
        k[x + radius] = c;
      }
      final scale = 1.0 / sum;
      for (var i = 0; i < k.length; ++i) {
        k[i] = k[i] * scale;
      }
      return k;
    });

void _pass(
  Uint8List from,
  Uint8List to,
  Float64List kernel,
  int radius, {
  required int lines,
  required int length,
  required int nc,
  required int lineStride,
  required int step,
}) {
  final taps = 2 * radius + 1;
  // 위치 x에서 j번째 탭이 읽는 바이트 오프셋(선 시작 기준). 반사 규칙은 라이브러리와 같다.
  final offsets = Int32List(length * taps);
  for (var x = 0; x < length; x++) {
    for (var j = -radius, j2 = 0; j <= radius; ++j, ++j2) {
      final p = x + j;
      final g = p < 0 ? -p : (p >= length ? length - (p - length) - 1 : p);
      offsets[x * taps + j2] = g * step;
    }
  }

  for (var line = 0; line < lines; line++) {
    final base = line * lineStride;
    for (var x = 0; x < length; x++) {
      final o = x * taps;
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      if (nc == 4) {
        for (var t = 0; t < taps; t++) {
          final c = kernel[t];
          final i = base + offsets[o + t];
          r += c * from[i];
          g += c * from[i + 1];
          b += c * from[i + 2];
          a += c * from[i + 3];
        }
      } else {
        for (var t = 0; t < taps; t++) {
          final c = kernel[t];
          final i = base + offsets[o + t];
          r += c * from[i];
          g += c * from[i + 1];
          b += c * from[i + 2];
        }
      }
      final d = base + x * step;
      to[d] = r.toInt();
      to[d + 1] = g.toInt();
      to[d + 2] = b.toInt();
      if (nc == 4) to[d + 3] = a.toInt();
    }
  }
}
