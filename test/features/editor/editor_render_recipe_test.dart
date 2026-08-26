import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';

void main() {
  test('copies mutable stroke input into an immutable render contract', () {
    final strokes = [
      const DodgeBurnStroke(
        x: 0.4,
        y: 0.6,
        radius: 0.12,
        strength: 0.3,
        isDodge: true,
      ),
    ];
    final recipe = EditorRenderRecipe(
      adjustParams: const AdjustParams(exposure: 0.25),
      lutBytes: null,
      intensity: 0.8,
      crop: const CropState(flipH: true),
      cropAspectRatio: 4 / 3,
      effect: ArtisticEffect.grainyFilm,
      effectStrength: 0.5,
      grainVariant: 2,
      selectiveActive: true,
      selectiveX: 0.2,
      selectiveY: 0.3,
      selectiveBrightness: 0.1,
      selectiveContrast: 0.2,
      selectiveSaturation: 0.3,
      selectiveRadius: 0.4,
      dodgeBurnActive: true,
      dodgeStrength: 0.2,
      dodgeY: 0.3,
      dodgeRadius: 0.4,
      burnStrength: 0.5,
      burnY: 0.6,
      burnRadius: 0.7,
      tiltActive: true,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.2,
      tiltMaxBlur: 8,
      lensActive: true,
      lensFocusDepth: 0.4,
      lensMaxRadius: 6,
      portrait: const PortraitParams(smooth: 30),
      creative: const CreativeParams(overlayText: 'Memoria'),
      brushStrokes: strokes,
    );

    strokes.clear();

    expect(recipe.adjustParams.exposure, 0.25);
    expect(recipe.crop.flipH, isTrue);
    expect(recipe.creative.overlayText, 'Memoria');
    expect(recipe.brushStrokes, hasLength(1));
    expect(
      () => recipe.brushStrokes.add(
        const DodgeBurnStroke(
          x: 0.1,
          y: 0.1,
          radius: 0.1,
          strength: 0.1,
          isDodge: false,
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
