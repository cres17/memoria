import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  기본 블러 함수들
// ─────────────────────────────────────────────────────────

/// 가우시안 블러 (image 패키지 래퍼)
img.Image gaussianBlur(img.Image image, int radius) {
  return img.gaussianBlur(image, radius: radius.clamp(1, 30));
}

/// 마스크 기반 블렌딩: mask=0 → original, mask=1 → blurred
img.Image applyBlurWithMask(
  img.Image original,
  img.Image blurred,
  Float32List mask,
) {
  assert(mask.length == original.width * original.height);
  final result = img.Image(width: original.width, height: original.height);

  for (int y = 0; y < original.height; y++) {
    for (int x = 0; x < original.width; x++) {
      final idx = y * original.width + x;
      final t   = mask[idx].clamp(0.0, 1.0);
      final o   = original.getPixel(x, y);
      final b   = blurred.getPixel(x, y);
      final r   = o.rNormalized + (b.rNormalized - o.rNormalized) * t;
      final g   = o.gNormalized + (b.gNormalized - o.gNormalized) * t;
      final bv  = o.bNormalized + (b.bNormalized - o.bNormalized) * t;
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (bv.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────
//  Tilt-Shift
// ─────────────────────────────────────────────────────────

/// Linear Tilt-Shift: 포커스 밴드 내부는 선명, 외부는 블러
/// [focusCenter] 0.0~1.0 (상단~하단 비율)
/// [focusBandWidth] 0.0~1.0 (포커스 밴드 폭)
/// [maxBlur] 최대 블러 반경
img.Image applyLinearTiltShift({
  required img.Image image,
  required double focusCenter,
  required double focusBandWidth,
  required double maxBlur,
}) {
  final blurred = gaussianBlur(image, maxBlur.round().clamp(1, 20));
  final mask    = Float32List(image.width * image.height);
  final H       = image.height.toDouble();
  final bandHalf = focusBandWidth / 2.0;
  final transition = 0.1.clamp(0.01, bandHalf);

  for (int y = 0; y < image.height; y++) {
    final yNorm = y / H;
    final dist  = (yNorm - focusCenter).abs();
    double t;
    if (dist <= bandHalf - transition) {
      t = 0.0;
    } else if (dist >= bandHalf + transition) {
      t = 1.0;
    } else {
      t = ((dist - (bandHalf - transition)) / (2 * transition)).clamp(0.0, 1.0);
    }
    for (int x = 0; x < image.width; x++) {
      mask[y * image.width + x] = t.toDouble();
    }
  }
  return applyBlurWithMask(image, blurred, mask);
}

/// Elliptical Tilt-Shift: 타원 포커스 영역
/// [centerX/Y] 0.0~1.0, [radiusX/Y] 0.0~1.0
img.Image applyEllipticalTiltShift({
  required img.Image image,
  required double centerX,
  required double centerY,
  required double radiusX,
  required double radiusY,
  required double maxBlur,
}) {
  final blurred    = gaussianBlur(image, maxBlur.round().clamp(1, 20));
  final mask       = Float32List(image.width * image.height);
  final W          = image.width.toDouble();
  final H          = image.height.toDouble();
  final transition = 0.15;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final nx  = x / W - centerX;
      final ny  = y / H - centerY;
      final ellDist = math.sqrt((nx / radiusX) * (nx / radiusX) + (ny / radiusY) * (ny / radiusY));
      double t;
      if (ellDist <= 1.0 - transition) {
        t = 0.0;
      } else if (ellDist >= 1.0 + transition) {
        t = 1.0;
      } else {
        t = ((ellDist - (1.0 - transition)) / (2 * transition)).clamp(0.0, 1.0);
      }
      mask[y * image.width + x] = t.toDouble();
    }
  }
  return applyBlurWithMask(image, blurred, mask);
}

// ─────────────────────────────────────────────────────────
//  Lens Blur (Depth-Map Guided)
// ─────────────────────────────────────────────────────────

/// Depth map 기반 적응적 블러 (렌즈 블러 효과)
/// [depthMap] 0~1 (0=가까움, 1=멈)
/// [focusDepth] 포커스 거리 0~1
/// [maxBlurRadius] 최대 블러 반경
img.Image applyLensBlur({
  required img.Image image,
  required Float32List depthMap,
  required double focusDepth,
  required double maxBlurRadius,
}) {
  // 다단계 블러: 여러 반경으로 블러를 미리 계산하고 가중치 합성
  const int levels = 5;
  final blurredLevels = <img.Image>[];
  for (int i = 0; i < levels; i++) {
    final radius = ((i + 1) * maxBlurRadius / levels).round().clamp(1, 25);
    blurredLevels.add(gaussianBlur(image, radius));
  }

  final result = img.Image(width: image.width, height: image.height);
  final W = image.width;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final depth     = depthMap[y * W + x].clamp(0.0, 1.0);
      final depthDiff = (depth - focusDepth).abs();
      final blurLevel = (depthDiff * levels).floor().clamp(0, levels - 1);
      final px        = blurredLevels[blurLevel].getPixel(x, y);
      result.setPixelRgb(x, y,
        (px.rNormalized * 255).round(),
        (px.gNormalized * 255).round(),
        (px.bNormalized * 255).round(),
      );
    }
  }
  return result;
}
