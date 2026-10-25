import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/fast_blur.dart';
import 'package:memoria/engine/lut_engine.dart';

/// 성능을 위해 바꾼 경로가 원래 구현과 바이트 단위로 같은 결과를 내는지 확인한다.
/// 기준은 최적화 전 구현을 그대로 옮긴 참조 코드(이 파일 아래쪽)와 package:image의 gaussianBlur다.

img.Image _random(int w, int h, int channels, int seed) {
  final rnd = math.Random(seed);
  final image = img.Image(width: w, height: h, numChannels: channels);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // 부드러운 바탕 + 잡음으로 반사·반올림 경계를 골고루 건드린다.
      final base = ((x * 5 + y * 3) % 256);
      image.setPixelRgba(
        x,
        y,
        (base + rnd.nextInt(40)) % 256,
        (base * 2 + rnd.nextInt(40)) % 256,
        (255 - base + rnd.nextInt(40)) % 256,
        channels == 4 ? rnd.nextInt(256) : 255,
      );
    }
  }
  return image;
}

void main() {
  group('fastGaussianBlur == img.gaussianBlur', () {
    for (final channels in [3, 4]) {
      for (final size in [(9, 9), (23, 17), (64, 40), (101, 7 + 12)]) {
        for (final radius in [1, 2, 5, 7, 8]) {
          test('${size.$1}x${size.$2} ch=$channels r=$radius', () {
            final source = _random(size.$1, size.$2, channels, size.$1 * 31 + radius);
            final expected = img.gaussianBlur(img.Image.from(source), radius: radius);
            final actual = fastGaussianBlur(img.Image.from(source), radius: radius);
            expect(actual.toUint8List(), expected.toUint8List());
          });
        }
      }
    }

    test('큰 반지름도 image 4.12의 경계 처리와 바이트 단위로 같다', () {
      // image 4.12 handles radii beyond the image extent instead of throwing.
      // This is the library fallback path, so verify pixels and in-place return.
      for (final size in [(1, 1), (2, 3), (6, 6)]) {
        for (final channels in [3, 4]) {
          final source = _random(size.$1, size.$2, channels, 1);
          final expected = img.gaussianBlur(img.Image.from(source), radius: 8);
          final actual = img.Image.from(source);
          expect(identical(fastGaussianBlur(actual, radius: 8), actual), isTrue);
          expect(actual.toUint8List(), expected.toUint8List());
        }
      }
    });

    test('반지름 0 이하는 아무것도 바꾸지 않는다', () {
      final small = _random(6, 6, 3, 1);
      expect(fastGaussianBlur(img.Image.from(small), radius: 0).toUint8List(),
          small.toUint8List());
    });

    test('제자리 변경·반환값이 라이브러리와 같다', () {
      final a = _random(30, 30, 3, 9);
      final result = fastGaussianBlur(a, radius: 3);
      expect(identical(result, a), isTrue);
    });
  });

  group('파이프라인 경로가 참조 구현과 같다', () {
    final source = _random(80, 60, 3, 77);

    Uint8List run(AdjustParams p) =>
        applyImagePipeline(image: source, params: p).toUint8List();

    test('HDR(pow 표) == 픽셀별 pow', () {
      final expected = _referenceHdr(
        applyImagePipeline(image: source, params: AdjustParams.zero),
        40,
        15,
      ).toUint8List();
      expect(run(const AdjustParams(hdrStrength: 40, hdrSaturation: 15)), expected);
    });

    test('샤픈 == 기존 반복문', () {
      final base = applyImagePipeline(image: source, params: AdjustParams.zero);
      final expected = _referenceDetail(base, 2, 40 / 100.0 * 1.5, mid: false).toUint8List();
      expect(run(const AdjustParams(sharpen: 40)), expected);
    });

    test('구조 == 기존 반복문', () {
      final base = applyImagePipeline(image: source, params: AdjustParams.zero);
      final expected = _referenceDetail(base, 1, 35 / 100.0 * 0.5, mid: false).toUint8List();
      expect(run(const AdjustParams(structure: 35)), expected);
    });

    test('선명도 == 기존 반복문', () {
      final base = applyImagePipeline(image: source, params: AdjustParams.zero);
      final expected = _referenceDetail(base, 7, 50 / 100.0 * 0.7, mid: true).toUint8List();
      expect(run(const AdjustParams(clarity: 50)), expected);
    });
  });
}

// ── 최적화 전 구현(참조) ─────────────────────────────────────

img.Image _referenceHdr(img.Image image, double strength, double saturation) {
  final W = image.width;
  final H = image.height;
  final blurred = img.gaussianBlur(img.Image.from(image), radius: 10);
  final result = img.Image(width: W, height: H);
  final str = strength / 100.0 * 0.8;
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final bpx = blurred.getPixel(x, y);
      var r = px.rNormalized.toDouble();
      var g = px.gNormalized.toDouble();
      var b = px.bNormalized.toDouble();
      final br = bpx.rNormalized.toDouble();
      final bg = bpx.gNormalized.toDouble();
      final bb = bpx.bNormalized.toDouble();
      const epsilon = 0.01;
      r = r * math.pow((r + epsilon) / (br + epsilon), str);
      g = g * math.pow((g + epsilon) / (bg + epsilon), str);
      b = b * math.pow((b + epsilon) / (bb + epsilon), str);
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      final s = 1.0 + saturation / 100.0 * 0.5;
      r = lum + (r - lum) * s;
      g = lum + (g - lum) * s;
      b = lum + (b - lum) * s;
      result.setPixelRgb(
        x,
        y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

img.Image _referenceDetail(img.Image image, int radius, double strength, {required bool mid}) {
  final blurred = img.gaussianBlur(img.Image.from(image), radius: radius);
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o = image.getPixel(x, y);
      final low = blurred.getPixel(x, y);
      double r, g, b;
      if (mid) {
        final lum = 0.2126 * o.rNormalized +
            0.7152 * o.gNormalized +
            0.0722 * o.bNormalized;
        final midMask = (1.0 - (lum - 0.5).abs() * 2.0).clamp(0.0, 1.0);
        r = (o.rNormalized + strength * midMask * (o.rNormalized - low.rNormalized)).clamp(0.0, 1.0);
        g = (o.gNormalized + strength * midMask * (o.gNormalized - low.gNormalized)).clamp(0.0, 1.0);
        b = (o.bNormalized + strength * midMask * (o.bNormalized - low.bNormalized)).clamp(0.0, 1.0);
      } else {
        r = (o.rNormalized + strength * (o.rNormalized - low.rNormalized)).clamp(0.0, 1.0);
        g = (o.gNormalized + strength * (o.gNormalized - low.gNormalized)).clamp(0.0, 1.0);
        b = (o.bNormalized + strength * (o.bNormalized - low.bNormalized)).clamp(0.0, 1.0);
      }
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}
