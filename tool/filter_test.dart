// ignore_for_file: avoid_print
/// Standalone filter accuracy test (matches current lut_engine algorithm).
/// Usage:
///   dart run tool/filter_test.dart <original.jpg> <filtered.jpg> <out_dir>
///
/// 1) Extracts StyleProfile from <filtered.jpg>
/// 2) Generates LUT using current algorithm (per-channel curves + zone tint)
/// 3) Also generates LUT using old algorithm (Lab-only zone push) for comparison
/// 4) Applies both to <original.jpg>, saves results, prints ?E metrics

library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

// ?€?€?€ Color utils ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

const _xn = 0.95047, _yn = 1.00000, _zn = 1.08883;

double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _delin(double c) => c <= 0.0031308
    ? 12.92 * c
    : 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
double _f(double t) {
  const d = 6.0 / 29.0;
  return t > d * d * d ? math.pow(t, 1.0 / 3.0).toDouble() : t / (3 * d * d) + 4.0 / 29.0;
}
double _fi(double t) {
  const d = 6.0 / 29.0;
  return t > d ? t * t * t : 3 * d * d * (t - 4.0 / 29.0);
}

class Lab {
  final double l, a, b;
  const Lab(this.l, this.a, this.b);
}
class Rgb {
  final double r, g, b;
  const Rgb(this.r, this.g, this.b);
}

Lab rgbToLab(Rgb c) {
  final rl = _lin(c.r), gl = _lin(c.g), bl = _lin(c.b);
  final x = 0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl;
  final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
  final z = 0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl;
  return Lab(116 * _f(y / _yn) - 16, 500 * (_f(x / _xn) - _f(y / _yn)), 200 * (_f(y / _yn) - _f(z / _zn)));
}

Rgb labToRgb(Lab c) {
  final fy = (c.l + 16) / 116, fx = c.a / 500 + fy, fz = fy - c.b / 200;
  final x = _fi(fx) * _xn, y = _fi(fy) * _yn, z = _fi(fz) * _zn;
  final rl = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
  final gl = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
  final bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
  return Rgb(_delin(rl.clamp(0, 1)), _delin(gl.clamp(0, 1)), _delin(bl.clamp(0, 1)));
}

// ?€?€?€ Neutral channel CDF: N(Î¼=115, ?=55) in 8-bit ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

final List<double> _neutralChannelCdf = () {
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
}();

// ?€?€?€ StyleProfile ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

class ZoneCast {
  final double a, b;
  const ZoneCast(this.a, this.b);
  static const zero = ZoneCast(0, 0);
}

class StyleProfile {
  final List<int> rCurve, gCurve, bCurve;
  final ZoneCast shadowCast, midtoneCast, highlightCast;
  final double meanL;
  final double blueDominance;
  final double blueCastStrength;
  const StyleProfile({
    required this.rCurve, required this.gCurve, required this.bCurve,
    required this.shadowCast, required this.midtoneCast, required this.highlightCast,
    required this.meanL,
    required this.blueDominance,
    required this.blueCastStrength,
  });
}

List<int> _channelCurve(List<int> hist) {
  final total = hist.fold(0, (a, b) => a + b);
  double cumul = 0;
  final styleCdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    cumul += hist[i] / total;
    styleCdf[i] = cumul;
  }
  final curve = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    final target = _neutralChannelCdf[i];
    int j = 0;
    while (j < 255 && styleCdf[j] < target) {
      j++;
    }
    curve[i] = j;
  }
  for (int i = 1; i < 256; i++) {
    if (curve[i] < curve[i - 1]) curve[i] = curve[i - 1];
  }
  return curve;
}

List<int> _channelCurveFromPair(List<int> sourceHist, List<int> targetHist) {
  final sourceTotal = sourceHist.fold(0, (a, b) => a + b);
  final targetTotal = targetHist.fold(0, (a, b) => a + b);
  if (sourceTotal == 0 || targetTotal == 0) {
    return List<int>.generate(256, (i) => i);
  }

  double sCumul = 0.0, tCumul = 0.0;
  final sourceCdf = List<double>.filled(256, 0.0);
  final targetCdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    sCumul += sourceHist[i] / sourceTotal;
    tCumul += targetHist[i] / targetTotal;
    sourceCdf[i] = sCumul;
    targetCdf[i] = tCumul;
  }

  final curve = List<int>.filled(256, 0);
  for (int i = 0; i < 256; i++) {
    final targetQ = sourceCdf[i];
    int j = 0;
    while (j < 255 && targetCdf[j] < targetQ) {
      j++;
    }
    curve[i] = j;
  }
  for (int i = 1; i < 256; i++) {
    if (curve[i] < curve[i - 1]) curve[i] = curve[i - 1];
  }
  return curve;
}

StyleProfile analyzeStyle(img.Image image) {
  final maxDim = math.max(image.width, image.height);
  img.Image sc = image;
  if (maxDim > 512) {
    final scale = 512.0 / maxDim;
    sc = img.copyResize(image, width: (image.width * scale).round(), height: (image.height * scale).round());
  }
  final rHist = List<int>.filled(256, 0);
  final gHist = List<int>.filled(256, 0);
  final bHist = List<int>.filled(256, 0);
  final blueBHist = List<int>.filled(256, 0);
  var sSumA = 0.0, sSumB = 0.0, mSumA = 0.0, mSumB = 0.0, hSumA = 0.0, hSumB = 0.0;
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
      rHist[(r * 255).round().clamp(0, 255)]++;
      gHist[(g * 255).round().clamp(0, 255)]++;
      bHist[(b * 255).round().clamp(0, 255)]++;
      final lab = rgbToLab(Rgb(r, g, b));
      sumL += lab.l;
      final blueDom = b - math.max(r, g);
      if (blueDom > 0.02) {
        blueCount++;
        blueDomSum += blueDom;
        blueNegBSum += (-lab.b).clamp(0.0, 110.0);
        blueBHist[(b * 255).round().clamp(0, 255)]++;
      }
      if (lab.l < 35) { sSumA += lab.a; sSumB += lab.b; sCount++; }
      else if (lab.l < 65) { mSumA += lab.a; mSumB += lab.b; mCount++; }
      else { hSumA += lab.a; hSumB += lab.b; hCount++; }
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
    shadowCast: sCount > 10 ? ZoneCast(sSumA / sCount, sSumB / sCount) : ZoneCast.zero,
    midtoneCast: mCount > 10 ? ZoneCast(mSumA / mCount, mSumB / mCount) : ZoneCast.zero,
    highlightCast: hCount > 10 ? ZoneCast(hSumA / hCount, hSumB / hCount) : ZoneCast.zero,
    meanL: sumL / n,
    blueDominance: blueDominance,
    blueCastStrength: blueCastStrength,
  );
}

StyleProfile analyzeStyleFromPair(img.Image originalImage, img.Image filteredImage) {
  final maxDim = math.max(
    math.max(originalImage.width, originalImage.height),
    math.max(filteredImage.width, filteredImage.height),
  );
  img.Image src = originalImage;
  img.Image tgt = filteredImage;
  if (maxDim > 512) {
    final scale = 512.0 / maxDim;
    src = img.copyResize(
      originalImage,
      width: (originalImage.width * scale).round(),
      height: (originalImage.height * scale).round(),
    );
    tgt = img.copyResize(
      filteredImage,
      width: (filteredImage.width * scale).round(),
      height: (filteredImage.height * scale).round(),
    );
  }

  if (src.width != tgt.width || src.height != tgt.height) {
    tgt = img.copyResize(tgt, width: src.width, height: src.height);
  }

  final srcRHist = List<int>.filled(256, 0);
  final srcGHist = List<int>.filled(256, 0);
  final srcBHist = List<int>.filled(256, 0);
  final tgtRHist = List<int>.filled(256, 0);
  final tgtGHist = List<int>.filled(256, 0);
  final tgtBHist = List<int>.filled(256, 0);
  final blueBHist = List<int>.filled(256, 0);

  var sSumA = 0.0, sSumB = 0.0, mSumA = 0.0, mSumB = 0.0, hSumA = 0.0, hSumB = 0.0;
  int sCount = 0, mCount = 0, hCount = 0;
  double sumL = 0.0;
  double blueDomSum = 0.0;
  double blueNegBSum = 0.0;
  int blueCount = 0;

  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final spx = src.getPixel(x, y);
      final tpx = tgt.getPixel(x, y);

      final sr = spx.rNormalized.toDouble();
      final sg = spx.gNormalized.toDouble();
      final sb = spx.bNormalized.toDouble();
      final tr = tpx.rNormalized.toDouble();
      final tg = tpx.gNormalized.toDouble();
      final tb = tpx.bNormalized.toDouble();

      srcRHist[(sr * 255).round().clamp(0, 255)]++;
      srcGHist[(sg * 255).round().clamp(0, 255)]++;
      srcBHist[(sb * 255).round().clamp(0, 255)]++;
      tgtRHist[(tr * 255).round().clamp(0, 255)]++;
      tgtGHist[(tg * 255).round().clamp(0, 255)]++;
      tgtBHist[(tb * 255).round().clamp(0, 255)]++;

      final lab = rgbToLab(Rgb(tr, tg, tb));
      sumL += lab.l;
      final blueDom = tb - math.max(tr, tg);
      if (blueDom > 0.02) {
        blueCount++;
        blueDomSum += blueDom;
        blueNegBSum += (-lab.b).clamp(0.0, 110.0);
        blueBHist[(tb * 255).round().clamp(0, 255)]++;
      }
      if (lab.l < 35) {
        sSumA += lab.a;
        sSumB += lab.b;
        sCount++;
      } else if (lab.l < 65) {
        mSumA += lab.a;
        mSumB += lab.b;
        mCount++;
      } else {
        hSumA += lab.a;
        hSumB += lab.b;
        hCount++;
      }
    }
  }

  final n = (src.width * src.height).toDouble();
  final blueDominance = blueCount > 0 ? (blueDomSum / blueCount).clamp(0.0, 1.0) : 0.0;
  final blueCastStrength = blueCount > 0
      ? (blueNegBSum / (blueCount * 55.0)).clamp(0.0, 1.0)
      : 0.0;

  final rCurve = _channelCurveFromPair(srcRHist, tgtRHist);
  final gCurve = _channelCurveFromPair(srcGHist, tgtGHist);
  final bCurve = _channelCurveFromPair(srcBHist, tgtBHist);

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
    shadowCast: sCount > 10 ? ZoneCast(sSumA / sCount, sSumB / sCount) : ZoneCast.zero,
    midtoneCast: mCount > 10 ? ZoneCast(mSumA / mCount, mSumB / mCount) : ZoneCast.zero,
    highlightCast: hCount > 10 ? ZoneCast(hSumA / hCount, hSumB / hCount) : ZoneCast.zero,
    meanL: sumL / n,
    blueDominance: blueDominance,
    blueCastStrength: blueCastStrength,
  );
}

// ?€?€?€ Float16 ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

int _toHalf(double v) {
  final f = Float32List(1)..[0] = v;
  final bits = f.buffer.asUint32List()[0];
  final sign = (bits >> 31) & 1;
  var exp = ((bits >> 23) & 0xFF) - 127 + 15;
  var m = (bits >> 13) & 0x3FF;
  if (exp <= 0) { exp = 0; m = 0; }
  if (exp >= 31) { exp = 31; m = 0; }
  return (sign << 15) | (exp << 10) | m;
}

double _fromHalf(int h) {
  final exp = (h >> 10) & 0x1F, m = h & 0x3FF;
  if (exp == 0) return 0;
  if (exp == 31) return double.infinity;
  return ((h >> 15) == 0 ? 1 : -1) * (1 + m / 1024.0) * math.pow(2, exp - 15);
}

// ?€?€?€ LUT generation: NEW algorithm (per-channel curves + zone tint) ?€?€?€?€?€?€?€?€?€?€

Uint8List generateLutNew(StyleProfile p) {
  const dim = 33, total = dim * dim * dim;
  final lut = Uint16List(total * 3);
  const baseTintStrength = 0.15;
  final tintStrength = (baseTintStrength + 0.12 * p.blueCastStrength).clamp(baseTintStrength, 0.30);
  int idx = 0;
  for (int r = 0; r < dim; r++) {
    for (int g = 0; g < dim; g++) {
      for (int b = 0; b < dim; b++) {
        final r8 = (r / 32.0 * 255).round().clamp(0, 255);
        final g8 = (g / 32.0 * 255).round().clamp(0, 255);
        final b8 = (b / 32.0 * 255).round().clamp(0, 255);
        final r1 = p.rCurve[r8] / 255.0;
        final g1 = p.gCurve[g8] / 255.0;
        final b1 = p.bCurve[b8] / 255.0;
        final lab = rgbToLab(Rgb(r1, g1, b1));
        double gw(double l, double center) {
          const sigma = 25.0;
          final d = l - center;
          return math.exp(-0.5 * d * d / (sigma * sigma));
        }
        final ws = gw(lab.l, 17.5), wm = gw(lab.l, 50.0), wh = gw(lab.l, 82.5);
        final wT = ws + wm + wh + 1e-10;
        final aOut = (lab.a + tintStrength * (ws * p.shadowCast.a + wm * p.midtoneCast.a + wh * p.highlightCast.a) / wT).clamp(-110.0, 110.0);
        final bOut = (lab.b + tintStrength * (ws * p.shadowCast.b + wm * p.midtoneCast.b + wh * p.highlightCast.b) / wT).clamp(-110.0, 110.0);
        final out = labToRgb(Lab(lab.l, aOut, bOut));
        lut[idx++] = _toHalf(out.r.clamp(0, 1));
        lut[idx++] = _toHalf(out.g.clamp(0, 1));
        lut[idx++] = _toHalf(out.b.clamp(0, 1));
      }
    }
  }
  return lut.buffer.asUint8List();
}

// ?€?€?€ LUT generation: OLD algorithm (Lab-only zone push, no per-channel) ?€?€?€?€?€?€

final List<double> _neutralLCdf = () {
  const mu = 50.0, sigma = 18.0;
  final hist = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final l = i * 100.0 / 255.0;
    final z = (l - mu) / sigma;
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
}();

List<double> _buildToneCurve(List<double> neutral, List<double> style) {
  final c = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final t = neutral[i];
    int j = 0;
    while (j < 255 && style[j] < t) {
      j++;
    }
    c[i] = j.toDouble();
  }
  for (int i = 1; i < c.length; i++) {
    if (c[i] < c[i - 1]) c[i] = c[i - 1];
  }
  return c;
}

Uint8List generateLutOld(img.Image styleImage) {
  final maxDim = math.max(styleImage.width, styleImage.height);
  img.Image sc = styleImage;
  if (maxDim > 512) {
    final scale = 512.0 / maxDim;
    sc = img.copyResize(styleImage, width: (styleImage.width * scale).round(), height: (styleImage.height * scale).round());
  }
  final lv = <double>[], av = <double>[], bv = <double>[];
  final lHist = List<int>.filled(256, 0);
  var sSumA = 0.0, sSumB = 0.0, sSumL = 0.0, mSumA = 0.0, mSumB = 0.0, mSumL = 0.0,
      hSumA = 0.0, hSumB = 0.0, hSumL = 0.0;
  int sC = 0, mC = 0, hC = 0;
  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final lab = rgbToLab(Rgb(px.rNormalized.toDouble(), px.gNormalized.toDouble(), px.bNormalized.toDouble()));
      lv.add(lab.l); av.add(lab.a); bv.add(lab.b);
      lHist[(lab.l * 255 / 100).round().clamp(0, 255)]++;
      if (lab.l < 35) { sSumA += lab.a; sSumB += lab.b; sSumL += lab.l; sC++; }
      else if (lab.l < 65) { mSumA += lab.a; mSumB += lab.b; mSumL += lab.l; mC++; }
      else { hSumA += lab.a; hSumB += lab.b; hSumL += lab.l; hC++; }
    }
  }
  final n = lv.length.toDouble();
  final muL = lv.fold(0.0, (s, v) => s + v) / n;
  final muA = av.fold(0.0, (s, v) => s + v) / n;
  final muB = bv.fold(0.0, (s, v) => s + v) / n;
  final sigL = math.sqrt(lv.fold(0.0, (s, v) { final d = v - muL; return s + d * d; }) / n).clamp(0.001, double.infinity);
  final sigA = math.sqrt(av.fold(0.0, (s, v) { final d = v - muA; return s + d * d; }) / n).clamp(0.001, double.infinity);
  final sigB = math.sqrt(bv.fold(0.0, (s, v) { final d = v - muB; return s + d * d; }) / n).clamp(0.001, double.infinity);
  final total = lHist.fold(0, (a, b) => a + b);
  double cumul = 0;
  final styleCdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) { cumul += lHist[i] / total; styleCdf[i] = cumul; }
  final tc = _buildToneCurve(_neutralLCdf, styleCdf);
  final ratioL = (sigL / 18.0).clamp(0.7, 1.4);
  final satBoost = ((sigA + sigB) / 16.0).clamp(0.85, 1.8);
  final sLab = sC > 0 ? Lab(sSumL / sC, sSumA / sC, sSumB / sC) : Lab(17.5, 0, 0);
  final mLab = mC > 0 ? Lab(mSumL / mC, mSumA / mC, mSumB / mC) : Lab(50, muA, muB);
  final hLab = hC > 0 ? Lab(hSumL / hC, hSumA / hC, hSumB / hC) : Lab(82.5, 0, 0);
  const dim = 33;
  final lut = Uint16List(dim * dim * dim * 3);
  int idx = 0;
  for (int r = 0; r < dim; r++) {
    for (int g = 0; g < dim; g++) {
      for (int b = 0; b < dim; b++) {
        final lab = rgbToLab(Rgb(r / 32.0, g / 32.0, b / 32.0));
        final lBin = (lab.l * 255 / 100).round().clamp(0, 255);
        final l1 = tc[lBin] * 100 / 255;
        final lOut = (l1 - 50) * ratioL + muL;
        double gw(double l, double c) { final d = l - c; return math.exp(-0.5 * d * d / 484); }
        final ws = gw(lOut, sLab.l), wm = gw(lOut, mLab.l), wh = gw(lOut, hLab.l);
        final wT = ws + wm + wh + 1e-10;
        final zA = (ws * sLab.a + wm * mLab.a + wh * hLab.a) / wT;
        final zB = (ws * sLab.b + wm * mLab.b + wh * hLab.b) / wT;
        final aOut = (lab.a * satBoost + 0.45 * zA).clamp(-110.0, 110.0);
        final bOut = (lab.b * satBoost + 0.45 * zB).clamp(-110.0, 110.0);
        final out = labToRgb(Lab(lOut, aOut, bOut));
        lut[idx++] = _toHalf(out.r.clamp(0, 1));
        lut[idx++] = _toHalf(out.g.clamp(0, 1));
        lut[idx++] = _toHalf(out.b.clamp(0, 1));
      }
    }
  }
  return lut.buffer.asUint8List();
}

// ?€?€?€ Apply LUT (trilinear) ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

Rgb applyLut(Uint8List bytes, Rgb c) {
  final lut = bytes.buffer.asUint16List();
  const dim = 33;
  final ri = c.r * 32, gi = c.g * 32, bi = c.b * 32;
  final r0 = ri.floor().clamp(0, 31), r1 = (r0 + 1).clamp(0, 32);
  final g0 = gi.floor().clamp(0, 31), g1 = (g0 + 1).clamp(0, 32);
  final b0 = bi.floor().clamp(0, 31), b1 = (b0 + 1).clamp(0, 32);
  final rf = ri - r0, gf = gi - g0, bf = bi - b0;
  Rgb s(int r, int g, int b) {
    final i = (r + g * dim + b * dim * dim) * 3;
    return Rgb(_fromHalf(lut[i]), _fromHalf(lut[i + 1]), _fromHalf(lut[i + 2]));
  }
  Rgb lerp(Rgb a, Rgb b, double t) => Rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t);
  final c00 = lerp(s(r0, g0, b0), s(r1, g0, b0), rf);
  final c10 = lerp(s(r0, g1, b0), s(r1, g1, b0), rf);
  final c01 = lerp(s(r0, g0, b1), s(r1, g0, b1), rf);
  final c11 = lerp(s(r0, g1, b1), s(r1, g1, b1), rf);
  return lerp(lerp(c00, c10, gf), lerp(c01, c11, gf), bf);
}

img.Image applyLutToImage(img.Image src, Uint8List lutBytes) {
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final px = src.getPixel(x, y);
      final r2 = applyLut(lutBytes, Rgb(px.rNormalized.toDouble(), px.gNormalized.toDouble(), px.bNormalized.toDouble()));
      out.setPixelRgb(x, y, (r2.r.clamp(0, 1) * 255).round(), (r2.g.clamp(0, 1) * 255).round(), (r2.b.clamp(0, 1) * 255).round());
    }
  }
  return out;
}

// ?€?€?€ Metrics ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

class Metrics {
  final double mean, p95, max;
  const Metrics(this.mean, this.p95, this.max);
}

Metrics computeDeltaE(img.Image result, img.Image target) {
  final rsc = img.copyResize(result, width: 256);
  final tsc = img.copyResize(target, width: 256);
  final w = math.min(rsc.width, tsc.width);
  final h = math.min(rsc.height, tsc.height);
  final deltas = <double>[];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final rp = rsc.getPixel(x, y), tp = tsc.getPixel(x, y);
      final rl = rgbToLab(Rgb(rp.rNormalized.toDouble(), rp.gNormalized.toDouble(), rp.bNormalized.toDouble()));
      final tl = rgbToLab(Rgb(tp.rNormalized.toDouble(), tp.gNormalized.toDouble(), tp.bNormalized.toDouble()));
      final dl = rl.l - tl.l, da = rl.a - tl.a, db = rl.b - tl.b;
      deltas.add(math.sqrt(dl * dl + da * da + db * db));
    }
  }
  deltas.sort();
  return Metrics(
    deltas.fold(0.0, (s, v) => s + v) / deltas.length,
    deltas[(deltas.length * 0.95).floor()],
    deltas.last,
  );
}

// ?€?€?€ Main ?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€?€

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart run tool/filter_test.dart <original.jpg> <filtered.jpg> <out_dir>');
    exit(1);
  }
  Directory(args[2]).createSync(recursive: true);

  print('Loading images...');
  final original = img.decodeImage(File(args[0]).readAsBytesSync())!;
  final filtered = img.decodeImage(File(args[1]).readAsBytesSync())!;

  print('Extracting style profile from filtered image (${filtered.width}x${filtered.height})...');
  final profile = analyzeStyle(filtered);
  final pairProfile = analyzeStyleFromPair(original, filtered);

  print('  Shadow  cast: a=${profile.shadowCast.a.toStringAsFixed(1)} b=${profile.shadowCast.b.toStringAsFixed(1)}');
  print('  Midtone cast: a=${profile.midtoneCast.a.toStringAsFixed(1)} b=${profile.midtoneCast.b.toStringAsFixed(1)}');
  print('  Highlight cast: a=${profile.highlightCast.a.toStringAsFixed(1)} b=${profile.highlightCast.b.toStringAsFixed(1)}');

  final maxDim = math.max(original.width, original.height);
  final scale = math.min(1.0, 512.0 / maxDim);
  final testImg = scale < 1.0 ? img.copyResize(original, width: (original.width * scale).round()) : original;
  final targetScaled = scale < 1.0 ? img.copyResize(filtered, width: (filtered.width * scale).round()) : filtered;

  print('\nGenerating LUTs...');
  final lutNew = generateLutNew(profile);
  final lutPair = generateLutNew(pairProfile);
  final lutOld = generateLutOld(filtered);

  print('Applying LUTs...');
  final resultNew = applyLutToImage(testImg, lutNew);
  final resultPair = applyLutToImage(testImg, lutPair);
  final resultOld = applyLutToImage(testImg, lutOld);

  print('\nComputing DeltaE (CIE76) vs filtered target...');
  final mNew = computeDeltaE(resultNew, targetScaled);
  final mPair = computeDeltaE(resultPair, targetScaled);
  final mOld = computeDeltaE(resultOld, targetScaled);

  print('\nAlgorithm comparison (lower is better)');
  print('  NEW  : mean=${mNew.mean.toStringAsFixed(2)} p95=${mNew.p95.toStringAsFixed(2)} max=${mNew.max.toStringAsFixed(2)}');
  print('  PAIR : mean=${mPair.mean.toStringAsFixed(2)} p95=${mPair.p95.toStringAsFixed(2)} max=${mPair.max.toStringAsFixed(2)}');
  print('  OLD  : mean=${mOld.mean.toStringAsFixed(2)} p95=${mOld.p95.toStringAsFixed(2)} max=${mOld.max.toStringAsFixed(2)}');
  print('DeltaE < 5: good | 5-10: acceptable | >10: visible');

  final scores = <String, double>{'NEW': mNew.mean, 'PAIR': mPair.mean, 'OLD': mOld.mean};
  final sorted = scores.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final winner = sorted[0];
  final second = sorted[1];
  final diff = ((second.value - winner.value) / second.value * 100).abs();
  print('\n${winner.key} is closest to target by ${diff.toStringAsFixed(1)}% vs ${second.key}');

  File('${args[2]}/result_new.jpg').writeAsBytesSync(img.encodeJpg(resultNew, quality: 90));
  File('${args[2]}/result_pair.jpg').writeAsBytesSync(img.encodeJpg(resultPair, quality: 90));
  File('${args[2]}/result_old.jpg').writeAsBytesSync(img.encodeJpg(resultOld, quality: 90));
  print('\nSaved: ${args[2]}/result_new.jpg  (NEW algorithm)');
  print('Saved: ${args[2]}/result_pair.jpg (PAIR algorithm)');
  print('Saved: ${args[2]}/result_old.jpg  (OLD algorithm)');
}
