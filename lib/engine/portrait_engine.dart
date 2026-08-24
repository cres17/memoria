import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/blur_engine.dart';

// ─────────────────────────────────────────────────────────
//  Portrait 이펙트 (세그멘테이션 마스크 기반)
// ─────────────────────────────────────────────────────────

enum SkinTone { none, pale, fair, medium, dark }

extension SkinToneX on SkinTone {
  String get label {
    switch (this) {
      case SkinTone.none:
        return '없음';
      case SkinTone.pale:
        return 'Pale';
      case SkinTone.fair:
        return 'Fair';
      case SkinTone.medium:
        return 'Medium';
      case SkinTone.dark:
        return 'Dark';
    }
  }

  // 목표 피부 색조 Hue (HSV 기준, null=보정 없음)
  double? get targetHue {
    switch (this) {
      case SkinTone.none:
        return null;
      case SkinTone.pale:
        return 15.0;
      case SkinTone.fair:
        return 20.0;
      case SkinTone.medium:
        return 25.0;
      case SkinTone.dark:
        return 30.0;
    }
  }
}

/// 피부 스무딩 (Bilateral filter 근사)
/// [faceMask] 0.0~1.0 픽셀 마스크 (1=피부 영역)
img.Image applySkinSmoothing(
  img.Image image,
  Float32List faceMask,
  double strength,
) {
  if (strength <= 0 || faceMask.length != image.width * image.height) {
    return image;
  }

  final sigma = (strength / 100.0 * 1.5).clamp(0.0, 2.0);
  final blurred = gaussianBlur(image, (sigma * 3).round().clamp(1, 8));
  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final idx = y * image.width + x;
      final w = (faceMask[idx] * strength / 100.0).clamp(0.0, 1.0);
      final o = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);
      final r = o.rNormalized + (bl.rNormalized - o.rNormalized) * w;
      final g = o.gNormalized + (bl.gNormalized - o.gNormalized) * w;
      final b = o.bNormalized + (bl.bNormalized - o.bNormalized) * w;
      result.setPixelRgba(
        x,
        y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
        o.a.toInt(),
      );
    }
  }
  return result;
}

/// 얼굴 스포트라이트 (얼굴 중심부 radial dodge)
img.Image applyFaceSpotlight(
  img.Image image,
  Float32List faceMask,
  double boost, {
  double faceCenterX = 0.5,
  double faceCenterY = 0.35,
}) {
  if (boost <= 0 || faceMask.length != image.width * image.height) {
    return image;
  }

  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);
  final W = image.width.toDouble();
  final H = image.height.toDouble();

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final idx = y * image.width + x;
      final maskVal = faceMask[idx];
      if (maskVal < 0.01) {
        final px = image.getPixel(x, y);
        result.setPixelRgba(
            x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), px.a.toInt());
        continue;
      }

      final dx = x / W - faceCenterX;
      final dy = y / H - faceCenterY;
      final dist = math.sqrt(dx * dx + dy * dy);
      final sigma = 0.25;
      final radial = math.exp(-0.5 * dist * dist / (sigma * sigma));
      final w = maskVal * radial * boost / 100.0;

      final px = image.getPixel(x, y);
      final r = (px.rNormalized + w * (1 - px.rNormalized)).clamp(0.0, 1.0);
      final g = (px.gNormalized + w * (1 - px.gNormalized)).clamp(0.0, 1.0);
      final b = (px.bNormalized + w * (1 - px.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgba(x, y, (r * 255).round(), (g * 255).round(),
          (b * 255).round(), px.a.toInt());
    }
  }
  return result;
}

/// 피부 색조 보정 (Hue shift in HSV space)
img.Image applySkinToning(
  img.Image image,
  Float32List faceMask,
  SkinTone tone,
  double strength,
) {
  if (tone == SkinTone.none ||
      strength <= 0 ||
      faceMask.length != image.width * image.height) return image;
  final targetHue = tone.targetHue;
  if (targetHue == null) return image;

  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final idx = y * image.width + x;
      final maskVal = faceMask[idx];
      final px = image.getPixel(x, y);

      if (maskVal < 0.01) {
        result.setPixelRgba(
            x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), px.a.toInt());
        continue;
      }

      final hsv = _rgbToHsv(px.rNormalized.toDouble(),
          px.gNormalized.toDouble(), px.bNormalized.toDouble());
      final hueDiff = targetHue - hsv.$1;
      final newHue = (hsv.$1 + hueDiff * maskVal * strength / 100.0) % 360.0;
      final rgb = _hsvToRgb(newHue, hsv.$2, hsv.$3);
      result.setPixelRgba(x, y, (rgb.$1 * 255).round(), (rgb.$2 * 255).round(),
          (rgb.$3 * 255).round(), px.a.toInt());
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────
//  HSV 변환 헬퍼
// ─────────────────────────────────────────────────────────

(double h, double s, double v) _rgbToHsv(double r, double g, double b) {
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final delta = max - min;

  double h = 0;
  if (delta != 0) {
    if (max == r) {
      h = 60 * ((g - b) / delta % 6);
    } else if (max == g) {
      h = 60 * ((b - r) / delta + 2);
    } else {
      h = 60 * ((r - g) / delta + 4);
    }
    if (h < 0) {
      h += 360;
    }
  }
  final s = max == 0 ? 0.0 : delta / max;
  return (h, s, max);
}

(double r, double g, double b) _hsvToRgb(double h, double s, double v) {
  final c = v * s;
  final x = c * (1 - (h / 60 % 2 - 1).abs());
  final m = v - c;
  double r = 0, g = 0, b = 0;

  if (h < 60) {
    r = c;
    g = x;
  } else if (h < 120) {
    r = x;
    g = c;
  } else if (h < 180) {
    g = c;
    b = x;
  } else if (h < 240) {
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }

  return (
    (r + m).clamp(0.0, 1.0),
    (g + m).clamp(0.0, 1.0),
    (b + m).clamp(0.0, 1.0)
  );
}

img.Image applyDepthBokeh(
  img.Image image,
  Float32List depthMap,
  double strength,
) {
  if (strength <= 0) return image;
  if (depthMap.length != image.width * image.height) return image;

  final sigma = (strength / 100.0 * 4.0).clamp(0.0, 10.0);
  final blurred = gaussianBlur(image, (sigma * 3).round().clamp(1, 12));
  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final idx = y * image.width + x;
      final d = depthMap[idx].clamp(0.0, 1.0);
      final w = d * strength / 100.0;

      final o = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);

      final r = o.rNormalized + (bl.rNormalized - o.rNormalized) * w;
      final g = o.gNormalized + (bl.gNormalized - o.gNormalized) * w;
      final b = o.bNormalized + (bl.bNormalized - o.bNormalized) * w;

      result.setPixelRgba(
        x,
        y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
        o.a.toInt(),
      );
    }
  }
  return result;
}

img.Image applyHeadPoseWarp(
  img.Image image,
  Float32List faceMask, {
  double yaw = 0.0,
  double pitch = 0.0,
}) {
  if (yaw == 0.0 && pitch == 0.0) return image;
  if (faceMask.length != image.width * image.height) return image;

  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);
  final W = image.width;
  final H = image.height;

  final maxShiftX = W * 0.08;
  final maxShiftY = H * 0.08;

  final dx = (yaw / 100.0) * maxShiftX;
  final dy = (pitch / 100.0) * maxShiftY;

  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final idx = y * W + x;
      final m = faceMask[idx].clamp(0.0, 1.0);

      if (m <= 0.0) {
        final px = image.getPixel(x, y);
        result.setPixelRgba(
          x,
          y,
          (px.rNormalized * 255).round(),
          (px.gNormalized * 255).round(),
          (px.bNormalized * 255).round(),
          px.a.toInt(),
        );
        continue;
      }

      final sx = (x - dx * m).round().clamp(0, W - 1);
      final sy = (y - dy * m).round().clamp(0, H - 1);

      final px = image.getPixel(sx, sy);
      result.setPixelRgba(
        x,
        y,
        (px.rNormalized * 255).round(),
        (px.gNormalized * 255).round(),
        (px.bNormalized * 255).round(),
        px.a.toInt(),
      );
    }
  }
  return result;
}
