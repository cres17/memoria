import 'dart:math' as math;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  Healing (Inpainting) - v1: Edge-fill + Gaussian blur
//  v2에서 PatchMatch로 업그레이드 예정
// ─────────────────────────────────────────────────────────

/// 마스크(mask[y][x]=true) 영역을 인페인팅으로 채웁니다.
/// [mask] true = 제거할 영역
img.Image applyHealing(img.Image image, List<List<bool>> mask) {
  final W = image.width;
  final H = image.height;
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

  // 마스크 영역 부드럽게 블렌딩
  final blurred = img.gaussianBlur(result, radius: 3);
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
    final cx = stroke.x * width;
    final cy = stroke.y * height;
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
