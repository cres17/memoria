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
