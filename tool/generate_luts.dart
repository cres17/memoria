/// Run: dart run tool/generate_luts.dart
/// Generates 7 built-in 65³ LUT .bin files (float16, RGB row-major).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int dim = 65;
const int total = dim * dim * dim;

void main() {
  final outDir = Directory('assets/luts');
  outDir.createSync(recursive: true);

  _generate('vivid',  _vivid);
  _generate('cool',   _cool);
  _generate('warm',   _warm);
  _generate('fade',   _fade);
  _generate('noir',   _noir);
  _generate('pastel', _pastel);
  _generate('golden', _golden);

  print('Done — 7 LUTs written to assets/luts/');
}

void _generate(String name, _LutFn fn) {
  final data = Uint16List(total * 3);
  int idx = 0;
  for (int r = 0; r < dim; r++) {
    for (int g = 0; g < dim; g++) {
      for (int b = 0; b < dim; b++) {
        final rn = r / (dim - 1);
        final gn = g / (dim - 1);
        final bn = b / (dim - 1);
        final out = fn(rn, gn, bn);
        data[idx++] = _f32ToF16(out.$1.clamp(0.0, 1.0));
        data[idx++] = _f32ToF16(out.$2.clamp(0.0, 1.0));
        data[idx++] = _f32ToF16(out.$3.clamp(0.0, 1.0));
      }
    }
  }
  File('assets/luts/$name.bin').writeAsBytesSync(data.buffer.asUint8List());
  print('  [$name] written (${data.lengthInBytes} bytes)');
}

typedef _LutFn = (double, double, double) Function(double r, double g, double b);

// ── Vivid: 채도+명암 강화 ─────────────────────────────────
(double, double, double) _vivid(double r, double g, double b) {
  // 채도 +30%, 대비 S-curve
  final avg = (r + g + b) / 3;
  double vr = avg + (r - avg) * 1.30;
  double vg = avg + (g - avg) * 1.30;
  double vb = avg + (b - avg) * 1.30;
  vr = _sCurve(vr, 0.15);
  vg = _sCurve(vg, 0.15);
  vb = _sCurve(vb, 0.15);
  return (vr, vg, vb);
}

// ── Cool: 청량한 블루 시프트 ──────────────────────────────
(double, double, double) _cool(double r, double g, double b) {
  final r2 = r * 0.88 - 0.02;
  final g2 = g * 0.96 + 0.02;
  final b2 = b * 1.08 + 0.06;
  return (r2, g2, b2);
}

// ── Warm: 황금빛 따뜻한 톤 ───────────────────────────────
(double, double, double) _warm(double r, double g, double b) {
  final r2 = r * 1.10 + 0.04;
  final g2 = g * 1.02 + 0.01;
  final b2 = b * 0.88 - 0.03;
  return (r2, g2, b2);
}

// ── Fade: 매트 페이드 (blacks lift, whites lower) ─────────
(double, double, double) _fade(double r, double g, double b) {
  // shadows lift to 0.08, highlights pull to 0.92
  final r2 = 0.08 + r * 0.84;
  final g2 = 0.08 + g * 0.84;
  final b2 = 0.10 + b * 0.82;
  // 살짝 채도 낮춤
  final avg = (r2 + g2 + b2) / 3;
  return (
    avg + (r2 - avg) * 0.80,
    avg + (g2 - avg) * 0.80,
    avg + (b2 - avg) * 0.80,
  );
}

// ── Noir: 흑백 + 강한 대비 ───────────────────────────────
(double, double, double) _noir(double r, double g, double b) {
  // Luminance (perceptual weights)
  final lum = r * 0.2126 + g * 0.7152 + b * 0.0722;
  // High-contrast S-curve on luminance
  final c = _sCurve(lum, 0.25);
  // Slight blue-green tint in mids for cinematic look
  final tintR = c * 0.93;
  final tintG = c * 0.97;
  final tintB = c * 1.04;
  return (tintR, tintG, tintB);
}

// ── Pastel: 부드러운 파스텔 ──────────────────────────────
(double, double, double) _pastel(double r, double g, double b) {
  // whites lift, blacks lift, desaturate
  final r2 = 0.06 + r * 0.88;
  final g2 = 0.07 + g * 0.87;
  final b2 = 0.09 + b * 0.86;
  final avg = (r2 + g2 + b2) / 3;
  // desaturate 40%
  final dr = avg + (r2 - avg) * 0.60;
  final dg = avg + (g2 - avg) * 0.60;
  final db = avg + (b2 - avg) * 0.60;
  // slight warm pink cast
  return (dr + 0.03, dg, db + 0.01);
}

// ── Golden: 황금 시간대 (golden hour) ────────────────────
(double, double, double) _golden(double r, double g, double b) {
  // warm orange-gold push
  final r2 = r * 1.14 + 0.06;
  final g2 = g * 1.04 + 0.02;
  final b2 = b * 0.76 - 0.04;
  // lift shadows with warm tint
  final lum = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final shadowBoost = (1 - lum) * 0.08;
  return (r2 + shadowBoost * 0.8, g2 + shadowBoost * 0.4, b2);
}

// ── Helpers ───────────────────────────────────────────────

/// Smooth S-curve contrast. [strength] 0..1
double _sCurve(double x, double strength) {
  // Hermite sigmoid: 3t²−2t³ blended with identity
  final s = x * x * (3 - 2 * x);
  return x + (s - x) * strength;
}

/// IEEE 754 float32 → float16 bit pattern
int _f32ToF16(double value) {
  if (value.isNaN) return 0x7E00;
  if (value.isInfinite) return value > 0 ? 0x7C00 : 0xFC00;
  if (value == 0.0) return 0;

  final bits = ByteData(4)..setFloat32(0, value, Endian.little);
  final i32  = bits.getUint32(0, Endian.little);
  final sign = (i32 >> 31) & 0x1;
  int exp    = ((i32 >> 23) & 0xFF) - 127 + 15;
  int mant   = (i32 >> 13) & 0x3FF;

  if (exp <= 0) return sign << 15;
  if (exp >= 31) return (sign << 15) | 0x7C00;
  return (sign << 15) | (exp << 10) | mant;
}
