import 'dart:math' as math;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  Selective 포인트 기반 로컬 조정
// ─────────────────────────────────────────────────────────

class LocalSelectivePoint {
  final double x; // 0.0~1.0 (이미지 정규화 좌표)
  final double y; // 0.0~1.0
  final double brightness; // -100 ~ +100
  final double contrast; // -100 ~ +100
  final double saturation; // -100 ~ +100
  final double radius; // 0.0~1.0 (반경)

  const LocalSelectivePoint({
    required this.x,
    required this.y,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.radius = 0.3,
  });

  LocalSelectivePoint copyWith({
    double? x,
    double? y,
    double? brightness,
    double? contrast,
    double? saturation,
    double? radius,
  }) =>
      LocalSelectivePoint(
        x: x ?? this.x,
        y: y ?? this.y,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        radius: radius ?? this.radius,
      );
}

/// 여러 LocalSelectivePoint를 이미지에 적용
img.Image applySelectiveAdjust(
    img.Image image, List<LocalSelectivePoint> points) {
  final effectivePoints = points
      .where((point) =>
          point.radius > 0 &&
          (point.brightness != 0 ||
              point.contrast != 0 ||
              point.saturation != 0))
      .toList(growable: false);
  if (effectivePoints.isEmpty) return image;

  final result = img.Image(width: image.width, height: image.height);
  final W = image.width.toDouble();
  final H = image.height.toDouble();
  // Combine spatial falloff with the colour sampled at each touched point.
  // This protects a nearby but visibly different subject/background region.
  final pointColors = effectivePoints.map((point) {
    final sampleX = (point.x.clamp(0.0, 1.0) * (image.width - 1))
        .round()
        .clamp(0, image.width - 1);
    final sampleY = (point.y.clamp(0.0, 1.0) * (image.height - 1))
        .round()
        .clamp(0, image.height - 1);
    final sample = image.getPixel(sampleX, sampleY);
    return (
      r: sample.rNormalized.toDouble(),
      g: sample.gNormalized.toDouble(),
      b: sample.bNormalized.toDouble(),
    );
  }).toList(growable: false);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      var r = px.rNormalized.toDouble();
      var g = px.gNormalized.toDouble();
      var b = px.bNormalized.toDouble();

      for (var index = 0; index < effectivePoints.length; index++) {
        final pt = effectivePoints[index];
        final sourceColor = pointColors[index];
        // 거리 마스크 (가우시안)
        final dx = x / W - pt.x;
        final dy = y / H - pt.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        final sigma = math.max(pt.radius * 0.5, 0.001);
        final spatialWeight = math.exp(-0.5 * dist * dist / (sigma * sigma));
        final dr = r - sourceColor.r;
        final dg = g - sourceColor.g;
        final db = b - sourceColor.b;
        final colorDistance = math.sqrt((dr * dr + dg * dg + db * db) / 3);
        final colorSigma = 0.10 + pt.radius * 0.20;
        final colorWeight = math.exp(
            -0.5 * colorDistance * colorDistance / (colorSigma * colorSigma));
        final weight = spatialWeight * colorWeight;

        if (weight < 0.001) continue;

        // Brightness
        if (pt.brightness != 0) {
          final adj = pt.brightness / 100.0 * 0.5 * weight;
          r = (r + adj).clamp(0.0, 1.0);
          g = (g + adj).clamp(0.0, 1.0);
          b = (b + adj).clamp(0.0, 1.0);
        }
        // Contrast
        if (pt.contrast != 0) {
          final f =
              (259.0 * (pt.contrast + 255)) / (255.0 * (259 - pt.contrast));
          final nr = (f * (r - 0.5) + 0.5).clamp(0.0, 1.0);
          final ng = (f * (g - 0.5) + 0.5).clamp(0.0, 1.0);
          final nb = (f * (b - 0.5) + 0.5).clamp(0.0, 1.0);
          r = r + (nr - r) * weight;
          g = g + (ng - g) * weight;
          b = b + (nb - b) * weight;
        }
        // Saturation
        if (pt.saturation != 0) {
          final s = 1.0 + pt.saturation / 100.0;
          final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
          final nr = (lum + (r - lum) * s).clamp(0.0, 1.0);
          final ng = (lum + (g - lum) * s).clamp(0.0, 1.0);
          final nb = (lum + (b - lum) * s).clamp(0.0, 1.0);
          r = r + (nr - r) * weight;
          g = g + (ng - g) * weight;
          b = b + (nb - b) * weight;
        }
      }

      result.setPixelRgb(
          x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────
//  Dodge & Burn 마스크 관리
// ─────────────────────────────────────────────────────────

class DodgeBurnStroke {
  final double x; // 0.0~1.0
  final double y; // 0.0~1.0
  final double radius; // 0.0~1.0
  final double strength; // 0.0~1.0
  final bool isDodge; // true=밝게(dodge), false=어둡게(burn)

  const DodgeBurnStroke({
    required this.x,
    required this.y,
    required this.radius,
    required this.strength,
    required this.isDodge,
  });
}

/// Dodge & Burn 브러시 적용
img.Image applyDodgeBurn(img.Image image, List<DodgeBurnStroke> strokes) {
  final effectiveStrokes = strokes
      .where((stroke) => stroke.radius > 0 && stroke.strength > 0)
      .toList(growable: false);
  if (effectiveStrokes.isEmpty) return image;

  final result = img.Image(width: image.width, height: image.height);
  final W = image.width.toDouble();
  final H = image.height.toDouble();

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      var r = px.rNormalized.toDouble();
      var g = px.gNormalized.toDouble();
      var b = px.bNormalized.toDouble();

      for (final stroke in effectiveStrokes) {
        final dx = x / W - stroke.x;
        final dy = y / H - stroke.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        final sigma = stroke.radius * 0.4;
        final weight =
            math.exp(-0.5 * dist * dist / (sigma * sigma)) * stroke.strength;

        if (weight < 0.001) continue;

        if (stroke.isDodge) {
          // Dodge: 밝게 (L += strength * (1-L))
          r = (r + weight * (1 - r)).clamp(0.0, 1.0);
          g = (g + weight * (1 - g)).clamp(0.0, 1.0);
          b = (b + weight * (1 - b)).clamp(0.0, 1.0);
        } else {
          // Burn: 어둡게 (L -= strength * L)
          r = (r - weight * r).clamp(0.0, 1.0);
          g = (g - weight * g).clamp(0.0, 1.0);
          b = (b - weight * b).clamp(0.0, 1.0);
        }
      }

      result.setPixelRgb(
          x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}
