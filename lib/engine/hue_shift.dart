import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'color_constancy.dart';

/// Hue Shift extractor — Part 3 Fix #2.
///
/// Extracts the hue shift introduced by the style image relative to a
/// neutral (illuminant-corrected) baseline, using circular K-means (k=8).
///
/// Algorithm:
///   1. Compute neutral = GrayWorld(reference)
///   2. Extract valid pixel hues (S > 0.15, 0.1 < L < 0.9) from both
///   3. Cluster each set with circular K-means (k=8)
///   4. Match clusters (nearest neighbor) → Δhue per cluster
class HueShiftExtractor {
  static const int k = 8;

  /// Extract 8 hue shift clusters from a style image.
  static List<HueCluster> extract(img.Image styleImage) {
    // 1. Neutral estimate via Gray World
    final neutral = ColorConstancyNormalizer.grayWorld(styleImage);

    // 2. Extract valid hues
    final huesStyle   = _extractValidHues(styleImage);
    final huesNeutral = _extractValidHues(neutral);

    if (huesStyle.isEmpty || huesNeutral.isEmpty) return [];

    // 3. Circular K-means on each
    final centersStyle   = circularKMeans(huesStyle,   k);
    final centersNeutral = circularKMeans(huesNeutral, k);

    // 4. Match & compute Δhue
    final shifts = <HueCluster>[];
    for (int i = 0; i < k; i++) {
      final nearestNeutral = _findNearestCircular(
          centersStyle[i], centersNeutral);
      final delta = _circularDiff(centersStyle[i], nearestNeutral);
      shifts.add(HueCluster(
        hueCenter: centersStyle[i],
        deltaHue: delta,
      ));
    }
    return shifts;
  }

  /// Circular K-means clustering on hue values (degrees 0–360).
  static List<double> circularKMeans(List<double> hues, int clusters) {
    if (hues.isEmpty) return List.filled(clusters, 0.0);

    // Initialise centers evenly spaced (good starting point for hue wheel)
    var centers = List<double>.generate(clusters, (i) => i * 360.0 / clusters);

    const maxIter = 50;
    for (int iter = 0; iter < maxIter; iter++) {
      // Assign each hue to nearest center
      final assignments = List<int>.filled(hues.length, 0);
      for (int hi = 0; hi < hues.length; hi++) {
        double minDist = double.infinity;
        int best = 0;
        for (int ci = 0; ci < clusters; ci++) {
          final d = _circularDistance(hues[hi], centers[ci]);
          if (d < minDist) { minDist = d; best = ci; }
        }
        assignments[hi] = best;
      }

      // Recompute centers using circular mean
      final newCenters = List<double>.from(centers);
      for (int ci = 0; ci < clusters; ci++) {
        final clusterHues = <double>[];
        for (int hi = 0; hi < hues.length; hi++) {
          if (assignments[hi] == ci) clusterHues.add(hues[hi]);
        }
        if (clusterHues.isNotEmpty) {
          newCenters[ci] = _circularMean(clusterHues);
        }
      }

      // Check convergence
      bool converged = true;
      for (int ci = 0; ci < clusters; ci++) {
        if (_circularDistance(centers[ci], newCenters[ci]) > 0.5) {
          converged = false;
          break;
        }
      }
      centers = newCenters;
      if (converged) break;
    }

    centers.sort();
    return centers;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static List<double> _extractValidHues(img.Image image) {
    final hues = <double>[];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final r = px.rNormalized.toDouble();
        final g = px.gNormalized.toDouble();
        final b = px.bNormalized.toDouble();
        final hsl = _rgbToHsl(r, g, b);
        // Filter: saturation > 0.15, lightness not extreme
        if (hsl.s > 0.15 && hsl.l > 0.1 && hsl.l < 0.9) {
          hues.add(hsl.h * 360.0); // hue in degrees
        }
      }
    }
    return hues;
  }

  static double _findNearestCircular(double hue, List<double> centers) {
    double minDist = double.infinity;
    double nearest = centers.first;
    for (final c in centers) {
      final d = _circularDistance(hue, c);
      if (d < minDist) { minDist = d; nearest = c; }
    }
    return nearest;
  }

  /// Circular distance between two hue values in [0, 360).
  static double _circularDistance(double h1, double h2) {
    final diff = (h1 - h2).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  /// Signed circular difference h1 - nearest(h2) in [-180, 180].
  static double _circularDiff(double h1, double h2) {
    double diff = h1 - h2;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  /// Circular mean using unit-vector averaging.
  static double _circularMean(List<double> hues) {
    double sinSum = 0, cosSum = 0;
    for (final h in hues) {
      final rad = h * math.pi / 180.0;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }
    final meanRad = math.atan2(sinSum / hues.length, cosSum / hues.length);
    final deg = meanRad * 180.0 / math.pi;
    return (deg + 360) % 360;
  }

  static _HslColor _rgbToHsl(double r, double g, double b) {
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final l = (max + min) / 2.0;

    if (max == min) return _HslColor(0, 0, l);

    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

    double h;
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6.0;

    return _HslColor(h, s, l);
  }
}

/// Result of hue shift analysis for a single cluster.
class HueCluster {
  /// Center hue of this cluster in the style image (degrees 0–360).
  final double hueCenter;

  /// How much this hue has shifted from neutral (degrees, signed).
  /// Positive = shifted clockwise (toward higher hue), negative = counter-clockwise.
  final double deltaHue;

  const HueCluster({required this.hueCenter, required this.deltaHue});

  @override
  String toString() =>
      'HueCluster(center: ${hueCenter.toStringAsFixed(1)}°, Δ: ${deltaHue.toStringAsFixed(1)}°)';
}

class _HslColor {
  final double h, s, l;
  const _HslColor(this.h, this.s, this.l);
}
