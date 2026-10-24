import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 하늘 영역 마스크(0..1). [width]×[height]는 마스크 해상도다.
class SkyMask {
  final Float32List data;
  final int width;
  final int height;

  const SkyMask(this.data, this.width, this.height);

  bool get isEmpty => data.isEmpty || !data.any((v) => v > 0.01);

  /// 사진 좌표계(0..1) 위치의 마스크 값. 쌍선형 보간.
  double sample(double u, double v) {
    final x = (u * (width - 1)).clamp(0.0, (width - 1).toDouble());
    final y = (v * (height - 1)).clamp(0.0, (height - 1).toDouble());
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final fx = x - x0;
    final fy = y - y0;
    final top = data[y0 * width + x0] * (1 - fx) + data[y0 * width + x1] * fx;
    final bottom = data[y1 * width + x0] * (1 - fx) + data[y1 * width + x1] * fx;
    return top * (1 - fy) + bottom * fy;
  }
}

/// 색과 연결성으로 하늘을 찾는 규칙 기반 방식(머신러닝 모델 아님).
///
/// 사진 위쪽에서 시작해 "푸른색이거나 밝고 채도가 낮은(구름) 부분 중 위쪽과
/// 이어진 영역"만 하늘로 본다. 푸른 부분이 거의 없는 영역은 하늘로 보지 않으므로
/// 구름만 낀 흐린 하늘, 일몰처럼 붉은 하늘은 찾지 못한다. 위쪽이 가려진 구도나
/// 푸른 건물이 위쪽과 이어진 경우는 틀릴 수 있다.
SkyMask detectSky(img.Image image, {int maxEdge = 256}) {
  final scale = math.min(1.0, maxEdge / math.max(image.width, image.height));
  final w = math.max(4, (image.width * scale).round());
  final h = math.max(4, (image.height * scale).round());
  final small = scale < 1
      ? img.copyResize(image,
          width: w, height: h, interpolation: img.Interpolation.average)
      : image;

  final luma = Float32List(w * h);
  final candidate = Uint8List(w * h);
  final blue = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final r = p.rNormalized.toDouble();
      final g = p.gNormalized.toDouble();
      final b = p.bNormalized.toDouble();
      luma[y * w + x] = (0.299 * r + 0.587 * g + 0.114 * b).toDouble();
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final r = p.rNormalized.toDouble();
      final g = p.gNormalized.toDouble();
      final b = p.bNormalized.toDouble();
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      final l = luma[y * w + x];
      final lx = luma[y * w + math.min(x + 1, w - 1)] -
          luma[y * w + math.max(x - 1, 0)];
      final ly = luma[math.min(y + 1, h - 1) * w + x] -
          luma[math.max(y - 1, 0) * w + x];
      final gradient = lx.abs() + ly.abs();

      final blueSky = b >= r + 0.02 && b >= g - 0.02 && l > 0.30 && gradient < 0.15;
      final cloud = l > 0.72 && sat < 0.22 && gradient < 0.10;
      if (blueSky) blue[y * w + x] = 1;
      if (blueSky || cloud) candidate[y * w + x] = 1;
    }
  }

  // 구름 가장자리처럼 색이 섞인 1~2픽셀 틈은 메우고(닫기),
  // 얇게 이어진 부분(전선, 창틀 사이 틈)으로 번지지 않도록 두 번 깎아서 연결을 본다.
  final allowAll = Uint8List(w * h)..fillRange(0, w * h, 1);
  final closed = _erode(_dilateWithin(candidate, allowAll, w, h), w, h);
  final core = _erode(_erode(closed, w, h), w, h);

  var sky = Uint8List(w * h);
  final queue = Queue<int>();
  final seedRows = math.max(1, (h * 0.12).round());
  for (var y = 0; y < seedRows; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (core[i] == 1 && sky[i] == 0) {
        sky[i] = 1;
        queue.add(i);
      }
    }
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w;
    final y = i ~/ w;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx;
      final ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final ni = ny * w + nx;
      if (core[ni] == 1 && sky[ni] == 0) {
        sky[ni] = 1;
        queue.add(ni);
      }
    }
  }
  // 깎은 만큼 되돌리되 후보 안에서만 넓힌다.
  sky = _dilateWithin(_dilateWithin(sky, closed, w, h), closed, w, h);

  // 푸른 하늘 증거가 거의 없는 영역(회색 건물 벽, 흰 눈밭 등)은 하늘로 보지 않는다.
  var skyCount = 0;
  var blueCount = 0;
  for (var i = 0; i < sky.length; i++) {
    if (sky[i] == 1) {
      skyCount++;
      blueCount += blue[i];
    }
  }
  if (skyCount == 0 || blueCount / skyCount < 0.10) {
    sky = Uint8List(w * h);
  }

  var mask = Float32List(w * h);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = sky[i].toDouble();
  }
  // 경계를 부드럽게: 상자 블러 2회.
  for (var pass = 0; pass < 2; pass++) {
    mask = _boxBlur(mask, w, h, 2);
  }
  return SkyMask(mask, w, h);
}

Uint8List _erode(Uint8List src, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (src[i] == 1 &&
          src[i - 1] == 1 &&
          src[i + 1] == 1 &&
          src[i - w] == 1 &&
          src[i + w] == 1) {
        out[i] = 1;
      }
    }
  }
  // 가장자리 한 줄은 안쪽 값을 따른다(위쪽 가장자리의 하늘이 사라지지 않게).
  for (var x = 0; x < w; x++) {
    out[x] = out[w + x];
    out[(h - 1) * w + x] = out[(h - 2) * w + x];
  }
  return out;
}

Uint8List _dilateWithin(Uint8List src, Uint8List allowed, int w, int h) {
  final out = Uint8List.fromList(src);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (src[i] == 1 || allowed[i] == 0) continue;
      if ((x > 0 && src[i - 1] == 1) ||
          (x < w - 1 && src[i + 1] == 1) ||
          (y > 0 && src[i - w] == 1) ||
          (y < h - 1 && src[i + w] == 1)) {
        out[i] = 1;
      }
    }
  }
  return out;
}

Float32List _boxBlur(Float32List src, int w, int h, int radius) {
  final tmp = Float32List(w * h);
  final out = Float32List(w * h);
  final window = (radius * 2 + 1).toDouble();
  for (var y = 0; y < h; y++) {
    var sum = 0.0;
    for (var x = -radius; x <= radius; x++) {
      sum += src[y * w + x.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[y * w + x] = sum / window;
      sum += src[y * w + math.min(x + radius + 1, w - 1)] -
          src[y * w + math.max(x - radius, 0)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0.0;
    for (var y = -radius; y <= radius; y++) {
      sum += tmp[y.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum / window;
      sum += tmp[math.min(y + radius + 1, h - 1) * w + x] -
          tmp[math.max(y - radius, 0) * w + x];
    }
  }
  return out;
}

/// 하늘에만 적용하는 보정값. 모두 -100..100, 0이면 변화 없음.
class SkyAdjust {
  final double brightness;
  final double saturation;

  /// 음수는 더 푸르게, 양수는 더 따뜻하게.
  final double warmth;

  const SkyAdjust({this.brightness = 0, this.saturation = 0, this.warmth = 0});

  bool get isNeutral => brightness == 0 && saturation == 0 && warmth == 0;
}

/// 하늘 영역에만 [adjust]를 적용한 새 이미지를 돌려준다.
/// [showMask]가 true면 보정 대신 하늘로 본 영역을 붉게 표시한다(영역 확인용).
img.Image applySkyAdjust(
  img.Image image,
  SkyAdjust adjust, {
  bool showMask = false,
  SkyMask? mask,
}) {
  if (adjust.isNeutral && !showMask) return image;
  final sky = mask ?? detectSky(image);
  if (sky.isEmpty) return image;

  final out = img.Image.from(image);
  final b = adjust.brightness / 100.0;
  final s = adjust.saturation / 100.0;
  final warm = adjust.warmth / 100.0;
  final w = image.width;
  final h = image.height;

  for (var y = 0; y < h; y++) {
    final v = h == 1 ? 0.0 : y / (h - 1);
    for (var x = 0; x < w; x++) {
      final weight = sky.sample(w == 1 ? 0.0 : x / (w - 1), v);
      if (weight <= 0.004) continue;
      final p = out.getPixel(x, y);
      var r = p.rNormalized.toDouble();
      var g = p.gNormalized.toDouble();
      var bl = p.bNormalized.toDouble();

      double nr, ng, nb;
      if (showMask) {
        nr = r * 0.4 + 0.6;
        ng = g * 0.4;
        nb = bl * 0.4;
      } else {
        final luma = 0.299 * r + 0.587 * g + 0.114 * bl;
        nr = luma + (r - luma) * (1 + s);
        ng = luma + (g - luma) * (1 + s);
        nb = luma + (bl - luma) * (1 + s);
        final gain = 1 + b * 0.6;
        nr = nr * gain * (1 + warm * 0.18);
        ng = ng * gain;
        nb = nb * gain * (1 - warm * 0.18);
      }
      r = r + (nr.clamp(0.0, 1.0) - r) * weight;
      g = g + (ng.clamp(0.0, 1.0) - g) * weight;
      bl = bl + (nb.clamp(0.0, 1.0) - bl) * weight;
      out.setPixelRgb(
        x,
        y,
        (r * 255).round(),
        (g * 255).round(),
        (bl * 255).round(),
      );
    }
  }
  return out;
}
