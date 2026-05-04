import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'color_utils.dart';

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
  String get label {
    switch (this) {
      case ArtisticEffect.none:        return '없음';
      case ArtisticEffect.grain:       return 'Grain';
      case ArtisticEffect.grainyFilm:  return 'Grainy Film';
      case ArtisticEffect.vintage:     return 'Vintage';
      case ArtisticEffect.retrolux:    return 'Retrolux';
      case ArtisticEffect.drama1:      return 'Drama 1';
      case ArtisticEffect.drama2:      return 'Drama 2';
      case ArtisticEffect.dramaBright1:return 'Bright 1';
      case ArtisticEffect.dramaBright2:return 'Bright 2';
      case ArtisticEffect.dramaDark1:  return 'Dark 1';
      case ArtisticEffect.dramaDark2:  return 'Dark 2';
      case ArtisticEffect.hdrFine:     return 'HDR Fine';
      case ArtisticEffect.hdrNature:   return 'HDR Nature';
      case ArtisticEffect.hdrPeople:   return 'HDR People';
      case ArtisticEffect.hdrStrong:   return 'HDR Strong';
      case ArtisticEffect.glamourGlow: return 'Glamour Glow';
      case ArtisticEffect.grunge:      return 'Grunge';
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
  int grainVariant = 3,     // grain_nils{n} 1~9
  int grungeVariant = 1,    // grunge variant 1~4
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
      return _applyDrama(image, strength, contrast: 60, clarity: 40, saturation: -10);
    case ArtisticEffect.drama2:
      return _applyDrama(image, strength, contrast: 80, clarity: 60, saturation: -25);
    case ArtisticEffect.dramaBright1:
      return _applyDrama(image, strength, contrast: 40, exposure: 0.3, clarity: 30);
    case ArtisticEffect.dramaBright2:
      return _applyDrama(image, strength, contrast: 50, exposure: 0.5, clarity: 50);
    case ArtisticEffect.dramaDark1:
      return _applyDrama(image, strength, contrast: 50, exposure: -0.3, shadows: -30);
    case ArtisticEffect.dramaDark2:
      return _applyDrama(image, strength, contrast: 70, exposure: -0.5, shadows: -50, vignette: 0.4);
    case ArtisticEffect.hdrFine:
      return _applyHdr(image, strength, compression: 0.7, detailBoost: 1.2);
    case ArtisticEffect.hdrNature:
      return _applyHdr(image, strength, compression: 0.8, detailBoost: 1.5, satBoost: 15);
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
  return src < 0.5
      ? 2 * src * dst
      : 1 - 2 * (1 - src) * (1 - dst);
}

img.Image _blendOverlay(img.Image base, img.Image texture, double strength) {
  final result = img.Image(width: base.width, height: base.height);
  final tw = texture.width;
  final th = texture.height;

  for (int y = 0; y < base.height; y++) {
    for (int x = 0; x < base.width; x++) {
      final bp  = base.getPixel(x, y);
      final tp  = texture.getPixel(x % tw, y % th);
      final tg  = (tp.rNormalized * 0.299 + tp.gNormalized * 0.587 + tp.bNormalized * 0.114).toDouble();
      final or_ = _overlay(bp.rNormalized.toDouble(), tg);
      final og  = _overlay(bp.gNormalized.toDouble(), tg);
      final ob  = _overlay(bp.bNormalized.toDouble(), tg);
      final r   = bp.rNormalized + (or_ - bp.rNormalized) * strength;
      final g   = bp.gNormalized + (og - bp.gNormalized) * strength;
      final b   = bp.bNormalized + (ob - bp.bNormalized) * strength;
      result.setPixelRgb(x, y, (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── 에셋 로드 헬퍼 ────────────────────────────────────────
Future<img.Image?> _loadAsset(String path) async {
  try {
    final data  = await rootBundle.load(path);
    final bytes = data.buffer.asUint8List();
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

// ── Grain ────────────────────────────────────────────────
// Available: grain_nils1-7, grain_nils9 (8 is missing — map 8→9)
const _grainVariants = [1, 2, 3, 4, 5, 6, 7, 9];

Future<img.Image> _applyGrain(img.Image image, double strength, int variant) async {
  final idx = (variant - 1).clamp(0, _grainVariants.length - 1);
  final v = _grainVariants[idx];
  final texture = await _loadAsset('assets/overlays/grain/grain_nils$v.png');
  if (texture == null) return image;
  return _blendOverlay(image, texture, strength * 0.6);
}

// ── Grainy Film: Grain + 필름 커브 ───────────────────────
Future<img.Image> _applyGrainyFilm(img.Image image, double strength, int variant) async {
  var result = await _applyGrain(image, strength, variant);
  // film_curves_def.png 적용 (1D LUT로 사용)
  final curveImg = await _loadAsset('assets/overlays/curves/film_curves_def.png');
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
    final px  = curveImg.getPixel(i, 0);
    rLut[i]   = px.rNormalized.toDouble();
    gLut[i]   = px.gNormalized.toDouble();
    bLut[i]   = px.bNormalized.toDouble();
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
      final px  = image.getPixel(x, y);
      final ri  = (px.rNormalized * 255).round().clamp(0, 255);
      final gi  = (px.gNormalized * 255).round().clamp(0, 255);
      final bi  = (px.bNormalized * 255).round().clamp(0, 255);
      final nr  = px.rNormalized + (rLut[ri] - px.rNormalized) * strength;
      final ng  = px.gNormalized + (gLut[gi] - px.gNormalized) * strength;
      final nb  = px.bNormalized + (bLut[bi] - px.bNormalized) * strength;
      result.setPixelRgb(x, y, (nr.clamp(0.0, 1.0) * 255).round(),
          (ng.clamp(0.0, 1.0) * 255).round(), (nb.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── Vintage ───────────────────────────────────────────────
Future<img.Image> _applyVintage(img.Image image, double strength) async {
  var result = image;

  // 1. 필름 커브
  final filmCurve = await _loadAsset('assets/overlays/curves/film_curves_def.png');
  if (filmCurve != null) result = _applyPngCurve(result, filmCurve, strength * 0.6);

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
  double contrast  = 0,
  double clarity   = 0,
  double saturation = 0,
  double exposure  = 0,
  double shadows   = 0,
  double vignette  = 0,
}) {
  var result = image;
  final s = strength;

  if (contrast != 0) result = _applyContrast(result, contrast * s);
  if (exposure != 0) result = _applyExposure(result, exposure * s);
  if (clarity  != 0) result = _applyClarityEffect(result, clarity * s);
  if (saturation != 0) result = _adjustSaturation(result, saturation * s);
  if (shadows  != 0) result = _adjustShadows(result, shadows * s);
  if (vignette != 0) result = _applyVignetteEffect(result, vignette * s);

  return result;
}

// ── HDR Scape: Local Tone Mapping ────────────────────────
img.Image _applyHdr(
  img.Image image,
  double strength, {
  double compression = 0.7,
  double detailBoost = 1.2,
  double satBoost    = 0,
}) {
  final blurred = img.gaussianBlur(image, radius: 8);
  final result  = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final lo = blurred.getPixel(x, y);

      final lab    = rgbToLab(RgbColor(
        o.rNormalized.toDouble(), o.gNormalized.toDouble(), o.bNormalized.toDouble()));
      final labLow = rgbToLab(RgbColor(
        lo.rNormalized.toDouble(), lo.gNormalized.toDouble(), lo.bNormalized.toDouble()));

      final detail  = lab.l - labLow.l;
      final lNew    = _sigmoid(labLow.l * compression / 100.0) * 100.0 + detail * detailBoost;
      var   aNew    = lab.a;
      var   bNew    = lab.b;

      if (satBoost != 0) {
        final factor = 1.0 + satBoost / 100.0 * strength;
        aNew = lab.a * factor;
        bNew = lab.b * factor;
      }

      final outRgb = labToRgb(LabColor(lNew.clamp(0, 100), aNew, bNew));
      final nr = outRgb.r + (outRgb.r - o.rNormalized) * (strength - 1);
      final ng = outRgb.g + (outRgb.g - o.gNormalized) * (strength - 1);
      final nb = outRgb.b + (outRgb.b - o.bNormalized) * (strength - 1);
      final blendR = o.rNormalized + (nr - o.rNormalized) * strength;
      final blendG = o.gNormalized + (ng - o.gNormalized) * strength;
      final blendB = o.bNormalized + (nb - o.bNormalized) * strength;

      result.setPixelRgb(x, y,
        (blendR.clamp(0.0, 1.0) * 255).round(),
        (blendG.clamp(0.0, 1.0) * 255).round(),
        (blendB.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x * 6.0 + 3.0));

// ── Glamour Glow: Gaussian + Screen ──────────────────────
img.Image _applyGlamourGlow(img.Image image, double strength) {
  final blurred = img.gaussianBlur(image, radius: 10);
  final result  = img.Image(width: image.width, height: image.height);
  final glowStr = strength * 0.5;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final src = image.getPixel(x, y);
      final glo = blurred.getPixel(x, y);
      // Screen blend: out = 1 - (1-src)*(1-glow)
      final sr = 1 - (1 - src.rNormalized) * (1 - glo.rNormalized * glowStr);
      final sg = 1 - (1 - src.gNormalized) * (1 - glo.gNormalized * glowStr);
      final sb = 1 - (1 - src.bNormalized) * (1 - glo.bNormalized * glowStr);
      final r  = src.rNormalized + (sr - src.rNormalized) * strength;
      final g  = src.gNormalized + (sg - src.gNormalized) * strength;
      final b  = src.bNormalized + (sb - src.bNormalized) * strength;
      result.setPixelRgb(x, y, (r.clamp(0.0, 1.0) * 255).round(),
          (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round());
    }
  }
  return result;
}

// ── Grunge ────────────────────────────────────────────────
Future<img.Image> _applyGrunge(img.Image image, double strength, int variant) async {
  var result = image;
  final v = ((variant - 1) % 4) + 1;

  // grunge texture multiply (actual asset filenames)
  final textures = ['grunge_2.jpg', 'grunge_5.jpg',
                    'grunge_6.jpg', 'grunge_7.jpg'];
  final txIdx   = (v - 1).clamp(0, textures.length - 1);

  // grunge 에셋 로드
  final grungeImg = await _loadAsset('assets/overlays/grunge/${textures[txIdx]}');

  if (grungeImg != null) {
    result = _blendMultiply(result, grungeImg, strength * 0.6);
  }

  // 커브 적용
  final grungeCurve = await _loadAsset('assets/overlays/curves/curves_for_grunge_march_17th.png');
  if (grungeCurve != null) result = _applyPngCurve(result, grungeCurve, strength * 0.5);

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
      final r  = bp.rNormalized + (mr - bp.rNormalized) * strength;
      final g  = bp.gNormalized + (mg - bp.gNormalized) * strength;
      final b  = bp.bNormalized + (mb - bp.bNormalized) * strength;
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
      final r  = (px.rNormalized + shift).clamp(0.0, 1.0);
      final b  = (px.bNormalized - shift).clamp(0.0, 1.0);
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
      final px  = image.getPixel(x, y);
      final lum = px.rNormalized * 0.2126 + px.gNormalized * 0.7152 + px.bNormalized * 0.0722;
      final r   = (lum + (px.rNormalized - lum) * s).clamp(0.0, 1.0);
      final g   = (lum + (px.gNormalized - lum) * s).clamp(0.0, 1.0);
      final b   = (lum + (px.bNormalized - lum) * s).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _applyContrast(img.Image image, double contrast) {
  final factor = (259.0 * (contrast + 255)) / (255.0 * (259 - contrast));
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final r  = (factor * (px.rNormalized - 0.5) + 0.5).clamp(0.0, 1.0);
      final g  = (factor * (px.gNormalized - 0.5) + 0.5).clamp(0.0, 1.0);
      final b  = (factor * (px.bNormalized - 0.5) + 0.5).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _applyExposure(img.Image image, double ev) {
  final factor = math.pow(2.0, ev).toDouble();
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final r  = (px.rNormalized * factor).clamp(0.0, 1.0);
      final g  = (px.gNormalized * factor).clamp(0.0, 1.0);
      final b  = (px.bNormalized * factor).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
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
      final r  = (px.rNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      final g  = (px.gNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      final b  = (px.bNormalized * (1 - lift) + lift).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _applyClarityEffect(img.Image image, double clarityValue) {
  final strength = clarityValue / 100.0 * 0.7;
  final blurred  = img.gaussianBlur(image, radius: 7);
  final result   = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o   = image.getPixel(x, y);
      final low = blurred.getPixel(x, y);
      final lum = 0.2126 * o.rNormalized + 0.7152 * o.gNormalized + 0.0722 * o.bNormalized;
      final mid = (1.0 - (lum - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      final r   = (o.rNormalized + strength * mid * (o.rNormalized - low.rNormalized)).clamp(0.0, 1.0);
      final g   = (o.gNormalized + strength * mid * (o.gNormalized - low.gNormalized)).clamp(0.0, 1.0);
      final b   = (o.bNormalized + strength * mid * (o.bNormalized - low.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

img.Image _adjustShadows(img.Image image, double shadowValue) {
  final adj = shadowValue / 100.0 * 0.5;
  final result = img.Image(width: image.width, height: image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px   = image.getPixel(x, y);
      final lum  = 0.2126 * px.rNormalized + 0.7152 * px.gNormalized + 0.0722 * px.bNormalized;
      final mask = (0.5 - lum).clamp(0.0, 0.5) * 2.0;
      final r    = (px.rNormalized + adj * mask).clamp(0.0, 1.0);
      final g    = (px.gNormalized + adj * mask).clamp(0.0, 1.0);
      final b    = (px.bNormalized + adj * mask).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
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
      final px   = image.getPixel(x, y);
      final dx   = x / W - 0.5;
      final dy   = y / H - 0.5;
      final dist = math.sqrt(dx * dx + dy * dy) / 0.707;
      final mask = (1.0 - dist * dist * strength * 0.8).clamp(0.0, 1.0);
      result.setPixelRgb(x, y,
        (px.rNormalized * mask * 255).round(),
        (px.gNormalized * mask * 255).round(),
        (px.bNormalized * mask * 255).round(),
      );
    }
  }
  return result;
}
