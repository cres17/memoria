import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/portrait_engine.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';

void main() {
  test('initial snapshot is the canonical empty committed state', () {
    final initial = EditorStateSnapshot.initial(localSubTabName: 'brush');
    final recipe = initial.toRenderRecipe(
      lutBytes: null,
      cropAspectRatio: null,
    );

    expect(initial.presetId, isNull);
    expect(initial.lutPath, isNull);
    expect(initial.intensity, 1);
    expect(initial.crop.ratio, CropRatioPreset.free);
    expect(initial.crop.centerX, 0.5);
    expect(initial.portrait.smooth, 0);
    expect(initial.portrait.skinTone, SkinTone.none);
    expect(initial.creative.blendImagePath, isNull);
    expect(initial.creative.frameIndex, -1);
    expect(initial.effects.artisticEffect, 'none');
    expect(initial.localSubTabName, 'brush');
    expect(recipe.effect, ArtisticEffect.none);
    expect(recipe.creative.overlayText, isEmpty);
  });

  test('one snapshot drives renderer, history, and version 3 draft payload',
      () {
    final snapshot = EditorStateSnapshot(
      adjustParams: const AdjustParams(exposure: 0.25),
      curves: const {},
      presetId: 'warm',
      lutPath: 'assets/luts/warm.cube',
      intensity: 0.7,
      crop: const CropState(
        ratio: CropRatioPreset.r1x1,
        centerX: 0.3,
        centerY: 0.7,
        cropLeft: 0.1,
        cropTop: 0.2,
        cropRight: 0.9,
        cropBottom: 0.8,
        rotation: 12,
        flipH: true,
        flipV: true,
        perspH: 4,
        perspV: -3,
        expandTop: 0.1,
        expandBottom: 0.2,
        expandLeft: 0.3,
        expandRight: 0.4,
      ),
      portrait: const PortraitParams(
        smooth: 20,
        spotlight: 10,
        skinTone: SkinTone.medium,
        skinToneStrength: 75,
      ),
      creative: const CreativeParams(
        blendImagePath: '/blend.jpg',
        blendMode: bm.BlendMode.overlay,
        blendOpacity: 0.6,
        frameIndex: 2,
        overlayText: 'Memoria',
        textSize: 44,
        textColorValue: 0xFF123456,
        textX: 0.2,
        textY: 0.6,
        textRotation: 20,
        fontFamily: 'NotoSerif',
      ),
      effects: const EditorEffectState(
        artisticEffect: 'dramaBright1',
        effectStrength: 0.8,
        grainVariant: 5,
        selectiveActive: true,
        selectiveX: 0.2,
        selectiveY: 0.8,
        selectiveBrightness: 12,
        selectiveContrast: 6,
        selectiveSaturation: -4,
        selectiveRadius: 0.4,
        dodgeBurnActive: true,
        brushMode: 'burn',
        dodgeStrength: 0.7,
        burnStrength: 0.6,
        tiltActive: true,
        lensActive: true,
      ),
      localSubTabName: 'selective',
    );

    final recipe = snapshot.toRenderRecipe(
      lutBytes: null,
      cropAspectRatio: 4 / 3,
    );
    final operation = snapshot.toOperation(
      id: 'snapshot',
      tool: EditToolType.globalAdjust,
      appliedAt: DateTime.utc(2026, 8, 25),
    );
    final draft = snapshot.toDraftJson(
      imagePath: '/photo.jpg',
      initialPresetId: null,
      history: {
        'imageUri': '/photo.jpg',
        'ops': [operation.toJson()],
        'undoCursor': 1,
      },
    );
    final restored = EditorStateSnapshot.fromDraftJson(
      Map<String, dynamic>.from(draft['snapshot'] as Map),
    );

    expect(recipe.adjustParams.exposure, 0.25);
    expect(recipe.effect, ArtisticEffect.dramaBright1);
    expect(recipe.crop.flipH, isTrue);
    expect(recipe.crop.perspV, -3);
    expect(recipe.selectiveBrightness, 12);
    expect(recipe.dodgeBurnActive, isTrue);
    expect(recipe.creative.blendImagePath, '/blend.jpg');
    expect(recipe.creative.textRotation, 20);
    expect(draft['version'], 3);
    expect(restored.presetId, 'warm');
    expect(restored.creative.overlayText, 'Memoria');
    expect(restored.creative.frameIndex, 2);
    expect(restored.crop.expandRight, 0.4);
    expect(restored.portrait.smooth, 20);
    expect(restored.portrait.skinTone, SkinTone.medium);
    expect(restored.effects.brushMode, 'burn');
    expect(restored.effects.lensActive, isTrue);
    expect(restored.localSubTabName, 'selective');
  });
}
