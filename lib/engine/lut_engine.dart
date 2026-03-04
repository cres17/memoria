import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/filter_preset.dart';
import '../domain/models/adjust_params.dart';
import 'color_utils.dart';
import 'style_analyzer.dart';

const int _dim = 33;

/// Float16 helpers (simple half-float via int16 bit pattern)
int _floatToHalf(double value) {
  final f32 = Float32List(1)..[0] = value;
  final bits = f32.buffer.asUint32List()[0];
  final sign = (bits >> 31) & 0x1;
  var exp = ((bits >> 23) & 0xFF) - 127 + 15;
  var mantissa = (bits >> 13) & 0x3FF;
  if (exp <= 0) { exp = 0; mantissa = 0; }
  if (exp >= 31) { exp = 31; mantissa = 0; }
  return (sign << 15) | (exp << 10) | mantissa;
}

double _halfToFloat(int half) {
  final sign     = (half >> 15) & 0x1;
  final exp      = (half >> 10) & 0x1F;
  final mantissa = half & 0x3FF;
  if (exp == 0) return 0.0;
  if (exp == 31) return sign == 0 ? double.infinity : double.negativeInfinity;
  final e = exp - 15;
  final m = 1.0 + mantissa / 1024.0;
  return (sign == 0 ? 1.0 : -1.0) * m * math.pow(2.0, e);
}

/// Generate a 33³ 3D LUT from a style image.
/// Returns [presetId, lutPath, thumbnailPath]
Future<Map<String, dynamic>> generateLutFromStyle(String styleImagePath) async {
  final id    = const Uuid().v4();
  final base  = await getApplicationDocumentsDirectory();
  final dir   = Directory('${base.path}/filters/$id')
    ..createSync(recursive: true);

  // Load + analyze style
  final bytes  = File(styleImagePath).readAsBytesSync();
  final image  = img.decodeImage(bytes)!;
  final stats  = StyleAnalyzer.analyze(image);

  // Build tone curve
  final toneCurve = buildToneCurve(NeutralStats.cdf, stats.cdf);

  // Clamped sigma ratios
  final ratioL = (stats.sigL / NeutralStats.sigL).clamp(0.5, 2.0);
  final ratioA = (stats.sigA / NeutralStats.sigA).clamp(0.5, 2.0);
  final ratioB = (stats.sigB / NeutralStats.sigB).clamp(0.5, 2.0);

  // Allocate LUT buffer (33³ × 3 × float16)
  const total   = _dim * _dim * _dim;
  final lutData = Uint16List(total * 3);
  int idx = 0;

  for (int r = 0; r < _dim; r++) {
    for (int g = 0; g < _dim; g++) {
      for (int b = 0; b < _dim; b++) {
        final rgb = RgbColor(r / 32.0, g / 32.0, b / 32.0);
        final lab = rgbToLab(rgb);

        // Map L (0..100) → bin (0..255)
        final lBin = (lab.l * 255.0 / 100.0).round().clamp(0, 255);
        final l1   = toneCurve[lBin] * 100.0 / 255.0; // back to [0,100]

        final l2 = (l1  - NeutralStats.muL) * ratioL + stats.muL;
        final a2 = (lab.a - NeutralStats.muA) * ratioA + stats.muA;
        final b2 = (lab.b - NeutralStats.muB) * ratioB + stats.muB;

        final outRgb = labToRgb(LabColor(l2, a2, b2));

        lutData[idx++] = _floatToHalf(outRgb.r);
        lutData[idx++] = _floatToHalf(outRgb.g);
        lutData[idx++] = _floatToHalf(outRgb.b);
      }
    }
  }

  // Save lut.bin
  final lutPath = '${dir.path}/lut.bin';
  File(lutPath).writeAsBytesSync(lutData.buffer.asUint8List());

  // Save thumbnail (128×128 crop of style)
  final thumb = img.copyResizeCropSquare(image, size: 128);
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));

  return {
    'presetId':      id,
    'lutPath':       lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': AdjustParams.zero.toJson(),
  };
}

/// Apply a 3D LUT (33³ float16 binary) to an image pixel (trilinear).
/// [lutBytes] is the raw uint8 content of lut.bin
RgbColor applyLut(Uint8List lutBytes, RgbColor rgb) {
  final lut = lutBytes.buffer.asUint16List();

  final ri  = rgb.r * 32.0;
  final gi  = rgb.g * 32.0;
  final bi  = rgb.b * 32.0;

  final r0  = ri.floor().clamp(0, 31);
  final r1  = (r0 + 1).clamp(0, 32);
  final g0  = gi.floor().clamp(0, 31);
  final g1  = (g0 + 1).clamp(0, 32);
  final b0  = bi.floor().clamp(0, 31);
  final b1  = (b0 + 1).clamp(0, 32);

  final rf  = ri - r0;
  final gf  = gi - g0;
  final bf  = bi - b0;

  RgbColor sample(int r, int g, int b) {
    final i = (r + g * _dim + b * _dim * _dim) * 3;
    return RgbColor(
      _halfToFloat(lut[i]),
      _halfToFloat(lut[i + 1]),
      _halfToFloat(lut[i + 2]),
    );
  }

  // Trilinear interpolation
  RgbColor lerp(RgbColor a, RgbColor b, double t) =>
      RgbColor(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t);

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

/// Apply adjust params to an sRGB pixel (value in [0,1]).
RgbColor applyAdjustParams(RgbColor rgb, AdjustParams p) {
  // Exposure
  var r = rgb.r * math.pow(2.0, p.exposure);
  var g = rgb.g * math.pow(2.0, p.exposure);
  var b = rgb.b * math.pow(2.0, p.exposure);

  // Contrast (S-curve approximation)
  if (p.contrast != 0) {
    final factor = (259.0 * (p.contrast + 255)) / (255.0 * (259 - p.contrast));
    r = factor * (r - 0.5) + 0.5;
    g = factor * (g - 0.5) + 0.5;
    b = factor * (b - 0.5) + 0.5;
  }

  // Saturation
  if (p.saturation != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final s   = 1.0 + p.saturation / 100.0;
    r = lum + (r - lum) * s;
    g = lum + (g - lum) * s;
    b = lum + (b - lum) * s;
  }

  // Temperature/Tint (simple RGB shift)
  if (p.temperature != 0) {
    r += p.temperature / 1000.0;
    b -= p.temperature / 1000.0;
  }
  if (p.tint != 0) {
    g += p.tint / 1000.0;
    r -= p.tint / 2000.0;
  }

  // Highlights / Shadows
  if (p.highlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (lum - 0.5).clamp(0.0, 0.5) * 2.0;
    final adj  = p.highlights / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }
  if (p.shadows != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final mask = (0.5 - lum).clamp(0.0, 0.5) * 2.0;
    final adj  = p.shadows / 100.0 * mask * 0.5;
    r += adj; g += adj; b += adj;
  }

  return RgbColor(r.toDouble(), g.toDouble(), b.toDouble()).clamp01();
}

/// Full pipeline: Adjust → LUT → Intensity mix
RgbColor applyPipeline({
  required RgbColor original,
  required AdjustParams params,
  required Uint8List? lutBytes,
  required double intensity,
}) {
  var processed = applyAdjustParams(original, params);

  if (lutBytes != null && lutBytes.isNotEmpty) {
    processed = applyLut(lutBytes, processed);
  }

  // Intensity mix
  return RgbColor(
    original.r * (1 - intensity) + processed.r * intensity,
    original.g * (1 - intensity) + processed.g * intensity,
    original.b * (1 - intensity) + processed.b * intensity,
  ).clamp01();
}

/// Load lut bytes from path (null if not found / empty)
Future<Uint8List?> loadLutBytes(String? lutPath) async {
  if (lutPath == null || lutPath.isEmpty) return null;
  final f = File(lutPath);
  if (!await f.exists()) return null;
  return f.readAsBytes();
}
