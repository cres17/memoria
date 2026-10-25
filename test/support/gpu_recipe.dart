import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';

EditorRenderRecipe gpuRecipe(AdjustParams params,
        {ArtisticEffect effect = ArtisticEffect.none, bool tools = false}) =>
    EditorRenderRecipe(
      adjustParams: params,
      lutBytes: null,
      intensity: 1,
      crop: CropState.identity,
      cropAspectRatio: null,
      effect: effect,
      effectStrength: 0.5,
      grainVariant: 3,
      selectiveActive: false,
      selectiveX: 0.5,
      selectiveY: 0.5,
      selectiveBrightness: 0,
      selectiveContrast: 0,
      selectiveSaturation: 0,
      selectiveRadius: 0.2,
      dodgeBurnActive: false,
      dodgeStrength: 0,
      dodgeY: 0.5,
      dodgeRadius: 0.2,
      burnStrength: 0,
      burnY: 0.5,
      burnRadius: 0.2,
      tiltActive: tools,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.2,
      tiltMaxBlur: 5,
      lensActive: tools,
      lensFocusDepth: 0.5,
      lensMaxRadius: 5,
      portrait: const PortraitParams(),
      creative: const CreativeParams(),
      brushStrokes: const [],
    );
