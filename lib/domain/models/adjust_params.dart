import 'dart:convert';
import 'curve_data.dart';

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
  final double structure;   // -100 ~ +100  (로컬 콘트라스트/텍스처 강조)
  final double clarity;     // -100 ~ +100  (미드톤 명료도)

  // Phase 2: 커브 (null = 리니어)
  final CurveData? luminanceCurve;
  final CurveData? rgbCurve;
  final CurveData? redCurve;
  final CurveData? greenCurve;
  final CurveData? blueCurve;

  bool get hasCurves =>
      luminanceCurve != null || rgbCurve != null ||
      redCurve != null || greenCurve != null || blueCurve != null;

  // Phase 3: B&W
  final bool   bnwEnabled; // 흑백 모드
  final double bnwRed;     // -100 ~ +100
  final double bnwGreen;   // -100 ~ +100
  final double bnwBlue;    // -100 ~ +100
  final double bnwYellow;  // -100 ~ +100

  // Phase 3: Tonal Contrast (존별 독립 콘트라스트)
  final double tonalShadows;    // -100 ~ +100
  final double tonalMidtones;   // -100 ~ +100
  final double tonalHighlights; // -100 ~ +100

  const AdjustParams({
    this.exposure    = 0.0,
    this.contrast    = 0.0,
    this.saturation  = 0.0,
    this.temperature = 0.0,
    this.tint        = 0.0,
    this.highlights  = 0.0,
    this.shadows     = 0.0,
    this.sharpen     = 0.0,
    this.vignette    = 0.0,
    this.structure   = 0.0,
    this.clarity     = 0.0,
    this.luminanceCurve,
    this.rgbCurve,
    this.redCurve,
    this.greenCurve,
    this.blueCurve,
    this.bnwEnabled      = false,
    this.bnwRed          = 0.0,
    this.bnwGreen        = 0.0,
    this.bnwBlue         = 0.0,
    this.bnwYellow       = 0.0,
    this.tonalShadows    = 0.0,
    this.tonalMidtones   = 0.0,
    this.tonalHighlights = 0.0,
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
    CurveData? luminanceCurve,
    CurveData? rgbCurve,
    CurveData? redCurve,
    CurveData? greenCurve,
    CurveData? blueCurve,
    bool?   bnwEnabled,
    double? bnwRed,
    double? bnwGreen,
    double? bnwBlue,
    double? bnwYellow,
    double? tonalShadows,
    double? tonalMidtones,
    double? tonalHighlights,
  }) {
    return AdjustParams(
      exposure:        exposure        ?? this.exposure,
      contrast:        contrast        ?? this.contrast,
      saturation:      saturation      ?? this.saturation,
      temperature:     temperature     ?? this.temperature,
      tint:            tint            ?? this.tint,
      highlights:      highlights      ?? this.highlights,
      shadows:         shadows         ?? this.shadows,
      sharpen:         sharpen         ?? this.sharpen,
      vignette:        vignette        ?? this.vignette,
      structure:       structure       ?? this.structure,
      clarity:         clarity         ?? this.clarity,
      luminanceCurve:  luminanceCurve  ?? this.luminanceCurve,
      rgbCurve:        rgbCurve        ?? this.rgbCurve,
      redCurve:        redCurve        ?? this.redCurve,
      greenCurve:      greenCurve      ?? this.greenCurve,
      blueCurve:       blueCurve       ?? this.blueCurve,
      bnwEnabled:      bnwEnabled      ?? this.bnwEnabled,
      bnwRed:          bnwRed          ?? this.bnwRed,
      bnwGreen:        bnwGreen        ?? this.bnwGreen,
      bnwBlue:         bnwBlue         ?? this.bnwBlue,
      bnwYellow:       bnwYellow       ?? this.bnwYellow,
      tonalShadows:    tonalShadows    ?? this.tonalShadows,
      tonalMidtones:   tonalMidtones   ?? this.tonalMidtones,
      tonalHighlights: tonalHighlights ?? this.tonalHighlights,
    );
  }

  Map<String, dynamic> toJson() => {
    'exposure':       exposure,
    'contrast':       contrast,
    'saturation':     saturation,
    'temperature':    temperature,
    'tint':           tint,
    'highlights':     highlights,
    'shadows':        shadows,
    'sharpen':        sharpen,
    'vignette':       vignette,
    'structure':      structure,
    'clarity':        clarity,
    if (luminanceCurve != null) 'luminanceCurve': luminanceCurve!.toJson(),
    if (rgbCurve       != null) 'rgbCurve':       rgbCurve!.toJson(),
    if (redCurve       != null) 'redCurve':        redCurve!.toJson(),
    if (greenCurve     != null) 'greenCurve':      greenCurve!.toJson(),
    if (blueCurve      != null) 'blueCurve':       blueCurve!.toJson(),
    'bnwEnabled':      bnwEnabled,
    'bnwRed':          bnwRed,
    'bnwGreen':        bnwGreen,
    'bnwBlue':         bnwBlue,
    'bnwYellow':       bnwYellow,
    'tonalShadows':    tonalShadows,
    'tonalMidtones':   tonalMidtones,
    'tonalHighlights': tonalHighlights,
  };

  factory AdjustParams.fromJson(Map<String, dynamic> json) => AdjustParams(
    exposure:    (json['exposure']    as num?)?.toDouble() ?? 0.0,
    contrast:    (json['contrast']    as num?)?.toDouble() ?? 0.0,
    saturation:  (json['saturation']  as num?)?.toDouble() ?? 0.0,
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
    tint:        (json['tint']        as num?)?.toDouble() ?? 0.0,
    highlights:  (json['highlights']  as num?)?.toDouble() ?? 0.0,
    shadows:     (json['shadows']     as num?)?.toDouble() ?? 0.0,
    sharpen:     (json['sharpen']     as num?)?.toDouble() ?? 0.0,
    vignette:    (json['vignette']    as num?)?.toDouble() ?? 0.0,
    structure:   (json['structure']   as num?)?.toDouble() ?? 0.0,
    clarity:     (json['clarity']     as num?)?.toDouble() ?? 0.0,
    luminanceCurve: json['luminanceCurve'] != null
        ? CurveData.fromJson(json['luminanceCurve'] as Map<String, dynamic>) : null,
    rgbCurve:    json['rgbCurve']    != null
        ? CurveData.fromJson(json['rgbCurve']    as Map<String, dynamic>) : null,
    redCurve:    json['redCurve']    != null
        ? CurveData.fromJson(json['redCurve']    as Map<String, dynamic>) : null,
    greenCurve:  json['greenCurve']  != null
        ? CurveData.fromJson(json['greenCurve']  as Map<String, dynamic>) : null,
    blueCurve:   json['blueCurve']   != null
        ? CurveData.fromJson(json['blueCurve']   as Map<String, dynamic>) : null,
    bnwEnabled:      json['bnwEnabled']      as bool?   ?? false,
    bnwRed:          (json['bnwRed']          as num?)?.toDouble() ?? 0.0,
    bnwGreen:        (json['bnwGreen']        as num?)?.toDouble() ?? 0.0,
    bnwBlue:         (json['bnwBlue']         as num?)?.toDouble() ?? 0.0,
    bnwYellow:       (json['bnwYellow']       as num?)?.toDouble() ?? 0.0,
    tonalShadows:    (json['tonalShadows']    as num?)?.toDouble() ?? 0.0,
    tonalMidtones:   (json['tonalMidtones']   as num?)?.toDouble() ?? 0.0,
    tonalHighlights: (json['tonalHighlights'] as num?)?.toDouble() ?? 0.0,
  );

  String toJsonString() => jsonEncode(toJson());

  bool get isZero =>
      exposure == 0 && contrast == 0 && saturation == 0 &&
      temperature == 0 && tint == 0 && highlights == 0 &&
      shadows == 0 && sharpen == 0 && vignette == 0 &&
      structure == 0 && clarity == 0 && !hasCurves &&
      !bnwEnabled &&
      tonalShadows == 0 && tonalMidtones == 0 && tonalHighlights == 0;
}
