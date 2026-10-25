import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'fast_blur.dart';

// ─────────────────────────────────────────────────────────
//  Healing (Inpainting) - v1: Edge-fill + Gaussian blur
//  v2에서 PatchMatch로 업그레이드 예정
// ─────────────────────────────────────────────────────────

/// 마스크(mask[y][x]=true) 영역을 인페인팅으로 채웁니다.
/// [mask] true = 제거할 영역
img.Image applyHealing(img.Image image, List<List<bool>> mask) {
  final W = image.width;
  final H = image.height;
  
  if (mask.length != H || mask.any((row) => row.length != W)) {
    return image;
  }

  final result = img.Image.from(image);

  // v1: 마스크 경계 픽셀들의 평균색으로 채우고 블러
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      if (!mask[y][x]) continue;

      // 주변 비마스크 픽셀 색 평균
      double sumR = 0, sumG = 0, sumB = 0;
      int    count = 0;
      const int searchRadius = 15;

      for (int dy = -searchRadius; dy <= searchRadius; dy++) {
        for (int dx = -searchRadius; dx <= searchRadius; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
          if (mask[ny][nx]) continue;
          final px = image.getPixel(nx, ny);
          sumR += px.rNormalized;
          sumG += px.gNormalized;
          sumB += px.bNormalized;
          count++;
        }
      }

      if (count > 0) {
        result.setPixelRgb(x, y,
          (sumR / count * 255).round(),
          (sumG / count * 255).round(),
          (sumB / count * 255).round(),
        );
      }
    }
  }

  // 마스크 영역 부드럽게 블렌딩 (인스턴스 복사본을 블러 처리하여 원본 비마스크 픽셀 보존)
  final blurred = fastGaussianBlur(img.Image.from(result), radius: 3);
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      if (!mask[y][x]) continue;
      final bl = blurred.getPixel(x, y);
      result.setPixelRgb(x, y,
        (bl.rNormalized * 255).round(),
        (bl.gNormalized * 255).round(),
        (bl.bNormalized * 255).round(),
      );
    }
  }

  return result;
}

/// 원형 브러시 마스크 생성 헬퍼
List<List<bool>> createBrushMask({
  required int width,
  required int height,
  required List<({double x, double y, double radius})> strokes,
}) {
  final mask = List.generate(height, (_) => List.filled(width, false));

  for (final stroke in strokes) {
    final cx = (stroke.x * width).clamp(0.0, width.toDouble());
    final cy = (stroke.y * height).clamp(0.0, height.toDouble());
    final r  = stroke.radius * math.min(width, height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        if (dist <= r) mask[y][x] = true;
      }
    }
  }

  return mask;
}

// ─────────────────────────────────────────────────────────
//  Heal brush: 주변에서 가장 잘 이어지는 조각을 골라 덮고,
//  경계 색을 맞춰 부드럽게 섞는다. 점·잡티·작은 물체 제거용이다.
// ─────────────────────────────────────────────────────────

/// 지우개 획. 좌표는 0..1(사진 기준), [radius]는 사진 짧은 변에 대한 비율.
class HealSpot {
  final double x;
  final double y;
  final double radius;

  const HealSpot({required this.x, required this.y, required this.radius});
}

/// [strokes]를 순서대로 적용한 새 이미지를 돌려준다. 원본은 바꾸지 않는다.
/// 작업 범위는 각 획 주변으로 한정되어 사진 크기와 거의 무관하게 빠르다.
img.Image applyHealSpots(img.Image image, List<HealSpot> strokes) {
  if (strokes.isEmpty) return image;
  final result = img.Image.from(image);
  final shortSide = math.min(image.width, image.height);
  for (final stroke in strokes) {
    final r = stroke.radius * shortSide;
    if (r < 1) continue;
    _healOne(
      result,
      stroke.x.clamp(0.0, 1.0) * (image.width - 1),
      stroke.y.clamp(0.0, 1.0) * (image.height - 1),
      r,
    );
  }
  return result;
}

const int _kRingAngles = 32;
const int _kCandidateAngles = 16;

void _healOne(img.Image image, double cx, double cy, double r) {
  final w = image.width;
  final h = image.height;
  final feather = r * 1.25;
  final ringRadii = [r * 1.15, r * 1.4];

  // 후보 조각의 중심 목록. 조각(반경 feather)이 사진 안에 완전히 들어와야 한다.
  final candidates = <(double, double)>[];
  for (final distance in [r * 2.7, r * 3.8]) {
    for (var i = 0; i < _kCandidateAngles; i++) {
      final angle = 2 * math.pi * i / _kCandidateAngles;
      final sx = cx + math.cos(angle) * distance;
      final sy = cy + math.sin(angle) * distance;
      if (sx - feather < 0 ||
          sy - feather < 0 ||
          sx + feather > w - 1 ||
          sy + feather > h - 1) {
        continue;
      }
      candidates.add((sx, sy));
    }
  }
  if (candidates.isEmpty) return;

  // 링(경계) 샘플 위치. 대상 쪽이 사진 밖으로 나가면 그 샘플은 버린다.
  final ring = <(int, int)>[];
  for (final radius in ringRadii) {
    for (var i = 0; i < _kRingAngles; i++) {
      final angle = 2 * math.pi * i / _kRingAngles;
      final x = (cx + math.cos(angle) * radius).round();
      final y = (cy + math.sin(angle) * radius).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      ring.add((x, y));
    }
  }
  if (ring.isEmpty) return;

  final target = <double>[];
  for (final (x, y) in ring) {
    final p = image.getPixel(x, y);
    target.addAll([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
  }

  var bestScore = double.infinity;
  (double, double)? best;
  var bestShift = const [0.0, 0.0, 0.0];
  for (final candidate in candidates) {
    final dx = candidate.$1 - cx;
    final dy = candidate.$2 - cy;
    final meanDiff = [0.0, 0.0, 0.0];
    final samples = <double>[];
    for (final (x, y) in ring) {
      final sx = (x + dx).round().clamp(0, w - 1);
      final sy = (y + dy).round().clamp(0, h - 1);
      final p = image.getPixel(sx, sy);
      samples.addAll([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
    }
    for (var i = 0; i < ring.length; i++) {
      for (var c = 0; c < 3; c++) {
        meanDiff[c] += (target[i * 3 + c] - samples[i * 3 + c]) / ring.length;
      }
    }
    // 밝기 차이는 색 보정으로 맞추고, 남는 무늬 차이만 점수로 본다.
    var score = 0.0;
    for (var i = 0; i < ring.length; i++) {
      for (var c = 0; c < 3; c++) {
        final d = target[i * 3 + c] - samples[i * 3 + c] - meanDiff[c];
        score += d * d;
      }
    }
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
      bestShift = meanDiff;
    }
  }
  if (best == null) return;

  final dx = best.$1 - cx;
  final dy = best.$2 - cy;
  final x0 = math.max(0, (cx - feather).floor());
  final x1 = math.min(w - 1, (cx + feather).ceil());
  final y0 = math.max(0, (cy - feather).floor());
  final y1 = math.min(h - 1, (cy + feather).ceil());

  // 조각을 먼저 읽어 두고 쓴다(대상과 원천은 겹치지 않지만 안전하게).
  final patch = <int, List<int>>{};
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (dist > feather) continue;
      final sx = (x + dx).round().clamp(0, w - 1);
      final sy = (y + dy).round().clamp(0, h - 1);
      final p = image.getPixel(sx, sy);
      patch[y * w + x] = [
        (p.r + bestShift[0]).round().clamp(0, 255),
        (p.g + bestShift[1]).round().clamp(0, 255),
        (p.b + bestShift[2]).round().clamp(0, 255),
      ];
    }
  }
  patch.forEach((index, rgb) {
    final x = index % w;
    final y = index ~/ w;
    final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
    // r 안쪽은 100%, feather까지 부드럽게 줄어든다.
    final t = dist <= r ? 1.0 : 1 - ((dist - r) / (feather - r)).clamp(0.0, 1.0);
    final weight = t * t * (3 - 2 * t);
    final base = image.getPixel(x, y);
    image.setPixelRgb(
      x,
      y,
      (base.r + (rgb[0] - base.r) * weight).round(),
      (base.g + (rgb[1] - base.g) * weight).round(),
      (base.b + (rgb[2] - base.b) * weight).round(),
    );
  });
}
