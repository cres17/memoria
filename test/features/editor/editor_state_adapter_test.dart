import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/features/editor/editor_state_adapter.dart';

void main() {
  test('one snapshot drives renderer, history, and version 3 draft payload',
      () {
    final snapshot = EditorStateSnapshot(
      adjustParams: const AdjustParams(exposure: 0.25),
      curves: const {},
      presetId: 'warm',
      lutPath: 'assets/luts/warm.cube',
      intensity: 0.7,
      crop: const CropState(flipH: true),
      portrait: const PortraitParams(smooth: 20),
      creative: const CreativeParams(overlayText: 'Memoria'),
      effects: const EditorEffectState(
        artisticEffect: 'dramaBright1',
        selectiveActive: true,
        selectiveBrightness: 12,
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
    expect(recipe.selectiveBrightness, 12);
    expect(draft['version'], 3);
    expect(restored.presetId, 'warm');
    expect(restored.creative.overlayText, 'Memoria');
    expect(restored.portrait.smooth, 20);
    expect(restored.localSubTabName, 'selective');
  });
}
