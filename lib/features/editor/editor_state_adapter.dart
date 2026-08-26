import 'dart:typed_data';

import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';

/// Immutable bridge between the editor's temporary UI fields and committed
/// renderer/history/draft values. Resource bytes stay outside this snapshot.
class EditorStateSnapshot {
  final AdjustParams adjustParams;
  final Map<CurveChannel, CurveData> curves;
  final String? presetId;
  final String? lutPath;
  final double intensity;
  final CropState crop;
  final PortraitParams portrait;
  final CreativeParams creative;
  final EditorEffectState effects;
  final String localSubTabName;

  EditorStateSnapshot({
    required this.adjustParams,
    required Map<CurveChannel, CurveData> curves,
    required this.presetId,
    required this.lutPath,
    required this.intensity,
    required this.crop,
    required this.portrait,
    required this.creative,
    required this.effects,
    required this.localSubTabName,
  }) : curves = Map.unmodifiable(curves);

  factory EditorStateSnapshot.fromOperation(EditOperation operation) =>
      EditorStateSnapshot(
        adjustParams: operation.params ?? AdjustParams.zero,
        curves: operation.curves ?? const {},
        presetId: operation.presetId,
        lutPath: operation.lutPath,
        intensity: operation.intensity ?? 1,
        crop: operation.cropState ?? CropState.identity,
        portrait: operation.portrait ?? PortraitParams.zero,
        creative: operation.creative ?? CreativeParams.zero,
        effects: operation.effectState ?? EditorEffectState.defaults,
        localSubTabName: 'tiltShift',
      );

  factory EditorStateSnapshot.fromDraftJson(Map<String, dynamic> json) {
    final operation = EditOperation.fromJson(json);
    final state = EditorStateSnapshot.fromOperation(operation);
    return EditorStateSnapshot(
      adjustParams: state.adjustParams,
      curves: state.curves,
      presetId: state.presetId,
      lutPath: state.lutPath,
      intensity: state.intensity,
      crop: state.crop,
      portrait: state.portrait,
      creative: state.creative,
      effects: state.effects,
      localSubTabName: json['localSubTab'] as String? ?? state.localSubTabName,
    );
  }

  EditOperation toOperation({
    required String id,
    required EditToolType tool,
    required DateTime appliedAt,
  }) =>
      EditOperation(
        id: id,
        tool: tool,
        schemaVersion: 2,
        appliedAt: appliedAt,
        params: adjustParams,
        presetId: presetId,
        lutPath: lutPath,
        intensity: intensity,
        curves: curves,
        cropState: crop,
        portrait: portrait,
        creative: creative,
        effectState: effects,
      );

  EditorRenderRecipe toRenderRecipe({
    required Uint8List? lutBytes,
    required double? cropAspectRatio,
    AdjustParams? adjustParamsOverride,
    Uint8List? lutBytesOverride,
    bool overrideLutBytes = false,
    double? intensityOverride,
  }) =>
      EditorRenderRecipe(
        adjustParams: adjustParamsOverride ?? adjustParams,
        lutBytes: overrideLutBytes ? lutBytesOverride : lutBytes,
        intensity: intensityOverride ?? intensity,
        crop: crop,
        cropAspectRatio: cropAspectRatio,
        effect: ArtisticEffect.values.firstWhere(
          (effect) => effect.name == effects.artisticEffect,
          orElse: () => ArtisticEffect.none,
        ),
        effectStrength: effects.effectStrength,
        grainVariant: effects.grainVariant,
        selectiveActive: effects.selectiveActive,
        selectiveX: effects.selectiveX,
        selectiveY: effects.selectiveY,
        selectiveBrightness: effects.selectiveBrightness,
        selectiveContrast: effects.selectiveContrast,
        selectiveSaturation: effects.selectiveSaturation,
        selectiveRadius: effects.selectiveRadius,
        dodgeBurnActive: effects.dodgeBurnActive,
        dodgeStrength: effects.dodgeStrength,
        dodgeY: effects.dodgeY,
        dodgeRadius: effects.dodgeRadius,
        burnStrength: effects.burnStrength,
        burnY: effects.burnY,
        burnRadius: effects.burnRadius,
        tiltActive: effects.tiltActive,
        tiltFocusCenter: effects.tiltFocusCenter,
        tiltBandWidth: effects.tiltBandWidth,
        tiltMaxBlur: effects.tiltMaxBlur,
        lensActive: effects.lensActive,
        lensFocusDepth: effects.lensFocusDepth,
        lensMaxRadius: effects.lensMaxRadius,
        portrait: portrait,
        creative: creative,
        brushStrokes: effects.brushStrokes
            .map(
              (stroke) => DodgeBurnStroke(
                x: stroke.x,
                y: stroke.y,
                radius: stroke.radius,
                strength: stroke.strength,
                isDodge: stroke.isDodge,
              ),
            )
            .toList(growable: false),
      );

  Map<String, dynamic> toDraftJson({
    required String? imagePath,
    required String? initialPresetId,
    required Map<String, dynamic> history,
  }) =>
      {
        'version': 3,
        'savedAt': DateTime.now().toIso8601String(),
        'imagePath': imagePath,
        'initialPresetId': initialPresetId,
        'snapshot': {
          ...toOperation(
            id: 'draft',
            tool: EditToolType.globalAdjust,
            appliedAt: DateTime.now(),
          ).toJson(),
          'localSubTab': localSubTabName,
        },
        // Keep the established key so version 2 readers and recovery tooling
        // can continue to locate committed history.
        'editSession': history,
      };
}
