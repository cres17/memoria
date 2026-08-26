import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';

void main() {
  test('preview and export use identical committed spatial transforms', () {
    final source = img.Image(width: 8, height: 6);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 20, y * 30, 100);
      }
    }
    final recipe = _recipe(
      const CropState(
        cropLeft: 0.25,
        cropTop: 0.0,
        cropRight: 1.0,
        cropBottom: 1.0,
        flipH: true,
        rotation: 90,
      ),
    );

    final preview = EditorSpatialRenderer.apply(source, recipe);
    final exported = EditorSpatialRenderer.apply(source, recipe);

    expect(preview.width, 6);
    expect(preview.height, 6);
    expect(preview.getBytes(), exported.getBytes());
  });

  test('interactive crop preview can defer only crop while preserving expand',
      () {
    final source = img.Image(width: 4, height: 2)
      ..clear(img.ColorRgba8(1, 2, 3, 255));
    final recipe = _recipe(
      const CropState(
        cropLeft: 0.5,
        cropRight: 1.0,
        expandLeft: 0.5,
        expandMode: 'white',
      ),
    );

    final deferred =
        EditorSpatialRenderer.apply(source, recipe, skipCrop: true);
    final committed = EditorSpatialRenderer.apply(source, recipe);

    expect(deferred.width, 6);
    expect(committed.width, 3);
  });

  test('segmentation mask follows expand, crop, flip, and rotation', () {
    final source = Float32List(4 * 3)..[1 * 4 + 1] = 1;
    final recipe = _recipe(
      const CropState(
        expandTop: 1 / 3,
        expandLeft: 1 / 4,
        expandMode: 'smart',
        cropLeft: 0.2,
        flipH: true,
        rotation: 90,
      ),
    );

    final transformed = EditorSpatialRenderer.applyMask(
      EditorSpatialMask(source, 4, 3),
      recipe,
    );

    expect(transformed.width, 4);
    expect(transformed.height, 4);
    expect(transformed.data[2 * transformed.width + 1], 1);
    expect(
      transformed.data.where((value) => value > 0.5),
      hasLength(1),
      reason: 'An asymmetric source mask must keep exactly one subject pixel',
    );
  });

  test('smart canvas expansion does not synthesize portrait-mask pixels', () {
    final source = Float32List.fromList(<double>[1, 0, 0, 0]);
    final recipe = _recipe(
      const CropState(
        expandTop: 0.5,
        expandLeft: 0.5,
        expandMode: 'smart',
      ),
    );

    final transformed = EditorSpatialRenderer.applyMask(
      EditorSpatialMask(source, 2, 2),
      recipe,
    );

    expect(transformed.width, 3);
    expect(transformed.height, 3);
    expect(transformed.data[0], 0);
    expect(transformed.data[1], 0);
    expect(transformed.data[transformed.width], 0);
    expect(transformed.data[transformed.width + 1], 1);
  });
}

EditorRenderRecipe _recipe(CropState crop) => EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: crop,
      cropAspectRatio: null,
      effect: ArtisticEffect.none,
      effectStrength: 1,
      grainVariant: 0,
      selectiveActive: false,
      selectiveX: 0.5,
      selectiveY: 0.5,
      selectiveBrightness: 0,
      selectiveContrast: 0,
      selectiveSaturation: 0,
      selectiveRadius: 0.3,
      dodgeBurnActive: false,
      dodgeStrength: 0,
      dodgeY: 0.5,
      dodgeRadius: 0.3,
      burnStrength: 0,
      burnY: 0.5,
      burnRadius: 0.3,
      tiltActive: false,
      tiltFocusCenter: 0.5,
      tiltBandWidth: 0.3,
      tiltMaxBlur: 0,
      lensActive: false,
      lensFocusDepth: 0,
      lensMaxRadius: 0,
      portrait: PortraitParams.zero,
      creative: CreativeParams.zero,
      brushStrokes: const [],
    );
