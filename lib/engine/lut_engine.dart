import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../ai/ai_manager.dart';
import '../ai/models/lut_predictor.dart';
import '../domain/models/adjust_params.dart';
import 'color_utils.dart';
import 'custom_lut_core.dart';

// ── HSL helpers ───────────────────────────────────────────

/// Returns hue in [0, 360), saturation in [0, 1], lightness in [0, 1].
({double h, double s, double l}) _rgbToHsl(double r, double g, double b) {
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final l = (max + min) * 0.5;
  if (max == min) return (h: 0.0, s: 0.0, l: l);
  final d = max - min;
  final s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
  double h;
  if (max == r) {
    h = (g - b) / d + (g < b ? 6.0 : 0.0);
  } else if (max == g) {
    h = (b - r) / d + 2.0;
  } else {
    h = (r - g) / d + 4.0;
  }
  return (h: h * 60.0, s: s, l: l);
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0.0) t += 1.0;
  if (t > 1.0) t -= 1.0;
  if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
  if (t < 0.5) return q;
  if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
  return p;
}

RgbColor _hslToRgb(double h, double s, double l) {
  final hNorm = h / 360.0;
  if (s == 0.0) return RgbColor(l, l, l);
  final q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
  final p = 2.0 * l - q;
  return RgbColor(
    _hue2rgb(p, q, hNorm + 1.0 / 3.0),
    _hue2rgb(p, q, hNorm),
    _hue2rgb(p, q, hNorm - 1.0 / 3.0),
  );
}

RgbColor _applyHslBands(RgbColor rgb, AdjustParams p) {
  final hsl = _rgbToHsl(rgb.r, rgb.g, rgb.b);
  final h = hsl.h;

  const centers = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 280.0, 320.0];
  const bands = [
    HslBand.red,
    HslBand.orange,
    HslBand.yellow,
    HslBand.green,
    HslBand.cyan,
    HslBand.blue,
    HslBand.purple,
    HslBand.magenta
  ];

  double totalW = 0.0;
  final weights = List<double>.filled(8, 0.0);
  for (int i = 0; i < 8; i++) {
    const double sigma = 35.0;
    double d = (h - centers[i]).abs();
    if (d > 180.0) d = 360.0 - d;
    weights[i] = math.exp(-0.5 * d * d / (sigma * sigma));
    totalW += weights[i];
  }

  if (totalW < 1e-6) return rgb;

  double dh = 0.0;
  double ds = 0.0;
  double dl = 0.0;
  for (int i = 0; i < 8; i++) {
    final bp = p.hsl[bands[i]] ?? HslBandParams.zero;
    dh += weights[i] * bp.hue;
    ds += weights[i] * bp.saturation;
    dl += weights[i] * bp.luminance;
  }
  dh /= totalW;
  ds = (ds / totalW) / 100.0;
  dl = (dl / totalW) / 100.0;

  final newH = (h + dh + 360.0) % 360.0;
  final newS = (hsl.s + ds).clamp(0.0, 1.0);
  final newL = (hsl.l + dl).clamp(0.0, 1.0);

  return _hslToRgb(newH, newS, newL);
}

(double, double, double) _applyHslBandsFlat(double r, double g, double b, AdjustParams p) {
  final hsl = _rgbToHsl(r, g, b);
  final h = hsl.h;

  const centers = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 280.0, 320.0];
  const bands = [
    HslBand.red,
    HslBand.orange,
    HslBand.yellow,
    HslBand.green,
    HslBand.cyan,
    HslBand.blue,
    HslBand.purple,
    HslBand.magenta
  ];

  double totalW = 0.0;
  final weights = List<double>.filled(8, 0.0);
  for (int i = 0; i < 8; i++) {
    const double sigma = 35.0;
    double d = (h - centers[i]).abs();
    if (d > 180.0) d = 360.0 - d;
    weights[i] = math.exp(-0.5 * d * d / (sigma * sigma));
    totalW += weights[i];
  }

  if (totalW < 1e-6) return (r, g, b);

  double dh = 0.0;
  double ds = 0.0;
  double dl = 0.0;
  for (int i = 0; i < 8; i++) {
    final bp = p.hsl[bands[i]] ?? HslBandParams.zero;
    dh += weights[i] * bp.hue;
    ds += weights[i] * bp.saturation;
    dl += weights[i] * bp.luminance;
  }
  dh /= totalW;
  ds = (ds / totalW) / 100.0;
  dl = (dl / totalW) / 100.0;

  final newH = (h + dh + 360.0) % 360.0;
  final newS = (hsl.s + ds).clamp(0.0, 1.0);
  final newL = (hsl.l + dl).clamp(0.0, 1.0);

  final hNorm = newH / 360.0;
  if (newS == 0.0) return (newL, newL, newL);
  final q = newL < 0.5 ? newL * (1.0 + newS) : newL + newS - newL * newS;
  final pVal = 2.0 * newL - q;
  
  final rOut = _hue2rgb(pVal, q, hNorm + 1.0 / 3.0).clamp(0.0, 1.0);
  final gOut = _hue2rgb(pVal, q, hNorm).clamp(0.0, 1.0);
  final bOut = _hue2rgb(pVal, q, hNorm - 1.0 / 3.0).clamp(0.0, 1.0);
  
  return (rOut, gOut, bOut);
}

// ── Split Toning ─────────────────────────────────────────────

RgbColor _applySplitToning(RgbColor rgb, AdjustParams p) {
  final lum = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
  final splitPoint = 0.5 + p.splitBalance / 200.0;

  final double denomShadow = splitPoint > 1e-4 ? splitPoint : 1e-4;
  final shadowW = 1.0 - (lum / denomShadow).clamp(0.0, 1.0);
  
  final double denomHigh = (1.0 - splitPoint) > 1e-4 ? (1.0 - splitPoint) : 1e-4;
  final highW = ((lum - splitPoint) / denomHigh).clamp(0.0, 1.0);

  var r = rgb.r;
  var g = rgb.g;
  var b = rgb.b;

  if (p.splitShadowSat > 0.0 && shadowW > 1e-4) {
    final hRad = p.splitShadowHue * math.pi / 180.0;
    final str = p.splitShadowSat / 100.0 * shadowW;
    r = (r + str * math.cos(hRad) * 0.5).clamp(0.0, 1.0);
    g = (g + str * math.cos(hRad - 2.094) * 0.5).clamp(0.0, 1.0);
    b = (b + str * math.cos(hRad + 2.094) * 0.5).clamp(0.0, 1.0);
  }
  if (p.splitHighSat > 0.0 && highW > 1e-4) {
    final hRad = p.splitHighHue * math.pi / 180.0;
    final str = p.splitHighSat / 100.0 * highW;
    r = (r + str * math.cos(hRad) * 0.5).clamp(0.0, 1.0);
    g = (g + str * math.cos(hRad - 2.094) * 0.5).clamp(0.0, 1.0);
    b = (b + str * math.cos(hRad + 2.094) * 0.5).clamp(0.0, 1.0);
  }
  return RgbColor(r, g, b);
}

(double, double, double) _applySplitToningFlat(double rIn, double gIn, double bIn, AdjustParams p) {
  final lum = 0.2126 * rIn + 0.7152 * gIn + 0.0722 * bIn;
  final splitPoint = 0.5 + p.splitBalance / 200.0;

  final double denomShadow = splitPoint > 1e-4 ? splitPoint : 1e-4;
  final shadowW = 1.0 - (lum / denomShadow).clamp(0.0, 1.0);
  
  final double denomHigh = (1.0 - splitPoint) > 1e-4 ? (1.0 - splitPoint) : 1e-4;
  final highW = ((lum - splitPoint) / denomHigh).clamp(0.0, 1.0);

  var r = rIn;
  var g = gIn;
  var b = bIn;

  if (p.splitShadowSat > 0.0 && shadowW > 1e-4) {
    final hRad = p.splitShadowHue * math.pi / 180.0;
    final str = p.splitShadowSat / 100.0 * shadowW;
    r = (r + str * math.cos(hRad) * 0.5).clamp(0.0, 1.0);
    g = (g + str * math.cos(hRad - 2.094) * 0.5).clamp(0.0, 1.0);
    b = (b + str * math.cos(hRad + 2.094) * 0.5).clamp(0.0, 1.0);
  }
  if (p.splitHighSat > 0.0 && highW > 1e-4) {
    final hRad = p.splitHighHue * math.pi / 180.0;
    final str = p.splitHighSat / 100.0 * highW;
    r = (r + str * math.cos(hRad) * 0.5).clamp(0.0, 1.0);
    g = (g + str * math.cos(hRad - 2.094) * 0.5).clamp(0.0, 1.0);
    b = (b + str * math.cos(hRad + 2.094) * 0.5).clamp(0.0, 1.0);
  }
  return (r, g, b);
}


// ─────────────────────────────────────────────────────────
//  Image-level pipeline (full img.Image in → img.Image out)
// ─────────────────────────────────────────────────────────

/// 전체 이미지 파이프라인:
/// Adjust (per-pixel) → LUT → Intensity → Sharpen → Structure → Clarity → Vignette
img.Image applyImagePipeline({
  required img.Image image,
  required AdjustParams params,
  Uint8List? lutBytes,
  double intensity = 1.0,
  Float32List? decodedLutValues,
  int decodedLutDim = 65,
  BakedCurveLuts? bakedLuts,
}) {
  var output = img.Image(width: image.width, height: image.height);
  final effectiveLut = (decodedLutValues != null && decodedLutValues.isNotEmpty)
      ? DecodedLut(decodedLutValues, decodedLutDim)
      : null;

  final decodedLutToUse = effectiveLut ?? tryDecodeCustomLut(lutBytes);
  final BakedCurveLuts luts = bakedLuts ?? bakeCurveLuts(params);

  final imageIterator = image.iterator;
  for (final frame in output.frames) {
    for (final pixel in frame) {
      if (imageIterator.moveNext()) {
        final inputPixel = imageIterator.current;
        final double origR = inputPixel.rNormalized.toDouble();
        final double origG = inputPixel.gNormalized.toDouble();
        final double origB = inputPixel.bNormalized.toDouble();

        var (r, g, b) = applyAdjustParamsFlat(origR, origG, origB, params, bakedLuts: luts);

        if (decodedLutToUse != null) {
          final lutRes = applyDecodedCustomLutFlat(decodedLutToUse, r, g, b);
          r = lutRes.$1;
          g = lutRes.$2;
          b = lutRes.$3;
        }

        r = origR * (1.0 - intensity) + r * intensity;
        g = origG * (1.0 - intensity) + g * intensity;
        b = origB * (1.0 - intensity) + b * intensity;

        pixel.r = r * pixel.maxChannelValue;
        pixel.g = g * pixel.maxChannelValue;
        pixel.b = b * pixel.maxChannelValue;
      }
    }
  }

  // Step 2: image-level effects
  final effLuminanceNR = params.luminanceNR * intensity;
  final effColourNR = params.colourNR * intensity;
  if (effLuminanceNR > 0 || effColourNR > 0) {
    output = _applyNoiseReduction(output, effLuminanceNR, effColourNR, params.nrDetail);
  }
  final effHdrStrength = params.hdrStrength * intensity;
  if (effHdrStrength > 0) {
    output = _applyHdrImage(output, effHdrStrength, params.hdrSaturation);
  }
  final effGlowStrength = params.glowStrength * intensity;
  if (effGlowStrength > 0) {
    output = _applyGlowImage(output, effGlowStrength, params.glowSaturation, params.glowWarmth);
  }
  final effLightLeakStrength = params.lightLeakStrength * intensity;
  if (effLightLeakStrength > 0) {
    output = _applyLightLeakImage(output, effLightLeakStrength, params.lightLeakAngle, params.lightLeakWarmth);
  }
  final effHalationStrength = params.halationStrength * intensity;
  if (effHalationStrength > 0) {
    output = _applyHalationImage(output, effHalationStrength, params.halationThreshold, params.halationWarmth);
  }
  final effGrainStrength = params.grainStrength * intensity;
  if (effGrainStrength > 0) {
    output = _applyGrainImage(output, effGrainStrength, params.grainSize, params.grainSeed);
  }

  final effSharpen = params.sharpen * intensity;
  if (effSharpen > 0)    output = _applySharpenImage(output, effSharpen);
  final effStructure = params.structure * intensity;
  if (effStructure != 0) output = _applyStructureImage(output, effStructure);
  final effClarity = params.clarity * intensity;
  if (effClarity != 0)   output = _applyClarityImage(output, effClarity);
  final effVignette = params.vignette * intensity;
  if (effVignette > 0)   output = _applyVignetteImage(output, effVignette);

  return output;
}

// ── Sharpen: Unsharp Mask ─────────────────────────────────
img.Image _applySharpenImage(img.Image image, double sharpenValue) {
  final strength = sharpenValue / 100.0 * 1.5;
  final blurred  = img.gaussianBlur(img.Image.from(image), radius: 2);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);
      final r  = (o.rNormalized + strength * (o.rNormalized - bl.rNormalized)).clamp(0.0, 1.0);
      final g  = (o.gNormalized + strength * (o.gNormalized - bl.gNormalized)).clamp(0.0, 1.0);
      final b  = (o.bNormalized + strength * (o.bNormalized - bl.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Structure: High-Pass Local Contrast ──────────────────
img.Image _applyStructureImage(img.Image image, double structureValue) {
  final strength = structureValue / 100.0 * 0.5;
  final blurred  = img.gaussianBlur(img.Image.from(image), radius: 1);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);
      final r  = (o.rNormalized + strength * (o.rNormalized - bl.rNormalized)).clamp(0.0, 1.0);
      final g  = (o.gNormalized + strength * (o.gNormalized - bl.gNormalized)).clamp(0.0, 1.0);
      final b  = (o.bNormalized + strength * (o.bNormalized - bl.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Clarity: Mid-Frequency Contrast (Retinex-lite) ───────
img.Image _applyClarityImage(img.Image image, double clarityValue) {
  final strength = clarityValue / 100.0 * 0.7;
  final blurred  = img.gaussianBlur(img.Image.from(image), radius: 7);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o   = image.getPixel(x, y);
      final low = blurred.getPixel(x, y);
      final lum = 0.2126 * o.rNormalized + 0.7152 * o.gNormalized + 0.0722 * o.bNormalized;
      final midMask = (1.0 - (lum - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      final r = (o.rNormalized + strength * midMask * (o.rNormalized - low.rNormalized)).clamp(0.0, 1.0);
      final g = (o.gNormalized + strength * midMask * (o.gNormalized - low.gNormalized)).clamp(0.0, 1.0);
      final b = (o.bNormalized + strength * midMask * (o.bNormalized - low.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Vignette: Radial Gradient Multiply ───────────────────
img.Image _applyVignetteImage(img.Image image, double vignetteValue) {
  final strength = vignetteValue / 100.0 * 0.8;
  final result   = img.Image(width: image.width, height: image.height);
  final W        = image.width.toDouble();
  final H        = image.height.toDouble();

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px  = image.getPixel(x, y);
      final dx  = x / W - 0.5;
      final dy  = y / H - 0.5;
      final dist = math.sqrt(dx * dx + dy * dy) / 0.707;
      final mask = (1.0 - dist * dist * strength).clamp(0.0, 1.0);
      result.setPixelRgb(x, y,
        (px.rNormalized * mask * 255).round(),
        (px.gNormalized * mask * 255).round(),
        (px.bNormalized * mask * 255).round(),
      );
    }
  }
  return result;
}

// ── Noise Reduction ──────────────────────────────────────
img.Image _applyNoiseReduction(img.Image image, double lumNR, double colNR, double nrDetail) {
  if (lumNR <= 0 && colNR <= 0) return image;

  final W = image.width;
  final H = image.height;
  final numPixels = W * H;

  final labL = Float32List(numPixels);
  final labA = Float32List(numPixels);
  final labB = Float32List(numPixels);

  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final lab = rgbToLab(RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      ));
      final idx = y * W + x;
      labL[idx] = lab.l;
      labA[idx] = lab.a;
      labB[idx] = lab.b;
    }
  }

  final outL = Float32List(numPixels);
  final outA = Float32List(numPixels);
  final outB = Float32List(numPixels);

  final lumRadius = lumNR > 0 ? (lumNR / 50.0 * 2.0 + 1.0).round().clamp(1, 3) : 0;
  final colRadius = colNR > 0 ? (colNR / 50.0 * 2.0 + 1.0).round().clamp(1, 3) : 0;

  final sigmaRangeL = 3.0 + lumNR * 0.22;
  final sigmaRangeC = 8.0 + colNR * 0.40;

  final sigRangeL2 = 2.0 * sigmaRangeL * sigmaRangeL;
  final sigRangeC2 = 2.0 * sigmaRangeC * sigmaRangeC;

  double spatialWeight(int dx, int dy, int r) {
    if (r == 0) return 1.0;
    final ss = r * 0.5;
    return math.exp(-(dx * dx + dy * dy).toDouble() / (2.0 * ss * ss));
  }

  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final cIdx = y * W + x;
      final cL = labL[cIdx];
      final cA = labA[cIdx];
      final cB = labB[cIdx];

      if (lumRadius > 0) {
        double sumL = 0.0, wSum = 0.0;
        for (int dy = -lumRadius; dy <= lumRadius; dy++) {
          final ny = (y + dy).clamp(0, H - 1);
          for (int dx = -lumRadius; dx <= lumRadius; dx++) {
            final nx = (x + dx).clamp(0, W - 1);
            final nIdx = ny * W + nx;
            final nL = labL[nIdx];
            final dL = nL - cL;
            final rangW = math.exp(-(dL * dL) / sigRangeL2);
            final spatW = spatialWeight(dx, dy, lumRadius);
            final w = rangW * spatW;
            sumL += w * nL;
            wSum += w;
          }
        }
        final filteredL = wSum > 1e-8 ? sumL / wSum : cL;
        final detailBlend = (nrDetail / 100.0).clamp(0.0, 1.0);
        outL[cIdx] = cL * detailBlend + filteredL * (1.0 - detailBlend);
      } else {
        outL[cIdx] = cL;
      }

      if (colRadius > 0) {
        double sumA = 0.0, sumBVal = 0.0, wSumC = 0.0;
        for (int dy = -colRadius; dy <= colRadius; dy++) {
          final ny = (y + dy).clamp(0, H - 1);
          for (int dx = -colRadius; dx <= colRadius; dx++) {
            final nx = (x + dx).clamp(0, W - 1);
            final nIdx = ny * W + nx;
            final nA = labA[nIdx];
            final nB = labB[nIdx];
            final dA = nA - cA;
            final dB = nB - cB;
            final rangW = math.exp(-(dA * dA + dB * dB) / sigRangeC2);
            final spatW = spatialWeight(dx, dy, colRadius);
            final w = rangW * spatW;
            sumA += w * nA;
            sumBVal += w * nB;
            wSumC += w;
          }
        }
        final filteredA = wSumC > 1e-8 ? sumA / wSumC : cA;
        final filteredB = wSumC > 1e-8 ? sumBVal / wSumC : cB;
        final detailBlend = (nrDetail / 100.0).clamp(0.0, 1.0);
        outA[cIdx] = cA * detailBlend + filteredA * (1.0 - detailBlend);
        outB[cIdx] = cB * detailBlend + filteredB * (1.0 - detailBlend);
      } else {
        outA[cIdx] = cA;
        outB[cIdx] = cB;
      }
    }
  }

  final result = img.Image(width: W, height: H);
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final idx = y * W + x;
      final rgb = labToRgb(LabColor(outL[idx], outA[idx], outB[idx]));
      result.setPixelRgb(x, y,
        (rgb.r * 255.0).round().clamp(0, 255),
        (rgb.g * 255.0).round().clamp(0, 255),
        (rgb.b * 255.0).round().clamp(0, 255),
      );
    }
  }
  return result;
}

// ── Glamour Glow ─────────────────────────────────────────
img.Image _applyGlowImage(img.Image image, double strength, double saturation, double warmth) {
  if (strength <= 0) return image;

  final W = image.width;
  final H = image.height;
  
  final glowLayer = img.Image(width: W, height: H);
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final r = px.rNormalized.toDouble();
      final g = px.gNormalized.toDouble();
      final b = px.bNormalized.toDouble();
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      
      final mask = lum * lum;
      
      var gr = r;
      var gg = g;
      var gb = b;
      
      if (saturation != 0) {
        final s = 1.0 + saturation / 100.0;
        gr = lum + (gr - lum) * s;
        gg = lum + (gg - lum) * s;
        gb = lum + (gb - lum) * s;
      }
      
      if (warmth != 0) {
        gr += warmth / 1000.0;
        gb -= warmth / 1000.0;
      }
      
      glowLayer.setPixelRgb(x, y,
        (gr.clamp(0.0, 1.0) * mask * 255).round(),
        (gg.clamp(0.0, 1.0) * mask * 255).round(),
        (gb.clamp(0.0, 1.0) * mask * 255).round(),
      );
    }
  }
  
  final blurredGlow = img.gaussianBlur(glowLayer, radius: 8);
  final result = img.Image(width: W, height: H);
  final str = strength / 100.0;
  
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final opx = image.getPixel(x, y);
      final gpx = blurredGlow.getPixel(x, y);
      
      final or = opx.rNormalized.toDouble();
      final og = opx.gNormalized.toDouble();
      final ob = opx.bNormalized.toDouble();
      
      final gr = gpx.rNormalized.toDouble() * str;
      final gg = gpx.gNormalized.toDouble() * str;
      final gb = gpx.bNormalized.toDouble() * str;
      
      final r = 1.0 - (1.0 - or) * (1.0 - gr);
      final g = 1.0 - (1.0 - og) * (1.0 - gg);
      final b = 1.0 - (1.0 - ob) * (1.0 - gb);
      
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

// ── HDR Scape ────────────────────────────────────────────
img.Image _applyHdrImage(img.Image image, double strength, double saturation) {
  if (strength <= 0) return image;

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
      
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

// ── Light Leak ───────────────────────────────────────────
img.Image _applyLightLeakImage(img.Image image, double strength, double angle, double warmth) {
  if (strength <= 0) return image;

  final W = image.width;
  final H = image.height;
  final result = img.Image(width: W, height: H);
  
  final rad = angle * math.pi / 180.0;
  final dx = math.cos(rad);
  final dy = math.sin(rad);
  final str = strength / 100.0 * 0.4;
  
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final nx = x / W - 0.5;
      final ny = y / H - 0.5;
      
      final projection = nx * dx + ny * dy;
      final dist = (projection + 0.7) / 1.4;
      final leak = dist * dist * str;
      
      final r = px.rNormalized.toDouble() + leak;
      final g = px.gNormalized.toDouble() + leak * 0.7;
      final b = px.bNormalized.toDouble() + leak * (0.3 + warmth / 200.0);
      
      result.setPixelRgb(x, y,
        (r.clamp(0.0, 1.0) * 255).round(),
        (g.clamp(0.0, 1.0) * 255).round(),
        (b.clamp(0.0, 1.0) * 255).round(),
      );
    }
  }
  return result;
}

// ── Halation ─────────────────────────────────────────────
img.Image _applyHalationImage(img.Image image, double strength, double threshold, double warmth) {
  if (strength <= 0) return image;

  final W = image.width;
  final H = image.height;
  
  final hlLayer = img.Image(width: W, height: H);
  final th = threshold / 100.0;
  
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final r = px.rNormalized.toDouble();
      final g = px.gNormalized.toDouble();
      final b = px.bNormalized.toDouble();
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      
      if (lum > th) {
        final w = (lum - th) / (1.0 - th);
        hlLayer.setPixelRgb(x, y, (r * w * 255).round(), (g * w * 255).round(), (b * w * 255).round());
      }
    }
  }
  
  final blurredHl = img.gaussianBlur(hlLayer, radius: 5);
  final result = img.Image(width: W, height: H);
  final str = strength / 100.0 * 0.6;
  
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      final px = image.getPixel(x, y);
      final hpx = blurredHl.getPixel(x, y);
      
      final rNorm = px.rNormalized.toDouble();
      final gNorm = px.gNormalized.toDouble();
      final bNorm = px.bNormalized.toDouble();
      
      final hr = hpx.rNormalized.toDouble() * str;
      final hg = hpx.gNormalized.toDouble() * str * 0.4;
      final hb = hpx.bNormalized.toDouble() * str * (0.1 - warmth / 1000.0);
      
      final r = (rNorm + hr).clamp(0.0, 1.0);
      final g = (gNorm + hg).clamp(0.0, 1.0);
      final b = (bNorm + hb).clamp(0.0, 1.0);
      
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Film Grain ───────────────────────────────────────────
img.Image _applyGrainImage(img.Image image, double strength, double size, int seed) {
  if (strength <= 0) return image;

  final rand = math.Random(seed);
  final W = image.width;
  final H = image.height;
  final result = img.Image(width: W, height: H);
  
  final double s = size.clamp(0.5, 3.0);
  final int gridW = (W / s).ceil();
  final int gridH = (H / s).ceil();
  
  final grid = Float32List(gridW * gridH);
  for (int i = 0; i < grid.length; i++) {
    grid[i] = rand.nextDouble() * 2.0 - 1.0;
  }
  
  for (int y = 0; y < H; y++) {
    final int gy = (y / s).floor().clamp(0, gridH - 1);
    for (int x = 0; x < W; x++) {
      final int gx = (x / s).floor().clamp(0, gridW - 1);
      final double noise = grid[gy * gridW + gx];
      
      final px = image.getPixel(x, y);
      final double rNorm = px.rNormalized.toDouble();
      final double gNorm = px.gNormalized.toDouble();
      final double bNorm = px.bNormalized.toDouble();
      final double lum = 0.2126 * rNorm + 0.7152 * gNorm + 0.0722 * bNorm;
      
      final double weight = 1.0 - (lum - 0.5) * (lum - 0.5) * 4.0;
      final double delta = noise * (strength / 100.0) * weight * (25.0 / 255.0);
      
      final r = (rNorm + delta).clamp(0.0, 1.0);
      final g = (gNorm + delta).clamp(0.0, 1.0);
      final b = (bNorm + delta).clamp(0.0, 1.0);
      
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

const int _dim = customLutDim;

typedef LutProgressCallback = void Function(String stage, double progress);

Future<Map<String, dynamic>> generateLutFromStyle(
  List<String> styleImagePaths, {
  String? basePath,
  LutProgressCallback? onProgress,
}) async {
  if (styleImagePaths.isEmpty) {
    throw ArgumentError('styleImagePaths cannot be empty');
  }
  if (styleImagePaths.length == 1 && AiManager.instance.colorTransferReady) {
    try {
      return await _generateLutNeural(styleImagePaths.first, basePath: basePath, onProgress: onProgress);
    } catch (_) {}
  }
  return _generateLutAlgorithmic(styleImagePaths, basePath: basePath, onProgress: onProgress);
}

Future<Map<String, dynamic>> _generateLutNeural(
  String styleImagePath, {
  String? basePath,
  LutProgressCallback? onProgress,
}) async {
  onProgress?.call('style_loading', 0.10);
  final id   = const Uuid().v4();
  final base = basePath != null
      ? Directory(basePath)
      : await getApplicationDocumentsDirectory();
  final dir  = Directory('${base.path}/filters/$id')
    ..createSync(recursive: true);

  onProgress?.call('model_inference', 0.25);
  final predictor = await LutPredictor.instance;
  final lut65     = await predictor.predict(styleImagePath);

  onProgress?.call('lut_encode', 0.70);
  const total   = _dim * _dim * _dim;
  final lutData = Uint16List(total * 3);
  for (int i = 0; i < total * 3; i++) {
    lutData[i] = floatToHalf(lut65[i]);
  }

  final lutPath = '${dir.path}/lut.bin';
  File(lutPath).writeAsBytesSync(lutData.buffer.asUint8List());

  onProgress?.call('thumbnail', 0.88);
  final bytes    = File(styleImagePath).readAsBytesSync();
  final image    = img.decodeImage(bytes)!;
  final thumb    = img.copyResizeCropSquare(image, size: 128);
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));

  final grain = analyzeGrainParameters(image);

  final defaultParams = AdjustParams.zero.copyWith(
    grainStrength: grain.strength,
    grainSize: grain.size,
  );

  onProgress?.call('saving', 0.96);
  return {
    'presetId':      id,
    'lutPath':       lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': defaultParams.toJson(),
  };
}

Future<Map<String, dynamic>> _generateLutAlgorithmic(
  List<String> styleImagePaths, {
  String? basePath,
  LutProgressCallback? onProgress,
}) async {
  onProgress?.call('style_loading', 0.10);
  final id    = const Uuid().v4();
  final base  = basePath != null
      ? Directory(basePath)
      : await getApplicationDocumentsDirectory();
  final dir   = Directory('${base.path}/filters/$id')
    ..createSync(recursive: true);

  final images = <img.Image>[];
  for (final path in styleImagePaths) {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      images.add(decoded);
    }
  }

  if (images.isEmpty) {
    throw Exception('Failed to decode any style images');
  }

  final lutBytes = buildCustomLutFromStyleImages(images, onProgress: onProgress);

  onProgress?.call('thumbnail', 0.90);
  final lutPath = '${dir.path}/lut.bin';
  File(lutPath).writeAsBytesSync(lutBytes);

  final thumb     = img.copyResizeCropSquare(images.first, size: 128);
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));

  var grainStr = 0.0;
  var grainSz = 1.0;
  for (final img in images) {
    final grain = analyzeGrainParameters(img);
    grainStr += grain.strength;
    grainSz += grain.size;
  }
  grainStr /= images.length;
  grainSz /= images.length;

  final defaultParams = AdjustParams.zero.copyWith(
    grainStrength: grainStr,
    grainSize: grainSz,
  );

  onProgress?.call('saving', 0.96);
  return {
    'presetId':      id,
    'lutPath':       lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': defaultParams.toJson(),
  };
}

RgbColor applyLut(Uint8List lutBytes, RgbColor rgb) {
  return applyCustomLut(lutBytes, rgb);
}

RgbColor applyAdjustParams(
  RgbColor rgb,
  AdjustParams p, {
  BakedCurveLuts? bakedLuts,
}) {
  var r = rgb.r * math.pow(2.0, p.exposure);
  var g = rgb.g * math.pow(2.0, p.exposure);
  var b = rgb.b * math.pow(2.0, p.exposure);

  if (p.contrast != 0) {
    final factor = (259.0 * (p.contrast + 255)) / (255.0 * (259 - p.contrast));
    r = factor * (r - 0.5) + 0.5;
    g = factor * (g - 0.5) + 0.5;
    b = factor * (b - 0.5) + 0.5;
  }

  if (p.saturation != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final s   = 1.0 + p.saturation / 100.0;
    r = lum + (r - lum) * s;
    g = lum + (g - lum) * s;
    b = lum + (b - lum) * s;
  }

  if (p.hasHsl) {
    final hslAdjusted = _applyHslBands(RgbColor(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0)), p);
    r = hslAdjusted.r;
    g = hslAdjusted.g;
    b = hslAdjusted.b;
  }

  if (p.hasSplitToning) {
    final splitAdjusted = _applySplitToning(RgbColor(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0)), p);
    r = splitAdjusted.r;
    g = splitAdjusted.g;
    b = splitAdjusted.b;
  }

  if (p.temperature != 0) {
    r += p.temperature / 1000.0;
    b -= p.temperature / 1000.0;
  }
  if (p.tint != 0) {
    g += p.tint / 1000.0;
    r -= p.tint / 2000.0;
  }

  if (p.highlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (lum - 0.5).clamp(0.0, 0.5) * 2.0;
    final adj  = p.highlights / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }
  if (p.shadows != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (0.5 - lum).clamp(0.0, 0.5) * 2.0;
    final adj  = p.shadows / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }

  if (p.ambiance != 0) {
    final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
    final a = p.ambiance / 100.0;
    final shadowMask = (1.0 - lum) * (1.0 - lum);
    final highlightMask = lum * lum;
    final brightAdj = a * (0.22 * shadowMask - 0.15 * highlightMask);
    r += brightAdj;
    g += brightAdj;
    b += brightAdj;
    final satMask = 4.0 * lum * (1.0 - lum);
    final satFactor = 1.0 + a * 0.35 * satMask;
    final newLum = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
    r = newLum + (r - newLum) * satFactor;
    g = newLum + (g - newLum) * satFactor;
    b = newLum + (b - newLum) * satFactor;
  }

  if (p.hasCurves) {
    final luts = bakedLuts ?? bakeCurveLuts(p);

    r = luts.rgbMaster[(r.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    g = luts.rgbMaster[(g.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    b = luts.rgbMaster[(b.clamp(0.0, 1.0) * 255.0).round()] / 255.0;

    r = luts.red[(r.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    g = luts.green[(g.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    b = luts.blue[(b.clamp(0.0, 1.0) * 255.0).round()] / 255.0;

    if (p.luminanceCurve != null && !p.luminanceCurve!.isLinear) {
      final lab  = rgbToLab(RgbColor(r.clamp(0.0,1.0), g.clamp(0.0,1.0), b.clamp(0.0,1.0)));
      final lNew = luts.luminance[(lab.l / 100.0 * 255.0).round().clamp(0, 255)] / 255.0 * 100.0;
      final rgb2 = labToRgb(LabColor(lNew, lab.a, lab.b));
      r = rgb2.r; g = rgb2.g; b = rgb2.b;
    }
  }

  if (p.tonalShadows != 0 || p.tonalMidtones != 0 || p.tonalHighlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    double sCurve(double v, double strength) {
      final f = strength / 100.0;
      return v + f * v * (1 - v) * 2.0;
    }

    double gw(double l, double center) {
      const sigma = 0.2;
      final d = l - center;
      return math.exp(-0.5 * d * d / (sigma * sigma));
    }
    final ws = gw(lum, 0.15);
    final wm = gw(lum, 0.5);
    final wh = gw(lum, 0.85);
    final wTotal = ws + wm + wh + 1e-10;

    final adj = (ws * sCurve(lum, p.tonalShadows) +
                 wm * sCurve(lum, p.tonalMidtones) +
                 wh * sCurve(lum, p.tonalHighlights)) / wTotal - lum;
    r = (r + adj).clamp(0.0, 1.0);
    g = (g + adj).clamp(0.0, 1.0);
    b = (b + adj).clamp(0.0, 1.0);
  }

  if (p.bnwEnabled) {
    final wr = 0.299 + p.bnwRed    / 100.0 * 0.3;
    final wg = 0.587 + p.bnwGreen  / 100.0 * 0.3;
    final wb = 0.114 + p.bnwBlue   / 100.0 * 0.3;
    final wy =         p.bnwYellow / 100.0 * 0.2;
    final L  = (r * wr + g * wg + b * wb + (r + g) / 2.0 * wy)
        .clamp(0.0, 1.0);
    r = L; g = L; b = L;
  }

  return RgbColor(r.toDouble(), g.toDouble(), b.toDouble()).clamp01();
}

(double, double, double) applyAdjustParamsFlat(
  double rIn, double gIn, double bIn,
  AdjustParams p, {
  BakedCurveLuts? bakedLuts,
}) {
  var r = rIn * math.pow(2.0, p.exposure);
  var g = gIn * math.pow(2.0, p.exposure);
  var b = bIn * math.pow(2.0, p.exposure);

  if (p.contrast != 0) {
    final factor = (259.0 * (p.contrast + 255)) / (255.0 * (259 - p.contrast));
    r = factor * (r - 0.5) + 0.5;
    g = factor * (g - 0.5) + 0.5;
    b = factor * (b - 0.5) + 0.5;
  }

  if (p.saturation != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final s   = 1.0 + p.saturation / 100.0;
    r = lum + (r - lum) * s;
    g = lum + (g - lum) * s;
    b = lum + (b - lum) * s;
  }

  if (p.hasHsl) {
    final hslAdjusted = _applyHslBandsFlat(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0), p);
    r = hslAdjusted.$1;
    g = hslAdjusted.$2;
    b = hslAdjusted.$3;
  }

  if (p.hasSplitToning) {
    final splitAdjusted = _applySplitToningFlat(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0), p);
    r = splitAdjusted.$1;
    g = splitAdjusted.$2;
    b = splitAdjusted.$3;
  }

  if (p.temperature != 0) {
    r += p.temperature / 1000.0;
    b -= p.temperature / 1000.0;
  }
  if (p.tint != 0) {
    g += p.tint / 1000.0;
    r -= p.tint / 2000.0;
  }

  if (p.highlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (lum - 0.5).clamp(0.0, 0.5) * 2.0;
    final adj  = p.highlights / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }
  if (p.shadows != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (0.5 - lum).clamp(0.0, 0.5) * 2.0;
    final adj  = p.shadows / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }

  if (p.ambiance != 0) {
    final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
    final a = p.ambiance / 100.0;
    final shadowMask = (1.0 - lum) * (1.0 - lum);
    final highlightMask = lum * lum;
    final brightAdj = a * (0.22 * shadowMask - 0.15 * highlightMask);
    r += brightAdj;
    g += brightAdj;
    b += brightAdj;
    final satMask = 4.0 * lum * (1.0 - lum);
    final satFactor = 1.0 + a * 0.35 * satMask;
    final newLum = (0.2126 * r + 0.7152 * g + 0.0722 * b).clamp(0.0, 1.0);
    r = newLum + (r - newLum) * satFactor;
    g = newLum + (g - newLum) * satFactor;
    b = newLum + (b - newLum) * satFactor;
  }

  if (p.hasCurves) {
    final luts = bakedLuts ?? bakeCurveLuts(p);

    r = luts.rgbMaster[(r.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    g = luts.rgbMaster[(g.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    b = luts.rgbMaster[(b.clamp(0.0, 1.0) * 255.0).round()] / 255.0;

    r = luts.red[(r.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    g = luts.green[(g.clamp(0.0, 1.0) * 255.0).round()] / 255.0;
    b = luts.blue[(b.clamp(0.0, 1.0) * 255.0).round()] / 255.0;

    if (p.luminanceCurve != null && !p.luminanceCurve!.isLinear) {
      final lab  = rgbToLab(RgbColor(r.clamp(0.0,1.0), g.clamp(0.0,1.0), b.clamp(0.0,1.0)));
      final lNew = luts.luminance[(lab.l / 100.0 * 255.0).round().clamp(0, 255)] / 255.0 * 100.0;
      final rgb2 = labToRgb(LabColor(lNew, lab.a, lab.b));
      r = rgb2.r; g = rgb2.g; b = rgb2.b;
    }
  }

  if (p.tonalShadows != 0 || p.tonalMidtones != 0 || p.tonalHighlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    double sCurve(double v, double strength) {
      final f = strength / 100.0;
      return v + f * v * (1 - v) * 2.0;
    }

    double gw(double l, double center) {
      const sigma = 0.2;
      final d = l - center;
      return math.exp(-0.5 * d * d / (sigma * sigma));
    }
    final ws = gw(lum, 0.15);
    final wm = gw(lum, 0.5);
    final wh = gw(lum, 0.85);
    final wTotal = ws + wm + wh + 1e-10;

    final adj = (ws * sCurve(lum, p.tonalShadows) +
                 wm * sCurve(lum, p.tonalMidtones) +
                 wh * sCurve(lum, p.tonalHighlights)) / wTotal - lum;
    r = (r + adj).clamp(0.0, 1.0);
    g = (g + adj).clamp(0.0, 1.0);
    b = (b + adj).clamp(0.0, 1.0);
  }

  if (p.bnwEnabled) {
    final wr = 0.299 + p.bnwRed    / 100.0 * 0.3;
    final wg = 0.587 + p.bnwGreen  / 100.0 * 0.3;
    final wb = 0.114 + p.bnwBlue   / 100.0 * 0.3;
    final wy =         p.bnwYellow / 100.0 * 0.2;
    final L  = (r * wr + g * wg + b * wb + (r + g) / 2.0 * wy)
        .clamp(0.0, 1.0);
    r = L; g = L; b = L;
  }

  return (r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0));
}


RgbColor applyPipeline({
  required RgbColor original,
  required AdjustParams params,
  required Uint8List? lutBytes,
  DecodedLut? decodedLut,
  BakedCurveLuts? bakedLuts,
  required double intensity,
}) {
  final effectiveLut = decodedLut ?? tryDecodeCustomLut(lutBytes);
  final base = effectiveLut != null
      ? applyDecodedCustomLut(effectiveLut, original)
      : original;
  final result = applyAdjustParams(base, params, bakedLuts: bakedLuts);
  final mix = intensity.clamp(0.0, 1.0);
  return RgbColor(
    original.r * (1 - mix) + result.r * mix,
    original.g * (1 - mix) + result.g * mix,
    original.b * (1 - mix) + result.b * mix,
  ).clamp01();
}

Future<Uint8List?> loadLutBytes(String? lutPath) async {
  if (lutPath == null || lutPath.isEmpty) return null;
  if (lutPath.startsWith('assets/')) {
    try {
      final data = await rootBundle.load(lutPath);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
  final f = File(lutPath);
  if (!await f.exists()) return null;
  return f.readAsBytes();
}

class BakedCurveLuts {
  final Uint8List rgbMaster;
  final Uint8List red;
  final Uint8List green;
  final Uint8List blue;
  final Uint8List luminance;

  BakedCurveLuts({
    required this.rgbMaster,
    required this.red,
    required this.green,
    required this.blue,
    required this.luminance,
  });
}

BakedCurveLuts bakeCurveLuts(AdjustParams p) {
  final rgbMaster = p.rgbCurve != null && !p.rgbCurve!.isLinear
      ? Uint8List.fromList(p.rgbCurve!.toLut())
      : Uint8List.fromList(List.generate(256, (i) => i));

  final red = p.redCurve != null && !p.redCurve!.isLinear
      ? Uint8List.fromList(p.redCurve!.toLut())
      : Uint8List.fromList(List.generate(256, (i) => i));

  final green = p.greenCurve != null && !p.greenCurve!.isLinear
      ? Uint8List.fromList(p.greenCurve!.toLut())
      : Uint8List.fromList(List.generate(256, (i) => i));

  final blue = p.blueCurve != null && !p.blueCurve!.isLinear
      ? Uint8List.fromList(p.blueCurve!.toLut())
      : Uint8List.fromList(List.generate(256, (i) => i));

  final luminance = p.luminanceCurve != null && !p.luminanceCurve!.isLinear
      ? Uint8List.fromList(p.luminanceCurve!.toLut())
      : Uint8List.fromList(List.generate(256, (i) => i));

  return BakedCurveLuts(
    rgbMaster: rgbMaster,
    red: red,
    green: green,
    blue: blue,
    luminance: luminance,
  );
}
