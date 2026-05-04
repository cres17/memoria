import 'dart:convert';
import 'adjust_params.dart';
import 'curve_data.dart';

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

/// Built-in filter presets — Snapseed-style, params-only (no external LUT file)
class BuiltinPresets {
  static const List<String> ids = [
    'original',
    'portrait',
    'smooth',
    'pop',
    'accentuate',
    'faded_glow',
    'morning',
    'fine_art',
    'structure',
  ];

  static FilterPreset _make({
    required String id,
    required String name,
    required AdjustParams params,
    double intensity = 1.0,
  }) =>
      FilterPreset(
        id:               id,
        name:             name,
        type:             FilterPresetType.builtin,
        lutPath:          '',
        params:           params,
        defaultIntensity: intensity,
        thumbnailPath:    'assets/images/${id}_thumb.jpg',
        createdAt:        DateTime(2026, 5, 3),
        updatedAt:        DateTime(2026, 5, 3),
      );

  static FilterPreset get original => _make(
    id: 'original', name: 'Original',
    params: AdjustParams.zero,
  );

  /// 인물의 피부톤을 밝게, 눈 강조
  static FilterPreset get portrait => _make(
    id: 'portrait', name: 'Portrait',
    intensity: 0.85,
    params: const AdjustParams(
      exposure:    0.15,
      highlights: -20,
      shadows:     25,
      temperature:  8,   // 피부 따뜻하게
      tint:         4,
      saturation:   8,
      clarity:     15,   // 눈·입술 디테일
      vignette:    18,
    ),
  );

  /// 노이즈 감소, 부드러운 질감
  static FilterPreset get smooth => _make(
    id: 'smooth', name: 'Smooth',
    intensity: 0.9,
    params: AdjustParams(
      exposure:    0.05,
      highlights: -15,
      shadows:     10,
      saturation:   5,
      clarity:    -30,   // 미드톤 부드럽게
      structure:  -20,   // 텍스처 억제
      luminanceCurve: const CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0.0, 0.0),
          CurvePoint(0.4, 0.42),
          CurvePoint(0.75, 0.78),
          CurvePoint(1.0, 1.0),
        ],
      ),
    ),
  );

  /// 색 대비·선명도 강조
  static FilterPreset get pop => _make(
    id: 'pop', name: 'Pop',
    params: const AdjustParams(
      contrast:    25,
      saturation:  30,
      sharpen:     30,
      clarity:     20,
      highlights:  -10,
      shadows:      10,
      vignette:    12,
    ),
  );

  /// 디테일 극대화, 드라마틱한 명암
  static FilterPreset get accentuate => _make(
    id: 'accentuate', name: 'Accentuate',
    params: AdjustParams(
      contrast:    35,
      structure:   60,
      clarity:     40,
      sharpen:     25,
      highlights: -25,
      shadows:    -15,
      vignette:    30,
      luminanceCurve: const CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0.0,  0.0),
          CurvePoint(0.25, 0.18),
          CurvePoint(0.5,  0.5),
          CurvePoint(0.75, 0.83),
          CurvePoint(1.0,  1.0),
        ],
      ),
    ),
  );

  /// 물 빠진 느낌 + 부드러운 광원
  static FilterPreset get fadedGlow => _make(
    id: 'faded_glow', name: 'Faded Glow',
    intensity: 0.9,
    params: AdjustParams(
      exposure:    0.2,
      highlights:  15,
      shadows:     30,
      saturation: -15,
      temperature:  5,
      clarity:    -20,
      luminanceCurve: const CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0.0,  0.08),  // 블랙 리프트
          CurvePoint(0.5,  0.58),
          CurvePoint(1.0,  0.95),  // 하이라이트 압축
        ],
      ),
      rgbCurve: const CurveData(
        channel: CurveChannel.rgb,
        points: [
          CurvePoint(0.0,  0.06),
          CurvePoint(0.5,  0.52),
          CurvePoint(1.0,  0.94),
        ],
      ),
    ),
  );

  /// 아침 햇살, 밝고 화사한 노출
  static FilterPreset get morning => _make(
    id: 'morning', name: 'Morning',
    params: AdjustParams(
      exposure:    0.35,
      temperature: 18,   // 따뜻한 햇살
      tint:         6,
      highlights:  -20,
      shadows:     35,
      saturation:  12,
      clarity:      8,
      luminanceCurve: const CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0.0,  0.0),
          CurvePoint(0.35, 0.45),  // 섀도 리프트
          CurvePoint(0.7,  0.78),
          CurvePoint(1.0,  1.0),
        ],
      ),
      redCurve: const CurveData(
        channel: CurveChannel.red,
        points: [
          CurvePoint(0.0, 0.0),
          CurvePoint(0.5, 0.56),  // 붉은 미드톤 강조
          CurvePoint(1.0, 1.0),
        ],
      ),
    ),
  );

  /// 흑백, 대비 극대화
  static FilterPreset get fineArt => _make(
    id: 'fine_art', name: 'Fine Art',
    params: AdjustParams(
      bnwEnabled:  true,
      bnwRed:      15,   // 피부톤 밝게
      bnwGreen:    10,
      bnwBlue:    -20,   // 하늘·그림자 어둡게
      bnwYellow:   20,
      contrast:    40,
      clarity:     30,
      structure:   25,
      vignette:    35,
      tonalShadows:   -20,
      tonalHighlights: 10,
      luminanceCurve: const CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0.0,  0.0),
          CurvePoint(0.2,  0.12),
          CurvePoint(0.5,  0.5),
          CurvePoint(0.8,  0.9),
          CurvePoint(1.0,  1.0),
        ],
      ),
    ),
  );

  /// 질감·구조 강하게 표현
  static FilterPreset get structureFilter => _make(
    id: 'structure', name: 'Structure',
    params: const AdjustParams(
      structure:   80,
      clarity:     50,
      sharpen:     35,
      contrast:    20,
      highlights: -15,
      shadows:    -10,
    ),
  );

  static List<FilterPreset> get all => [
    original,
    portrait,
    smooth,
    pop,
    accentuate,
    fadedGlow,
    morning,
    fineArt,
    structureFilter,
  ];
}
