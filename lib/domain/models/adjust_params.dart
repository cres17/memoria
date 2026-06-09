import 'dart:convert';
import 'curve_data.dart';

// ── HSL band model ────────────────────────────────────────

enum HslBand { red, orange, yellow, green, cyan, blue, purple, magenta }

class HslBandParams {
  final double hue; // -180 ~ +180
  final double saturation; // -100 ~ +100
  final double luminance; // -100 ~ +100

  const HslBandParams({
    this.hue = 0.0,
    this.saturation = 0.0,
    this.luminance = 0.0,
  });

  static const zero = HslBandParams();

  bool get isZero => hue == 0 && saturation == 0 && luminance == 0;

  HslBandParams copyWith({
    double? hue,
    double? saturation,
    double? luminance,
  }) =>
      HslBandParams(
        hue: hue ?? this.hue,
        saturation: saturation ?? this.saturation,
        luminance: luminance ?? this.luminance,
      );

  Map<String, dynamic> toJson() =>
      {'hue': hue, 'saturation': saturation, 'luminance': luminance};

  factory HslBandParams.fromJson(Map<String, dynamic> j) => HslBandParams(
        hue: (j['hue'] as num?)?.toDouble() ?? 0.0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 0.0,
        luminance: (j['luminance'] as num?)?.toDouble() ?? 0.0,
      );
}

typedef HslMap = Map<HslBand, HslBandParams>;

const HslMap _kHslZero = {
  HslBand.red: HslBandParams.zero,
  HslBand.orange: HslBandParams.zero,
  HslBand.yellow: HslBandParams.zero,
  HslBand.green: HslBandParams.zero,
  HslBand.cyan: HslBandParams.zero,
  HslBand.blue: HslBandParams.zero,
  HslBand.purple: HslBandParams.zero,
  HslBand.magenta: HslBandParams.zero,
};

class AdjustParams {
  final double exposure;    // -2.0 ~ +2.0
  final double contrast;    // -100 ~ +100
  final double saturation;  // -100 ~ +100
  final double temperature; // -100 ~ +100
  final double tint;        // -100 ~ +100
  final double highlights;  // -100 ~ +100
  final double shadows;     // -100 ~ +100
  final double sharpen;     // 0 ~ 100
  final double vignette;    // 0 ~ 100
  final double structure;   // -100 ~ +100
  final double clarity;     // -100 ~ +100
  final double ambiance;    // -100 ~ +100

  // Phase 2: Curves
  final CurveData? luminanceCurve;
  final CurveData? rgbCurve;
  final CurveData? redCurve;
  final CurveData? greenCurve;
  final CurveData? blueCurve;

  bool get hasCurves =>
      luminanceCurve != null ||
      rgbCurve != null ||
      redCurve != null ||
      greenCurve != null ||
      blueCurve != null;

  // Phase 3: B&W
  final bool bnwEnabled;
  final double bnwRed;
  final double bnwGreen;
  final double bnwBlue;
  final double bnwYellow;

  // Phase 3: Tonal Contrast
  final double tonalShadows;
  final double tonalMidtones;
  final double tonalHighlights;

  // HSL
  final HslMap hsl;

  // Split Toning
  final double splitShadowHue;
  final double splitShadowSat;
  final double splitHighHue;
  final double splitHighSat;
  final double splitBalance;

  // Film Grain
  final double grainStrength;
  final double grainSize;
  final int grainSeed;

  // Noise Reduction
  final double luminanceNR;
  final double colourNR;
  final double nrDetail;

  // Glamour Glow
  final double glowStrength;
  final double glowSaturation;
  final double glowWarmth;

  // HDR Scape
  final double hdrStrength;
  final double hdrSaturation;

  // Light Leak
  final double lightLeakStrength;
  final double lightLeakAngle;
  final double lightLeakWarmth;

  // Halation
  final double halationStrength;
  final double halationThreshold;
  final double halationWarmth;

  const AdjustParams({
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.sharpen = 0.0,
    this.vignette = 0.0,
    this.structure = 0.0,
    this.clarity = 0.0,
    this.ambiance = 0.0,
    this.luminanceCurve,
    this.rgbCurve,
    this.redCurve,
    this.greenCurve,
    this.blueCurve,
    this.bnwEnabled = false,
    this.bnwRed = 0.0,
    this.bnwGreen = 0.0,
    this.bnwBlue = 0.0,
    this.bnwYellow = 0.0,
    this.tonalShadows = 0.0,
    this.tonalMidtones = 0.0,
    this.tonalHighlights = 0.0,
    this.hsl = _kHslZero,
    this.splitShadowHue = 0.0,
    this.splitShadowSat = 0.0,
    this.splitHighHue = 0.0,
    this.splitHighSat = 0.0,
    this.splitBalance = 0.0,
    this.grainStrength = 0.0,
    this.grainSize = 1.0,
    this.grainSeed = 0,
    this.luminanceNR = 0.0,
    this.colourNR = 0.0,
    this.nrDetail = 0.0,
    this.glowStrength = 0.0,
    this.glowSaturation = 0.0,
    this.glowWarmth = 0.0,
    this.hdrStrength = 0.0,
    this.hdrSaturation = 0.0,
    this.lightLeakStrength = 0.0,
    this.lightLeakAngle = 35.0,
    this.lightLeakWarmth = 55.0,
    this.halationStrength = 0.0,
    this.halationThreshold = 70.0,
    this.halationWarmth = 70.0,
  });

  static const AdjustParams zero = AdjustParams();

  AdjustParams copyWith({
    double? exposure,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? sharpen,
    double? vignette,
    double? structure,
    double? clarity,
    double? ambiance,
    CurveData? luminanceCurve,
    CurveData? rgbCurve,
    CurveData? redCurve,
    CurveData? greenCurve,
    CurveData? blueCurve,
    bool? bnwEnabled,
    double? bnwRed,
    double? bnwGreen,
    double? bnwBlue,
    double? bnwYellow,
    double? tonalShadows,
    double? tonalMidtones,
    double? tonalHighlights,
    HslMap? hsl,
    double? splitShadowHue,
    double? splitShadowSat,
    double? splitHighHue,
    double? splitHighSat,
    double? splitBalance,
    double? grainStrength,
    double? grainSize,
    int? grainSeed,
    double? luminanceNR,
    double? colourNR,
    double? nrDetail,
    double? glowStrength,
    double? glowSaturation,
    double? glowWarmth,
    double? hdrStrength,
    double? hdrSaturation,
    double? lightLeakStrength,
    double? lightLeakAngle,
    double? lightLeakWarmth,
    double? halationStrength,
    double? halationThreshold,
    double? halationWarmth,
  }) {
    return AdjustParams(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      sharpen: sharpen ?? this.sharpen,
      vignette: vignette ?? this.vignette,
      structure: structure ?? this.structure,
      clarity: clarity ?? this.clarity,
      ambiance: ambiance ?? this.ambiance,
      luminanceCurve: luminanceCurve ?? this.luminanceCurve,
      rgbCurve: rgbCurve ?? this.rgbCurve,
      redCurve: redCurve ?? this.redCurve,
      greenCurve: greenCurve ?? this.greenCurve,
      blueCurve: blueCurve ?? this.blueCurve,
      bnwEnabled: bnwEnabled ?? this.bnwEnabled,
      bnwRed: bnwRed ?? this.bnwRed,
      bnwGreen: bnwGreen ?? this.bnwGreen,
      bnwBlue: bnwBlue ?? this.bnwBlue,
      bnwYellow: bnwYellow ?? this.bnwYellow,
      tonalShadows: tonalShadows ?? this.tonalShadows,
      tonalMidtones: tonalMidtones ?? this.tonalMidtones,
      tonalHighlights: tonalHighlights ?? this.tonalHighlights,
      hsl: hsl ?? this.hsl,
      splitShadowHue: splitShadowHue ?? this.splitShadowHue,
      splitShadowSat: splitShadowSat ?? this.splitShadowSat,
      splitHighHue: splitHighHue ?? this.splitHighHue,
      splitHighSat: splitHighSat ?? this.splitHighSat,
      splitBalance: splitBalance ?? this.splitBalance,
      grainStrength: grainStrength ?? this.grainStrength,
      grainSize: grainSize ?? this.grainSize,
      grainSeed: grainSeed ?? this.grainSeed,
      luminanceNR: luminanceNR ?? this.luminanceNR,
      colourNR: colourNR ?? this.colourNR,
      nrDetail: nrDetail ?? this.nrDetail,
      glowStrength: glowStrength ?? this.glowStrength,
      glowSaturation: glowSaturation ?? this.glowSaturation,
      glowWarmth: glowWarmth ?? this.glowWarmth,
      hdrStrength: hdrStrength ?? this.hdrStrength,
      hdrSaturation: hdrSaturation ?? this.hdrSaturation,
      lightLeakStrength: lightLeakStrength ?? this.lightLeakStrength,
      lightLeakAngle: lightLeakAngle ?? this.lightLeakAngle,
      lightLeakWarmth: lightLeakWarmth ?? this.lightLeakWarmth,
      halationStrength: halationStrength ?? this.halationStrength,
      halationThreshold: halationThreshold ?? this.halationThreshold,
      halationWarmth: halationWarmth ?? this.halationWarmth,
    );
  }

  AdjustParams withHslBand(HslBand band, HslBandParams params) {
    final updated = Map<HslBand, HslBandParams>.from(hsl);
    updated[band] = params;
    return copyWith(hsl: updated);
  }

  Map<String, dynamic> toJson() => {
        'exposure': exposure,
        'contrast': contrast,
        'saturation': saturation,
        'temperature': temperature,
        'tint': tint,
        'highlights': highlights,
        'shadows': shadows,
        'sharpen': sharpen,
        'vignette': vignette,
        'structure': structure,
        'clarity': clarity,
        'ambiance': ambiance,
        if (luminanceCurve != null) 'luminanceCurve': luminanceCurve!.toJson(),
        if (rgbCurve != null) 'rgbCurve': rgbCurve!.toJson(),
        if (redCurve != null) 'redCurve': redCurve!.toJson(),
        if (greenCurve != null) 'greenCurve': greenCurve!.toJson(),
        if (blueCurve != null) 'blueCurve': blueCurve!.toJson(),
        'bnwEnabled': bnwEnabled,
        'bnwRed': bnwRed,
        'bnwGreen': bnwGreen,
        'bnwBlue': bnwBlue,
        'bnwYellow': bnwYellow,
        'tonalShadows': tonalShadows,
        'tonalMidtones': tonalMidtones,
        'tonalHighlights': tonalHighlights,
        'hsl': {
          for (final e in hsl.entries) e.key.name: e.value.toJson(),
        },
        'splitShadowHue': splitShadowHue,
        'splitShadowSat': splitShadowSat,
        'splitHighHue': splitHighHue,
        'splitHighSat': splitHighSat,
        'splitBalance': splitBalance,
        'grainStrength': grainStrength,
        'grainSize': grainSize,
        'grainSeed': grainSeed,
        'luminanceNR': luminanceNR,
        'colourNR': colourNR,
        'nrDetail': nrDetail,
        'glowStrength': glowStrength,
        'glowSaturation': glowSaturation,
        'glowWarmth': glowWarmth,
        'hdrStrength': hdrStrength,
        'hdrSaturation': hdrSaturation,
        'lightLeakStrength': lightLeakStrength,
        'lightLeakAngle': lightLeakAngle,
        'lightLeakWarmth': lightLeakWarmth,
        'halationStrength': halationStrength,
        'halationThreshold': halationThreshold,
        'halationWarmth': halationWarmth,
      }..remove('glowWarmWarm'); // Clean up typo helper if any, wait, let's write it cleanly:
      // 'glowWarmth': glowWarmth

  factory AdjustParams.fromJson(Map<String, dynamic> json) {
    HslMap decodedHsl = _kHslZero;
    if (json['hsl'] != null) {
      final map = json['hsl'] as Map<String, dynamic>;
      final temp = Map<HslBand, HslBandParams>.from(_kHslZero);
      for (final band in HslBand.values) {
        if (map[band.name] != null) {
          temp[band] = HslBandParams.fromJson(map[band.name] as Map<String, dynamic>);
        }
      }
      decodedHsl = temp;
    }

    return AdjustParams(
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      sharpen: (json['sharpen'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      structure: (json['structure'] as num?)?.toDouble() ?? 0.0,
      clarity: (json['clarity'] as num?)?.toDouble() ?? 0.0,
      ambiance: (json['ambiance'] as num?)?.toDouble() ?? 0.0,
      luminanceCurve: json['luminanceCurve'] != null
          ? CurveData.fromJson(json['luminanceCurve'] as Map<String, dynamic>)
          : null,
      rgbCurve: json['rgbCurve'] != null
          ? CurveData.fromJson(json['rgbCurve'] as Map<String, dynamic>)
          : null,
      redCurve: json['redCurve'] != null
          ? CurveData.fromJson(json['redCurve'] as Map<String, dynamic>)
          : null,
      greenCurve: json['greenCurve'] != null
          ? CurveData.fromJson(json['greenCurve'] as Map<String, dynamic>)
          : null,
      blueCurve: json['blueCurve'] != null
          ? CurveData.fromJson(json['blueCurve'] as Map<String, dynamic>)
          : null,
      bnwEnabled: json['bnwEnabled'] as bool? ?? false,
      bnwRed: (json['bnwRed'] as num?)?.toDouble() ?? 0.0,
      bnwGreen: (json['bnwGreen'] as num?)?.toDouble() ?? 0.0,
      bnwBlue: (json['bnwBlue'] as num?)?.toDouble() ?? 0.0,
      bnwYellow: (json['bnwYellow'] as num?)?.toDouble() ?? 0.0,
      tonalShadows: (json['tonalShadows'] as num?)?.toDouble() ?? 0.0,
      tonalMidtones: (json['tonalMidtones'] as num?)?.toDouble() ?? 0.0,
      tonalHighlights: (json['tonalHighlights'] as num?)?.toDouble() ?? 0.0,
      hsl: decodedHsl,
      splitShadowHue: (json['splitShadowHue'] as num?)?.toDouble() ?? 0.0,
      splitShadowSat: (json['splitShadowSat'] as num?)?.toDouble() ?? 0.0,
      splitHighHue: (json['splitHighHue'] as num?)?.toDouble() ?? 0.0,
      splitHighSat: (json['splitHighSat'] as num?)?.toDouble() ?? 0.0,
      splitBalance: (json['splitBalance'] as num?)?.toDouble() ?? 0.0,
      grainStrength: (json['grainStrength'] as num?)?.toDouble() ?? 0.0,
      grainSize: (json['grainSize'] as num?)?.toDouble() ?? 1.0,
      grainSeed: (json['grainSeed'] as num?)?.toInt() ?? 0,
      luminanceNR: (json['luminanceNR'] as num?)?.toDouble() ?? 0.0,
      colourNR: (json['colourNR'] as num?)?.toDouble() ?? 0.0,
      nrDetail: (json['nrDetail'] as num?)?.toDouble() ?? 0.0,
      glowStrength: (json['glowStrength'] as num?)?.toDouble() ?? 0.0,
      glowSaturation: (json['glowSaturation'] as num?)?.toDouble() ?? 0.0,
      glowWarmth: (json['glowWarmth'] as num?)?.toDouble() ?? 0.0,
      hdrStrength: (json['hdrStrength'] as num?)?.toDouble() ?? 0.0,
      hdrSaturation: (json['hdrSaturation'] as num?)?.toDouble() ?? 0.0,
      lightLeakStrength: (json['lightLeakStrength'] as num?)?.toDouble() ?? 0.0,
      lightLeakAngle: (json['lightLeakAngle'] as num?)?.toDouble() ?? 35.0,
      lightLeakWarmth: (json['lightLeakWarmth'] as num?)?.toDouble() ?? 55.0,
      halationStrength: (json['halationStrength'] as num?)?.toDouble() ?? 0.0,
      halationThreshold: (json['halationThreshold'] as num?)?.toDouble() ?? 70.0,
      halationWarmth: (json['halationWarmth'] as num?)?.toDouble() ?? 70.0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  String get cacheKey {
    final sb = StringBuffer()
      ..write(exposure.toStringAsFixed(2))
      ..write(',')
      ..write(contrast.toStringAsFixed(2))
      ..write(',')
      ..write(saturation.toStringAsFixed(2))
      ..write(',')
      ..write(temperature.toStringAsFixed(2))
      ..write(',')
      ..write(tint.toStringAsFixed(2))
      ..write(',')
      ..write(highlights.toStringAsFixed(2))
      ..write(',')
      ..write(shadows.toStringAsFixed(2))
      ..write(',')
      ..write(sharpen.toStringAsFixed(2))
      ..write(',')
      ..write(vignette.toStringAsFixed(2))
      ..write(',')
      ..write(structure.toStringAsFixed(2))
      ..write(',')
      ..write(clarity.toStringAsFixed(2))
      ..write(',')
      ..write(ambiance.toStringAsFixed(2))
      ..write(',')
      ..write(bnwEnabled ? '1' : '0')
      ..write(',')
      ..write(bnwRed.toStringAsFixed(2))
      ..write(',')
      ..write(bnwGreen.toStringAsFixed(2))
      ..write(',')
      ..write(bnwBlue.toStringAsFixed(2))
      ..write(',')
      ..write(bnwYellow.toStringAsFixed(2))
      ..write(',')
      ..write(tonalShadows.toStringAsFixed(2))
      ..write(',')
      ..write(tonalMidtones.toStringAsFixed(2))
      ..write(',')
      ..write(tonalHighlights.toStringAsFixed(2))
      ..write(',')
      ..write(splitShadowHue.toStringAsFixed(1))
      ..write(',')
      ..write(splitShadowSat.toStringAsFixed(1))
      ..write(',')
      ..write(splitHighHue.toStringAsFixed(1))
      ..write(',')
      ..write(splitHighSat.toStringAsFixed(1))
      ..write(',')
      ..write(splitBalance.toStringAsFixed(1))
      ..write(',')
      ..write(grainStrength.toStringAsFixed(1))
      ..write(',')
      ..write(grainSize.toStringAsFixed(1))
      ..write(',')
      ..write(grainSeed.toString())
      ..write(',')
      ..write(luminanceNR.toStringAsFixed(1))
      ..write(',')
      ..write(colourNR.toStringAsFixed(1))
      ..write(',')
      ..write(nrDetail.toStringAsFixed(1))
      ..write(',')
      ..write(glowStrength.toStringAsFixed(1))
      ..write(',')
      ..write(glowSaturation.toStringAsFixed(1))
      ..write(',')
      ..write(glowWarmth.toStringAsFixed(1))
      ..write(',')
      ..write(hdrStrength.toStringAsFixed(1))
      ..write(',')
      ..write(hdrSaturation.toStringAsFixed(1))
      ..write(',')
      ..write(lightLeakStrength.toStringAsFixed(1))
      ..write(',')
      ..write(lightLeakAngle.toStringAsFixed(1))
      ..write(',')
      ..write(lightLeakWarmth.toStringAsFixed(1))
      ..write(',')
      ..write(halationStrength.toStringAsFixed(1))
      ..write(',')
      ..write(halationThreshold.toStringAsFixed(1))
      ..write(',')
      ..write(halationWarmth.toStringAsFixed(1));

    for (final band in HslBand.values) {
      final bp = hsl[band] ?? HslBandParams.zero;
      sb.write(',');
      sb.write(bp.hue.toStringAsFixed(1));
      sb.write(':');
      sb.write(bp.saturation.toStringAsFixed(1));
      sb.write(':');
      sb.write(bp.luminance.toStringAsFixed(1));
    }

    for (final curve in [
      luminanceCurve,
      rgbCurve,
      redCurve,
      greenCurve,
      blueCurve
    ]) {
      if (curve == null) {
        sb.write(',~');
      } else {
        sb.write(',');
        sb.write(curve.channel.name[0]);
        for (final pt in curve.points) {
          sb.write(pt.x.toStringAsFixed(3));
          sb.write(':');
          sb.write(pt.y.toStringAsFixed(3));
          sb.write(';');
        }
      }
    }
    return sb.toString();
  }

  bool get hasHsl => hsl.values.any((b) => !b.isZero);

  bool get hasSplitToning => splitShadowSat > 0 || splitHighSat > 0;

  bool get hasGrain => grainStrength > 0;

  bool get hasNoiseReduction => luminanceNR > 0 || colourNR > 0;

  bool get hasGlow => glowStrength > 0;

  bool get hasHdr => hdrStrength > 0;

  bool get hasLightLeak => lightLeakStrength > 0;

  bool get hasHalation => halationStrength > 0;

  bool get isZero =>
      exposure == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      temperature == 0 &&
      tint == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      sharpen == 0 &&
      vignette == 0 &&
      structure == 0 &&
      clarity == 0 &&
      ambiance == 0 &&
      !hasCurves &&
      !bnwEnabled &&
      tonalShadows == 0 &&
      tonalMidtones == 0 &&
      tonalHighlights == 0 &&
      !hasHsl &&
      !hasSplitToning &&
      !hasGrain &&
      !hasNoiseReduction &&
      !hasGlow &&
      !hasHdr &&
      !hasLightLeak &&
      !hasHalation;
}
