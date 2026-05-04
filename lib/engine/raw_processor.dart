import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  RAW Processor
//  v1: JPEG에 Noise Reduction 적용
//  v2 예정: DNG 파싱 (libtiff/libraw via FFI)
// ─────────────────────────────────────────────────────────

/// Non-Local Means 근사 노이즈 제거 (패치 기반)
/// [noiseReduction] 0~100
img.Image applyNoiseReduction(img.Image image, double noiseReduction) {
  if (noiseReduction <= 0) return image;

  // v1: Bilateral filter 근사 (가우시안 블러 + 엣지 보존)
  final strength = noiseReduction / 100.0;
  final radius   = (strength * 3).round().clamp(1, 6);
  final blurred  = img.gaussianBlur(image, radius: radius);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);

      // 엣지 보존: 고대비 영역은 덜 블러
      final dr    = (o.rNormalized - bl.rNormalized).abs();
      final dg    = (o.gNormalized - bl.gNormalized).abs();
      final db    = (o.bNormalized - bl.bNormalized).abs();
      final edge  = (dr + dg + db) / 3.0;
      final w     = (strength * (1 - edge * 5).clamp(0.0, 1.0));

      final r = o.rNormalized + (bl.rNormalized - o.rNormalized) * w;
      final g = o.gNormalized + (bl.gNormalized - o.gNormalized) * w;
      final b = o.bNormalized + (bl.bNormalized - o.bNormalized) * w;
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}
