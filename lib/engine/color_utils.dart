import 'dart:math' as math;

/// sRGB ↔ CIE Lab (D65) color space conversions.
/// All sRGB values are in [0, 1].
/// Lab: L ∈ [0, 100], a ∈ [-128, 127], b ∈ [-128, 127]

class LabColor {
  final double l, a, b;
  const LabColor(this.l, this.a, this.b);
}

class RgbColor {
  final double r, g, b;
  const RgbColor(this.r, this.g, this.b);

  RgbColor clamp01() => RgbColor(
    r.clamp(0.0, 1.0),
    g.clamp(0.0, 1.0),
    b.clamp(0.0, 1.0),
  );
}

// D65 white point
const _xn = 0.95047;
const _yn = 1.00000;
const _zn = 1.08883;

double _linearize(double c) {
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _delinearize(double c) {
  return c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
}

double _f(double t) {
  const d = 6.0 / 29.0;
  return t > d * d * d
      ? math.pow(t, 1.0 / 3.0).toDouble()
      : t / (3 * d * d) + 4.0 / 29.0;
}

double _fInv(double t) {
  const d = 6.0 / 29.0;
  return t > d ? t * t * t : 3 * d * d * (t - 4.0 / 29.0);
}

LabColor rgbToLab(RgbColor rgb) {
  // sRGB → linear
  final rl = _linearize(rgb.r);
  final gl = _linearize(rgb.g);
  final bl = _linearize(rgb.b);

  // linear RGB → XYZ (D65)
  final x = 0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl;
  final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
  final z = 0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl;

  // XYZ → Lab
  final fx = _f(x / _xn);
  final fy = _f(y / _yn);
  final fz = _f(z / _zn);

  return LabColor(
    116.0 * fy - 16.0,
    500.0 * (fx - fy),
    200.0 * (fy - fz),
  );
}

RgbColor labToRgb(LabColor lab) {
  final fy = (lab.l + 16.0) / 116.0;
  final fx = lab.a / 500.0 + fy;
  final fz = fy - lab.b / 200.0;

  final x = _fInv(fx) * _xn;
  final y = _fInv(fy) * _yn;
  final z = _fInv(fz) * _zn;

  // XYZ → linear RGB (D65)
  final rl =  3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
  final gl = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
  final bl =  0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

  return RgbColor(
    _delinearize(rl.clamp(0.0, 1.0)),
    _delinearize(gl.clamp(0.0, 1.0)),
    _delinearize(bl.clamp(0.0, 1.0)),
  ).clamp01();
}

class OklabColor {
  final double l, a, b;
  const OklabColor(this.l, this.a, this.b);
}

OklabColor rgbToOklab(RgbColor rgb) {
  // sRGB to linear
  final r = _linearize(rgb.r);
  final g = _linearize(rgb.g);
  final b = _linearize(rgb.b);

  // Linear RGB to LMS
  final lmsL = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final lmsM = 0.2119034982 * r + 0.6806995451 * g + 0.1073970077 * b;
  final lmsS = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

  // Non-linear LMS (cube root)
  final lPrime = lmsL > 0.0 ? math.pow(lmsL, 1.0 / 3.0).toDouble() : (lmsL < 0.0 ? -math.pow(-lmsL, 1.0 / 3.0).toDouble() : 0.0);
  final mPrime = lmsM > 0.0 ? math.pow(lmsM, 1.0 / 3.0).toDouble() : (lmsM < 0.0 ? -math.pow(-lmsM, 1.0 / 3.0).toDouble() : 0.0);
  final sPrime = lmsS > 0.0 ? math.pow(lmsS, 1.0 / 3.0).toDouble() : (lmsS < 0.0 ? -math.pow(-lmsS, 1.0 / 3.0).toDouble() : 0.0);

  // LMS to Oklab
  final okL = 0.2104542553 * lPrime + 0.7936177850 * mPrime - 0.0040720468 * sPrime;
  final okA = 1.9779984951 * lPrime - 2.4285922050 * mPrime + 0.4505937099 * sPrime;
  final okB = 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.8086757660 * sPrime;

  return OklabColor(okL, okA, okB);
}

RgbColor oklabToRgb(OklabColor oklab) {
  // Oklab to non-linear LMS
  final lPrime = oklab.l + 0.3963377774 * oklab.a + 0.2158037573 * oklab.b;
  final mPrime = oklab.l - 0.1055613458 * oklab.a - 0.0638541728 * oklab.b;
  final sPrime = oklab.l - 0.0894841775 * oklab.a - 1.2914855480 * oklab.b;

  // Non-linear LMS to linear LMS (cube)
  final lmsL = lPrime * lPrime * lPrime;
  final lmsM = mPrime * mPrime * mPrime;
  final lmsS = sPrime * sPrime * sPrime;

  // LMS to Linear RGB
  final rl =  4.0767416621 * lmsL - 3.3077115913 * lmsM + 0.2309699292 * lmsS;
  final gl = -1.2684380046 * lmsL + 2.6097574011 * lmsM - 0.3413193965 * lmsS;
  final bl = -0.0041960863 * lmsL - 0.7034186147 * lmsM + 1.7076147010 * lmsS;

  // Linear to sRGB
  return RgbColor(
    _delinearize(rl.clamp(0.0, 1.0)),
    _delinearize(gl.clamp(0.0, 1.0)),
    _delinearize(bl.clamp(0.0, 1.0)),
  ).clamp01();
}

