import 'dart:convert';

import 'adjust_params.dart';
import 'filter_recipe.dart';

enum FilterPresetType { builtin, custom }

enum FilterBrand { fujifilm, leica }

extension FilterBrandPresentation on FilterBrand {
  String get wordmark => switch (this) {
        FilterBrand.fujifilm => 'FUJIFILM',
        FilterBrand.leica => 'LEICA',
      };
}

FilterBrand? _filterBrandFromName(Object? raw) {
  if (raw is! String) return null;
  for (final brand in FilterBrand.values) {
    if (brand.name == raw) return brand;
  }
  return null;
}

class FilterPreset {
  final String id;
  final String name;
  final FilterPresetType type;
  final String lutPath;
  final AdjustParams params;
  final double defaultIntensity;
  final String thumbnailPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FilterRecipe? recipe;
  final FilterBrand? brand;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.type,
    required this.lutPath,
    required this.params,
    required this.defaultIntensity,
    required this.thumbnailPath,
    required this.createdAt,
    required this.updatedAt,
    this.recipe,
    this.brand,
  });

  FilterPreset copyWith({
    String? id,
    String? name,
    FilterPresetType? type,
    String? lutPath,
    AdjustParams? params,
    double? defaultIntensity,
    String? thumbnailPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    FilterRecipe? recipe,
    FilterBrand? brand,
  }) {
    return FilterPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      lutPath: lutPath ?? this.lutPath,
      params: params ?? this.params,
      defaultIntensity: defaultIntensity ?? this.defaultIntensity,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      recipe: recipe ?? this.recipe,
      brand: brand ?? this.brand,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'lut_path': lutPath,
        'params': params.toJson(),
        'default_intensity': defaultIntensity,
        'thumbnail_path': thumbnailPath,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'recipe': effectiveRecipe.toJson(),
        if (brand != null) 'brand': brand!.name,
      };

  factory FilterPreset.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'custom'
        ? FilterPresetType.custom
        : FilterPresetType.builtin;
    final lutPath = json['lut_path'] as String;
    final recipeJson = json['recipe'];
    return FilterPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      type: type,
      lutPath: lutPath,
      params: AdjustParams.fromJson(json['params'] as Map<String, dynamic>),
      defaultIntensity: (json['default_intensity'] as num).toDouble(),
      thumbnailPath: json['thumbnail_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      recipe: recipeJson is Map
          ? FilterRecipe.fromJson(Map<String, dynamic>.from(recipeJson))
          : FilterRecipe.legacy(
              hasLut: lutPath.isNotEmpty,
              presetType: type.name,
            ),
      brand: _filterBrandFromName(json['brand']),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  bool get isCustom => type == FilterPresetType.custom;
  bool get isBuiltin => type == FilterPresetType.builtin;

  /// Legacy presets acquire this deterministic v0 descriptor on read and are
  /// serialized as v1 on their next repository write.
  FilterRecipe get effectiveRecipe =>
      recipe ??
      FilterRecipe.legacy(
        hasLut: lutPath.isNotEmpty,
        presetType: type.name,
      );
}

/// Product-visible built-in filters.
///
/// Only the approved Fujifilm and Leica LUT families are exposed, plus an
/// Original reset entry. Each thumbnail is generated from one fixed scene with
/// the preset LUT applied so users compare color intent instead of scene content.
class BuiltinPresets {
  static const List<String> ids = [
    'original',
    'fuji_provia',
    'fuji_velvia',
    'fuji_astia',
    'fuji_classic_chrome',
    'fuji_classic_neg',
    'fuji_nostalgic_neg',
    'fuji_pro_neg_hi',
    'fuji_pro_neg_std',
    'fuji_eterna',
    'fuji_acros',
    'fuji_acros_ye',
    'fuji_acros_r',
    'fuji_acros_g',
    'fuji_mono',
    'fuji_mono_ye',
    'fuji_mono_r',
    'fuji_mono_g',
    'fuji_sepia',
    'leica_m8',
    'leica_m8_bw',
    'leica_chocolate',
    'leica_chocolate_hc',
    'leica_chocolate_ehc',
  ];

  static FilterPreset _lut({
    required String id,
    required String name,
    required FilterBrand brand,
    double intensity = 0.9,
  }) =>
      FilterPreset(
        id: id,
        name: name,
        type: FilterPresetType.builtin,
        lutPath: 'assets/luts/$id.bin',
        params: AdjustParams.zero,
        defaultIntensity: intensity,
        thumbnailPath: 'assets/images/${id}_thumb.jpg',
        createdAt: DateTime(2026, 5, 3),
        updatedAt: DateTime(2026, 5, 3),
        brand: brand,
      );

  static FilterPreset get original => FilterPreset(
        id: 'original',
        name: 'Original',
        type: FilterPresetType.builtin,
        lutPath: '',
        params: AdjustParams.zero,
        defaultIntensity: 1,
        thumbnailPath: 'assets/images/original_thumb.jpg',
        createdAt: DateTime(2026, 5, 3),
        updatedAt: DateTime(2026, 5, 3),
      );

  static FilterPreset get fujiProvia =>
      _lut(id: 'fuji_provia', name: 'Provia', brand: FilterBrand.fujifilm);
  static FilterPreset get fujiVelvia => _lut(
      id: 'fuji_velvia',
      name: 'Velvia',
      brand: FilterBrand.fujifilm,
      intensity: 0.85);
  static FilterPreset get fujiAstia =>
      _lut(id: 'fuji_astia', name: 'Astia', brand: FilterBrand.fujifilm);
  static FilterPreset get fujiClassicChrome => _lut(
      id: 'fuji_classic_chrome',
      name: 'Classic Chrome',
      brand: FilterBrand.fujifilm);
  static FilterPreset get fujiClassicNegative => _lut(
      id: 'fuji_classic_neg',
      name: 'Classic Negative',
      brand: FilterBrand.fujifilm);
  static FilterPreset get fujiNostalgicNegative => _lut(
      id: 'fuji_nostalgic_neg',
      name: 'Nostalgic Negative',
      brand: FilterBrand.fujifilm);
  static FilterPreset get fujiProNegativeHigh => _lut(
      id: 'fuji_pro_neg_hi', name: 'Pro Neg. Hi', brand: FilterBrand.fujifilm);
  static FilterPreset get fujiProNegativeStandard => _lut(
      id: 'fuji_pro_neg_std',
      name: 'Pro Neg. Std',
      brand: FilterBrand.fujifilm);
  static FilterPreset get fujiEterna =>
      _lut(id: 'fuji_eterna', name: 'Eterna', brand: FilterBrand.fujifilm);
  static FilterPreset get fujiAcros => _lut(
      id: 'fuji_acros',
      name: 'ACROS',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiAcrosYellow => _lut(
      id: 'fuji_acros_ye',
      name: 'ACROS + Ye',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiAcrosRed => _lut(
      id: 'fuji_acros_r',
      name: 'ACROS + R',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiAcrosGreen => _lut(
      id: 'fuji_acros_g',
      name: 'ACROS + G',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiMonochrome => _lut(
      id: 'fuji_mono',
      name: 'Monochrome',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiMonochromeYellow => _lut(
      id: 'fuji_mono_ye',
      name: 'Monochrome + Ye',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiMonochromeRed => _lut(
      id: 'fuji_mono_r',
      name: 'Monochrome + R',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiMonochromeGreen => _lut(
      id: 'fuji_mono_g',
      name: 'Monochrome + G',
      brand: FilterBrand.fujifilm,
      intensity: 1);
  static FilterPreset get fujiSepia => _lut(
      id: 'fuji_sepia',
      name: 'Sepia',
      brand: FilterBrand.fujifilm,
      intensity: 0.85);
  static FilterPreset get leicaM8 =>
      _lut(id: 'leica_m8', name: 'M8', brand: FilterBrand.leica);
  static FilterPreset get leicaM8BlackAndWhite => _lut(
      id: 'leica_m8_bw',
      name: 'M8 Monochrom',
      brand: FilterBrand.leica,
      intensity: 1);
  static FilterPreset get leicaChocolate =>
      _lut(id: 'leica_chocolate', name: 'Chocolate', brand: FilterBrand.leica);
  static FilterPreset get leicaChocolateHighContrast => _lut(
      id: 'leica_chocolate_hc', name: 'Chocolate HC', brand: FilterBrand.leica);
  static FilterPreset get leicaChocolateExtraHighContrast => _lut(
      id: 'leica_chocolate_ehc',
      name: 'Chocolate EHC',
      brand: FilterBrand.leica,
      intensity: 0.85);

  static List<FilterPreset> get all => [
        original,
        fujiProvia,
        fujiVelvia,
        fujiAstia,
        fujiClassicChrome,
        fujiClassicNegative,
        fujiNostalgicNegative,
        fujiProNegativeHigh,
        fujiProNegativeStandard,
        fujiEterna,
        fujiAcros,
        fujiAcrosYellow,
        fujiAcrosRed,
        fujiAcrosGreen,
        fujiMonochrome,
        fujiMonochromeYellow,
        fujiMonochromeRed,
        fujiMonochromeGreen,
        fujiSepia,
        leicaM8,
        leicaM8BlackAndWhite,
        leicaChocolate,
        leicaChocolateHighContrast,
        leicaChocolateExtraHighContrast,
      ];
}
