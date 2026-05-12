import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'color_utils.dart';

const int customLutDim = 65;

typedef CustomLutProgressCallback = void Function(String stage, double progress);

Map<String, double> inspectCustomLutStyle(img.Image styleImage) {
  final profile = _analyzeStyle(styleImage);
  final labProfile = _analyzeLabStyle(styleImage);
  return {
    'neutralConfidence': labProfile.neutralConfidence,
    'castStrength': labProfile.castStrength,
    'blueCastStrength': profile.blueCastStrength,
    'curveStrength': profile.curveStrength,
    'styleStrength': _styleStrength(profile, labProfile),
    'labBlendWeight': _labBlendWeight(labProfile.castStrength, labProfile.neutralConfidence),
  };
}

Uint8List buildCustomLutFromStyleImage(
  img.Image styleImage, {
  int dim = customLutDim,
  CustomLutProgressCallback? onProgress,
}) {
  onProgress?.call('style_analyze', 0.22);
  final profile = _analyzeStyle(styleImage);
  onProgress?.call('lab_analyze', 0.36);
  final labProfile = _analyzeLabStyle(styleImage);

  onProgress?.call('lut_build', 0.50);
  final total = dim * dim * dim;
  final lutData = Uint16List(total * 3);
  final maxIdx = (dim - 1).toDouble();
  var lutIdx = 0;

  for (int b = 0; b < dim; b++) {
    if (b % 16 == 0) {
      onProgress?.call('lut_build', 0.50 + b / dim * 0.36);
    }
    for (int g = 0; g < dim; g++) {
      for (int r = 0; r < dim; r++) {
        final original = RgbColor(r / maxIdx, g / maxIdx, b / maxIdx);
        final channelRgb = _applyChannelStyle(original, profile, labProfile);
        final labRgb = _applyLabStyle(original, labProfile);
        final blend = _labBlendWeight(labProfile.castStrength, labProfile.neutralConfidence);
        final mixed = RgbColor(
          channelRgb.r * (1.0 - blend) + labRgb.r * blend,
          channelRgb.g * (1.0 - blend) + labRgb.g * blend,
          channelRgb.b * (1.0 - blend) + labRgb.b * blend,
        ).clamp01();
        final protected = _protectMemoryColors(original, mixed, profile);
        final strength = _styleStrength(profile, labProfile);
        final finalRgb = RgbColor(
          original.r * (1.0 - strength) + protected.r * strength,
          original.g * (1.0 - strength) + protected.g * strength,
          original.b * (1.0 - strength) + protected.b * strength,
        ).clamp01();

        lutData[lutIdx++] = floatToHalf(finalRgb.r);
        lutData[lutIdx++] = floatToHalf(finalRgb.g);
        lutData[lutIdx++] = floatToHalf(finalRgb.b);
      }
    }
  }

  return lutData.buffer.asUint8List();
}

RgbColor applyCustomLut(Uint8List lutBytes, RgbColor rgb, {int dim = customLutDim}) {
  final lut = lutBytes.buffer.asUint16List();
  final maxIdx = (dim - 1).toDouble();

  final ri = rgb.r * maxIdx;
  final gi = rgb.g * maxIdx;
  final bi = rgb.b * maxIdx;

  final r0 = ri.floor().clamp(0, dim - 2);
  final r1 = (r0 + 1).clamp(0, dim - 1);
  final g0 = gi.floor().clamp(0, dim - 2);
  final g1 = (g0 + 1).clamp(0, dim - 1);
  final b0 = bi.floor().clamp(0, dim - 2);
  final b1 = (b0 + 1).clamp(0, dim - 1);

  final rf = ri - r0;
  final gf = gi - g0;
  final bf = bi - b0;

  RgbColor sample(int r, int g, int b) {
    final i = (r + g * dim + b * dim * dim) * 3;
    return RgbColor(
      halfToFloat(lut[i]),
      halfToFloat(lut[i + 1]),
      halfToFloat(lut[i + 2]),
    );
  }

  RgbColor lerp(RgbColor a, RgbColor b, double t) => RgbColor(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
      );

  final c000 = sample(r0, g0, b0);
  final c100 = sample(r1, g0, b0);
  final c010 = sample(r0, g1, b0);
  final c110 = sample(r1, g1, b0);
  final c001 = sample(r0, g0, b1);
  final c101 = sample(r1, g0, b1);
  final c011 = sample(r0, g1, b1);
  final c111 = sample(r1, g1, b1);

  final c00 = lerp(c000, c100, rf);
  final c10 = lerp(c010, c110, rf);
  final c01 = lerp(c001, c101, rf);
  final c11 = lerp(c011, c111, rf);

  final c0 = lerp(c00, c10, gf);
  final c1 = lerp(c01, c11, gf);

  return lerp(c0, c1, bf).clamp01();
}

int floatToHalf(double value) {
  final f32 = Float32List(1)..[0] = value.clamp(0.0, 1.0);
  final bits = f32.buffer.asUint32List()[0];
  final sign = (bits >> 31) & 0x1;
  var exp = ((bits >> 23) & 0xFF) - 127 + 15;
  var mantissa = (bits >> 13) & 0x3FF;
  if (exp <= 0) {
    exp = 0;
    mantissa = 0;
  }
  if (exp >= 31) {
    exp = 31;
    mantissa = 0;
  }
  return (sign << 15) | (exp << 10) | mantissa;
}

double halfToFloat(int half) {
  final sign = (half >> 15) & 0x1;
  final exp = (half >> 10) & 0x1F;
  final mantissa = half & 0x3FF;
  if (exp == 0) return 0.0;
  if (exp == 31) return sign == 0 ? double.infinity : double.negativeInfinity;
  final e = exp - 15;
  final m = 1.0 + mantissa / 1024.0;
  return (sign == 0 ? 1.0 : -1.0) * m * math.pow(2.0, e);
}

class _ZoneCast {
  final double a;
  final double b;
  final int count;

  const _ZoneCast(this.a, this.b, this.count);

  static const zero = _ZoneCast(0, 0, 0);
}

class _StyleProfile {
  final List<int> rCurve;
  final List<int> gCurve;
  final List<int> bCurve;
  final _ZoneCast shadowCast;
  final _ZoneCast midtoneCast;
  final _ZoneCast highlightCast;
  final double blueCastStrength;
  final double curveStrength;

  const _StyleProfile({
    required this.rCurve,
    required this.gCurve,
    required this.bCurve,
    required this.shadowCast,
    required this.midtoneCast,
    required this.highlightCast,
    required this.blueCastStrength,
    required this.curveStrength,
  });
}

class _LabStyleProfile {
  final List<double> toneCurve;
  final double meanL;
  final double contrastRatio;
  final double satBoost;
  final double castStrength;
  final double neutralConfidence;
  final LabColor shadow;
  final LabColor midtone;
  final LabColor highlight;

  const _LabStyleProfile({
    required this.toneCurve,
    required this.meanL,
    required this.contrastRatio,
    required this.satBoost,
    required this.castStrength,
    required this.neutralConfidence,
    required this.shadow,
    required this.midtone,
    required this.highlight,
  });
}

final List<double> _neutralChannelCdf = _buildNeutralChannelCdf();
final List<double> _neutralLCdf = _buildNeutralLCdf();

List<double> _buildNeutralChannelCdf() {
  const mu = 115.0;
  const sigma = 55.0;
  final hist = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final z = (i - mu) / sigma;
    hist[i] = math.exp(-0.5 * z * z);
  }
  return _histToCdf(hist);
}

List<double> _buildNeutralLCdf() {
  const mu = 50.0;
  const sigma = 18.0;
  final hist = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final l = i * 100.0 / 255.0;
    final z = (l - mu) / sigma;
    hist[i] = math.exp(-0.5 * z * z);
  }
  return _histToCdf(hist);
}

List<double> _histToCdf(List<double> hist) {
  final sum = hist.fold(0.0, (a, b) => a + b);
  var cumul = 0.0;
  final cdf = List<double>.filled(hist.length, 0.0);
  for (int i = 0; i < hist.length; i++) {
    cumul += hist[i] / sum;
    cdf[i] = cumul;
  }
  return cdf;
}

_StyleProfile _analyzeStyle(img.Image styleImage) {
  final sc = _downscale(styleImage, 512);
  final rHist = List<int>.filled(256, 0);
  final gHist = List<int>.filled(256, 0);
  final bHist = List<int>.filled(256, 0);
  final blueBHist = List<int>.filled(256, 0);

  var sGlobalA = 0.0, sGlobalB = 0.0, mGlobalA = 0.0, mGlobalB = 0.0, hGlobalA = 0.0, hGlobalB = 0.0;
  var sNeutralA = 0.0, sNeutralB = 0.0, mNeutralA = 0.0, mNeutralB = 0.0, hNeutralA = 0.0, hNeutralB = 0.0;
  var sGlobalCount = 0, mGlobalCount = 0, hGlobalCount = 0;
  var sNeutralCount = 0, mNeutralCount = 0, hNeutralCount = 0;
  var blueNegBSum = 0.0;
  var blueCount = 0;
  var highChromaCount = 0;

  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final rgb = RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      );
      final r8 = (rgb.r * 255).round().clamp(0, 255);
      final g8 = (rgb.g * 255).round().clamp(0, 255);
      final b8 = (rgb.b * 255).round().clamp(0, 255);
      rHist[r8]++;
      gHist[g8]++;
      bHist[b8]++;

      final lab = rgbToLab(rgb);
      final chroma = math.sqrt(lab.a * lab.a + lab.b * lab.b);
      if (chroma > 34) highChromaCount++;

      final blueDom = rgb.b - math.max(rgb.r, rgb.g);
      if (blueDom > 0.02) {
        blueCount++;
        blueNegBSum += (-lab.b).clamp(0.0, 110.0);
        blueBHist[b8]++;
      }

      final isNeutral = chroma < 18.0 || _rgbSaturation(rgb) < 0.18;
      if (lab.l < 35.0) {
        sGlobalA += lab.a; sGlobalB += lab.b; sGlobalCount++;
        if (isNeutral) { sNeutralA += lab.a; sNeutralB += lab.b; sNeutralCount++; }
      } else if (lab.l < 65.0) {
        mGlobalA += lab.a; mGlobalB += lab.b; mGlobalCount++;
        if (isNeutral) { mNeutralA += lab.a; mNeutralB += lab.b; mNeutralCount++; }
      } else {
        hGlobalA += lab.a; hGlobalB += lab.b; hGlobalCount++;
        if (isNeutral) { hNeutralA += lab.a; hNeutralB += lab.b; hNeutralCount++; }
      }
    }
  }

  final n = (sc.width * sc.height).toDouble();
  final blueCastStrength = blueCount > 0
      ? (blueNegBSum / (blueCount * 55.0)).clamp(0.0, 1.0)
      : 0.0;
  final contentRisk = (highChromaCount / n).clamp(0.0, 1.0);
  final curveStrength = (0.86 - contentRisk * 0.22 + blueCastStrength * 0.08).clamp(0.62, 0.92);

  final rCurve = _softenCurve(_channelCurve(rHist), curveStrength);
  final gCurve = _softenCurve(_channelCurve(gHist), curveStrength);
  final bCurve = _softenCurve(_channelCurve(bHist), curveStrength);

  if (blueCount > 500) {
    final blueCurve = _channelCurve(blueBHist);
    final blueRatio = (blueCount / n).clamp(0.0, 1.0);
    final baseWeight = (0.18 + 0.42 * blueRatio).clamp(0.0, 0.60);
    for (int i = 0; i < 256; i++) {
      final highMask = ((i - 36) / 219.0).clamp(0.0, 1.0);
      final w = baseWeight * highMask;
      bCurve[i] = ((1.0 - w) * bCurve[i] + w * blueCurve[i]).round().clamp(0, 255);
    }
    _monotonic(bCurve);
  }

  return _StyleProfile(
    rCurve: rCurve,
    gCurve: gCurve,
    bCurve: bCurve,
    shadowCast: _resolvedCast(sGlobalA, sGlobalB, sGlobalCount, sNeutralA, sNeutralB, sNeutralCount),
    midtoneCast: _resolvedCast(mGlobalA, mGlobalB, mGlobalCount, mNeutralA, mNeutralB, mNeutralCount),
    highlightCast: _resolvedCast(hGlobalA, hGlobalB, hGlobalCount, hNeutralA, hNeutralB, hNeutralCount),
    blueCastStrength: blueCastStrength,
    curveStrength: curveStrength,
  );
}

_LabStyleProfile _analyzeLabStyle(img.Image styleImage) {
  final sc = _downscale(styleImage, 512);
  final lHist = List<int>.filled(256, 0);
  final lValues = <double>[];
  final aValues = <double>[];
  final bValues = <double>[];

  var sGlobalL = 0.0, sGlobalA = 0.0, sGlobalB = 0.0;
  var mGlobalL = 0.0, mGlobalA = 0.0, mGlobalB = 0.0;
  var hGlobalL = 0.0, hGlobalA = 0.0, hGlobalB = 0.0;
  var sNeutralL = 0.0, sNeutralA = 0.0, sNeutralB = 0.0;
  var mNeutralL = 0.0, mNeutralA = 0.0, mNeutralB = 0.0;
  var hNeutralL = 0.0, hNeutralA = 0.0, hNeutralB = 0.0;
  var sGlobalCount = 0, mGlobalCount = 0, hGlobalCount = 0;
  var sNeutralCount = 0, mNeutralCount = 0, hNeutralCount = 0;

  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final rgb = RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      );
      final lab = rgbToLab(rgb);
      final chroma = math.sqrt(lab.a * lab.a + lab.b * lab.b);
      final isNeutral = chroma < 18.0 || _rgbSaturation(rgb) < 0.18;

      lValues.add(lab.l);
      aValues.add(lab.a);
      bValues.add(lab.b);
      lHist[(lab.l * 255.0 / 100.0).round().clamp(0, 255)]++;

      if (lab.l < 35.0) {
        sGlobalL += lab.l; sGlobalA += lab.a; sGlobalB += lab.b; sGlobalCount++;
        if (isNeutral) { sNeutralL += lab.l; sNeutralA += lab.a; sNeutralB += lab.b; sNeutralCount++; }
      } else if (lab.l < 65.0) {
        mGlobalL += lab.l; mGlobalA += lab.a; mGlobalB += lab.b; mGlobalCount++;
        if (isNeutral) { mNeutralL += lab.l; mNeutralA += lab.a; mNeutralB += lab.b; mNeutralCount++; }
      } else {
        hGlobalL += lab.l; hGlobalA += lab.a; hGlobalB += lab.b; hGlobalCount++;
        if (isNeutral) { hNeutralL += lab.l; hNeutralA += lab.a; hNeutralB += lab.b; hNeutralCount++; }
      }
    }
  }

  final n = lValues.length.toDouble();
  final meanL = lValues.fold(0.0, (sum, value) => sum + value) / n;
  final meanA = aValues.fold(0.0, (sum, value) => sum + value) / n;
  final meanB = bValues.fold(0.0, (sum, value) => sum + value) / n;
  final sigL = _stdDev(lValues, meanL);
  final sigA = _stdDev(aValues, meanA);
  final sigB = _stdDev(bValues, meanB);
  final neutralCount = sNeutralCount + mNeutralCount + hNeutralCount;
  final neutralConfidence = (neutralCount / n * 4.0).clamp(0.0, 1.0);

  final styleCdf = _histToCdf(lHist.map((v) => v.toDouble()).toList());
  final toneCurve = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final target = _neutralLCdf[i];
    var j = 0;
    while (j < 255 && styleCdf[j] < target) {
      j++;
    }
    toneCurve[i] = j.toDouble();
  }
  for (int i = 1; i < toneCurve.length; i++) {
    if (toneCurve[i] < toneCurve[i - 1]) toneCurve[i] = toneCurve[i - 1];
  }

  LabColor zone({
    required double fallbackL,
    required double globalL,
    required double globalA,
    required double globalB,
    required int globalCount,
    required double neutralL,
    required double neutralA,
    required double neutralB,
    required int neutralZoneCount,
  }) {
    final global = globalCount > 10
        ? LabColor(globalL / globalCount, globalA / globalCount, globalB / globalCount)
        : LabColor(fallbackL, meanA, meanB);
    if (neutralZoneCount <= 10) {
      return LabColor(global.l, global.a * 0.55, global.b * 0.55);
    }
    final neutral = LabColor(
      neutralL / neutralZoneCount,
      neutralA / neutralZoneCount,
      neutralB / neutralZoneCount,
    );
    final trust = (neutralZoneCount / math.max(globalCount, 1) * 2.8).clamp(0.0, 1.0);
    return LabColor(
      global.l * (1.0 - trust) + neutral.l * trust,
      global.a * (1.0 - trust) + neutral.a * trust,
      global.b * (1.0 - trust) + neutral.b * trust,
    );
  }

  return _LabStyleProfile(
    toneCurve: toneCurve,
    meanL: meanL,
    contrastRatio: (sigL / 18.0).clamp(0.72, 1.34),
    satBoost: ((sigA + sigB) / 18.0).clamp(0.82, 1.55),
    castStrength: math.sqrt(meanA * meanA + meanB * meanB).clamp(0.0, 45.0) / 45.0,
    neutralConfidence: neutralConfidence,
    shadow: zone(
      fallbackL: 17.5,
      globalL: sGlobalL, globalA: sGlobalA, globalB: sGlobalB, globalCount: sGlobalCount,
      neutralL: sNeutralL, neutralA: sNeutralA, neutralB: sNeutralB, neutralZoneCount: sNeutralCount,
    ),
    midtone: zone(
      fallbackL: 50.0,
      globalL: mGlobalL, globalA: mGlobalA, globalB: mGlobalB, globalCount: mGlobalCount,
      neutralL: mNeutralL, neutralA: mNeutralA, neutralB: mNeutralB, neutralZoneCount: mNeutralCount,
    ),
    highlight: zone(
      fallbackL: 82.5,
      globalL: hGlobalL, globalA: hGlobalA, globalB: hGlobalB, globalCount: hGlobalCount,
      neutralL: hNeutralL, neutralA: hNeutralA, neutralB: hNeutralB, neutralZoneCount: hNeutralCount,
    ),
  );
}

List<int> _channelCurve(List<int> styleHist) {
  final total = styleHist.fold(0, (a, b) => a + b);
  var cumul = 0.0;
  final styleCdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    cumul += styleHist[i] / total;
    styleCdf[i] = cumul;
  }

  final curve = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    final target = _neutralChannelCdf[i];
    var j = 0;
    while (j < 255 && styleCdf[j] < target) {
      j++;
    }
    curve[i] = j;
  }
  _monotonic(curve);
  return curve;
}

List<int> _softenCurve(List<int> curve, double strength) {
  final out = List<int>.filled(curve.length, 0);
  for (int i = 0; i < curve.length; i++) {
    out[i] = (i + (curve[i] - i) * strength).round().clamp(0, 255);
  }
  _monotonic(out);
  return out;
}

void _monotonic(List<int> curve) {
  for (int i = 1; i < curve.length; i++) {
    if (curve[i] < curve[i - 1]) curve[i] = curve[i - 1];
  }
}

_ZoneCast _resolvedCast(
  double globalA,
  double globalB,
  int globalCount,
  double neutralA,
  double neutralB,
  int neutralCount,
) {
  if (globalCount <= 10) return _ZoneCast.zero;
  final global = _ZoneCast(globalA / globalCount, globalB / globalCount, globalCount);
  if (neutralCount <= 10) {
    return _ZoneCast(global.a * 0.55, global.b * 0.55, global.count);
  }
  final neutral = _ZoneCast(neutralA / neutralCount, neutralB / neutralCount, neutralCount);
  final trust = (neutralCount / globalCount * 2.8).clamp(0.0, 1.0);
  return _ZoneCast(
    global.a * (1.0 - trust) + neutral.a * trust,
    global.b * (1.0 - trust) + neutral.b * trust,
    globalCount,
  );
}

RgbColor _applyChannelStyle(RgbColor rgb, _StyleProfile profile, _LabStyleProfile labProfile) {
  final r8 = (rgb.r * 255).round().clamp(0, 255);
  final g8 = (rgb.g * 255).round().clamp(0, 255);
  final b8 = (rgb.b * 255).round().clamp(0, 255);
  final lab = rgbToLab(RgbColor(
    profile.rCurve[r8] / 255.0,
    profile.gCurve[g8] / 255.0,
    profile.bCurve[b8] / 255.0,
  ));

  final neutralBoost = 0.12 * labProfile.neutralConfidence;
  final tintStrength = (0.14 +
          0.16 * labProfile.castStrength +
          neutralBoost +
          0.10 * profile.blueCastStrength)
      .clamp(0.12, 0.40);
  final zone = _weightedZoneCast(
    lab.l,
    profile.shadowCast,
    profile.midtoneCast,
    profile.highlightCast,
  );
  return labToRgb(LabColor(
    lab.l,
    (lab.a + tintStrength * zone.a).clamp(-110.0, 110.0),
    (lab.b + tintStrength * zone.b).clamp(-110.0, 110.0),
  ));
}

RgbColor _applyLabStyle(RgbColor rgb, _LabStyleProfile profile) {
  final lab = rgbToLab(rgb);
  final lBin = (lab.l * 255.0 / 100.0).round().clamp(0, 255);
  final l1 = profile.toneCurve[lBin] * 100.0 / 255.0;
  final lOut = (l1 - 50.0) * profile.contrastRatio + profile.meanL;
  final zone = _weightedLabZone(lOut, profile);
  final castAmount = 0.32 + 0.18 * profile.neutralConfidence;
  return labToRgb(LabColor(
    _softClipL(lOut),
    (lab.a * profile.satBoost + castAmount * zone.a).clamp(-110.0, 110.0),
    (lab.b * profile.satBoost + castAmount * zone.b).clamp(-110.0, 110.0),
  ));
}

RgbColor _protectMemoryColors(RgbColor original, RgbColor styled, _StyleProfile profile) {
  final lab = rgbToLab(original);
  var weight = 0.0;

  final skin = original.r > original.g &&
      original.g > original.b &&
      lab.l > 24 &&
      lab.l < 92 &&
      lab.a > 4 &&
      lab.a < 36 &&
      lab.b > 4 &&
      lab.b < 48;
  if (skin) weight = math.max(weight, 0.30);

  final foliage = original.g > original.r * 1.05 &&
      original.g > original.b * 1.05 &&
      lab.a < -4 &&
      lab.l > 18 &&
      lab.l < 82;
  if (foliage) weight = math.max(weight, 0.22);

  final sky = original.b > original.r &&
      original.b > original.g &&
      lab.b < -4 &&
      lab.l > 35;
  if (sky) {
    weight = math.max(weight, profile.blueCastStrength > 0.28 ? 0.10 : 0.24);
  }

  if (weight == 0.0) return styled;
  return RgbColor(
    styled.r * (1.0 - weight) + original.r * weight,
    styled.g * (1.0 - weight) + original.g * weight,
    styled.b * (1.0 - weight) + original.b * weight,
  ).clamp01();
}

_ZoneCast _weightedZoneCast(
  double l,
  _ZoneCast shadow,
  _ZoneCast midtone,
  _ZoneCast highlight,
) {
  final ws = _zoneWeight(l, 17.5, 25.0);
  final wm = _zoneWeight(l, 50.0, 25.0);
  final wh = _zoneWeight(l, 82.5, 25.0);
  final total = ws + wm + wh + 1e-10;
  return _ZoneCast(
    (ws * shadow.a + wm * midtone.a + wh * highlight.a) / total,
    (ws * shadow.b + wm * midtone.b + wh * highlight.b) / total,
    0,
  );
}

LabColor _weightedLabZone(double l, _LabStyleProfile profile) {
  final ws = _zoneWeight(l, profile.shadow.l, 22.0);
  final wm = _zoneWeight(l, profile.midtone.l, 22.0);
  final wh = _zoneWeight(l, profile.highlight.l, 22.0);
  final total = ws + wm + wh + 1e-10;
  return LabColor(
    (ws * profile.shadow.l + wm * profile.midtone.l + wh * profile.highlight.l) / total,
    (ws * profile.shadow.a + wm * profile.midtone.a + wh * profile.highlight.a) / total,
    (ws * profile.shadow.b + wm * profile.midtone.b + wh * profile.highlight.b) / total,
  );
}

double _labBlendWeight(double castStrength, double neutralConfidence) {
  return (0.74 - 0.56 * castStrength + 0.16 * neutralConfidence).clamp(0.22, 0.82);
}

double _styleStrength(_StyleProfile profile, _LabStyleProfile labProfile) {
  if (labProfile.castStrength > 0.35 && profile.blueCastStrength > 0.30) {
    return 0.18;
  }
  final evidence = labProfile.neutralConfidence;
  final castPenalty = labProfile.castStrength * 0.45;
  final bluePenalty = profile.blueCastStrength * 0.20;
  return (0.22 + evidence * 0.42 - castPenalty - bluePenalty).clamp(0.06, 0.70);
}

double _zoneWeight(double l, double center, double sigma) {
  final d = l - center;
  return math.exp(-0.5 * d * d / (sigma * sigma));
}

double _softClipL(double l) {
  if (l < 0) return l * 0.35;
  if (l > 100) return 100 + (l - 100) * 0.35;
  return l;
}

double _rgbSaturation(RgbColor rgb) {
  final maxC = math.max(rgb.r, math.max(rgb.g, rgb.b));
  final minC = math.min(rgb.r, math.min(rgb.g, rgb.b));
  if (maxC == 0) return 0;
  return (maxC - minC) / maxC;
}

double _stdDev(List<double> values, double mean) {
  final variance = values.fold(0.0, (sum, value) {
    final d = value - mean;
    return sum + d * d;
  }) / values.length;
  return math.sqrt(variance).clamp(0.001, double.infinity);
}

img.Image _downscale(img.Image image, int maxDim) {
  final side = math.max(image.width, image.height);
  if (side <= maxDim) return image;
  final scale = maxDim / side;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}
