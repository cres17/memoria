import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'color_utils.dart';

// ─── Zone color cast ─────────────────────────────────────────────────────────

/// Mean Lab a,b of all pixels that fall in a fixed luminance zone.
/// Shadow: L < 35  |  Midtone: 35 ≤ L < 65  |  Highlight: L ≥ 65
class ZoneCast {
  final double a, b;
  final int count;

  const ZoneCast({required this.a, required this.b, required this.count});

  static const zero = ZoneCast(a: 0, b: 0, count: 0);
}

// ─── Style profile ────────────────────────────────────────────────────────────

/// Complete extracted style profile.
/// Fully describes the color grade in a style image — enough to reproduce
/// the same look on any other photo.
class StyleProfile {
  /// Per-channel tone curves (256 entries, 8-bit input → 8-bit output).
  /// rCurve[i] = output value for input value i in the R channel.
  final List<int> rCurve, gCurve, bCurve;

  /// Zone Lab color casts (fixed L thresholds: 35, 65).
  final ZoneCast shadowCast;    // L < 35
  final ZoneCast midtoneCast;   // 35 ≤ L < 65
  final ZoneCast highlightCast; // L ≥ 65

  /// Mean luminance of the style image (for overall exposure reference).
  final double meanL;

  /// Mean blue dominance on blue pixels: max(0, B - max(R, G)).
  /// Range [0, 1], larger means stronger "blue subject" presence.
  final double blueDominance;

  /// Strength of blue cast measured from negative Lab b in blue pixels.
  /// Range [0, 1], larger means deeper blue/cyan style tendency.
  final double blueCastStrength;

  const StyleProfile({
    required this.rCurve,
    required this.gCurve,
    required this.bCurve,
    required this.shadowCast,
    required this.midtoneCast,
    required this.highlightCast,
    required this.meanL,
    required this.blueDominance,
    required this.blueCastStrength,
  });
}

// ─── Style analyzer ──────────────────────────────────────────────────────────

class StyleAnalyzer {
  /// Outlier rejection helper using standard deviation threshold (1.5 * stdDev).
  static double _rejectOutliersAndMean(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length <= 2) {
      return values.reduce((a, b) => a + b) / values.length;
    }
    double sum = 0.0;
    for (final v in values) sum += v;
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

  /// Fuse multiple StyleProfile objects into one.
  static StyleProfile fuseProfiles(List<StyleProfile> profiles) {
    if (profiles.isEmpty) {
      throw ArgumentError('Profiles list cannot be empty');
    }
    if (profiles.length == 1) {
      return profiles.first;
    }

    // Fuse per-channel tone curves
    final rCurve = List<int>.filled(256, 0);
    final gCurve = List<int>.filled(256, 0);
    final bCurve = List<int>.filled(256, 0);

    for (int i = 0; i < 256; i++) {
      final rVals = profiles.map((p) => p.rCurve[i].toDouble()).toList();
      final gVals = profiles.map((p) => p.gCurve[i].toDouble()).toList();
      final bVals = profiles.map((p) => p.bCurve[i].toDouble()).toList();

      rCurve[i] = _rejectOutliersAndMean(rVals).round().clamp(0, 255);
      gCurve[i] = _rejectOutliersAndMean(gVals).round().clamp(0, 255);
      bCurve[i] = _rejectOutliersAndMean(bVals).round().clamp(0, 255);
    }

    // Enforce curves monotonicity
    for (int i = 1; i < 256; i++) {
      if (rCurve[i] < rCurve[i - 1]) rCurve[i] = rCurve[i - 1];
      if (gCurve[i] < gCurve[i - 1]) gCurve[i] = gCurve[i - 1];
      if (bCurve[i] < bCurve[i - 1]) bCurve[i] = bCurve[i - 1];
    }

    // Fuse zone casts
    ZoneCast fuseZone(List<ZoneCast> casts) {
      final valid = casts.where((c) => c.count > 0).toList();
      if (valid.isEmpty) return ZoneCast.zero;
      final aVals = valid.map((c) => c.a).toList();
      final bVals = valid.map((c) => c.b).toList();
      final counts = valid.map((c) => c.count.toDouble()).toList();

      return ZoneCast(
        a: _rejectOutliersAndMean(aVals),
        b: _rejectOutliersAndMean(bVals),
        count: (_rejectOutliersAndMean(counts)).round(),
      );
    }

    final shadowCast = fuseZone(profiles.map((p) => p.shadowCast).toList());
    final midtoneCast = fuseZone(profiles.map((p) => p.midtoneCast).toList());
    final highlightCast = fuseZone(profiles.map((p) => p.highlightCast).toList());

    final meanL = _rejectOutliersAndMean(profiles.map((p) => p.meanL).toList());
    final blueDominance = _rejectOutliersAndMean(profiles.map((p) => p.blueDominance).toList());
    final blueCastStrength = _rejectOutliersAndMean(profiles.map((p) => p.blueCastStrength).toList());

    return StyleProfile(
      rCurve: rCurve,
      gCurve: gCurve,
      bCurve: bCurve,
      shadowCast: shadowCast,
      midtoneCast: midtoneCast,
      highlightCast: highlightCast,
      meanL: meanL,
      blueDominance: blueDominance,
      blueCastStrength: blueCastStrength,
    );
  }

  /// Neutral per-channel CDF: Gaussian N(μ=115, σ=55) in 8-bit space.
  /// Neutral per-channel CDF: Gaussian N(μ=115, σ=55) in 8-bit space.
  ///
  /// Represents a balanced, naturally-exposed photograph with no color cast.
  /// Any deviation of a style image's channel CDF from this represents the
  /// color grade applied to it.
  static final List<double> _neutralChannelCdf = _buildNeutralChannelCdf();

  static List<double> _buildNeutralChannelCdf() {
    const mu = 115.0, sigma = 55.0;
    final hist = List<double>.filled(256, 0.0);
    for (int i = 0; i < 256; i++) {
      final z = (i - mu) / sigma;
      hist[i] = math.exp(-0.5 * z * z);
    }
    final sum = hist.fold(0.0, (a, b) => a + b);
    double cumul = 0.0;
    final cdf = List<double>.filled(256, 0.0);
    for (int i = 0; i < 256; i++) {
      cumul += hist[i] / sum;
      cdf[i] = cumul;
    }
    return cdf;
  }

  /// Build a 256-entry tone curve that maps the neutral channel distribution
  /// to the style channel distribution (histogram matching).
  static List<int> _channelCurve(List<int> styleHist) {
    // Build style CDF
    final total = styleHist.fold(0, (a, b) => a + b);
    double cumul = 0.0;
    final styleCdf = List<double>.filled(256, 0.0);
    for (int i = 0; i < 256; i++) {
      cumul += styleHist[i] / total;
      styleCdf[i] = cumul;
    }

    // For each neutral quantile i, find j where style CDF reaches the same value.
    final curve = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      final target = _neutralChannelCdf[i];
      int j = 0;
      while (j < 255 && styleCdf[j] < target) {
        j++;
      }
      curve[i] = j;
    }

    // Enforce monotonicity (prevent hue inversions at curve extremes)
    for (int i = 1; i < 256; i++) {
      if (curve[i] < curve[i - 1]) curve[i] = curve[i - 1];
    }
    return curve;
  }

  /// Analyze [styleImage] and extract a complete [StyleProfile].
  ///
  /// Does NOT apply color-constancy normalization — the style's color character
  /// (temperature, tint, cast) is exactly what we want to capture.
  static StyleProfile analyze(img.Image styleImage) {
    // Downscale to max 512px for performance
    final maxDim = math.max(styleImage.width, styleImage.height);
    img.Image sc = styleImage;
    if (maxDim > 512) {
      final scale = 512.0 / maxDim;
      sc = img.copyResize(
        styleImage,
        width: (styleImage.width * scale).round(),
        height: (styleImage.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    // Per-channel histograms (8-bit)
    final rHist = List<int>.filled(256, 0);
    final gHist = List<int>.filled(256, 0);
    final bHist = List<int>.filled(256, 0);
    final blueBHist = List<int>.filled(256, 0);

    // Fixed zone Lab accumulators
    // Shadow:    L < 35
    // Midtone:   35 ≤ L < 65
    // Highlight: L ≥ 65
    var sSumA = 0.0, sSumB = 0.0;
    var mSumA = 0.0, mSumB = 0.0;
    var hSumA = 0.0, hSumB = 0.0;
    int sCount = 0, mCount = 0, hCount = 0;
    double sumL = 0.0;
    double blueDomSum = 0.0;
    double blueNegBSum = 0.0;
    int blueCount = 0;

    for (int y = 0; y < sc.height; y++) {
      for (int x = 0; x < sc.width; x++) {
        final px = sc.getPixel(x, y);
        final r = px.rNormalized.toDouble();
        final g = px.gNormalized.toDouble();
        final b = px.bNormalized.toDouble();

        // Accumulate per-channel histograms
        rHist[(r * 255).round().clamp(0, 255)]++;
        gHist[(g * 255).round().clamp(0, 255)]++;
        bHist[(b * 255).round().clamp(0, 255)]++;

        // Accumulate zone Lab stats
        final lab = rgbToLab(RgbColor(r, g, b));
        sumL += lab.l;

        // Track blue-only statistics so LUT generation can preserve blue styles.
        final blueDom = b - math.max(r, g);
        if (blueDom > 0.02) {
          blueCount++;
          blueDomSum += blueDom;
          blueNegBSum += (-lab.b).clamp(0.0, 110.0);
          blueBHist[(b * 255).round().clamp(0, 255)]++;
        }

        if (lab.l < 35.0) {
          sSumA += lab.a; sSumB += lab.b; sCount++;
        } else if (lab.l < 65.0) {
          mSumA += lab.a; mSumB += lab.b; mCount++;
        } else {
          hSumA += lab.a; hSumB += lab.b; hCount++;
        }
      }
    }

    final n = (sc.width * sc.height).toDouble();
    final blueDominance = blueCount > 0
        ? (blueDomSum / blueCount).clamp(0.0, 1.0)
        : 0.0;
    final blueCastStrength = blueCount > 0
        ? (blueNegBSum / (blueCount * 55.0)).clamp(0.0, 1.0)
        : 0.0;

    final rCurve = _channelCurve(rHist);
    final gCurve = _channelCurve(gHist);
    final bCurve = _channelCurve(bHist);

    // Blend in a blue-only B-curve when style image has enough blue pixels.
    if (blueCount > 500) {
      final blueCurve = _channelCurve(blueBHist);
      final blueRatio = (blueCount / n).clamp(0.0, 1.0);
      final baseWeight = (0.25 + 0.55 * blueRatio).clamp(0.0, 0.8);
      for (int i = 0; i < 256; i++) {
        final highMask = ((i - 32) / 223.0).clamp(0.0, 1.0);
        final w = baseWeight * highMask;
        bCurve[i] = ((1.0 - w) * bCurve[i] + w * blueCurve[i]).round().clamp(0, 255);
      }
      for (int i = 1; i < 256; i++) {
        if (bCurve[i] < bCurve[i - 1]) bCurve[i] = bCurve[i - 1];
      }
    }

    return StyleProfile(
      rCurve: rCurve,
      gCurve: gCurve,
      bCurve: bCurve,
      shadowCast: sCount > 10
          ? ZoneCast(a: sSumA / sCount, b: sSumB / sCount, count: sCount)
          : ZoneCast.zero,
      midtoneCast: mCount > 10
          ? ZoneCast(a: mSumA / mCount, b: mSumB / mCount, count: mCount)
          : ZoneCast.zero,
      highlightCast: hCount > 10
          ? ZoneCast(a: hSumA / hCount, b: hSumB / hCount, count: hCount)
          : ZoneCast.zero,
      meanL: sumL / n,
      blueDominance: blueDominance,
      blueCastStrength: blueCastStrength,
    );
  }
}

// ─── Legacy helpers (kept for backward compatibility with test tooling) ───────

/// Pre-computed neutral L CDF: N(μ=50, σ=18) in Lab space [0..100] → 256 bins.
class NeutralStats {
  static const double muL  = 50.0;
  static const double sigL = 18.0;
  static const double muA  = 0.0;
  static const double sigA = 8.0;
  static const double muB  = 0.0;
  static const double sigB = 8.0;

  static final List<double> cdf = _buildNeutralCdf();

  static List<double> _buildNeutralCdf() {
    const bins = 256;
    final hist = List<double>.filled(bins, 0.0);
    for (int i = 0; i < bins; i++) {
      final l = i * 100.0 / 255.0;
      final z = (l - muL) / sigL;
      hist[i] = math.exp(-0.5 * z * z);
    }
    final sum = hist.fold(0.0, (a, b) => a + b);
    double cumul = 0.0;
    final cdf = List<double>.filled(bins, 0.0);
    for (int i = 0; i < bins; i++) {
      cumul += hist[i] / sum;
      cdf[i] = cumul;
    }
    return cdf;
  }
}

/// CDF histogram matching — maps neutral CDF → style CDF.
List<double> buildToneCurve(List<double> neutralCdf, List<double> styleCdf) {
  final curve = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final target = neutralCdf[i];
    int j = 0;
    while (j < 255 && styleCdf[j] < target) {
      j++;
    }
    curve[i] = j.toDouble();
  }
  return enforceMonotonic(curve);
}

List<double> enforceMonotonic(List<double> curve) {
  final result = List<double>.from(curve);
  for (int i = 1; i < result.length; i++) {
    if (result[i] < result[i - 1]) result[i] = result[i - 1];
  }
  return result;
}

// ─── Style profile UI helpers ─────────────────────────────────────────────────

/// Extract 4 representative colors from a style image via coarse quantization.
List<Color> extractPalette(img.Image image) {
  final sc = image.width > 128 || image.height > 128
      ? img.copyResize(image, width: 64, height: 64, interpolation: img.Interpolation.linear)
      : image;

  // Divide into 4 quadrants and take mean color of each
  final colors = <Color>[];
  final hw = sc.width ~/ 2, hh = sc.height ~/ 2;
  final regions = [
    [0, 0, hw, hh],
    [hw, 0, sc.width, hh],
    [0, hh, hw, sc.height],
    [hw, hh, sc.width, sc.height],
  ];
  for (final r in regions) {
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    for (int y = r[1]; y < r[3]; y++) {
      for (int x = r[0]; x < r[2]; x++) {
        final px = sc.getPixel(x, y);
        sumR += px.rNormalized;
        sumG += px.gNormalized;
        sumB += px.bNormalized;
        count++;
      }
    }
    if (count > 0) {
      colors.add(Color.fromARGB(
        255,
        (sumR / count * 255).round().clamp(0, 255),
        (sumG / count * 255).round().clamp(0, 255),
        (sumB / count * 255).round().clamp(0, 255),
      ));
    }
  }
  return colors;
}

/// Derive style tags from a [StyleProfile].
List<String> deriveStyleTags(StyleProfile profile) {
  final tags = <String>[];

  // Luminance
  if (profile.meanL < 35) {
    tags.add('Dark');
  } else if (profile.meanL > 65) {
    tags.add('Bright');
  } else {
    tags.add('Natural');
  }

  // Color temperature from midtone cast Lab b: positive=warm, negative=cool
  if (profile.midtoneCast.b > 6) {
    tags.add('Warm');
  } else if (profile.midtoneCast.b < -6) {
    tags.add('Cool');
  }

  // Blue style
  if (profile.blueCastStrength > 0.3) {
    tags.add('Ocean');
  } else if (profile.blueDominance > 0.15) {
    tags.add('Blue');
  }

  // Green cast
  if (profile.midtoneCast.a < -5) {
    tags.add('Green');
  }

  // Skin/sunset tones
  if (profile.midtoneCast.a > 6 && profile.midtoneCast.b > 8) {
    tags.add('Warm Skin');
  }

  // Vintage: de-saturated + warm shadows
  if (profile.shadowCast.b > 4 && profile.meanL < 55) {
    tags.add('Vintage');
  }

  // Moody: dark with teal shadows
  if (profile.shadowCast.b < -4 && profile.meanL < 50) {
    tags.add('Moody');
  }

  return tags.take(3).toList();
}
