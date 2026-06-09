import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  6개 블렌드 모드 (Double Exposure용)
// ─────────────────────────────────────────────────────────

enum BlendMode {
  normal,
  add,
  lighten,
  darken,
  overlay,
  subtract,
}

extension BlendModeX on BlendMode {
  String get label {
    switch (this) {
      case BlendMode.normal:   return 'Normal';
      case BlendMode.add:      return 'Add';
      case BlendMode.lighten:  return 'Lighten';
      case BlendMode.darken:   return 'Darken';
      case BlendMode.overlay:  return 'Overlay';
      case BlendMode.subtract: return 'Subtract';
    }
  }

  double blend(double src, double dst) {
    switch (this) {
      case BlendMode.normal:
        return src; // opacity로 lerp
      case BlendMode.add:
        return (src + dst).clamp(0.0, 1.0);
      case BlendMode.lighten:
        return src > dst ? src : dst;
      case BlendMode.darken:
        return src < dst ? src : dst;
      case BlendMode.overlay:
        return dst < 0.5
            ? 2 * src * dst
            : 1 - 2 * (1 - src) * (1 - dst);
      case BlendMode.subtract:
        return (src - dst).clamp(0.0, 1.0);
    }
  }
}

/// 두 이미지를 블렌드 모드로 합성
/// [src] 위 레이어, [dst] 아래 레이어
/// [opacity] src 불투명도 0.0~1.0
img.Image blendImages({
  required img.Image dst,
  required img.Image src,
  required BlendMode mode,
  required double opacity,
}) {
  // src를 dst 크기로 맞추기
  final srcResized = src.width != dst.width || src.height != dst.height
      ? img.copyResize(src, width: dst.width, height: dst.height)
      : src;

  final result = img.Image(width: dst.width, height: dst.height);

  for (int y = 0; y < dst.height; y++) {
    for (int x = 0; x < dst.width; x++) {
      final dstPx = dst.getPixel(x, y);
      final srcPx = srcResized.getPixel(x, y);

      double blend(double s, double d) {
        final blended = mode.blend(s, d);
        return d + (blended - d) * opacity;
      }

      result.setPixelRgb(x, y,
        (blend(srcPx.rNormalized.toDouble(), dstPx.rNormalized.toDouble()).clamp(0.0, 1.0) * 255).round(),
        (blend(srcPx.gNormalized.toDouble(), dstPx.gNormalized.toDouble()).clamp(0.0, 1.0) * 255).round(),
        (blend(srcPx.bNormalized.toDouble(), dstPx.bNormalized.toDouble()).clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────
//  Stacks Brush: 마스크 기반 선택적 필터 적용
// ─────────────────────────────────────────────────────────

/// [original] 원본, [filtered] 필터 적용된 이미지, [mask] 0~1 (1=filtered)
img.Image applyStacksMask({
  required img.Image original,
  required img.Image filtered,
  required Float32List mask,
}) {
  assert(mask.length == original.width * original.height);
  final result = img.Image(width: original.width, height: original.height);

  for (int y = 0; y < original.height; y++) {
    for (int x = 0; x < original.width; x++) {
      final idx = y * original.width + x;
      final t   = mask[idx].clamp(0.0, 1.0);
      final o   = original.getPixel(x, y);
      final f   = filtered.getPixel(x, y);
      final r   = o.rNormalized + (f.rNormalized - o.rNormalized) * t;
      final g   = o.gNormalized + (f.gNormalized - o.gNormalized) * t;
      final b   = o.bNormalized + (f.bNormalized - o.bNormalized) * t;
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}
