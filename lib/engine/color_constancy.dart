import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Color Constancy normalization — Part 3 Fix #1.
///
/// Corrects illuminant bias in the style image before LUT generation.
/// Combines Gray World (per-channel mean equalization) and
/// White Patch (98th-percentile normalization) with an adaptive alpha.
///
/// Pipeline: normalize(img, illuminantStrength) returns corrected image.
class ColorConstancyNormalizer {
  // ── Gray World ──────────────────────────────────────────────────────────────
  /// Per-channel mean equalization.
  /// Scales each channel so its mean equals the average of all channel means.
  static img.Image grayWorld(img.Image src) {
    final stats = _channelStats(src);
    final muAvg = (stats.muR + stats.muG + stats.muB) / 3.0;
    final scaleR = muAvg / stats.muR.clamp(1e-6, double.infinity);
    final scaleG = muAvg / stats.muG.clamp(1e-6, double.infinity);
    final scaleB = muAvg / stats.muB.clamp(1e-6, double.infinity);
    return _scaleChannels(src, scaleR, scaleG, scaleB);
  }

  // ── White Patch ─────────────────────────────────────────────────────────────
  /// Per-channel 98th-percentile normalization.
  /// Maps brightest pixels (per channel) to 1.0.
  static img.Image whitePatch(img.Image src) {
    final maxR = _channelPercentile(src, _Channel.r, 0.98).clamp(1e-6, 1.0);
    final maxG = _channelPercentile(src, _Channel.g, 0.98).clamp(1e-6, 1.0);
    final maxB = _channelPercentile(src, _Channel.b, 0.98).clamp(1e-6, 1.0);
    return _scaleChannels(src, 1.0 / maxR, 1.0 / maxG, 1.0 / maxB);
  }

  // ── Adaptive blend ──────────────────────────────────────────────────────────
  /// Blends Gray World and White Patch based on measured illuminant strength.
  ///
  /// illuminantStrength is computed as the max channel deviation from neutral
  /// (channel mean / average-of-means - 1), clamped to [0, 1].
  ///
  /// Alpha rules (from Part 3 spec):
  ///   < 0.15 → α = 0.0  (no correction)
  ///   0.15–0.30 → α = 0.3  (mild Gray World)
  ///   > 0.30 → α = 0.7  (strong mixed correction)
  static img.Image normalize(img.Image src) {
    final strength = illuminantStrength(src);
    final double alpha;
    if (strength < 0.15) {
      alpha = 0.0;
    } else if (strength < 0.30) {
      alpha = 0.3;
    } else {
      alpha = 0.7;
    }

    if (alpha == 0.0) return src; // no correction needed

    final gw = grayWorld(src);
    final wp = whitePatch(src);
    return _blend(gw, wp, alpha);
  }

  /// Measures illuminant strength as max normalized channel deviation.
  static double illuminantStrength(img.Image src) {
    final stats = _channelStats(src);
    final muAvg = (stats.muR + stats.muG + stats.muB) / 3.0;
    if (muAvg < 1e-6) return 0.0;
    final devR = (stats.muR / muAvg - 1.0).abs();
    final devG = (stats.muG / muAvg - 1.0).abs();
    final devB = (stats.muB / muAvg - 1.0).abs();
    return math.max(devR, math.max(devG, devB)).clamp(0.0, 1.0);
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static _RgbStats _channelStats(img.Image src) {
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        sumR += px.rNormalized;
        sumG += px.gNormalized;
        sumB += px.bNormalized;
        count++;
      }
    }
    final n = count.toDouble().clamp(1.0, double.infinity);
    return _RgbStats(sumR / n, sumG / n, sumB / n);
  }

  static double _channelPercentile(
      img.Image src, _Channel ch, double p) {
    final values = <double>[];
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        switch (ch) {
          case _Channel.r: values.add(px.rNormalized.toDouble()); break;
          case _Channel.g: values.add(px.gNormalized.toDouble()); break;
          case _Channel.b: values.add(px.bNormalized.toDouble()); break;
        }
      }
    }
    values.sort();
    final idx = ((values.length - 1) * p).round();
    return values[idx];
  }

  static img.Image _scaleChannels(
      img.Image src, double sr, double sg, double sb) {
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final px = src.getPixel(x, y);
        final r = (px.rNormalized * sr).clamp(0.0, 1.0);
        final g = (px.gNormalized * sg).clamp(0.0, 1.0);
        final b = (px.bNormalized * sb).clamp(0.0, 1.0);
        out.setPixelRgb(x, y,
          (r * 255).round(), (g * 255).round(), (b * 255).round());
      }
    }
    return out;
  }

  /// Linear blend: result = gw * alpha + wp * (1 - alpha)
  static img.Image _blend(img.Image gw, img.Image wp, double alpha) {
    final out = img.Image(width: gw.width, height: gw.height);
    for (int y = 0; y < gw.height; y++) {
      for (int x = 0; x < gw.width; x++) {
        final pg = gw.getPixel(x, y);
        final pw = wp.getPixel(x, y);
        final r = (pg.rNormalized * alpha + pw.rNormalized * (1 - alpha)).clamp(0.0, 1.0);
        final g = (pg.gNormalized * alpha + pw.gNormalized * (1 - alpha)).clamp(0.0, 1.0);
        final b = (pg.bNormalized * alpha + pw.bNormalized * (1 - alpha)).clamp(0.0, 1.0);
        out.setPixelRgb(x, y,
          (r * 255).round(), (g * 255).round(), (b * 255).round());
      }
    }
    return out;
  }
}

enum _Channel { r, g, b }

class _RgbStats {
  final double muR, muG, muB;
  const _RgbStats(this.muR, this.muG, this.muB);
}
