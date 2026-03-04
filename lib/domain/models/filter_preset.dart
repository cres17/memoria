import 'dart:convert';
import 'adjust_params.dart';

enum FilterPresetType { builtin, custom }

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
  }) {
    return FilterPreset(
      id:               id               ?? this.id,
      name:             name             ?? this.name,
      type:             type             ?? this.type,
      lutPath:          lutPath          ?? this.lutPath,
      params:           params           ?? this.params,
      defaultIntensity: defaultIntensity ?? this.defaultIntensity,
      thumbnailPath:    thumbnailPath    ?? this.thumbnailPath,
      createdAt:        createdAt        ?? this.createdAt,
      updatedAt:        updatedAt        ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'name':             name,
    'type':             type.name,
    'lut_path':         lutPath,
    'params':           params.toJson(),
    'default_intensity':defaultIntensity,
    'thumbnail_path':   thumbnailPath,
    'created_at':       createdAt.toIso8601String(),
    'updated_at':       updatedAt.toIso8601String(),
  };

  factory FilterPreset.fromJson(Map<String, dynamic> json) => FilterPreset(
    id:               json['id'] as String,
    name:             json['name'] as String,
    type:             json['type'] == 'custom'
                        ? FilterPresetType.custom
                        : FilterPresetType.builtin,
    lutPath:          json['lut_path'] as String,
    params:           AdjustParams.fromJson(
                        json['params'] as Map<String, dynamic>),
    defaultIntensity: (json['default_intensity'] as num).toDouble(),
    thumbnailPath:    json['thumbnail_path'] as String,
    createdAt:        DateTime.parse(json['created_at'] as String),
    updatedAt:        DateTime.parse(json['updated_at'] as String),
  );

  String toJsonString() => jsonEncode(toJson());

  bool get isCustom => type == FilterPresetType.custom;
  bool get isBuiltin => type == FilterPresetType.builtin;
}

/// Built-in filter presets (names only; LUT assets bundled)
class BuiltinPresets {
  static const List<String> names = [
    'Original',
    'Vivid',
    'Cool',
    'Warm',
    'Fade',
    'Noir',
    'Pastel',
    'Golden',
  ];

  static FilterPreset fromName(String name) {
    final id = name.toLowerCase();
    return FilterPreset(
      id:               id,
      name:             name,
      type:             FilterPresetType.builtin,
      lutPath:          name == 'Original' ? '' : 'assets/luts/$id.bin',
      params:           AdjustParams.zero,
      defaultIntensity: 1.0,
      thumbnailPath:    'assets/images/${id}_thumb.jpg',
      createdAt:        DateTime(2026, 3, 4),
      updatedAt:        DateTime(2026, 3, 4),
    );
  }

  static List<FilterPreset> get all =>
      names.map((n) => fromName(n)).toList();
}
