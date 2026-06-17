import 'dart:convert';
import 'dart:typed_data';
import 'adjust_params.dart';
import 'crop_ratio_preset.dart';
import 'curve_data.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/portrait_engine.dart' show SkinTone;

// ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????
//  EditOperation ????쑵?녷꽴??紐꾩춿 ?臾믩씜 ??μ맄
//  筌뤴뫀諭??紐꾩춿?? ??????놁벥 ?紐꾨뮞??곷뮞嚥?疫꿸퀡以??몃빍??
//  EditSession.ops ?귐딅뮞?紐꾨퓠 ??뽮퐣??嚥??蹂?뵠筌?
//  EditOperationPlayer揶쎛 ??? ??뽮퐣??嚥??????븍퉸 筌ㅼ뮇伊????筌왖??筌띾슢踰??덈뼄.
// ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????

enum EditToolType {
  globalAdjust,
  filter,
  curve,
  crop,
  brush,
  selective,
  heal,
  portrait,
  creative,
  hslAdjust,
  splitTone,
  grainOverlay,
  rawDevelop,
  details,
  vignette,
  glow,
  drama,
  lightLeak,
  halation,
}

// ???? ????疫꿸퀬釉?癰궰€???怨밴묶 ????????????????????????????????????????????????????????????????????

class CropState {
  final CropRatioPreset ratio;
  final double centerX; // 0-1
  final double centerY;
  final double cropLeft; // 0.0 ~ 1.0
  final double cropTop; // 0.0 ~ 1.0
  final double cropRight; // 0.0 ~ 1.0
  final double cropBottom; // 0.0 ~ 1.0
  final double rotation; // degrees -45..+45
  final bool flipH;
  final bool flipV;
  final double perspH; // degrees
  final double perspV;

  // Canvas Expand fields
  final double expandTop; // 0.0 ~ 0.5 (fraction of original height)
  final double expandBottom;
  final double expandLeft; // 0.0 ~ 0.5 (fraction of original width)
  final double expandRight;
  final String expandMode; // 'smart', 'white', 'black'

  const CropState({
    this.ratio = CropRatioPreset.free,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.cropLeft = 0.0,
    this.cropTop = 0.0,
    this.cropRight = 1.0,
    this.cropBottom = 1.0,
    this.rotation = 0.0,
    this.flipH = false,
    this.flipV = false,
    this.perspH = 0.0,
    this.perspV = 0.0,
    this.expandTop = 0.0,
    this.expandBottom = 0.0,
    this.expandLeft = 0.0,
    this.expandRight = 0.0,
    this.expandMode = 'smart',
  });

  static const identity = CropState();

  bool get isIdentity =>
      ratio == CropRatioPreset.free &&
      cropLeft == 0.0 &&
      cropTop == 0.0 &&
      cropRight == 1.0 &&
      cropBottom == 1.0 &&
      !flipH &&
      !flipV &&
      rotation == 0 &&
      perspH == 0 &&
      perspV == 0 &&
      expandTop == 0 &&
      expandBottom == 0 &&
      expandLeft == 0 &&
      expandRight == 0;

  CropState copyWith({
    CropRatioPreset? ratio,
    double? centerX,
    double? centerY,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    double? rotation,
    bool? flipH,
    bool? flipV,
    double? perspH,
    double? perspV,
    double? expandTop,
    double? expandBottom,
    double? expandLeft,
    double? expandRight,
    String? expandMode,
  }) =>
      CropState(
        ratio: ratio ?? this.ratio,
        centerX: centerX ?? this.centerX,
        centerY: centerY ?? this.centerY,
        cropLeft: cropLeft ?? this.cropLeft,
        cropTop: cropTop ?? this.cropTop,
        cropRight: cropRight ?? this.cropRight,
        cropBottom: cropBottom ?? this.cropBottom,
        rotation: rotation ?? this.rotation,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        perspH: perspH ?? this.perspH,
        perspV: perspV ?? this.perspV,
        expandTop: expandTop ?? this.expandTop,
        expandBottom: expandBottom ?? this.expandBottom,
        expandLeft: expandLeft ?? this.expandLeft,
        expandRight: expandRight ?? this.expandRight,
        expandMode: expandMode ?? this.expandMode,
      );

  Map<String, dynamic> toJson() => {
        'ratio': ratio.name,
        'centerX': centerX,
        'centerY': centerY,
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropRight': cropRight,
        'cropBottom': cropBottom,
        'rotation': rotation,
        'flipH': flipH,
        'flipV': flipV,
        'perspH': perspH,
        'perspV': perspV,
        'expandTop': expandTop,
        'expandBottom': expandBottom,
        'expandLeft': expandLeft,
        'expandRight': expandRight,
        'expandMode': expandMode,
      };

  factory CropState.fromJson(Map<String, dynamic> j) => CropState(
        ratio: CropRatioPreset.values.firstWhere(
          (e) => e.name == (j['ratio'] as String? ?? 'free'),
          orElse: () => CropRatioPreset.free,
        ),
        centerX: (j['centerX'] as num? ?? 0.5).toDouble(),
        centerY: (j['centerY'] as num? ?? 0.5).toDouble(),
        cropLeft: (j['cropLeft'] as num? ?? 0.0).toDouble(),
        cropTop: (j['cropTop'] as num? ?? 0.0).toDouble(),
        cropRight: (j['cropRight'] as num? ?? 1.0).toDouble(),
        cropBottom: (j['cropBottom'] as num? ?? 1.0).toDouble(),
        rotation: (j['rotation'] as num? ?? 0.0).toDouble(),
        flipH: j['flipH'] as bool? ?? false,
        flipV: j['flipV'] as bool? ?? false,
        perspH: (j['perspH'] as num? ?? 0.0).toDouble(),
        perspV: (j['perspV'] as num? ?? 0.0).toDouble(),
        expandTop: (j['expandTop'] as num? ?? 0.0).toDouble(),
        expandBottom: (j['expandBottom'] as num? ?? 0.0).toDouble(),
        expandLeft: (j['expandLeft'] as num? ?? 0.0).toDouble(),
        expandRight: (j['expandRight'] as num? ?? 0.0).toDouble(),
        expandMode: j['expandMode'] as String? ?? 'smart',
      );
}

// ???? ?紐꺪?癰귣똻?????뵬沃섎챸苑?????????????????????????????????????????????????????????????????????????

class PortraitParams {
  final double smooth; // 0-100
  final double spotlight; // 0-100
  final SkinTone skinTone;
  final double skinToneStrength; // 0-100
  final double bokeh; // 0-100
  final double headYaw; // -100..100
  final double headPitch; // -100..100

  const PortraitParams({
    this.smooth = 0.0,
    this.spotlight = 0.0,
    this.skinTone = SkinTone.none,
    this.skinToneStrength = 50.0,
    this.bokeh = 0.0,
    this.headYaw = 0.0,
    this.headPitch = 0.0,
  });

  static const zero = PortraitParams();

  bool get isZero =>
      smooth == 0 &&
      spotlight == 0 &&
      skinTone == SkinTone.none &&
      bokeh == 0 &&
      headYaw == 0 &&
      headPitch == 0;

  Map<String, dynamic> toJson() => {
        'smooth': smooth,
        'spotlight': spotlight,
        'skinTone': skinTone.name,
        'skinToneStrength': skinToneStrength,
        'bokeh': bokeh,
        'headYaw': headYaw,
        'headPitch': headPitch,
      };

  factory PortraitParams.fromJson(Map<String, dynamic> j) => PortraitParams(
        smooth: (j['smooth'] as num? ?? 0.0).toDouble(),
        spotlight: (j['spotlight'] as num? ?? 0.0).toDouble(),
        skinTone: SkinTone.values.firstWhere(
          (e) => e.name == (j['skinTone'] as String? ?? 'none'),
          orElse: () => SkinTone.none,
        ),
        skinToneStrength: (j['skinToneStrength'] as num? ?? 50.0).toDouble(),
        bokeh: (j['bokeh'] as num? ?? 0.0).toDouble(),
        headYaw: (j['headYaw'] as num? ?? 0.0).toDouble(),
        headPitch: (j['headPitch'] as num? ?? 0.0).toDouble(),
      );
}

// ???? 筌≪럩????ｋ궢 ???뵬沃섎챸苑?????????????????????????????????????????????????????????????????????????

class CreativeParams {
  final String? blendImagePath;
  final bm.BlendMode blendMode;
  final double blendOpacity; // 0-1
  final int frameIndex; // -1 = none
  final String overlayText;
  final double textSize;
  final int textColorValue; // ARGB32
  final double textX; // 0-1
  final double textY; // 0-1
  final double textRotation; // degrees
  final String fontFamily;

  const CreativeParams({
    this.blendImagePath,
    this.blendMode = bm.BlendMode.lighten,
    this.blendOpacity = 0.5,
    this.frameIndex = -1,
    this.overlayText = '',
    this.textSize = 32.0,
    this.textColorValue = 0xFFFFFFFF,
    this.textX = 0.5,
    this.textY = 0.82,
    this.textRotation = 0.0,
    this.fontFamily = 'Montserrat',
  });

  static const zero = CreativeParams();

  bool get isZero =>
      blendImagePath == null && frameIndex < 0 && overlayText.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        if (blendImagePath != null) 'blendImagePath': blendImagePath,
        'blendMode': blendMode.name,
        'blendOpacity': blendOpacity,
        'frameIndex': frameIndex,
        'overlayText': overlayText,
        'textSize': textSize,
        'textColorValue': textColorValue,
        'textX': textX,
        'textY': textY,
        'textRotation': textRotation,
        'fontFamily': fontFamily,
      };

  factory CreativeParams.fromJson(Map<String, dynamic> j) => CreativeParams(
        blendImagePath: j['blendImagePath'] as String?,
        blendMode: bm.BlendMode.values.firstWhere(
          (e) => e.name == (j['blendMode'] as String? ?? 'lighten'),
          orElse: () => bm.BlendMode.lighten,
        ),
        blendOpacity: (j['blendOpacity'] as num? ?? 0.5).toDouble(),
        frameIndex: j['frameIndex'] as int? ?? -1,
        overlayText: j['overlayText'] as String? ?? '',
        textSize: (j['textSize'] as num? ?? 32.0).toDouble(),
        textColorValue: j['textColorValue'] as int? ?? 0xFFFFFFFF,
        textX: (j['textX'] as num? ?? 0.5).toDouble(),
        textY: (j['textY'] as num? ?? 0.82).toDouble(),
        textRotation: (j['textRotation'] as num? ?? 0.0).toDouble(),
        fontFamily: j['fontFamily'] as String? ?? 'Montserrat',
      );
}

// ???? ?됰슢?????쎈뱜嚥≪뮉寃?筌띾뜆???(Phase 2.1) ??????????????????????????????????????

class BrushStroke {
  final double x; // 0-1 ?類?뇣??  final double y;
  final double y;
  final double radius; // 0-1 (???筌왖 ??? 疫꿸퀣?)
  final double pressure; // 0-1 (沃섎챶???類ㅼ삢??

  const BrushStroke({
    required this.x,
    required this.y,
    required this.radius,
    this.pressure = 1.0,
  });

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'r': radius, 'p': pressure};

  factory BrushStroke.fromJson(Map<String, dynamic> j) => BrushStroke(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        radius: (j['r'] as num).toDouble(),
        pressure: (j['p'] as num? ?? 1.0).toDouble(),
      );
}

class BrushMaskData {
  final AdjustParams
      localParams; // ?됰슢????怨몄뒠 嚥≪뮇類?鈺곌퀣?쇿첎?  final String toolName;           // 'expose'|'contrast'|'sat'|'temp'|'sharp'|'clarity'|'eraser'
  final String toolName;
  final double hardness; // 0=soft, 1=hard
  final List<BrushStroke> strokes;
  final Float32List? cachedMask;
  // 筌?Ŋ?? null????strokes?癒?퐣 ?????  final Float32List? cachedMask;

  const BrushMaskData({
    required this.localParams,
    required this.toolName,
    this.hardness = 0.5,
    required this.strokes,
    this.cachedMask,
  });

  Map<String, dynamic> toJson() => {
        'localParams': localParams.toJson(),
        'toolName': toolName,
        'hardness': hardness,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        // cachedMask?? 筌욊낮?????뽰뇚 (?????揶쎛??
      };

  factory BrushMaskData.fromJson(Map<String, dynamic> j) => BrushMaskData(
        localParams:
            AdjustParams.fromJson(j['localParams'] as Map<String, dynamic>),
        toolName: j['toolName'] as String? ?? 'expose',
        hardness: (j['hardness'] as num? ?? 0.5).toDouble(),
        strokes: (j['strokes'] as List<dynamic>? ?? [])
            .map((s) => BrushStroke.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// ???? ?醫뤾문 癰귣똻???????(Phase 2.2) ??????????????????????????????????????????????????

enum SelectiveMode { circle, colorAuto, diffusion }

class SelectivePoint {
  final double x; // 0-1 ?類?뇣??  final double y;
  final double y;
  final double radius; // 0-1 (???筌왖 ??? 疫꿸퀣?)
  final AdjustParams localParams;
  final SelectiveMode mode;

  const SelectivePoint({
    required this.x,
    required this.y,
    this.radius = 0.25,
    required this.localParams,
    this.mode = SelectiveMode.circle,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'radius': radius,
        'localParams': localParams.toJson(),
        'mode': mode.name,
      };

  factory SelectivePoint.fromJson(Map<String, dynamic> j) => SelectivePoint(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        radius: (j['radius'] as num? ?? 0.25).toDouble(),
        localParams:
            AdjustParams.fromJson(j['localParams'] as Map<String, dynamic>),
        mode: SelectiveMode.values.firstWhere(
          (e) => e.name == (j['mode'] as String? ?? 'circle'),
          orElse: () => SelectiveMode.circle,
        ),
      );
}

// ???? ?癒?춦 ??쎈뱜嚥≪뮉寃?(Phase 2.5) ??????????????????????????????????????????????????????????

class HealStroke {
  final List<Map<String, double>> path; // [{x,y}, ...] ?類?뇣???ル슦紐?
  final double radius;

  const HealStroke({required this.path, required this.radius});

  Map<String, dynamic> toJson() => {'path': path, 'radius': radius};

  factory HealStroke.fromJson(Map<String, dynamic> j) => HealStroke(
        path: (j['path'] as List<dynamic>)
            .map((p) => Map<String, double>.from((p as Map)
                .map((k, v) => MapEntry(k as String, (v as num).toDouble()))))
            .toList(),
        radius: (j['radius'] as num).toDouble(),
      );
}

// ???? ???뼎: EditOperation ????????????????????????????????????????????????????????????????????

class EditOperation {
  final String id; // uuid v4
  final EditToolType tool;
  final int schemaVersion; // migration guard, ?袁⑹삺 1
  final DateTime appliedAt;

  // globalAdjust / hslAdjust / splitTone / grainOverlay
  final AdjustParams? params;

  // filter
  final String? presetId;
  final String? lutPath;
  final double? intensity; // 0-1 ?袁り숲 ?됰뗀???
  // curve (?紐꾩춿???뚣끇?뺧쭕???釉?
  final Map<CurveChannel, CurveData>? curves;

  // crop
  final CropState? cropState;

  // brush
  final BrushMaskData? brushMask;

  // selective
  final List<SelectivePoint>? selectivePoints;

  // heal
  final List<HealStroke>? healStrokes;

  // portrait
  final PortraitParams? portrait;

  // creative
  final CreativeParams? creative;

  const EditOperation({
    required this.id,
    required this.tool,
    this.schemaVersion = 1,
    required this.appliedAt,
    this.params,
    this.presetId,
    this.lutPath,
    this.intensity,
    this.curves,
    this.cropState,
    this.brushMask,
    this.selectivePoints,
    this.healStrokes,
    this.portrait,
    this.creative,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'tool': tool.name,
      'v': schemaVersion,
      'at': appliedAt.toIso8601String(),
    };
    if (params != null) m['params'] = params!.toJson();
    if (presetId != null) m['presetId'] = presetId;
    if (lutPath != null) m['lutPath'] = lutPath;
    if (intensity != null) m['intensity'] = intensity;
    if (curves != null && curves!.isNotEmpty) {
      m['curves'] = curves!.map(
        (ch, cd) => MapEntry(ch.name, cd.toJson()),
      );
    }
    if (cropState != null) m['crop'] = cropState!.toJson();
    if (brushMask != null) m['brush'] = brushMask!.toJson();
    if (selectivePoints != null) {
      m['selective'] = selectivePoints!.map((p) => p.toJson()).toList();
    }
    if (healStrokes != null) {
      m['heal'] = healStrokes!.map((s) => s.toJson()).toList();
    }
    if (portrait != null) m['portrait'] = portrait!.toJson();
    if (creative != null) m['creative'] = creative!.toJson();
    return m;
  }

  factory EditOperation.fromJson(Map<String, dynamic> j) {
    final tool = EditToolType.values.firstWhere(
      (e) => e.name == (j['tool'] as String),
      orElse: () => EditToolType.globalAdjust,
    );

    Map<CurveChannel, CurveData>? curves;
    if (j['curves'] is Map) {
      final rawCurves = j['curves'] as Map<String, dynamic>;
      curves = rawCurves.map((k, v) {
        final ch = CurveChannel.values.firstWhere(
          (e) => e.name == k,
          orElse: () => CurveChannel.luminance,
        );
        return MapEntry(ch, CurveData.fromJson(v as Map<String, dynamic>));
      });
    }

    return EditOperation(
      id: j['id'] as String,
      tool: tool,
      schemaVersion: j['v'] as int? ?? 1,
      appliedAt: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      params: j['params'] != null
          ? AdjustParams.fromJson(j['params'] as Map<String, dynamic>)
          : null,
      presetId: j['presetId'] as String?,
      lutPath: j['lutPath'] as String?,
      intensity: (j['intensity'] as num?)?.toDouble(),
      curves: curves,
      cropState: j['crop'] != null
          ? CropState.fromJson(j['crop'] as Map<String, dynamic>)
          : null,
      brushMask: j['brush'] != null
          ? BrushMaskData.fromJson(j['brush'] as Map<String, dynamic>)
          : null,
      selectivePoints: (j['selective'] as List<dynamic>?)
          ?.map((p) => SelectivePoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      healStrokes: (j['heal'] as List<dynamic>?)
          ?.map((s) => HealStroke.fromJson(s as Map<String, dynamic>))
          .toList(),
      portrait: j['portrait'] != null
          ? PortraitParams.fromJson(j['portrait'] as Map<String, dynamic>)
          : null,
      creative: j['creative'] != null
          ? CreativeParams.fromJson(j['creative'] as Map<String, dynamic>)
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory EditOperation.fromJsonString(String s) =>
      EditOperation.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
