import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  아티스틱 이펙트 정의
// ─────────────────────────────────────────────────────────

enum ArtisticEffect {
  none,
  grain,
  grainyFilm,
  vintage,
  retrolux,
  dramaDark1,
  dramaDark2,
  dramaBright1,
  dramaBright2,
  drama1,
  drama2,
  hdrFine,
  hdrNature,
  hdrPeople,
  hdrStrong,
  glamourGlow,
  grunge,
}

extension ArtisticEffectX on ArtisticEffect {
  String get l10nKey {
    switch (this) {
      case ArtisticEffect.none:
        return 'effect.none';
      case ArtisticEffect.grain:
        return 'effect.grain';
      case ArtisticEffect.grainyFilm:
        return 'effect.grainy_film';
      case ArtisticEffect.vintage:
        return 'effect.vintage';
      case ArtisticEffect.retrolux:
        return 'effect.retrolux';
      case ArtisticEffect.drama1:
        return 'effect.drama_1';
      case ArtisticEffect.drama2:
        return 'effect.drama_2';
      case ArtisticEffect.dramaBright1:
        return 'effect.drama_bright_1';
      case ArtisticEffect.dramaBright2:
        return 'effect.drama_bright_2';
      case ArtisticEffect.dramaDark1:
        return 'effect.drama_dark_1';
      case ArtisticEffect.dramaDark2:
        return 'effect.drama_dark_2';
      case ArtisticEffect.hdrFine:
        return 'effect.hdr_fine';
      case ArtisticEffect.hdrNature:
        return 'effect.hdr_nature';
      case ArtisticEffect.hdrPeople:
        return 'effect.hdr_people';
      case ArtisticEffect.hdrStrong:
        return 'effect.hdr_strong';
      case ArtisticEffect.glamourGlow:
        return 'effect.glamour_glow';
      case ArtisticEffect.grunge:
        return 'effect.grunge';
    }
  }
}

// ─────────────────────────────────────────────────────────
//  메인 적용 함수
// ─────────────────────────────────────────────────────────

/// 아티스틱 이펙트를 이미지에 적용합니다. [strength] 0.0~1.0
Future<img.Image> applyArtisticEffect(
  img.Image image,
  ArtisticEffect effect, {
  double strength = 1.0,
  int grainVariant = 3, // grain_nils{n} 1~9
  int grungeVariant = 1, // grunge variant 1~4
}) async {
  if (effect == ArtisticEffect.none || strength <= 0) return image;

  switch (effect) {
    case ArtisticEffect.grain:
      return _applyGrain(image, strength, grainVariant);
    case ArtisticEffect.grainyFilm:
      return _applyGrainyFilm(image, strength, grainVariant);
    case ArtisticEffect.vintage:
      return _applyVintage(image, strength);
    case ArtisticEffect.retrolux:
      return _applyRetrolux(image, strength);
    case ArtisticEffect.drama1:
      return _applyDrama(image, strength,
          contrast: 60, clarity: 40, saturation: -10);
    case ArtisticEffect.drama2:
      return _applyDrama(image, strength,
          contrast: 80, clarity: 60, saturation: -25);
    case ArtisticEffect.dramaBright1:
      return _applyDrama(image, strength,
          contrast: 25, exposure: 0.3, clarity: 30);
    case ArtisticEffect.dramaBright2:
      return _applyDrama(image, strength,
          contrast: 30, exposure: 0.5, clarity: 50);
    case ArtisticEffect.dramaDark1:
      return _applyDrama(image, strength,
          contrast: 50, exposure: -0.3, shadows: -30);
    case ArtisticEffect.dramaDark2:
      return _applyDrama(image, strength,
          contrast: 70, exposure: -0.5, shadows: -50, vignette: 0.4);
    case ArtisticEffect.hdrFine:
      return _applyHdr(image, strength, compression: 0.7, detailBoost: 1.2);
    case ArtisticEffect.hdrNature:
      return _applyHdr(image, strength,
          compression: 0.8, detailBoost: 1.5, satBoost: 15);
    case ArtisticEffect.hdrPeople:
      return _applyHdr(image, strength, compression: 0.75, detailBoost: 1.0);
    case ArtisticEffect.hdrStrong:
      return _applyHdr(image, strength, compression: 0.5, detailBoost: 2.0);
    case ArtisticEffect.glamourGlow:
      return _applyGlamourGlow(image, strength);
    case ArtisticEffect.grunge:
      return _applyGrunge(image, strength, grungeVariant);
    default:
      return image;
  }
}

// ─────────────────────────────────────────────────────────
//  개별 이펙트 구현
// ─────────────────────────────────────────────────────────

// ── Overlay 블렌드 헬퍼 ───────────────────────────────────
double _overlay(double src, double dst) {
  return src < 0.5 ? 2 * src * dst : 1 - 2 * (1 - src) * (1 - dst);
}

img.Image _blendOverlay(img.Image base, img.Image texture, double strength) {
  final result = img.Image(width: base.width, height: base.height);
  final tw = texture.width;
  final th = texture.height;

  for (int y = 0; y < base.height; y++) {
    for (int x = 0; x < base.width; x++) {
      final bp = base.getPixel(x, y);
      final tp = texture.getPixel(x % tw, y % th);
      final tg = (tp.rNormalized * 0.299 +
              tp.gNormalized * 0.587 +
              tp.bNormalized * 0.114)
          .toDouble();
      final or_ = _overlay(bp.rNormalized.toDouble(), tg);
      final og = _overlay(bp.gNormalized.toDouble(), tg);
      final ob = _overlay(bp.bNormalized.toDouble(), tg);
      final r = bp.rNormalized + (or_ - bp.rNormalized) * strength;
      final g = bp.gNormalized + (og - bp.gNormalized) * strength;
      final b = bp.bNormalized + (ob - bp.bNormalized) * strength;
      result.setPixelRgb(x, y, (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── 에셋 로드 헬퍼 ────────────────────────────────────────
Future<img.Image?> _loadAsset(String path) async {
  try {
    final data = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    return img.decodeImage(bytes);
  } on Object {
    // Optional texture assets degrade to the untextured effect.
    return null;
  }
}

// ── Grain ────────────────────────────────────────────────
// Available: grain_nils1-7, grain_nils9 (8 is missing — map 8→9)
const _grainVariants = [1, 2, 3, 4, 5, 6, 7, 9];

Future<img.Image> _applyGrain(
    img.Image image, double strength, int variant) async {
  final idx = (variant - 1).clamp(0, _grainVariants.length - 1);
  final v = _grainVariants[idx];
  final texture = await _loadAsset('assets/overlays/grain/grain_nils$v.png');
  if (texture == null) return image;
  return _blendOverlay(image, texture, strength * 0.6);
}

// ── Grainy Film: Grain + 필름 커브 ───────────────────────
Future<img.Image> _applyGrainyFilm(
    img.Image image, double strength, int variant) async {
  var result = await _applyGrain(image, strength, variant);
  // film_curves_def.png 적용 (1D LUT로 사용)
  final curveImg =
      await _loadAsset('assets/overlays/curves/film_curves_def.png');
  if (curveImg != null) {
    result = _applyPngCurve(result, curveImg, strength * 0.7);
  }
  return result;
}

// ── PNG 커브 적용 (256px 너비 1D LUT) ────────────────────
img.Image _applyPngCurve(img.Image image, img.Image curveImg, double strength) {
  // 커브 PNG: 256×N, 각 열의 첫 번째 픽셀이 LUT 값
  final List<double> rLut = List.filled(256, 0);
  final List<double> gLut = List.filled(256, 0);
  final List<double> bLut = List.filled(256, 0);

  final maxX = math.min(curveImg.width - 1, 255);
  for (int i = 0; i <= maxX; i++) {
    final px = curveImg.getPixel(i, 0);
    rLut[i] = px.rNormalized.toDouble();
    gLut[i] = px.gNormalized.toDouble();
    bLut[i] = px.bNormalized.toDouble();
  }
  // 남은 인덱스는 선형 보간으로 채움
  for (int i = maxX + 1; i < 256; i++) {
    rLut[i] = i / 255.0;
    gLut[i] = i / 255.0;
    bLut[i] = i / 255.0;
  }

  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final ri = (px.rNormalized * 255).round().clamp(0, 255);
      final gi = (px.gNormalized * 255).round().clamp(0, 255);
      final bi = (px.bNormalized * 255).round().clamp(0, 255);
      final nr = px.rNormalized + (rLut[ri] - px.rNormalized) * strength;
      final ng = px.gNormalized + (gLut[gi] - px.gNormalized) * strength;
      final nb = px.bNormalized + (bLut[bi] - px.bNormalized) * strength;
      result.setPixelRgb(
          x,
          y,
          (nr.clamp(0.0, 1.0) * 255).round(),
          (ng.clamp(0.0, 1.0) * 255).round(),
          (nb.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── Vintage ───────────────────────────────────────────────
Future<img.Image> _applyVintage(img.Image image, double strength) async {
  var result = image;

  // 1. 필름 커브
  final filmCurve =
      await _loadAsset('assets/overlays/curves/film_curves_def.png');
  if (filmCurve != null) {
    result = _applyPngCurve(result, filmCurve, strength * 0.6);
  }

  // 2. Grain 오버레이
  final grain = await _loadAsset('assets/overlays/grain/grain_nils3.png');
  if (grain != null) result = _blendOverlay(result, grain, strength * 0.3);

  // 3. 색온도 warm shift
  result = _shiftTemperature(result, strength * 20);

  // 4. 비네팅
  result = _applyVignetteEffect(result, strength * 0.4);

  return result;
}

// ── Retrolux ─────────────────────────────────────────────
Future<img.Image> _applyRetrolux(img.Image image, double strength) async {
  var result = image;

  // 1. Faded: 검정점 올리기 (lift shadows)
  result = _liftShadows(result, strength * 30);

  // 2. 색온도 warm + 채도 약간 낮추기
  result = _shiftTemperature(result, strength * 25);
  result = _adjustSaturation(result, -15 * strength);

  // 3. Grain
  final grain = await _loadAsset('assets/overlays/grain/grain_nilsnew_7.png');
  if (grain != null) result = _blendOverlay(result, grain, strength * 0.25);

  // 4. 비네팅
  result = _applyVignetteEffect(result, strength * 0.3);

  return result;
}

// ── Drama ────────────────────────────────────────────────
img.Image _applyDrama(
  img.Image image,
  double strength, {
  double contrast = 0,
  double clarity = 0,
  double saturation = 0,
  double exposure = 0,
  double shadows = 0,
  double vignette = 0,
}) {
  final s = strength.clamp(0.0, 1.0);
  if (s <= 0) return image;
  final blurred = clarity == 0 ? null : _rgbGaussianBlur(image, 7);
  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);
  final contrastAmount = (contrast * s / 100.0).clamp(-0.95, 0.95);
  final exposureEv = exposure * s;
  final exposureFactor = math.pow(2.0, exposureEv).toDouble();
  final highlightLift = exposureEv > 0 ? 1.0 - 1.0 / exposureFactor : 0.0;
  final saturationFactor = 1.0 + saturation * s / 100.0;
  final shadowAdjustment = shadows * s / 100.0 * 0.5;
  final clarityAmount = clarity * s / 100.0 * 0.7;
  final width = image.width.toDouble();
  final height = image.height.toDouble();

  double contrastCurve(double value) =>
      (value + contrastAmount * (value - 0.5) * 4.0 * value * (1.0 - value))
          .clamp(0.0, 1.0);
  double expose(double value) => exposureEv > 0
      ? value + (1.0 - value) * highlightLift
      : (value * exposureFactor).clamp(0.0, 1.0);

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final source = image.getPixel(x, y);
      var r = expose(contrastCurve(source.rNormalized.toDouble()));
      var g = expose(contrastCurve(source.gNormalized.toDouble()));
      var b = expose(contrastCurve(source.bNormalized.toDouble()));

      var luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      r = luminance + (r - luminance) * saturationFactor;
      g = luminance + (g - luminance) * saturationFactor;
      b = luminance + (b - luminance) * saturationFactor;

      if (shadowAdjustment != 0) {
        final shadowMask = (0.5 - luminance).clamp(0.0, 0.5) * 2.0;
        r += shadowAdjustment * shadowMask;
        g += shadowAdjustment * shadowMask;
        b += shadowAdjustment * shadowMask;
      }

      if (blurred != null && clarityAmount != 0) {
        final low = blurred.getPixel(x, y);
        final lowLum = 0.2126 * low.rNormalized +
            0.7152 * low.gNormalized +
            0.0722 * low.bNormalized;
        final sourceLum = 0.2126 * source.rNormalized +
            0.7152 * source.gNormalized +
            0.0722 * source.bNormalized;
        final detail = sourceLum - lowLum;
        final localRange = _localLuminanceRange(image, x, y, 2);
        // Ignore flat sensor noise and hard step edges. Clarity should reveal
        // texture, not create dark/bright outlines around silhouettes.
        final detailGate = _smoothStep(0.008, 0.03, detail.abs()) *
            (1.0 - _smoothStep(0.08, 0.22, detail.abs())) *
            (1.0 - _smoothStep(0.08, 0.18, localRange));
        final clarityDelta = detail * clarityAmount * detailGate;
        r += clarityDelta;
        g += clarityDelta;
        b += clarityDelta;
      }

      if (vignette != 0) {
        final dx = x / width - 0.5;
        final dy = y / height - 0.5;
        final distance = math.sqrt(dx * dx + dy * dy) / 0.707;
        final mask =
            (1.0 - distance * distance * vignette * s * 0.8).clamp(0.0, 1.0);
        r *= mask;
        g *= mask;
        b *= mask;
      }

      result.setPixelRgba(
        x,
        y,
        _quantizeWithoutNewClipping(r, source.r.toInt()),
        _quantizeWithoutNewClipping(g, source.g.toInt()),
        _quantizeWithoutNewClipping(b, source.b.toInt()),
        source.a.toInt(),
      );
    }
  }
  return result;
}

double _localLuminanceRange(
  img.Image image,
  int centerX,
  int centerY,
  int radius,
) {
  var minimum = 1.0;
  var maximum = 0.0;
  final startX = math.max(0, centerX - radius);
  final endX = math.min(image.width - 1, centerX + radius);
  final startY = math.max(0, centerY - radius);
  final endY = math.min(image.height - 1, centerY + radius);
  for (var y = startY; y <= endY; y++) {
    for (var x = startX; x <= endX; x++) {
      final pixel = image.getPixel(x, y);
      final luminance = 0.2126 * pixel.rNormalized +
          0.7152 * pixel.gNormalized +
          0.0722 * pixel.bNormalized;
      minimum = math.min(minimum, luminance);
      maximum = math.max(maximum, luminance);
    }
  }
  return maximum - minimum;
}

int _quantizeWithoutNewClipping(double value, int source) {
  final quantized = (value.clamp(0.0, 1.0) * 255).round();
  if (source < 255 && quantized == 255) return source;
  if (source > 0 && quantized == 0) return source;
  return quantized;
}

// ── HDR Scape: Local Tone Mapping ────────────────────────
img.Image _applyHdr(
  img.Image image,
  double strength, {
  double compression = 0.7,
  double detailBoost = 1.2,
  double satBoost = 0,
}) {
  final blurred = _rgbGaussianBlur(image, 8);
  final result =
      img.Image(width: image.width, height: image.height, numChannels: 4);
  final compressionAmount = (1.0 - compression).clamp(0.0, 1.0);
  // Prevent low-amplitude sensor noise from becoming false local detail.
  final detailAmount = (detailBoost - 1.0).clamp(0.0, 1.2) * 0.65;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o = image.getPixel(x, y);
      final lo = blurred.getPixel(x, y);

      final r = o.rNormalized.toDouble();
      final g = o.gNormalized.toDouble();
      final b = o.bNormalized.toDouble();
      final sourceLum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      final baseLum = 0.2126 * lo.rNormalized +
          0.7152 * lo.gNormalized +
          0.0722 * lo.bNormalized;
      final detail = sourceLum - baseLum;
      final noiseGate = _smoothStep(0.012, 0.075, detail.abs());

      // A bounded S-shaped luminance curve compresses highlights and lifts
      // shadows without the hue shifts and harsh clipping caused by per-RGB
      // local contrast. Local detail is gated in flat/noisy regions.
      final toneBase = baseLum +
          compressionAmount * 1.4 * baseLum * (1.0 - baseLum) * (0.5 - baseLum);
      final targetLum = (toneBase + detail * (1.0 + detailAmount * noiseGate))
          .clamp(0.0, 1.0);
      final lumaScale = sourceLum > 0.0001 ? targetLum / sourceLum : 0.0;
      var nr = (r * lumaScale).clamp(0.0, 1.0);
      var ng = (g * lumaScale).clamp(0.0, 1.0);
      var nb = (b * lumaScale).clamp(0.0, 1.0);

      if (satBoost != 0) {
        final saturation = 1.0 + satBoost / 100.0;
        nr = (targetLum + (nr - targetLum) * saturation).clamp(0.0, 1.0);
        ng = (targetLum + (ng - targetLum) * saturation).clamp(0.0, 1.0);
        nb = (targetLum + (nb - targetLum) * saturation).clamp(0.0, 1.0);
      }

      final blendR = r + (nr - r) * strength;
      final blendG = g + (ng - g) * strength;
      final blendB = b + (nb - b) * strength;
      result.setPixelRgba(
        x,
        y,
        (blendR.clamp(0.0, 1.0) * 255).round(),
        (blendG.clamp(0.0, 1.0) * 255).round(),
        (blendB.clamp(0.0, 1.0) * 255).round(),
        o.a.toInt(),
      );
    }
  }
  return result;
}

double _smoothStep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

img.Image _rgbGaussianBlur(img.Image image, int preferredRadius) {
  // image 4.8's separable Gaussian path assumes RGB storage for some layouts.
  // Use an explicit RGB buffer and keep the radius below the shortest edge.
  final blurInput =
      img.Image(width: image.width, height: image.height, numChannels: 3);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      blurInput.setPixelRgb(
          x, y, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    }
  }
  final radius = math.min(
    preferredRadius,
    math.max(1, math.min(image.width, image.height) ~/ 8),
  );
  return img.gaussianBlur(blurInput, radius: radius);
}

// ── Glamour Glow: Gaussian + Screen ──────────────────────
img.Image _applyGlamourGlow(img.Image image, double strength) {
  final blurred = img.gaussianBlur(image, radius: 10);
  final result = img.Image(width: image.width, height: image.height);
  final glowStr = strength * 0.5;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final src = image.getPixel(x, y);
      final glo = blurred.getPixel(x, y);
      // Screen blend: out = 1 - (1-src)*(1-glow)
      final sr = 1 - (1 - src.rNormalized) * (1 - glo.rNormalized * glowStr);
      final sg = 1 - (1 - src.gNormalized) * (1 - glo.gNormalized * glowStr);
      final sb = 1 - (1 - src.bNormalized) * (1 - glo.bNormalized * glowStr);
      final r = src.rNormalized + (sr - src.rNormalized) * strength;
      final g = src.gNormalized + (sg - src.gNormalized) * strength;
      final b = src.bNormalized + (sb - src.bNormalized) * strength;
      result.setPixelRgb(x, y, (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── Grunge ────────────────────────────────────────────────
Future<img.Image> _applyGrunge(
    img.Image image, double strength, int variant) async {
  var result = image;
  final v = ((variant - 1) % 4) + 1;

  // grunge texture multiply (actual asset filenames)
  final textures = [
    'grunge_2.jpg',
    'grunge_5.jpg',
    'grunge_6.jpg',
    'grunge_7.jpg'
  ];
  final txIdx = (v - 1).clamp(0, textures.length - 1);

  // grunge 에셋 로드
  final grungeImg =
      await _loadAsset('assets/overlays/grunge/${textures[txIdx]}');

  if (grungeImg != null) {
    result = _blendMultiply(result, grungeImg, strength * 0.6);
  }

  // 커브 적용
  final grungeCurve = await _loadAsset(
      'assets/overlays/curves/curves_for_grunge_march_17th.png');
  if (grungeCurve != null) {
    result = _applyPngCurve(result, grungeCurve, strength * 0.5);
  }

  // 채도 낮추기
  result = _adjustSaturation(result, -30 * strength);

  // 그레인
  final grain = await _loadAsset('assets/overlays/grain/grain_nils7.png');
  if (grain != null) result = _blendOverlay(result, grain, strength * 0.3);

  return result;
}

img.Image _blendMultiply(img.Image base, img.Image texture, double strength) {
  final result = img.Image(width: base.width, height: base.height);
  final tw = texture.width;
  final th = texture.height;

  for (int y = 0; y < base.height; y++) {
    for (int x = 0; x < base.width; x++) {
      final bp = base.getPixel(x, y);
      final tp = texture.getPixel(x % tw, y % th);
      final mr = bp.rNormalized * tp.rNormalized;
      final mg = bp.gNormalized * tp.gNormalized;
      final mb = bp.bNormalized * tp.bNormalized;
      final r = bp.rNormalized + (mr - bp.rNormalized) * strength;
      final g = bp.gNormalized + (mg - bp.gNormalized) * strength;
      final b = bp.bNormalized + (mb - bp.bNormalized) * strength;
      result.setPixelRgb(x, y, (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────
//  공통 픽셀 헬퍼
// ─────────────────────────────────────────────────────────

img.Image _shiftTemperature(img.Image image, double amount) {
  final shift = amount / 1000.0;
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final r = (px.rNormalized + shift).clamp(0.0, 1.0);
      final b = (px.bNormalized - shift).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(),
          (px.gNormalized * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _adjustSaturation(img.Image image, double saturation) {
  final s = 1.0 + saturation / 100.0;
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final lum = px.rNormalized * 0.2126 +
          px.gNormalized * 0.7152 +
          px.bNormalized * 0.0722;
      final r = (lum + (px.rNormalized - lum) * s).clamp(0.0, 1.0);
      final g = (lum + (px.gNormalized - lum) * s).clamp(0.0, 1.0);
      final b = (lum + (px.bNormalized - lum) * s).clamp(0.0, 1.0);
      result.setPixelRgb(
          x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _liftShadows(img.Image image, double liftAmount) {
  final lift = liftAmount / 255.0;
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final r = (px.rNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      final g = (px.gNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      final b = (px.bNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      result.setPixelRgb(
          x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _applyVignetteEffect(img.Image image, double strength) {
  final result = img.Image(width: image.width, height: image.height);
  final W = image.width.toDouble();
  final H = image.height.toDouble();
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final dx = x / W - 0.5;
      final dy = y / H - 0.5;
      final dist = math.sqrt(dx * dx + dy * dy) / 0.707;
      final mask = (1.0 - dist * dist * strength * 0.8).clamp(0.0, 1.0);
      result.setPixelRgb(
        x,
        y,
        (px.rNormalized * mask * 255).round(),
        (px.gNormalized * mask * 255).round(),
        (px.bNormalized * mask * 255).round(),
      );
    }
  }
  return result;
}
