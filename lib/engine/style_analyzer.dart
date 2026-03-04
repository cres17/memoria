import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'color_utils.dart';

/// Neutral reference constants (fixed — do NOT use input image stats)
class NeutralStats {
  static const double muL    = 50.0;
  static const double sigL   = 18.0;
  static const double muA    = 0.0;
  static const double sigA   = 8.0;
  static const double muB    = 0.0;
  static const double sigB   = 8.0;

  /// Pre-computed neutral L CDF (256 bins) for a N(50,18) distribution
  /// approximated as a uniform-ish ramp (used for CDF matching baseline).
  static final List<double> cdf = _buildNeutralCdf();

  static List<double> _buildNeutralCdf() {
    // Gaussian N(muL=50, sigL=18) mapped to [0,255]
    // L ∈ [0,100], we map to 0..255 via L*255/100
    const bins = 256;
    final hist = List<double>.filled(bins, 0.0);
    for (int i = 0; i < bins; i++) {
      final l = i * 100.0 / 255.0; // L in [0, 100]
      final z = (l - muL) / sigL;
      hist[i] = math.exp(-0.5 * z * z);
    }
    // normalise
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

class StyleStats {
  final double muL, sigL, muA, sigA, muB, sigB;
  final List<double> cdf; // 256 bins

  const StyleStats({
    required this.muL, required this.sigL,
    required this.muA, required this.sigA,
    required this.muB, required this.sigB,
    required this.cdf,
  });
}

class StyleAnalyzer {
  /// Analyse the style image and return statistics.
  static StyleStats analyze(img.Image styleImage) {
    // Downscale to max 512px
    final maxDim = math.max(styleImage.width, styleImage.height);
    img.Image scaled = styleImage;
    if (maxDim > 512) {
      final scale = 512.0 / maxDim;
      scaled = img.copyResize(
        styleImage,
        width: (styleImage.width * scale).round(),
        height: (styleImage.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    final lValues  = <double>[];
    final aValues  = <double>[];
    final bValues  = <double>[];
    final lHist    = List<int>.filled(256, 0);

    for (int y = 0; y < scaled.height; y++) {
      for (int x = 0; x < scaled.width; x++) {
        final px = scaled.getPixel(x, y);
        final r = px.rNormalized;
        final g = px.gNormalized;
        final b = px.bNormalized;
        final lab = rgbToLab(RgbColor(r, g, b));

        lValues.add(lab.l);
        aValues.add(lab.a);
        bValues.add(lab.b);

        // Map L (0..100) → bin (0..255)
        final bin = (lab.l * 255.0 / 100.0).round().clamp(0, 255);
        lHist[bin]++;
      }
    }

    final n = lValues.length.toDouble();
    final muL  = lValues.fold(0.0, (s, v) => s + v) / n;
    final muA  = aValues.fold(0.0, (s, v) => s + v) / n;
    final muB  = bValues.fold(0.0, (s, v) => s + v) / n;
    final sigL = _std(lValues, muL);
    final sigA = _std(aValues, muA);
    final sigB = _std(bValues, muB);

    // Build CDF
    final total  = lHist.fold(0, (a, b) => a + b);
    double cumul = 0.0;
    final cdf    = List<double>.filled(256, 0.0);
    for (int i = 0; i < 256; i++) {
      cumul += lHist[i] / total;
      cdf[i] = cumul;
    }

    return StyleStats(
      muL: muL, sigL: sigL,
      muA: muA, sigA: sigA,
      muB: muB, sigB: sigB,
      cdf: cdf,
    );
  }

  static double _std(List<double> vals, double mean) {
    if (vals.isEmpty) return 1.0;
    final variance = vals.fold(0.0, (s, v) {
      final d = v - mean;
      return s + d * d;
    }) / vals.length;
    return math.sqrt(variance).clamp(0.001, double.infinity);
  }
}

/// CDF histogram matching to build a 256-point tone curve.
/// Maps neutral CDF → style CDF.
List<double> buildToneCurve(List<double> neutralCdf, List<double> styleCdf) {
  final curve = List<double>.filled(256, 0.0);

  for (int i = 0; i < 256; i++) {
    final target = neutralCdf[i];
    // Find j in styleCdf where styleCdf[j] >= target
    int j = 0;
    while (j < 255 && styleCdf[j] < target) j++;
    curve[i] = j.toDouble();
  }

  // Enforce monotonicity
  return enforceMonotonic(curve);
}

List<double> enforceMonotonic(List<double> curve) {
  final result = List<double>.from(curve);
  for (int i = 1; i < result.length; i++) {
    if (result[i] < result[i - 1]) result[i] = result[i - 1];
  }
  return result;
}
