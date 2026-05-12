import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../ai/ai_manager.dart';
import '../ai/models/lut_predictor.dart';
import '../domain/models/adjust_params.dart';
import 'color_utils.dart';
import 'style_analyzer.dart';

// ─────────────────────────────────────────────────────────
//  Image-level pipeline (full img.Image in → img.Image out)
// ─────────────────────────────────────────────────────────

/// 전체 이미지 파이프라인:
/// Adjust (per-pixel) → LUT → Intensity → Sharpen → Structure → Clarity → Vignette
img.Image applyImagePipeline({
  required img.Image image,
  required AdjustParams params,
  Uint8List? lutBytes,
  double intensity = 1.0,
}) {
  // Step 1: per-pixel adjust + LUT + intensity mix
  var output = img.Image(width: image.width, height: image.height);
  final effectiveLut = (lutBytes != null && lutBytes.isNotEmpty) ? lutBytes : null;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px   = image.getPixel(x, y);
      final orig = RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      );
      var result = applyAdjustParams(orig, params);

      if (effectiveLut != null) {
        final lutResult = applyLut(effectiveLut, result);
        result = RgbColor(
          orig.r * (1 - intensity) + lutResult.r * intensity,
          orig.g * (1 - intensity) + lutResult.g * intensity,
          orig.b * (1 - intensity) + lutResult.b * intensity,
        ).clamp01();
      }

      output.setPixelRgb(x, y,
        (result.r * 255).round(),
        (result.g * 255).round(),
        (result.b * 255).round(),
      );
    }
  }

  // Step 2: image-level effects
  if (params.sharpen > 0)    output = _applySharpenImage(output, params.sharpen);
  if (params.structure != 0) output = _applyStructureImage(output, params.structure);
  if (params.clarity != 0)   output = _applyClarityImage(output, params.clarity);
  if (params.vignette > 0)   output = _applyVignetteImage(output, params.vignette);

  return output;
}

// ── Sharpen: Unsharp Mask ─────────────────────────────────
img.Image _applySharpenImage(img.Image image, double sharpenValue) {
  final strength = sharpenValue / 100.0 * 1.5;
  final blurred  = img.gaussianBlur(image, radius: 2);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);
      final r  = (o.rNormalized + strength * (o.rNormalized - bl.rNormalized)).clamp(0.0, 1.0);
      final g  = (o.gNormalized + strength * (o.gNormalized - bl.gNormalized)).clamp(0.0, 1.0);
      final b  = (o.bNormalized + strength * (o.bNormalized - bl.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Structure: High-Pass Local Contrast ──────────────────
img.Image _applyStructureImage(img.Image image, double structureValue) {
  final strength = structureValue / 100.0 * 0.5;
  final blurred  = img.gaussianBlur(image, radius: 1);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o  = image.getPixel(x, y);
      final bl = blurred.getPixel(x, y);
      final r  = (o.rNormalized + strength * (o.rNormalized - bl.rNormalized)).clamp(0.0, 1.0);
      final g  = (o.gNormalized + strength * (o.gNormalized - bl.gNormalized)).clamp(0.0, 1.0);
      final b  = (o.bNormalized + strength * (o.bNormalized - bl.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Clarity: Mid-Frequency Contrast (Retinex-lite) ───────
img.Image _applyClarityImage(img.Image image, double clarityValue) {
  final strength = clarityValue / 100.0 * 0.7;
  final blurred  = img.gaussianBlur(image, radius: 7);
  final result   = img.Image(width: image.width, height: image.height);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final o   = image.getPixel(x, y);
      final low = blurred.getPixel(x, y);
      final lum = 0.2126 * o.rNormalized + 0.7152 * o.gNormalized + 0.0722 * o.bNormalized;
      // 미드톤 마스크: 0.5 근처에서 최대 효과
      final midMask = (1.0 - (lum - 0.5).abs() * 2.0).clamp(0.0, 1.0);
      final r = (o.rNormalized + strength * midMask * (o.rNormalized - low.rNormalized)).clamp(0.0, 1.0);
      final g = (o.gNormalized + strength * midMask * (o.gNormalized - low.gNormalized)).clamp(0.0, 1.0);
      final b = (o.bNormalized + strength * midMask * (o.bNormalized - low.bNormalized)).clamp(0.0, 1.0);
      result.setPixelRgb(x, y, (r * 255).round(), (g * 255).round(), (b * 255).round());
    }
  }
  return result;
}

// ── Vignette: Radial Gradient Multiply ───────────────────
img.Image _applyVignetteImage(img.Image image, double vignetteValue) {
  final strength = vignetteValue / 100.0 * 0.8;
  final result   = img.Image(width: image.width, height: image.height);
  final W        = image.width.toDouble();
  final H        = image.height.toDouble();

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px  = image.getPixel(x, y);
      final dx  = x / W - 0.5;
      final dy  = y / H - 0.5;
      final dist = math.sqrt(dx * dx + dy * dy) / 0.707;
      final mask = (1.0 - dist * dist * strength).clamp(0.0, 1.0);
      result.setPixelRgb(x, y,
        (px.rNormalized * mask * 255).round(),
        (px.gNormalized * mask * 255).round(),
        (px.bNormalized * mask * 255).round(),
      );
    }
  }
  return result;
}

const int _dim = 65;

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

/// Generate a 65³ 3D LUT from a style image.
/// Neural path (TFLite) when model is ready; algorithmic fallback otherwise.
/// Returns [presetId, lutPath, thumbnailPath, defaultParams]
Future<Map<String, dynamic>> generateLutFromStyle(
  String styleImagePath, {
  String? basePath,
}) async {
  if (AiManager.instance.colorTransferReady) {
    try {
      return await _generateLutNeural(styleImagePath, basePath: basePath);
    } catch (_) {
      // Neural inference failed → algorithmic fallback
    }
  }
  return _generateLutAlgorithmic(styleImagePath, basePath: basePath);
}

/// Neural path: TFLite model predicts 5³ LUT → upsampled to 65³.
Future<Map<String, dynamic>> _generateLutNeural(
  String styleImagePath, {
  String? basePath,
}) async {
  final id   = const Uuid().v4();
  final base = basePath != null
      ? Directory(basePath)
      : await getApplicationDocumentsDirectory();
  final dir  = Directory('${base.path}/filters/$id')
    ..createSync(recursive: true);

  final predictor = await LutPredictor.instance;
  final lut65     = await predictor.predict(styleImagePath); // Float32List (65³×3)

  const total   = _dim * _dim * _dim;
  final lutData = Uint16List(total * 3);
  for (int i = 0; i < total * 3; i++) {
    lutData[i] = _floatToHalf(lut65[i]);
  }

  final lutPath = '${dir.path}/lut.bin';
  File(lutPath).writeAsBytesSync(lutData.buffer.asUint8List());

  final bytes    = File(styleImagePath).readAsBytesSync();
  final image    = img.decodeImage(bytes)!;
  final thumb    = img.copyResizeCropSquare(image, size: 128);
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));

  return {
    'presetId':      id,
    'lutPath':       lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': AdjustParams.zero.toJson(),
  };
}

/// Algorithmic fallback (used before Neural model is downloaded).
Future<Map<String, dynamic>> _generateLutAlgorithmic(
  String styleImagePath, {
  String? basePath,
}) async {
  final id    = const Uuid().v4();
  final base  = basePath != null
      ? Directory(basePath)
      : await getApplicationDocumentsDirectory();
  final dir   = Directory('${base.path}/filters/$id')
    ..createSync(recursive: true);

  final bytes   = File(styleImagePath).readAsBytesSync();
  final image   = img.decodeImage(bytes)!;
  final profile = StyleAnalyzer.analyze(image);
  final labProfile = _analyzeLabStyle(image);

  const total    = _dim * _dim * _dim;
  final lutData  = Uint16List(total * 3);
  final maxIdx   = (_dim - 1).toDouble();
  int lutIdx = 0;

  for (int r = 0; r < _dim; r++) {
    for (int g = 0; g < _dim; g++) {
      for (int b = 0; b < _dim; b++) {
        final rgb = RgbColor(r / maxIdx, g / maxIdx, b / maxIdx);
        final channelRgb = _applyChannelStyle(rgb, profile, labProfile.castStrength);
        final labRgb = _applyLabStyle(rgb, labProfile);
        final blend = _labBlendWeight(labProfile.castStrength);
        final outRgb = RgbColor(
          channelRgb.r * (1.0 - blend) + labRgb.r * blend,
          channelRgb.g * (1.0 - blend) + labRgb.g * blend,
          channelRgb.b * (1.0 - blend) + labRgb.b * blend,
        ).clamp01();

        lutData[lutIdx++] = _floatToHalf(outRgb.r);
        lutData[lutIdx++] = _floatToHalf(outRgb.g);
        lutData[lutIdx++] = _floatToHalf(outRgb.b);
      }
    }
  }

  final lutPath = '${dir.path}/lut.bin';
  File(lutPath).writeAsBytesSync(lutData.buffer.asUint8List());

  final thumb     = img.copyResizeCropSquare(image, size: 128);
  final thumbPath = '${dir.path}/thumbnail.jpg';
  File(thumbPath).writeAsBytesSync(img.encodeJpg(thumb, quality: 80));

  return {
    'presetId':      id,
    'lutPath':       lutPath,
    'thumbnailPath': thumbPath,
    'defaultParams': AdjustParams.zero.toJson(),
  };
}

class _LabStyleProfile {
  final List<double> toneCurve;
  final double meanL;
  final double contrastRatio;
  final double satBoost;
  final double castStrength;
  final LabColor shadow;
  final LabColor midtone;
  final LabColor highlight;

  const _LabStyleProfile({
    required this.toneCurve,
    required this.meanL,
    required this.contrastRatio,
    required this.satBoost,
    required this.castStrength,
    required this.shadow,
    required this.midtone,
    required this.highlight,
  });
}

final List<double> _neutralLCdf = () {
  const mu = 50.0;
  const sigma = 18.0;
  final hist = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    final l = i * 100.0 / 255.0;
    final z = (l - mu) / sigma;
    hist[i] = math.exp(-0.5 * z * z);
  }
  final sum = hist.fold(0.0, (a, b) => a + b);
  var cumul = 0.0;
  final cdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    cumul += hist[i] / sum;
    cdf[i] = cumul;
  }
  return cdf;
}();

_LabStyleProfile _analyzeLabStyle(img.Image styleImage) {
  final maxDim = math.max(styleImage.width, styleImage.height);
  var sc = styleImage;
  if (maxDim > 512) {
    final scale = 512.0 / maxDim;
    sc = img.copyResize(
      styleImage,
      width: (styleImage.width * scale).round(),
      height: (styleImage.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  final lHist = List<int>.filled(256, 0);
  final lValues = <double>[];
  final aValues = <double>[];
  final bValues = <double>[];
  var sL = 0.0, sA = 0.0, sB = 0.0;
  var mL = 0.0, mA = 0.0, mB = 0.0;
  var hL = 0.0, hA = 0.0, hB = 0.0;
  var sCount = 0, mCount = 0, hCount = 0;

  for (int y = 0; y < sc.height; y++) {
    for (int x = 0; x < sc.width; x++) {
      final px = sc.getPixel(x, y);
      final lab = rgbToLab(RgbColor(
        px.rNormalized.toDouble(),
        px.gNormalized.toDouble(),
        px.bNormalized.toDouble(),
      ));
      lValues.add(lab.l);
      aValues.add(lab.a);
      bValues.add(lab.b);
      lHist[(lab.l * 255.0 / 100.0).round().clamp(0, 255)]++;

      if (lab.l < 35.0) {
        sL += lab.l; sA += lab.a; sB += lab.b; sCount++;
      } else if (lab.l < 65.0) {
        mL += lab.l; mA += lab.a; mB += lab.b; mCount++;
      } else {
        hL += lab.l; hA += lab.a; hB += lab.b; hCount++;
      }
    }
  }

  final n = lValues.length.toDouble();
  final meanL = lValues.fold(0.0, (sum, value) => sum + value) / n;
  final meanA = aValues.fold(0.0, (sum, value) => sum + value) / n;
  final meanB = bValues.fold(0.0, (sum, value) => sum + value) / n;

  double stdDev(List<double> values, double mean) {
    final variance = values.fold(0.0, (sum, value) {
      final d = value - mean;
      return sum + d * d;
    }) / values.length;
    return math.sqrt(variance).clamp(0.001, double.infinity);
  }

  final sigL = stdDev(lValues, meanL);
  final sigA = stdDev(aValues, meanA);
  final sigB = stdDev(bValues, meanB);

  final total = lHist.fold(0, (a, b) => a + b);
  var cumul = 0.0;
  final styleCdf = List<double>.filled(256, 0.0);
  for (int i = 0; i < 256; i++) {
    cumul += lHist[i] / total;
    styleCdf[i] = cumul;
  }

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
    if (toneCurve[i] < toneCurve[i - 1]) {
      toneCurve[i] = toneCurve[i - 1];
    }
  }

  LabColor zone(double fallbackL, double fallbackA, double fallbackB,
      double l, double a, double b, int count) {
    if (count <= 10) return LabColor(fallbackL, fallbackA, fallbackB);
    return LabColor(l / count, a / count, b / count);
  }

  return _LabStyleProfile(
    toneCurve: toneCurve,
    meanL: meanL,
    contrastRatio: (sigL / 18.0).clamp(0.70, 1.40),
    satBoost: ((sigA + sigB) / 16.0).clamp(0.85, 1.80),
    castStrength: math.sqrt(meanA * meanA + meanB * meanB).clamp(0.0, 45.0) / 45.0,
    shadow: zone(17.5, meanA, meanB, sL, sA, sB, sCount),
    midtone: zone(50.0, meanA, meanB, mL, mA, mB, mCount),
    highlight: zone(82.5, meanA, meanB, hL, hA, hB, hCount),
  );
}

RgbColor _applyChannelStyle(
  RgbColor rgb,
  StyleProfile profile,
  double castStrength,
) {
  final r8 = (rgb.r * 255).round().clamp(0, 255);
  final g8 = (rgb.g * 255).round().clamp(0, 255);
  final b8 = (rgb.b * 255).round().clamp(0, 255);
  final lab = rgbToLab(RgbColor(
    profile.rCurve[r8] / 255.0,
    profile.gCurve[g8] / 255.0,
    profile.bCurve[b8] / 255.0,
  ));

  final tintStrength = (0.16 + 0.18 * castStrength + 0.12 * profile.blueCastStrength)
      .clamp(0.16, 0.42);
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
  return labToRgb(LabColor(
    lOut.clamp(0.0, 100.0),
    (lab.a * profile.satBoost + 0.45 * zone.a).clamp(-110.0, 110.0),
    (lab.b * profile.satBoost + 0.45 * zone.b).clamp(-110.0, 110.0),
  ));
}

ZoneCast _weightedZoneCast(
  double l,
  ZoneCast shadow,
  ZoneCast midtone,
  ZoneCast highlight,
) {
  final ws = _zoneWeight(l, 17.5, 25.0);
  final wm = _zoneWeight(l, 50.0, 25.0);
  final wh = _zoneWeight(l, 82.5, 25.0);
  final total = ws + wm + wh + 1e-10;
  return ZoneCast(
    a: (ws * shadow.a + wm * midtone.a + wh * highlight.a) / total,
    b: (ws * shadow.b + wm * midtone.b + wh * highlight.b) / total,
    count: 0,
  );
}

LabColor _weightedLabZone(double l, _LabStyleProfile profile) {
  final ws = _zoneWeight(l, profile.shadow.l, 22.0);
  final wm = _zoneWeight(l, profile.midtone.l, 22.0);
  final wh = _zoneWeight(l, profile.highlight.l, 22.0);
  final total = ws + wm + wh + 1e-10;
  return LabColor(
    (ws * profile.shadow.l + wm * profile.midtone.l + wh * profile.highlight.l) / total,
    (ws * profile.shadow.a + wm * profile.midtone.a + wh * profile.highlight.a) / total,
    (ws * profile.shadow.b + wm * profile.midtone.b + wh * profile.highlight.b) / total,
  );
}

double _zoneWeight(double l, double center, double sigma) {
  final d = l - center;
  return math.exp(-0.5 * d * d / (sigma * sigma));
}

double _labBlendWeight(double castStrength) {
  // Mild references benefit from Lab contrast/saturation transfer; strong color
  // casts stay closer to channel curves to avoid over-pushing blues and greens.
  return (0.78 - 0.70 * castStrength).clamp(0.18, 0.78);
}

/// Apply a 65³ 3D LUT (float16 binary) to an image pixel via trilinear interpolation.
RgbColor applyLut(Uint8List lutBytes, RgbColor rgb) {
  final lut    = lutBytes.buffer.asUint16List();
  const dim    = _dim;
  final maxIdx = (_dim - 1).toDouble();

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
      _halfToFloat(lut[i]),
      _halfToFloat(lut[i + 1]),
      _halfToFloat(lut[i + 2]),
    );
  }

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

  // Curves (Phase 2)
  if (p.hasCurves) {
    // RGB curve: 모든 채널 동시 적용
    if (p.rgbCurve != null && !p.rgbCurve!.isLinear) {
      final lut = p.rgbCurve!.toLut();
      r = lut[(r.clamp(0.0, 1.0) * 255).round()] / 255.0;
      g = lut[(g.clamp(0.0, 1.0) * 255).round()] / 255.0;
      b = lut[(b.clamp(0.0, 1.0) * 255).round()] / 255.0;
    }
    // 개별 채널 커브
    if (p.redCurve   != null && !p.redCurve!.isLinear) {
      final lut = p.redCurve!.toLut();
      r = lut[(r.clamp(0.0, 1.0) * 255).round()] / 255.0;
    }
    if (p.greenCurve != null && !p.greenCurve!.isLinear) {
      final lut = p.greenCurve!.toLut();
      g = lut[(g.clamp(0.0, 1.0) * 255).round()] / 255.0;
    }
    if (p.blueCurve  != null && !p.blueCurve!.isLinear) {
      final lut = p.blueCurve!.toLut();
      b = lut[(b.clamp(0.0, 1.0) * 255).round()] / 255.0;
    }
    // Luminance curve: Lab L채널에 적용
    if (p.luminanceCurve != null && !p.luminanceCurve!.isLinear) {
      final lut  = p.luminanceCurve!.toLut();
      final lab  = rgbToLab(RgbColor(r.clamp(0.0,1.0), g.clamp(0.0,1.0), b.clamp(0.0,1.0)));
      final lNew = lut[(lab.l / 100.0 * 255).round().clamp(0, 255)] / 255.0 * 100.0;
      final rgb2 = labToRgb(LabColor(lNew, lab.a, lab.b));
      r = rgb2.r; g = rgb2.g; b = rgb2.b;
    }
  }

  // Tonal Contrast (Phase 3): 존별 독립 S-curve
  if (p.tonalShadows != 0 || p.tonalMidtones != 0 || p.tonalHighlights != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    double sCurve(double v, double strength) {
      final f = strength / 100.0;
      return v + f * v * (1 - v) * (v - 0.5) * 4.0;
    }

    double gw(double l, double center) {
      const sigma = 0.2;
      final d = l - center;
      return math.exp(-0.5 * d * d / (sigma * sigma));
    }
    final ws = gw(lum, 0.15);
    final wm = gw(lum, 0.5);
    final wh = gw(lum, 0.85);
    final wTotal = ws + wm + wh + 1e-10;

    final adj = (ws * sCurve(lum, p.tonalShadows) +
                 wm * sCurve(lum, p.tonalMidtones) +
                 wh * sCurve(lum, p.tonalHighlights)) / wTotal - lum;
    r = (r + adj).clamp(0.0, 1.0);
    g = (g + adj).clamp(0.0, 1.0);
    b = (b + adj).clamp(0.0, 1.0);
  }

  // B&W (Phase 3): 채널 가중치 기반 흑백 변환
  if (p.bnwEnabled) {
    final wr = 0.299 + p.bnwRed    / 100.0 * 0.3;
    final wg = 0.587 + p.bnwGreen  / 100.0 * 0.3;
    final wb = 0.114 + p.bnwBlue   / 100.0 * 0.3;
    final wy =         p.bnwYellow / 100.0 * 0.2;
    final L  = (r * wr + g * wg + b * wb + (r + g) / 2.0 * wy)
        .clamp(0.0, 1.0);
    r = L; g = L; b = L;
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
