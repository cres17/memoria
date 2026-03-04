import 'dart:convert';

class AdjustParams {
  final double exposure;   // -2.0 ~ +2.0
  final double contrast;   // -100 ~ +100
  final double saturation; // -100 ~ +100
  final double temperature;// -100 ~ +100
  final double tint;       // -100 ~ +100
  final double highlights; // -100 ~ +100
  final double shadows;    // -100 ~ +100
  final double sharpen;    // 0 ~ 100
  final double vignette;   // 0 ~ 100

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
  }) {
    return AdjustParams(
      exposure:    exposure    ?? this.exposure,
      contrast:    contrast    ?? this.contrast,
      saturation:  saturation  ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint:        tint        ?? this.tint,
      highlights:  highlights  ?? this.highlights,
      shadows:     shadows     ?? this.shadows,
      sharpen:     sharpen     ?? this.sharpen,
      vignette:    vignette    ?? this.vignette,
    );
  }

  Map<String, dynamic> toJson() => {
    'exposure':    exposure,
    'contrast':    contrast,
    'saturation':  saturation,
    'temperature': temperature,
    'tint':        tint,
    'highlights':  highlights,
    'shadows':     shadows,
    'sharpen':     sharpen,
    'vignette':    vignette,
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
  );

  String toJsonString() => jsonEncode(toJson());

  bool get isZero =>
      exposure == 0 && contrast == 0 && saturation == 0 &&
      temperature == 0 && tint == 0 && highlights == 0 &&
      shadows == 0 && sharpen == 0 && vignette == 0;
}
