import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'color_utils.dart';

const int customLutDim = 65;

typedef CustomLutProgressCallback = void Function(
    String stage, double progress);

/// Lightweight checks that catch the most destructive LUT failures before a
/// generated filter is persisted. The thresholds intentionally allow a stylized
/// look; they only reject discontinuities, collapse, and broad hard clipping.
class LutSafetyReport {
  final bool validEncoding;
  final bool hasNonFiniteValues;
  final double interiorClipRatio;
  final double maxAdjacentDelta;
  final double neutralLuminanceRange;
  final int neutralInversions;
  final double primaryMinChroma;

  const LutSafetyReport({
    required this.validEncoding,
    required this.hasNonFiniteValues,
    required this.interiorClipRatio,
    required this.maxAdjacentDelta,
    required this.neutralLuminanceRange,
    required this.neutralInversions,
    required this.primaryMinChroma,
  });

  const LutSafetyReport.invalid()
      : validEncoding = false,
        hasNonFiniteValues = true,
        interiorClipRatio = 1.0,
        maxAdjacentDelta = double.infinity,
        neutralLuminanceRange = 0.0,
        neutralInversions = 1,
        primaryMinChroma = 0.0;

  bool get isSafe =>
      validEncoding &&
      !hasNonFiniteValues &&
      interiorClipRatio <= 0.08 &&
      maxAdjacentDelta <= 0.35 &&
      neutralInversions == 0 &&
      neutralLuminanceRange >= 0.55 &&
      primaryMinChroma >= 0.05;

  Map<String, dynamic> toJson() => {
        'validEncoding': validEncoding,
        'hasNonFiniteValues': hasNonFiniteValues,
        'interiorClipRatio': interiorClipRatio,
        'maxAdjacentDelta': maxAdjacentDelta,
        'neutralLuminanceRange': neutralLuminanceRange,
        'neutralInversions': neutralInversions,
        'primaryMinChroma': primaryMinChroma,
        'isSafe': isSafe,
      };
}

/// A persisted LUT must always be safe to apply. When a candidate is too
/// aggressive, we blend it back toward identity in deterministic steps.
class ConstrainedLutResult {
  final Uint8List bytes;
  final double appliedStrength;
  final LutSafetyReport report;
  final String? fallbackReason;

  const ConstrainedLutResult({
    required this.bytes,
    required this.appliedStrength,
    required this.report,
    this.fallbackReason,
  });
}

/// Diagnostics for the 1–5 reference-image fusion stage. These values are
/// safe to persist because they contain no image pixels or paths.
class ReferenceFusionDiagnostics {
  final int inputReferenceCount;
  final int usedReferenceCount;
  final int medoidIndex;
  final double confidence;
  final double medianStyleDistance;

  const ReferenceFusionDiagnostics({
    required this.inputReferenceCount,
    required this.usedReferenceCount,
    required this.medoidIndex,
    required this.confidence,
    required this.medianStyleDistance,
  });

  int get excludedReferenceCount => inputReferenceCount - usedReferenceCount;

  Map<String, dynamic> toJson() => {
        'inputReferenceCount': inputReferenceCount,
        'usedReferenceCount': usedReferenceCount,
        'excludedReferenceCount': excludedReferenceCount,
        'medoidIndex': medoidIndex,
        'confidence': confidence,
        'medianStyleDistance': medianStyleDistance,
      };
}

class CustomLutBuildResult {
  final Uint8List bytes;
  final ReferenceFusionDiagnostics fusion;

  const CustomLutBuildResult({
    required this.bytes,
    required this.fusion,
  });
}

Uint8List buildIdentityCustomLut({int dim = customLutDim}) {
  final values = Uint16List(dim * dim * dim * 3);
  final maxIndex = (dim - 1).toDouble();
  var i = 0;
  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        values[i++] = floatToHalf(r / maxIndex);
        values[i++] = floatToHalf(g / maxIndex);
        values[i++] = floatToHalf(b / maxIndex);
      }
    }
  }
  return values.buffer.asUint8List();
}

LutSafetyReport inspectCustomLutSafety(
  Uint8List lutBytes, {
  int dim = customLutDim,
}) {
  if (dim < 2 || lutBytes.offsetInBytes.isOdd) {
    return const LutSafetyReport.invalid();
  }

  final expectedBytes = dim * dim * dim * 3 * 2;
  if (lutBytes.lengthInBytes < expectedBytes) {
    return const LutSafetyReport.invalid();
  }

  final values = lutBytes.buffer.asUint16List(
    lutBytes.offsetInBytes,
    expectedBytes ~/ 2,
  );
  var hasNonFiniteValues = false;

  int indexOf(int r, int g, int b) => (r + g * dim + b * dim * dim) * 3;

  double valueAt(int r, int g, int b, int c) {
    final value = halfToFloat(values[indexOf(r, g, b) + c]);
    if (!value.isFinite) {
      hasNonFiniteValues = true;
      return 0.0;
    }
    return value;
  }

  var interiorCount = 0;
  var interiorClipped = 0;
  var maxAdjacentDelta = 0.0;

  void compareNeighbors(
    int r1,
    int g1,
    int b1,
    int r2,
    int g2,
    int b2,
  ) {
    final dr = valueAt(r1, g1, b1, 0) - valueAt(r2, g2, b2, 0);
    final dg = valueAt(r1, g1, b1, 1) - valueAt(r2, g2, b2, 1);
    final db = valueAt(r1, g1, b1, 2) - valueAt(r2, g2, b2, 2);
    final delta = math.sqrt(dr * dr + dg * dg + db * db);
    if (delta > maxAdjacentDelta) maxAdjacentDelta = delta;
  }

  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        final isInterior = r > 0 &&
            r < dim - 1 &&
            g > 0 &&
            g < dim - 1 &&
            b > 0 &&
            b < dim - 1;
        for (var c = 0; c < 3; c++) {
          final value = valueAt(r, g, b, c);
          if (isInterior) {
            interiorCount++;
            if (value <= 0.0001 || value >= 0.9999) interiorClipped++;
          }
        }
        if (r + 1 < dim) compareNeighbors(r, g, b, r + 1, g, b);
        if (g + 1 < dim) compareNeighbors(r, g, b, r, g + 1, b);
        if (b + 1 < dim) compareNeighbors(r, g, b, r, g, b + 1);
      }
    }
  }

  var previousLuminance = double.negativeInfinity;
  var firstNeutralLuminance = 0.0;
  var lastNeutralLuminance = 0.0;
  var neutralInversions = 0;
  for (var i = 0; i < dim; i++) {
    final r = valueAt(i, i, i, 0);
    final g = valueAt(i, i, i, 1);
    final b = valueAt(i, i, i, 2);
    final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    if (i == 0) firstNeutralLuminance = luminance;
    if (luminance + 0.001 < previousLuminance) neutralInversions++;
    previousLuminance = luminance;
    lastNeutralLuminance = luminance;
  }

  double chromaAt(int r, int g, int b) {
    final cr = valueAt(r, g, b, 0);
    final cg = valueAt(r, g, b, 1);
    final cb = valueAt(r, g, b, 2);
    return math.max(cr, math.max(cg, cb)) - math.min(cr, math.min(cg, cb));
  }

  final primaryMinChroma = math.min(
    chromaAt(dim - 1, 0, 0),
    math.min(chromaAt(0, dim - 1, 0), chromaAt(0, 0, dim - 1)),
  );

  return LutSafetyReport(
    validEncoding: true,
    hasNonFiniteValues: hasNonFiniteValues,
    interiorClipRatio:
        interiorCount == 0 ? 1.0 : interiorClipped / interiorCount,
    maxAdjacentDelta: maxAdjacentDelta,
    neutralLuminanceRange: lastNeutralLuminance - firstNeutralLuminance,
    neutralInversions: neutralInversions,
    primaryMinChroma: primaryMinChroma,
  );
}

ConstrainedLutResult constrainCustomLut(
  Uint8List lutBytes, {
  int dim = customLutDim,
  List<double> strengthSteps = const [1.0, 0.75, 0.5, 0.25],
}) {
  final originalReport = inspectCustomLutSafety(lutBytes, dim: dim);
  if (!originalReport.validEncoding || originalReport.hasNonFiniteValues) {
    final identity = buildIdentityCustomLut(dim: dim);
    return ConstrainedLutResult(
      bytes: identity,
      appliedStrength: 0.0,
      report: inspectCustomLutSafety(identity, dim: dim),
      fallbackReason: 'lut_safety_identity_fallback',
    );
  }

  for (final strength in strengthSteps) {
    final candidate = strength == 1.0
        ? Uint8List.fromList(lutBytes)
        : _blendLutWithIdentity(lutBytes, strength, dim: dim);
    final report = inspectCustomLutSafety(candidate, dim: dim);
    if (report.isSafe) {
      return ConstrainedLutResult(
        bytes: candidate,
        appliedStrength: strength,
        report: report,
        fallbackReason: strength == 1.0 ? null : 'lut_safety_strength_reduced',
      );
    }
  }

  final identity = buildIdentityCustomLut(dim: dim);
  return ConstrainedLutResult(
    bytes: identity,
    appliedStrength: 0.0,
    report: inspectCustomLutSafety(identity, dim: dim),
    fallbackReason: 'lut_safety_identity_fallback',
  );
}

Uint8List _blendLutWithIdentity(
  Uint8List lutBytes,
  double strength, {
  required int dim,
}) {
  final expectedBytes = dim * dim * dim * 3 * 2;
  if (lutBytes.offsetInBytes.isOdd || lutBytes.lengthInBytes < expectedBytes) {
    return buildIdentityCustomLut(dim: dim);
  }

  final source = lutBytes.buffer.asUint16List(
    lutBytes.offsetInBytes,
    expectedBytes ~/ 2,
  );
  final output = Uint16List(source.length);
  final maxIndex = (dim - 1).toDouble();
  var i = 0;
  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        final identity = [r / maxIndex, g / maxIndex, b / maxIndex];
        for (var c = 0; c < 3; c++) {
          final value = halfToFloat(source[i]);
          final safeValue = value.isFinite ? value : identity[c];
          output[i] = floatToHalf(
            identity[c] + (safeValue - identity[c]) * strength,
          );
          i++;
        }
      }
    }
  }
  return output.buffer.asUint8List();
}

Map<String, double> inspectCustomLutStyle(img.Image styleImage) {
  final profile = _analyzeStyle(styleImage);
  final labProfile = _analyzeLabStyle(styleImage);
  return {
    'neutralConfidence': labProfile.neutralConfidence,
    'castStrength': labProfile.castStrength,
    'blueCastStrength': profile.blueCastStrength,
    'curveStrength': profile.curveStrength,
    'styleStrength': _styleStrength(profile, labProfile),
    'labBlendWeight':
        _labBlendWeight(labProfile.castStrength, labProfile.neutralConfidence),
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
        final blend = _labBlendWeight(
            labProfile.castStrength, labProfile.neutralConfidence);
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

RgbColor applyCustomLut(Uint8List lutBytes, RgbColor rgb,
    {int dim = customLutDim}) {
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

  var sGlobalA = 0.0,
      sGlobalB = 0.0,
      mGlobalA = 0.0,
      mGlobalB = 0.0,
      hGlobalA = 0.0,
      hGlobalB = 0.0;
  var sNeutralA = 0.0,
      sNeutralB = 0.0,
      mNeutralA = 0.0,
      mNeutralB = 0.0,
      hNeutralA = 0.0,
      hNeutralB = 0.0;
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
        sGlobalA += lab.a;
        sGlobalB += lab.b;
        sGlobalCount++;
        if (isNeutral) {
          sNeutralA += lab.a;
          sNeutralB += lab.b;
          sNeutralCount++;
        }
      } else if (lab.l < 65.0) {
        mGlobalA += lab.a;
        mGlobalB += lab.b;
        mGlobalCount++;
        if (isNeutral) {
          mNeutralA += lab.a;
          mNeutralB += lab.b;
          mNeutralCount++;
        }
      } else {
        hGlobalA += lab.a;
        hGlobalB += lab.b;
        hGlobalCount++;
        if (isNeutral) {
          hNeutralA += lab.a;
          hNeutralB += lab.b;
          hNeutralCount++;
        }
      }
    }
  }

  final n = (sc.width * sc.height).toDouble();
  final blueCastStrength =
      blueCount > 0 ? (blueNegBSum / (blueCount * 55.0)).clamp(0.0, 1.0) : 0.0;
  final contentRisk = (highChromaCount / n).clamp(0.0, 1.0);
  final curveStrength =
      (0.86 - contentRisk * 0.22 + blueCastStrength * 0.08).clamp(0.62, 0.92);

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
      bCurve[i] =
          ((1.0 - w) * bCurve[i] + w * blueCurve[i]).round().clamp(0, 255);
    }
    _monotonic(bCurve);
  }

  return _StyleProfile(
    rCurve: rCurve,
    gCurve: gCurve,
    bCurve: bCurve,
    shadowCast: _resolvedCast(
        sGlobalA, sGlobalB, sGlobalCount, sNeutralA, sNeutralB, sNeutralCount),
    midtoneCast: _resolvedCast(
        mGlobalA, mGlobalB, mGlobalCount, mNeutralA, mNeutralB, mNeutralCount),
    highlightCast: _resolvedCast(
        hGlobalA, hGlobalB, hGlobalCount, hNeutralA, hNeutralB, hNeutralCount),
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
        sGlobalL += lab.l;
        sGlobalA += lab.a;
        sGlobalB += lab.b;
        sGlobalCount++;
        if (isNeutral) {
          sNeutralL += lab.l;
          sNeutralA += lab.a;
          sNeutralB += lab.b;
          sNeutralCount++;
        }
      } else if (lab.l < 65.0) {
        mGlobalL += lab.l;
        mGlobalA += lab.a;
        mGlobalB += lab.b;
        mGlobalCount++;
        if (isNeutral) {
          mNeutralL += lab.l;
          mNeutralA += lab.a;
          mNeutralB += lab.b;
          mNeutralCount++;
        }
      } else {
        hGlobalL += lab.l;
        hGlobalA += lab.a;
        hGlobalB += lab.b;
        hGlobalCount++;
        if (isNeutral) {
          hNeutralL += lab.l;
          hNeutralA += lab.a;
          hNeutralB += lab.b;
          hNeutralCount++;
        }
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
        ? LabColor(
            globalL / globalCount, globalA / globalCount, globalB / globalCount)
        : LabColor(fallbackL, meanA, meanB);
    if (neutralZoneCount <= 10) {
      return LabColor(global.l, global.a * 0.55, global.b * 0.55);
    }
    final neutral = LabColor(
      neutralL / neutralZoneCount,
      neutralA / neutralZoneCount,
      neutralB / neutralZoneCount,
    );
    final trust =
        (neutralZoneCount / math.max(globalCount, 1) * 2.8).clamp(0.0, 1.0);
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
    castStrength:
        math.sqrt(meanA * meanA + meanB * meanB).clamp(0.0, 45.0) / 45.0,
    neutralConfidence: neutralConfidence,
    shadow: zone(
      fallbackL: 17.5,
      globalL: sGlobalL,
      globalA: sGlobalA,
      globalB: sGlobalB,
      globalCount: sGlobalCount,
      neutralL: sNeutralL,
      neutralA: sNeutralA,
      neutralB: sNeutralB,
      neutralZoneCount: sNeutralCount,
    ),
    midtone: zone(
      fallbackL: 50.0,
      globalL: mGlobalL,
      globalA: mGlobalA,
      globalB: mGlobalB,
      globalCount: mGlobalCount,
      neutralL: mNeutralL,
      neutralA: mNeutralA,
      neutralB: mNeutralB,
      neutralZoneCount: mNeutralCount,
    ),
    highlight: zone(
      fallbackL: 82.5,
      globalL: hGlobalL,
      globalA: hGlobalA,
      globalB: hGlobalB,
      globalCount: hGlobalCount,
      neutralL: hNeutralL,
      neutralA: hNeutralA,
      neutralB: hNeutralB,
      neutralZoneCount: hNeutralCount,
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
  final global =
      _ZoneCast(globalA / globalCount, globalB / globalCount, globalCount);
  if (neutralCount <= 10) {
    return _ZoneCast(global.a * 0.55, global.b * 0.55, global.count);
  }
  final neutral =
      _ZoneCast(neutralA / neutralCount, neutralB / neutralCount, neutralCount);
  final trust = (neutralCount / globalCount * 2.8).clamp(0.0, 1.0);
  return _ZoneCast(
    global.a * (1.0 - trust) + neutral.a * trust,
    global.b * (1.0 - trust) + neutral.b * trust,
    globalCount,
  );
}

RgbColor _applyChannelStyle(
    RgbColor rgb, _StyleProfile profile, _LabStyleProfile labProfile) {
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

RgbColor _protectMemoryColors(
    RgbColor original, RgbColor styled, _StyleProfile profile) {
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
    (ws * profile.shadow.l +
            wm * profile.midtone.l +
            wh * profile.highlight.l) /
        total,
    (ws * profile.shadow.a +
            wm * profile.midtone.a +
            wh * profile.highlight.a) /
        total,
    (ws * profile.shadow.b +
            wm * profile.midtone.b +
            wh * profile.highlight.b) /
        total,
  );
}

double _labBlendWeight(double castStrength, double neutralConfidence) {
  return (0.74 - 0.56 * castStrength + 0.16 * neutralConfidence)
      .clamp(0.22, 0.82);
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
      }) /
      values.length;
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

class DecodedLut {
  final Float32List values;
  final int dim;

  DecodedLut(this.values, this.dim);
}

final Expando<DecodedLut> _lutCache = Expando<DecodedLut>();

DecodedLut decodeCustomLut(Uint8List bytes) {
  final cached = _lutCache[bytes];
  if (cached != null) return cached;

  const dim = customLutDim; // 65
  const numElements = dim * dim * dim * 3;

  final halfList =
      bytes.buffer.asUint16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
  final values = Float32List(numElements);

  for (int i = 0; i < numElements; i++) {
    values[i] = halfToFloat(halfList[i]);
  }

  final decoded = DecodedLut(values, dim);
  _lutCache[bytes] = decoded;
  return decoded;
}

DecodedLut? tryDecodeCustomLut(Uint8List? bytes) {
  if (bytes == null ||
      bytes.length < customLutDim * customLutDim * customLutDim * 3 * 2) {
    return null;
  }
  try {
    return decodeCustomLut(bytes);
  } on Object {
    // Invalid optional LUT data disables the LUT; the base adjustments remain.
    return null;
  }
}

RgbColor applyDecodedCustomLut(DecodedLut decoded, RgbColor rgb) {
  final values = decoded.values;
  final dim = decoded.dim;
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
      values[i],
      values[i + 1],
      values[i + 2],
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

(double, double, double) applyDecodedCustomLutFlat(
    DecodedLut decoded, double r, double g, double b) {
  final values = decoded.values;
  final dim = decoded.dim;
  final maxIdx = (dim - 1).toDouble();

  final ri = r * maxIdx;
  final gi = g * maxIdx;
  final bi = b * maxIdx;

  final r0 = ri.floor().clamp(0, dim - 2);
  final r1 = (r0 + 1).clamp(0, dim - 1);
  final g0 = gi.floor().clamp(0, dim - 2);
  final g1 = (g0 + 1).clamp(0, dim - 1);
  final b0 = bi.floor().clamp(0, dim - 2);
  final b1 = (b0 + 1).clamp(0, dim - 1);

  final rf = ri - r0;
  final gf = gi - g0;
  final bf = bi - b0;

  final i000 = (r0 + g0 * dim + b0 * dim * dim) * 3;
  final i100 = (r1 + g0 * dim + b0 * dim * dim) * 3;
  final i010 = (r0 + g1 * dim + b0 * dim * dim) * 3;
  final i110 = (r1 + g1 * dim + b0 * dim * dim) * 3;
  final i001 = (r0 + g0 * dim + b1 * dim * dim) * 3;
  final i101 = (r1 + g0 * dim + b1 * dim * dim) * 3;
  final i011 = (r0 + g1 * dim + b1 * dim * dim) * 3;
  final i111 = (r1 + g1 * dim + b1 * dim * dim) * 3;

  final r000 = values[i000];
  final g000 = values[i000 + 1];
  final b000 = values[i000 + 2];
  final r100 = values[i100];
  final g100 = values[i100 + 1];
  final b100 = values[i100 + 2];
  final r010 = values[i010];
  final g010 = values[i010 + 1];
  final b010 = values[i010 + 2];
  final r110 = values[i110];
  final g110 = values[i110 + 1];
  final b110 = values[i110 + 2];
  final r001 = values[i001];
  final g001 = values[i001 + 1];
  final b001 = values[i001 + 2];
  final r101 = values[i101];
  final g101 = values[i101 + 1];
  final b101 = values[i101 + 2];
  final r011 = values[i011];
  final g011 = values[i011 + 1];
  final b011 = values[i011 + 2];
  final r111 = values[i111];
  final g111 = values[i111 + 1];
  final b111 = values[i111 + 2];

  final r00 = r000 + (r100 - r000) * rf;
  final g00 = g000 + (g100 - g000) * rf;
  final b00 = b000 + (b100 - b000) * rf;

  final r10 = r010 + (r110 - r010) * rf;
  final g10 = g010 + (g110 - g010) * rf;
  final b10 = b010 + (b110 - b010) * rf;

  final r01 = r001 + (r101 - r001) * rf;
  final g01 = g001 + (g101 - g001) * rf;
  final b01 = b001 + (b101 - b001) * rf;

  final r11 = r011 + (r111 - r011) * rf;
  final g11 = g011 + (g111 - g011) * rf;
  final b11 = b011 + (b111 - b011) * rf;

  final r0L = r00 + (r10 - r00) * gf;
  final g0L = g00 + (g10 - g00) * gf;
  final b0L = b00 + (b10 - b00) * gf;

  final r1L = r01 + (r11 - r01) * gf;
  final g1L = g01 + (g11 - g01) * gf;
  final b1L = b01 + (b11 - b01) * gf;

  final rFinal = (r0L + (r1L - r0L) * bf).clamp(0.0, 1.0);
  final gFinal = (g0L + (g1L - g0L) * bf).clamp(0.0, 1.0);
  final bFinal = (b0L + (b1L - b0L) * bf).clamp(0.0, 1.0);

  return (rFinal, gFinal, bFinal);
}

class OklabStats {
  final double meanL, meanA, meanB;
  final double stdL, stdA, stdB;
  const OklabStats({
    required this.meanL,
    required this.meanA,
    required this.meanB,
    required this.stdL,
    required this.stdA,
    required this.stdB,
  });
}

OklabStats _analyzeOklabStats(img.Image styleImage) {
  final sc = _downscale(styleImage, 256);
  final lValues = <double>[];
  final aValues = <double>[];
  final bValues = <double>[];

  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final rgb = RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      );
      final ok = rgbToOklab(rgb);
      lValues.add(ok.l);
      aValues.add(ok.a);
      bValues.add(ok.b);
    }
  }

  final n = lValues.length.toDouble();
  final meanL = lValues.fold(0.0, (s, v) => s + v) / n;
  final meanA = aValues.fold(0.0, (s, v) => s + v) / n;
  final meanB = bValues.fold(0.0, (s, v) => s + v) / n;

  final stdL = _stdDev(lValues, meanL);
  final stdA = _stdDev(aValues, meanA);
  final stdB = _stdDev(bValues, meanB);

  return OklabStats(
    meanL: meanL,
    meanA: meanA,
    meanB: meanB,
    stdL: stdL,
    stdA: stdA,
    stdB: stdB,
  );
}

OklabStats _fuseOklabStats(List<OklabStats> statsList) {
  if (statsList.length == 1) return statsList.first;

  double fuseValues(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length <= 2) {
      return values.reduce((a, b) => a + b) / values.length;
    }
    double sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    double variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    final stdDev = math.sqrt(variance / values.length);
    if (stdDev < 1e-4) return mean;

    final filtered = <double>[];
    for (final v in values) {
      if ((v - mean).abs() <= 1.5 * stdDev) {
        filtered.add(v);
      }
    }
    if (filtered.isEmpty) return mean;
    return filtered.reduce((a, b) => a + b) / filtered.length;
  }

  final meanL = fuseValues(statsList.map((s) => s.meanL).toList());
  final meanA = fuseValues(statsList.map((s) => s.meanA).toList());
  final meanB = fuseValues(statsList.map((s) => s.meanB).toList());
  final stdL = fuseValues(statsList.map((s) => s.stdL).toList());
  final stdA = fuseValues(statsList.map((s) => s.stdA).toList());
  final stdB = fuseValues(statsList.map((s) => s.stdB).toList());

  return OklabStats(
    meanL: meanL,
    meanA: meanA,
    meanB: meanB,
    stdL: stdL,
    stdA: stdA,
    stdB: stdB,
  );
}

class Tps3D {
  final List<OklabColor> srcPoints;
  final List<OklabColor> dstPoints;

  late List<List<double>> w;
  late List<List<double>> v;

  Tps3D(this.srcPoints, this.dstPoints) {
    _solve();
  }

  void _solve() {
    final n = srcPoints.length;
    final size = n + 4;

    final m = List.generate(size, (_) => List<double>.filled(size, 0.0));
    final y = List.generate(size, (_) => List<double>.filled(3, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        if (i == j) {
          m[i][j] = 0.0;
        } else {
          final dx = srcPoints[i].l - srcPoints[j].l;
          final dy = srcPoints[i].a - srcPoints[j].a;
          final dz = srcPoints[i].b - srcPoints[j].b;
          m[i][j] = math.sqrt(dx * dx + dy * dy + dz * dz);
        }
      }
    }

    for (int i = 0; i < n; i++) {
      m[i][n] = 1.0;
      m[i][n + 1] = srcPoints[i].l;
      m[i][n + 2] = srcPoints[i].a;
      m[i][n + 3] = srcPoints[i].b;

      m[n][i] = 1.0;
      m[n + 1][i] = srcPoints[i].l;
      m[n + 2][i] = srcPoints[i].a;
      m[n + 3][i] = srcPoints[i].b;
    }

    for (int i = 0; i < n; i++) {
      y[i][0] = dstPoints[i].l;
      y[i][1] = dstPoints[i].a;
      y[i][2] = dstPoints[i].b;
    }

    final x = _solveLinearSystem(m, y);

    w = List.generate(n, (i) => [x[i][0], x[i][1], x[i][2]]);
    v = List.generate(4, (i) => [x[n + i][0], x[n + i][1], x[n + i][2]]);
  }

  OklabColor evaluate(OklabColor p) {
    double lOut = v[0][0] + v[1][0] * p.l + v[2][0] * p.a + v[3][0] * p.b;
    double aOut = v[0][1] + v[1][1] * p.l + v[2][1] * p.a + v[3][1] * p.b;
    double bOut = v[0][2] + v[1][2] * p.l + v[2][2] * p.a + v[3][2] * p.b;

    for (int i = 0; i < srcPoints.length; i++) {
      final dx = p.l - srcPoints[i].l;
      final dy = p.a - srcPoints[i].a;
      final dz = p.b - srcPoints[i].b;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);

      lOut += w[i][0] * dist;
      aOut += w[i][1] * dist;
      bOut += w[i][2] * dist;
    }

    return OklabColor(lOut, aOut, bOut);
  }

  List<List<double>> _solveLinearSystem(
      List<List<double>> a, List<List<double>> b) {
    final n = a.length;
    final ac = List.generate(n, (i) => List<double>.from(a[i]));
    final bc = List.generate(n, (i) => List<double>.from(b[i]));

    for (int i = 0; i < n; i++) {
      int pivot = i;
      for (int j = i + 1; j < n; j++) {
        if (ac[j][i].abs() > ac[pivot][i].abs()) {
          pivot = j;
        }
      }

      if (pivot != i) {
        final tempA = ac[i];
        ac[i] = ac[pivot];
        ac[pivot] = tempA;

        final tempB = bc[i];
        bc[i] = bc[pivot];
        bc[pivot] = tempB;
      }

      if (ac[i][i].abs() < 1e-9) {
        continue;
      }

      for (int j = i + 1; j < n; j++) {
        final factor = ac[j][i] / ac[i][i];
        for (int k = i; k < n; k++) {
          ac[j][k] -= factor * ac[i][k];
        }
        for (int k = 0; k < 3; k++) {
          bc[j][k] -= factor * bc[i][k];
        }
      }
    }

    final x = List.generate(n, (_) => List<double>.filled(3, 0.0));
    for (int i = n - 1; i >= 0; i--) {
      if (ac[i][i].abs() < 1e-9) continue;
      for (int k = 0; k < 3; k++) {
        double sum = bc[i][k];
        for (int j = i + 1; j < n; j++) {
          sum -= ac[i][j] * x[j][k];
        }
        x[i][k] = sum / ac[i][i];
      }
    }

    return x;
  }
}

List<OklabColor> _extractTpsControlPoints(img.Image image) {
  final sc = _downscale(image, 128);
  var sumSL = 0.0, sumSA = 0.0, sumSB = 0.0;
  int sCount = 0;
  var sumML = 0.0, sumMA = 0.0, sumMB = 0.0;
  int mCount = 0;
  var sumHL = 0.0, sumHA = 0.0, sumHB = 0.0;
  int hCount = 0;
  var sumWL = 0.0, sumWA = 0.0, sumWB = 0.0;
  int wCount = 0;

  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final rgb = RgbColor(px.rNormalized.toDouble(), px.gNormalized.toDouble(),
          px.bNormalized.toDouble());
      final ok = rgbToOklab(rgb);

      if (ok.l < 0.35) {
        sumSL += ok.l;
        sumSA += ok.a;
        sumSB += ok.b;
        sCount++;
      } else if (ok.l < 0.65) {
        sumML += ok.l;
        sumMA += ok.a;
        sumMB += ok.b;
        mCount++;
      } else {
        sumHL += ok.l;
        sumHA += ok.a;
        sumHB += ok.b;
        hCount++;
      }

      if (ok.l > 0.4 && ok.l < 0.8 && ok.a > 0.02 && ok.b > 0.02) {
        sumWL += ok.l;
        sumWA += ok.a;
        sumWB += ok.b;
        wCount++;
      }
    }
  }

  return [
    sCount > 5
        ? OklabColor(sumSL / sCount, sumSA / sCount, sumSB / sCount)
        : const OklabColor(0.15, 0.0, 0.0),
    mCount > 5
        ? OklabColor(sumML / mCount, sumMA / mCount, sumMB / mCount)
        : const OklabColor(0.50, 0.0, 0.0),
    hCount > 5
        ? OklabColor(sumHL / hCount, sumHA / hCount, sumHB / hCount)
        : const OklabColor(0.85, 0.0, 0.0),
    wCount > 5
        ? OklabColor(sumWL / wCount, sumWA / wCount, sumWB / wCount)
        : const OklabColor(0.60, 0.06, 0.06),
  ];
}

List<OklabColor> _fuseTpsControlPoints(List<List<OklabColor>> allPointsList) {
  if (allPointsList.length == 1) return allPointsList.first;
  final fused = <OklabColor>[];
  for (int i = 0; i < 4; i++) {
    double sumL = 0, sumA = 0, sumB = 0;
    for (final list in allPointsList) {
      sumL += list[i].l;
      sumA += list[i].a;
      sumB += list[i].b;
    }
    final len = allPointsList.length.toDouble();
    fused.add(OklabColor(sumL / len, sumA / len, sumB / len));
  }
  return fused;
}

List<double> fitMonotonicCubicSpline(List<double> xs, List<double> ys) {
  final n = xs.length;
  final ms = List<double>.filled(n, 0.0);
  final deltas = List<double>.filled(n - 1, 0.0);

  for (int i = 0; i < n - 1; i++) {
    deltas[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]);
  }

  ms[0] = deltas[0];
  for (int i = 1; i < n - 1; i++) {
    ms[i] = (deltas[i - 1] + deltas[i]) * 0.5;
  }
  ms[n - 1] = deltas[n - 2];

  for (int i = 0; i < n - 1; i++) {
    if (deltas[i].abs() < 1e-9) {
      ms[i] = 0.0;
      ms[i + 1] = 0.0;
    } else {
      final alpha = ms[i] / deltas[i];
      final beta = ms[i + 1] / deltas[i];
      final mag = alpha * alpha + beta * beta;
      if (mag > 9.0) {
        final tau = 3.0 / math.sqrt(mag);
        ms[i] = tau * alpha * deltas[i];
        ms[i + 1] = tau * beta * deltas[i];
      }
    }
  }

  final curve = List<double>.filled(256, 0.0);
  for (int x = 0; x < 256; x++) {
    final xVal = x.toDouble();
    int i = 0;
    while (i < n - 2 && xs[i + 1] < xVal) {
      i++;
    }
    final h = xs[i + 1] - xs[i];
    final t = (xVal - xs[i]) / h;

    final h00 = 2 * t * t * t - 3 * t * t + 1;
    final h10 = t * t * t - 2 * t * t + t;
    final h01 = -2 * t * t * t + 3 * t * t;
    final h11 = t * t * t - t * t;

    curve[x] =
        h00 * ys[i] + h10 * h * ms[i] + h01 * ys[i + 1] + h11 * h * ms[i + 1];
  }
  return curve;
}

List<int> smoothCurveSpline(List<int> curve) {
  final xs = [0.0, 32.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 255.0];
  final ys = xs.map((x) => curve[x.round()].toDouble()).toList();
  final smoothed = fitMonotonicCubicSpline(xs, ys);
  final out = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    out[i] = smoothed[i].round().clamp(0, 255);
  }
  return out;
}

({double strength, double size}) analyzeGrainParameters(img.Image image) {
  final sc = _downscale(image, 256);
  var sumDiff2 = 0.0;
  int count = 0;
  for (int y = 1; y < sc.height - 1; y += 2) {
    for (int x = 1; x < sc.width - 1; x += 2) {
      final px = sc.getPixel(x, y);
      final l = 0.2126 * px.rNormalized +
          0.7152 * px.gNormalized +
          0.0722 * px.bNormalized;

      final n1 = sc.getPixel(x - 1, y);
      final n2 = sc.getPixel(x + 1, y);
      final n3 = sc.getPixel(x, y - 1);
      final n4 = sc.getPixel(x, y + 1);

      final lB =
          (n1.rNormalized + n2.rNormalized + n3.rNormalized + n4.rNormalized) *
              0.25;
      final diff = (l - lB).abs();

      if (diff < 0.08) {
        sumDiff2 += diff * diff;
        count++;
      }
    }
  }

  final variance = count > 0 ? sumDiff2 / count : 0.0;
  final strength = (math.sqrt(variance) * 800.0).clamp(0.0, 75.0);
  final size = strength > 15.0 ? 1.4 : 1.1;

  return (strength: strength, size: size);
}

_StyleProfile _fuseStyleProfiles(List<_StyleProfile> profiles) {
  if (profiles.length == 1) return profiles.first;

  double fuseValues(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length <= 2) {
      return values.reduce((a, b) => a + b) / values.length;
    }
    double sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    double variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    final stdDev = math.sqrt(variance / values.length);
    if (stdDev < 1e-4) return mean;

    final filtered = <double>[];
    for (final v in values) {
      if ((v - mean).abs() <= 1.5 * stdDev) {
        filtered.add(v);
      }
    }
    if (filtered.isEmpty) return mean;
    return filtered.reduce((a, b) => a + b) / filtered.length;
  }

  List<int> fuseCurve(List<List<int>> curves) {
    final result = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      final values = curves.map((c) => c[i].toDouble()).toList();
      result[i] = fuseValues(values).round().clamp(0, 255);
    }
    _monotonic(result);
    return result;
  }

  final rCurve = fuseCurve(profiles.map((p) => p.rCurve).toList());
  final gCurve = fuseCurve(profiles.map((p) => p.gCurve).toList());
  final bCurve = fuseCurve(profiles.map((p) => p.bCurve).toList());

  _ZoneCast fuseZoneCast(List<_ZoneCast> casts) {
    final nonZeroCasts = casts.where((c) => c.count > 0).toList();
    if (nonZeroCasts.isEmpty) return _ZoneCast.zero;
    final as = nonZeroCasts.map((c) => c.a).toList();
    final bs = nonZeroCasts.map((c) => c.b).toList();
    final counts = nonZeroCasts.map((c) => c.count.toDouble()).toList();
    return _ZoneCast(
      fuseValues(as),
      fuseValues(bs),
      (counts.reduce((a, b) => a + b) / counts.length).round(),
    );
  }

  final shadowCast = fuseZoneCast(profiles.map((p) => p.shadowCast).toList());
  final midtoneCast = fuseZoneCast(profiles.map((p) => p.midtoneCast).toList());
  final highlightCast =
      fuseZoneCast(profiles.map((p) => p.highlightCast).toList());

  final blueCastStrength =
      fuseValues(profiles.map((p) => p.blueCastStrength).toList());
  final curveStrength =
      fuseValues(profiles.map((p) => p.curveStrength).toList());

  return _StyleProfile(
    rCurve: rCurve,
    gCurve: gCurve,
    bCurve: bCurve,
    shadowCast: shadowCast,
    midtoneCast: midtoneCast,
    highlightCast: highlightCast,
    blueCastStrength: blueCastStrength,
    curveStrength: curveStrength,
  );
}

_LabStyleProfile _fuseLabStyleProfiles(List<_LabStyleProfile> profiles) {
  if (profiles.length == 1) return profiles.first;

  double fuseValues(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length <= 2) {
      return values.reduce((a, b) => a + b) / values.length;
    }
    double sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    double variance = 0.0;
    for (final v in values) {
      variance += (v - mean) * (v - mean);
    }
    final stdDev = math.sqrt(variance / values.length);
    if (stdDev < 1e-4) return mean;

    final filtered = <double>[];
    for (final v in values) {
      if ((v - mean).abs() <= 1.5 * stdDev) {
        filtered.add(v);
      }
    }
    if (filtered.isEmpty) return mean;
    return filtered.reduce((a, b) => a + b) / filtered.length;
  }

  final toneCurve = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final values = profiles.map((p) => p.toneCurve[i]).toList();
    toneCurve[i] = fuseValues(values);
  }
  for (int i = 1; i < toneCurve.length; i++) {
    if (toneCurve[i] < toneCurve[i - 1]) toneCurve[i] = toneCurve[i - 1];
  }

  final meanL = fuseValues(profiles.map((p) => p.meanL).toList());
  final contrastRatio =
      fuseValues(profiles.map((p) => p.contrastRatio).toList());
  final satBoost = fuseValues(profiles.map((p) => p.satBoost).toList());
  final castStrength = fuseValues(profiles.map((p) => p.castStrength).toList());
  final neutralConfidence =
      fuseValues(profiles.map((p) => p.neutralConfidence).toList());

  LabColor fuseLabColor(List<LabColor> colors) {
    final ls = colors.map((c) => c.l).toList();
    final as = colors.map((c) => c.a).toList();
    final bs = colors.map((c) => c.b).toList();
    return LabColor(
      fuseValues(ls),
      fuseValues(as),
      fuseValues(bs),
    );
  }

  final shadow = fuseLabColor(profiles.map((p) => p.shadow).toList());
  final midtone = fuseLabColor(profiles.map((p) => p.midtone).toList());
  final highlight = fuseLabColor(profiles.map((p) => p.highlight).toList());

  return _LabStyleProfile(
    toneCurve: toneCurve,
    meanL: meanL,
    contrastRatio: contrastRatio,
    satBoost: satBoost,
    castStrength: castStrength,
    neutralConfidence: neutralConfidence,
    shadow: shadow,
    midtone: midtone,
    highlight: highlight,
  );
}

class _ReferenceFusionPlan {
  final List<int> includedIndices;
  final ReferenceFusionDiagnostics diagnostics;

  const _ReferenceFusionPlan({
    required this.includedIndices,
    required this.diagnostics,
  });
}

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) * 0.5;
}

double _labZoneDistance(LabColor a, LabColor b) {
  final l = (a.l - b.l).abs() / 100.0;
  final chroma = math.sqrt(
        math.pow((a.a - b.a) / 128.0, 2) + math.pow((a.b - b.b) / 128.0, 2),
      ) /
      math.sqrt(2.0);
  return (0.45 * l + 0.55 * chroma).clamp(0.0, 1.0);
}

/// Distance between two reference looks, not between two source images. The
/// descriptor intentionally ignores composition and uses only global color
/// characteristics that affect a generated LUT.
double _styleProfileDistance(_LabStyleProfile a, _LabStyleProfile b) {
  const curveSamples = [16, 64, 128, 192, 240];
  var curveDistance = 0.0;
  for (final index in curveSamples) {
    curveDistance += (a.toneCurve[index] - b.toneCurve[index]).abs() / 255.0;
  }
  curveDistance /= curveSamples.length;

  final zones = (_labZoneDistance(a.shadow, b.shadow) +
          _labZoneDistance(a.midtone, b.midtone) +
          _labZoneDistance(a.highlight, b.highlight)) /
      3.0;
  final meanLightness = (a.meanL - b.meanL).abs() / 100.0;
  final contrast = (a.contrastRatio - b.contrastRatio).abs() / 2.0;
  final saturation = (a.satBoost - b.satBoost).abs() / 1.5;
  final cast = (a.castStrength - b.castStrength).abs();

  return (0.28 * curveDistance +
          0.32 * zones +
          0.12 * meanLightness +
          0.10 * contrast.clamp(0.0, 1.0) +
          0.10 * saturation.clamp(0.0, 1.0) +
          0.08 * cast.clamp(0.0, 1.0))
      .clamp(0.0, 1.0);
}

_ReferenceFusionPlan _planReferenceFusion(List<_LabStyleProfile> profiles) {
  if (profiles.isEmpty) {
    throw ArgumentError('profiles cannot be empty');
  }
  if (profiles.length == 1) {
    return const _ReferenceFusionPlan(
      includedIndices: [0],
      diagnostics: ReferenceFusionDiagnostics(
        inputReferenceCount: 1,
        usedReferenceCount: 1,
        medoidIndex: 0,
        confidence: 1.0,
        medianStyleDistance: 0.0,
      ),
    );
  }

  final distances = List.generate(
    profiles.length,
    (_) => List<double>.filled(profiles.length, 0.0),
  );
  for (var i = 0; i < profiles.length; i++) {
    for (var j = i + 1; j < profiles.length; j++) {
      final distance = _styleProfileDistance(profiles[i], profiles[j]);
      distances[i][j] = distance;
      distances[j][i] = distance;
    }
  }

  var medoidIndex = 0;
  var medoidTotal = double.infinity;
  for (var i = 0; i < profiles.length; i++) {
    final total = distances[i].reduce((sum, value) => sum + value);
    if (total < medoidTotal) {
      medoidTotal = total;
      medoidIndex = i;
    }
  }

  final medoidDistances = distances[medoidIndex];
  final nonMedoidDistances = <double>[
    for (var i = 0; i < medoidDistances.length; i++)
      if (i != medoidIndex) medoidDistances[i],
  ];
  final medianDistance = _median(nonMedoidDistances);
  final consistency = (1.0 - medianDistance / 0.60).clamp(0.25, 1.0);

  // With only two references, neither image is an objectively safer outlier.
  // Preserve both and reduce the effect when their looks disagree.
  if (profiles.length == 2) {
    return _ReferenceFusionPlan(
      includedIndices: const [0, 1],
      diagnostics: ReferenceFusionDiagnostics(
        inputReferenceCount: 2,
        usedReferenceCount: 2,
        medoidIndex: medoidIndex,
        confidence: consistency,
        medianStyleDistance: medianDistance,
      ),
    );
  }

  final absoluteDeviations = nonMedoidDistances
      .map((value) => (value - medianDistance).abs())
      .toList();
  final mad = _median(absoluteDeviations);
  final cutoff = medianDistance + math.max(0.06, 2.5 * mad);
  final includedIndices = <int>[
    for (var i = 0; i < medoidDistances.length; i++)
      if (medoidDistances[i] <= cutoff) i,
  ];
  if (!includedIndices.contains(medoidIndex)) {
    includedIndices.add(medoidIndex);
    includedIndices.sort();
  }

  final retention = includedIndices.length / profiles.length;
  final confidence = ((0.25 + 0.75 * retention) * consistency).clamp(0.25, 1.0);
  return _ReferenceFusionPlan(
    includedIndices: includedIndices,
    diagnostics: ReferenceFusionDiagnostics(
      inputReferenceCount: profiles.length,
      usedReferenceCount: includedIndices.length,
      medoidIndex: medoidIndex,
      confidence: confidence,
      medianStyleDistance: medianDistance,
    ),
  );
}

/// Exposes only aggregate reference-fusion diagnostics for UI messaging and
/// tests. It does not retain image content.
ReferenceFusionDiagnostics inspectReferenceFusion(List<img.Image> styleImages) {
  if (styleImages.isEmpty) {
    throw ArgumentError('styleImages cannot be empty');
  }
  return _planReferenceFusion(styleImages.map(_analyzeLabStyle).toList())
      .diagnostics;
}

Uint8List buildCustomLutFromStyleImages(
  List<img.Image> styleImages, {
  int dim = customLutDim,
  CustomLutProgressCallback? onProgress,
}) {
  return buildCustomLutFromStyleImagesWithDiagnostics(
    styleImages,
    dim: dim,
    onProgress: onProgress,
  ).bytes;
}

CustomLutBuildResult buildCustomLutFromStyleImagesWithDiagnostics(
  List<img.Image> styleImages, {
  int dim = customLutDim,
  CustomLutProgressCallback? onProgress,
}) {
  if (styleImages.isEmpty) {
    throw ArgumentError('styleImages cannot be empty');
  }
  if (styleImages.length == 1) {
    return CustomLutBuildResult(
      bytes: buildCustomLutFromStyleImage(styleImages.first,
          dim: dim, onProgress: onProgress),
      fusion: const ReferenceFusionDiagnostics(
        inputReferenceCount: 1,
        usedReferenceCount: 1,
        medoidIndex: 0,
        confidence: 1.0,
        medianStyleDistance: 0.0,
      ),
    );
  }

  onProgress?.call('style_analyze', 0.15);
  final profiles = <_StyleProfile>[];
  final labProfiles = <_LabStyleProfile>[];
  final tpsCtrlPointsList = <List<OklabColor>>[];
  final oklabStatsList = <OklabStats>[];

  for (int i = 0; i < styleImages.length; i++) {
    final progressStep = 0.15 + (i / styleImages.length) * 0.30;
    onProgress?.call('style_analyze', progressStep);

    final profile = _analyzeStyle(styleImages[i]);
    final smoothedProfile = _StyleProfile(
      rCurve: smoothCurveSpline(profile.rCurve),
      gCurve: smoothCurveSpline(profile.gCurve),
      bCurve: smoothCurveSpline(profile.bCurve),
      shadowCast: profile.shadowCast,
      midtoneCast: profile.midtoneCast,
      highlightCast: profile.highlightCast,
      blueCastStrength: profile.blueCastStrength,
      curveStrength: profile.curveStrength,
    );
    profiles.add(smoothedProfile);

    final labProfile = _analyzeLabStyle(styleImages[i]);
    final smoothedLabProfile = _LabStyleProfile(
      toneCurve: fitMonotonicCubicSpline(
        [0.0, 32.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 255.0],
        [0.0, 32.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 255.0]
            .map((x) => labProfile.toneCurve[x.round()])
            .toList(),
      ),
      meanL: labProfile.meanL,
      contrastRatio: labProfile.contrastRatio,
      satBoost: labProfile.satBoost,
      castStrength: labProfile.castStrength,
      neutralConfidence: labProfile.neutralConfidence,
      shadow: labProfile.shadow,
      midtone: labProfile.midtone,
      highlight: labProfile.highlight,
    );
    labProfiles.add(smoothedLabProfile);

    oklabStatsList.add(_analyzeOklabStats(styleImages[i]));
    tpsCtrlPointsList.add(_extractTpsControlPoints(styleImages[i]));
  }

  onProgress?.call('lab_analyze', 0.45);
  final fusionPlan = _planReferenceFusion(labProfiles);
  final includedIndices = fusionPlan.includedIndices;
  final fusedProfile =
      _fuseStyleProfiles([for (final i in includedIndices) profiles[i]]);
  final fusedLabProfile =
      _fuseLabStyleProfiles([for (final i in includedIndices) labProfiles[i]]);
  final fusedOklabStats =
      _fuseOklabStats([for (final i in includedIndices) oklabStatsList[i]]);
  final fusedDstPoints = _fuseTpsControlPoints(
      [for (final i in includedIndices) tpsCtrlPointsList[i]]);

  final srcPoints = [
    const OklabColor(0.15, 0.0, 0.0),
    const OklabColor(0.50, 0.0, 0.0),
    const OklabColor(0.85, 0.0, 0.0),
    const OklabColor(0.60, 0.06, 0.06),
  ];
  final tps = Tps3D(srcPoints, fusedDstPoints);

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

        final channelRgb =
            _applyChannelStyle(original, fusedProfile, fusedLabProfile);
        final labRgb = _applyLabStyle(original, fusedLabProfile);
        final blend = _labBlendWeight(
            fusedLabProfile.castStrength, fusedLabProfile.neutralConfidence);
        final mixed = RgbColor(
          channelRgb.r * (1.0 - blend) + labRgb.r * blend,
          channelRgb.g * (1.0 - blend) + labRgb.g * blend,
          channelRgb.b * (1.0 - blend) + labRgb.b * blend,
        ).clamp01();

        final okCov = applyOklabCovarianceStyle(original, fusedOklabStats);
        final rgbCov = oklabToRgb(okCov);

        final okOrig = rgbToOklab(original);
        final okTps = tps.evaluate(okOrig);
        final rgbTps = oklabToRgb(okTps);

        final finalRgb = RgbColor(
          mixed.r * 0.40 + rgbCov.r * 0.30 + rgbTps.r * 0.30,
          mixed.g * 0.40 + rgbCov.g * 0.30 + rgbTps.g * 0.30,
          mixed.b * 0.40 + rgbCov.b * 0.30 + rgbTps.b * 0.30,
        ).clamp01();

        final protected =
            _protectMemoryColors(original, finalRgb, fusedProfile);

        final strength = (_styleStrength(fusedProfile, fusedLabProfile) *
                fusionPlan.diagnostics.confidence)
            .clamp(0.0, 1.0);
        final outputRgb = RgbColor(
          original.r * (1.0 - strength) + protected.r * strength,
          original.g * (1.0 - strength) + protected.g * strength,
          original.b * (1.0 - strength) + protected.b * strength,
        ).clamp01();

        lutData[lutIdx++] = floatToHalf(outputRgb.r);
        lutData[lutIdx++] = floatToHalf(outputRgb.g);
        lutData[lutIdx++] = floatToHalf(outputRgb.b);
      }
    }
  }

  return CustomLutBuildResult(
    bytes: lutData.buffer.asUint8List(),
    fusion: fusionPlan.diagnostics,
  );
}

OklabColor applyOklabCovarianceStyle(RgbColor rgb, OklabStats styleStats) {
  final ok = rgbToOklab(rgb);
  final lOut = (ok.l - 0.5) * (styleStats.stdL / 0.28) + styleStats.meanL;
  final aOut = ok.a * (styleStats.stdA / 0.08) + styleStats.meanA;
  final bOut = ok.b * (styleStats.stdB / 0.08) + styleStats.meanB;
  return OklabColor(lOut.clamp(0.0, 1.0), aOut, bOut);
}

Map<String, double> inspectCustomLutStyles(List<img.Image> styleImages) {
  if (styleImages.isEmpty) return {};
  if (styleImages.length == 1) return inspectCustomLutStyle(styleImages.first);

  final profiles = styleImages.map(_analyzeStyle).toList();
  final labProfiles = styleImages.map(_analyzeLabStyle).toList();

  final fusedProfile = _fuseStyleProfiles(profiles);
  final fusedLabProfile = _fuseLabStyleProfiles(labProfiles);

  return {
    'neutralConfidence': fusedLabProfile.neutralConfidence,
    'castStrength': fusedLabProfile.castStrength,
    'blueCastStrength': fusedProfile.blueCastStrength,
    'curveStrength': fusedProfile.curveStrength,
    'styleStrength': _styleStrength(fusedProfile, fusedLabProfile),
    'labBlendWeight': _labBlendWeight(
        fusedLabProfile.castStrength, fusedLabProfile.neutralConfidence),
  };
}
