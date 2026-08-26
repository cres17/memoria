import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_edit_state.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';

void main() {
  test('container owns and restores every editable state family', () {
    final preset =
        BuiltinPresets.all.firstWhere((item) => item.id != 'original');
    final state = EditorEditState()
      ..params = const AdjustParams(exposure: 0.4, contrast: 12)
      ..selectedPreset = preset
      ..intensity = 0.65
      ..effect = ArtisticEffect.dramaBright1
      ..effectStrength = 0.75
      ..grainVariant = 5
      ..cropRatio = CropRatioPreset.r4x3
      ..cropCenterX = 0.3
      ..cropCenterY = 0.7
      ..cropLeft = 0.1
      ..cropBottom = 0.8
      ..rotation = 14
      ..flipH = true
      ..perspectiveV = -3
      ..expandRight = 0.2
      ..portraitSmooth = 25
      ..portraitSpotlight = 15
      ..skinTone = SkinTone.medium
      ..skinToneStrength = 70
      ..portraitBokeh = 20
      ..headYaw = -5
      ..headPitch = 3
      ..blendImagePath = '/blend.jpg'
      ..blendMode = bm.BlendMode.overlay
      ..blendOpacity = 0.6
      ..frameIndex = 3
      ..overlayText = 'Memoria'
      ..textSize = 48
      ..textColorValue = 0xFF123456
      ..textX = 0.2
      ..textY = 0.6
      ..textRotation = 18
      ..textFontFamily = 'NotoSerif'
      ..selectiveActive = true
      ..selectiveBrightness = 8
      ..dodgeBurnActive = true
      ..brushMode = 'burn'
      ..tiltActive = true
      ..lensActive = true
      ..brushStrokes.add(
        const DodgeBurnStroke(
          x: 0.2,
          y: 0.4,
          radius: 0.1,
          strength: 0.5,
          isDodge: false,
        ),
      );

    final snapshot = state.toSnapshot(localSubTabName: 'selective');
    final restored = EditorEditState()
      ..restore(snapshot, resolvedPreset: preset);

    expect(restored.params.exposure, 0.4);
    expect(restored.selectedPreset, same(preset));
    expect(restored.intensity, 0.65);
    expect(restored.effect, ArtisticEffect.dramaBright1);
    expect(restored.cropRatio, CropRatioPreset.r4x3);
    expect(restored.cropBottom, 0.8);
    expect(restored.perspectiveV, -3);
    expect(restored.expandRight, 0.2);
    expect(restored.skinTone, SkinTone.medium);
    expect(restored.portraitBokeh, 20);
    expect(restored.headYaw, -5);
    expect(restored.blendMode, bm.BlendMode.overlay);
    expect(restored.textColorValue, 0xFF123456);
    expect(restored.textFontFamily, 'NotoSerif');
    expect(restored.selectiveBrightness, 8);
    expect(restored.brushMode, 'burn');
    expect(restored.brushStrokes.single.isDodge, isFalse);
    expect(restored.tiltActive, isTrue);
    expect(restored.lensActive, isTrue);
    expect(snapshot.localSubTabName, 'selective');
  });

  test('initial snapshot resets the container through the same restore path',
      () {
    final state = EditorEditState()
      ..params = const AdjustParams(exposure: 1)
      ..overlayText = 'temporary'
      ..selectiveActive = true;

    state.restore(
      EditorStateSnapshot.initial(localSubTabName: 'tiltShift'),
      resolvedPreset: null,
    );

    expect(state.params, AdjustParams.zero);
    expect(state.overlayText, isEmpty);
    expect(state.selectiveActive, isFalse);
    expect(state.cropRatio, CropRatioPreset.free);
  });
}
