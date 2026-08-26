import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';

/// Mutable owner of every user-editable value on [EditorPage].
///
/// Loaded resources, rendering caches, asynchronous progress, and screen
/// navigation deliberately stay outside this type. Snapshot conversion lives
/// here so a new edit field cannot acquire separate history/draft/render
/// mappings inside the page.
class EditorEditState {
  AdjustParams params = AdjustParams.zero;
  FilterPreset? selectedPreset;
  double intensity = 1;
  final Map<CurveChannel, CurveData> curves = {};

  ArtisticEffect effect = ArtisticEffect.none;
  double effectStrength = 1;
  int grainVariant = 3;

  CropRatioPreset cropRatio = CropRatioPreset.free;
  double cropCenterX = 0.5;
  double cropCenterY = 0.5;
  double cropLeft = 0;
  double cropTop = 0;
  double cropRight = 1;
  double cropBottom = 1;
  double rotation = 0;
  bool flipH = false;
  bool flipV = false;
  double perspectiveH = 0;
  double perspectiveV = 0;
  double expandTop = 0;
  double expandBottom = 0;
  double expandLeft = 0;
  double expandRight = 0;
  String expandMode = 'black';

  double portraitSmooth = 0;
  double portraitSpotlight = 0;
  SkinTone skinTone = SkinTone.none;
  double skinToneStrength = 50;
  double portraitBokeh = 0;
  double headYaw = 0;
  double headPitch = 0;

  String? blendImagePath;
  bm.BlendMode blendMode = bm.BlendMode.lighten;
  double blendOpacity = 0.5;
  int frameIndex = -1;
  String overlayText = '';
  double textSize = 32;
  int textColorValue = 0xFFFFFFFF;
  String textFontFamily = 'Montserrat';
  double textX = 0.5;
  double textY = 0.82;
  double textRotation = 0;

  bool selectiveActive = false;
  double selectiveX = 0.5;
  double selectiveY = 0.5;
  double selectiveBrightness = 0;
  double selectiveContrast = 0;
  double selectiveSaturation = 0;
  double selectiveRadius = 0.3;

  bool dodgeBurnActive = false;
  String brushMode = 'dodge';
  double dodgeY = 0.25;
  double dodgeRadius = 0.25;
  double dodgeStrength = 0.3;
  double burnY = 0.75;
  double burnRadius = 0.25;
  double burnStrength = 0.3;
  final List<DodgeBurnStroke> brushStrokes = [];

  bool tiltActive = false;
  double tiltFocusCenter = 0.5;
  double tiltBandWidth = 0.3;
  double tiltMaxBlur = 8;
  bool lensActive = false;
  double lensFocusDepth = 0;
  double lensMaxRadius = 8;

  EditorStateSnapshot toSnapshot({required String localSubTabName}) =>
      EditorStateSnapshot(
        adjustParams: params,
        curves: curves,
        presetId: selectedPreset?.id,
        lutPath: selectedPreset?.lutPath,
        intensity: intensity,
        crop: CropState(
          ratio: cropRatio,
          centerX: cropCenterX,
          centerY: cropCenterY,
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropRight: cropRight,
          cropBottom: cropBottom,
          rotation: rotation,
          flipH: flipH,
          flipV: flipV,
          perspH: perspectiveH,
          perspV: perspectiveV,
          expandTop: expandTop,
          expandBottom: expandBottom,
          expandLeft: expandLeft,
          expandRight: expandRight,
          expandMode: expandMode,
        ),
        portrait: PortraitParams(
          smooth: portraitSmooth,
          spotlight: portraitSpotlight,
          skinTone: skinTone,
          skinToneStrength: skinToneStrength,
          bokeh: portraitBokeh,
          headYaw: headYaw,
          headPitch: headPitch,
        ),
        creative: CreativeParams(
          blendImagePath: blendImagePath,
          blendMode: blendMode,
          blendOpacity: blendOpacity,
          frameIndex: frameIndex,
          overlayText: overlayText,
          textSize: textSize,
          textColorValue: textColorValue,
          textX: textX,
          textY: textY,
          textRotation: textRotation,
          fontFamily: textFontFamily,
        ),
        effects: EditorEffectState(
          artisticEffect: effect.name,
          effectStrength: effectStrength,
          grainVariant: grainVariant,
          selectiveActive: selectiveActive,
          selectiveX: selectiveX,
          selectiveY: selectiveY,
          selectiveBrightness: selectiveBrightness,
          selectiveContrast: selectiveContrast,
          selectiveSaturation: selectiveSaturation,
          selectiveRadius: selectiveRadius,
          dodgeBurnActive: dodgeBurnActive,
          brushMode: brushMode,
          dodgeY: dodgeY,
          dodgeRadius: dodgeRadius,
          dodgeStrength: dodgeStrength,
          burnY: burnY,
          burnRadius: burnRadius,
          burnStrength: burnStrength,
          brushStrokes: brushStrokes
              .map(
                (stroke) => DodgeBurnHistoryStroke(
                  x: stroke.x,
                  y: stroke.y,
                  radius: stroke.radius,
                  strength: stroke.strength,
                  isDodge: stroke.isDodge,
                ),
              )
              .toList(growable: false),
          tiltActive: tiltActive,
          tiltFocusCenter: tiltFocusCenter,
          tiltBandWidth: tiltBandWidth,
          tiltMaxBlur: tiltMaxBlur,
          lensActive: lensActive,
          lensFocusDepth: lensFocusDepth,
          lensMaxRadius: lensMaxRadius,
        ),
        localSubTabName: localSubTabName,
      );

  void restore(
    EditorStateSnapshot state, {
    required FilterPreset? resolvedPreset,
  }) {
    params = state.adjustParams;
    syncCurvesFromParams();
    if (state.curves.isNotEmpty) {
      curves
        ..clear()
        ..addAll(state.curves);
    }
    selectedPreset = resolvedPreset;
    intensity = state.intensity;

    final crop = state.crop;
    cropRatio = crop.ratio;
    cropCenterX = crop.centerX;
    cropCenterY = crop.centerY;
    cropLeft = crop.cropLeft;
    cropTop = crop.cropTop;
    cropRight = crop.cropRight;
    cropBottom = crop.cropBottom;
    rotation = crop.rotation;
    flipH = crop.flipH;
    flipV = crop.flipV;
    perspectiveH = crop.perspH;
    perspectiveV = crop.perspV;
    expandTop = crop.expandTop;
    expandBottom = crop.expandBottom;
    expandLeft = crop.expandLeft;
    expandRight = crop.expandRight;
    expandMode = crop.expandMode;

    final portrait = state.portrait;
    portraitSmooth = portrait.smooth;
    portraitSpotlight = portrait.spotlight;
    skinTone = portrait.skinTone;
    skinToneStrength = portrait.skinToneStrength;
    portraitBokeh = portrait.bokeh;
    headYaw = portrait.headYaw;
    headPitch = portrait.headPitch;

    final creative = state.creative;
    blendImagePath = creative.blendImagePath;
    blendMode = creative.blendMode;
    blendOpacity = creative.blendOpacity;
    frameIndex = creative.frameIndex;
    overlayText = creative.overlayText;
    textSize = creative.textSize;
    textColorValue = creative.textColorValue;
    textX = creative.textX;
    textY = creative.textY;
    textRotation = creative.textRotation;
    textFontFamily = creative.fontFamily;

    final effects = state.effects;
    effect = ArtisticEffect.values.firstWhere(
      (value) => value.name == effects.artisticEffect,
      orElse: () => ArtisticEffect.none,
    );
    effectStrength = effects.effectStrength;
    grainVariant = effects.grainVariant;
    selectiveActive = effects.selectiveActive;
    selectiveX = effects.selectiveX;
    selectiveY = effects.selectiveY;
    selectiveBrightness = effects.selectiveBrightness;
    selectiveContrast = effects.selectiveContrast;
    selectiveSaturation = effects.selectiveSaturation;
    selectiveRadius = effects.selectiveRadius;
    dodgeBurnActive = effects.dodgeBurnActive;
    brushMode = effects.brushMode;
    dodgeY = effects.dodgeY;
    dodgeRadius = effects.dodgeRadius;
    dodgeStrength = effects.dodgeStrength;
    burnY = effects.burnY;
    burnRadius = effects.burnRadius;
    burnStrength = effects.burnStrength;
    brushStrokes
      ..clear()
      ..addAll(
        effects.brushStrokes.map(
          (stroke) => DodgeBurnStroke(
            x: stroke.x,
            y: stroke.y,
            radius: stroke.radius,
            strength: stroke.strength,
            isDodge: stroke.isDodge,
          ),
        ),
      );
    tiltActive = effects.tiltActive;
    tiltFocusCenter = effects.tiltFocusCenter;
    tiltBandWidth = effects.tiltBandWidth;
    tiltMaxBlur = effects.tiltMaxBlur;
    lensActive = effects.lensActive;
    lensFocusDepth = effects.lensFocusDepth;
    lensMaxRadius = effects.lensMaxRadius;
  }

  void syncCurvesFromParams() {
    curves
      ..clear()
      ..addEntries([
        if (params.luminanceCurve != null)
          MapEntry(CurveChannel.luminance, params.luminanceCurve!),
        if (params.rgbCurve != null)
          MapEntry(CurveChannel.rgb, params.rgbCurve!),
        if (params.redCurve != null)
          MapEntry(CurveChannel.red, params.redCurve!),
        if (params.greenCurve != null)
          MapEntry(CurveChannel.green, params.greenCurve!),
        if (params.blueCurve != null)
          MapEntry(CurveChannel.blue, params.blueCurve!),
      ]);
  }
}
