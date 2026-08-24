/// Versioned, portable metadata for recreating a generated filter result.
///
/// The actual LUT is intentionally kept as a separate binary file. A recipe
/// records its contract and diagnostics, but never stores source image paths
/// or pixels.
class FilterRecipe {
  static const int currentVersion = 1;
  static const String srgb = 'sRGB';
  static const String rFastestRgb = 'r_fastest_rgb';
  static const String currentRenderOrder = 'lut_then_adjust_then_intensity';

  final int version;
  final String colorSpace;
  final int lutDimension;
  final String lutAxisOrder;
  final String renderOrder;
  final String engineVersion;
  final String generatorType;
  final double lutStrength;
  final int referenceCount;
  final Map<String, dynamic> safetyMetrics;
  final Map<String, dynamic>? referenceFusion;
  final String? fallbackReason;
  final String? modelId;
  final String? modelVersion;
  final LutAssetProvenance? assetProvenance;

  FilterRecipe({
    this.version = currentVersion,
    this.colorSpace = srgb,
    required this.lutDimension,
    this.lutAxisOrder = rFastestRgb,
    this.renderOrder = currentRenderOrder,
    required this.engineVersion,
    required this.generatorType,
    required this.lutStrength,
    required this.referenceCount,
    Map<String, dynamic> safetyMetrics = const {},
    Map<String, dynamic>? referenceFusion,
    this.fallbackReason,
    this.modelId,
    this.modelVersion,
    this.assetProvenance,
  })  : safetyMetrics = Map.unmodifiable(safetyMetrics),
        referenceFusion =
            referenceFusion == null ? null : Map.unmodifiable(referenceFusion);

  factory FilterRecipe.legacy({
    required bool hasLut,
    required String presetType,
  }) =>
      FilterRecipe(
        lutDimension: hasLut ? 65 : 0,
        engineVersion: 'legacy_preset_v0',
        generatorType: 'legacy_$presetType',
        lutStrength: 1.0,
        referenceCount: 0,
      );

  factory FilterRecipe.fromJson(Map<String, dynamic> json) {
    final provenance = json['assetProvenance'];
    final fusion = json['referenceFusion'];
    final metrics = json['safetyMetrics'];
    return FilterRecipe(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      colorSpace: json['colorSpace'] as String? ?? srgb,
      lutDimension: (json['lutDimension'] as num?)?.toInt() ?? 0,
      lutAxisOrder: json['lutAxisOrder'] as String? ?? rFastestRgb,
      renderOrder: json['renderOrder'] as String? ?? currentRenderOrder,
      engineVersion: json['engineVersion'] as String? ?? 'unknown',
      generatorType: json['generatorType'] as String? ?? 'unknown',
      lutStrength: (json['lutStrength'] as num?)?.toDouble() ?? 1.0,
      referenceCount: (json['referenceCount'] as num?)?.toInt() ?? 0,
      safetyMetrics: metrics is Map
          ? Map<String, dynamic>.from(metrics)
          : const <String, dynamic>{},
      referenceFusion: fusion is Map ? Map<String, dynamic>.from(fusion) : null,
      fallbackReason: json['fallbackReason'] as String?,
      modelId: json['modelId'] as String?,
      modelVersion: json['modelVersion'] as String?,
      assetProvenance: provenance is Map
          ? LutAssetProvenance.fromJson(Map<String, dynamic>.from(provenance))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'colorSpace': colorSpace,
        'lutDimension': lutDimension,
        'lutAxisOrder': lutAxisOrder,
        'renderOrder': renderOrder,
        'engineVersion': engineVersion,
        'generatorType': generatorType,
        'lutStrength': lutStrength,
        'referenceCount': referenceCount,
        'safetyMetrics': safetyMetrics,
        if (referenceFusion != null) 'referenceFusion': referenceFusion,
        if (fallbackReason != null) 'fallbackReason': fallbackReason,
        if (modelId != null) 'modelId': modelId,
        if (modelVersion != null) 'modelVersion': modelVersion,
        if (assetProvenance != null)
          'assetProvenance': assetProvenance!.toJson(),
      };
}

/// Provenance required before a bundled LUT can be selected at runtime.
class LutAssetProvenance {
  final String source;
  final String license;
  final String? sourceUrl;
  final String? attribution;
  final bool commercialUseVerified;
  final bool redistributionVerified;

  const LutAssetProvenance({
    required this.source,
    required this.license,
    this.sourceUrl,
    this.attribution,
    required this.commercialUseVerified,
    required this.redistributionVerified,
  });

  bool get isRuntimeEligible =>
      commercialUseVerified &&
      redistributionVerified &&
      license != 'unverified';

  factory LutAssetProvenance.fromJson(Map<String, dynamic> json) =>
      LutAssetProvenance(
        source: json['source'] as String? ?? 'unknown',
        license: json['license'] as String? ?? 'unverified',
        sourceUrl: json['sourceUrl'] as String?,
        attribution: json['attribution'] as String?,
        commercialUseVerified: json['commercialUseVerified'] as bool? ?? false,
        redistributionVerified:
            json['redistributionVerified'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'license': license,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (attribution != null) 'attribution': attribution,
        'commercialUseVerified': commercialUseVerified,
        'redistributionVerified': redistributionVerified,
      };
}
