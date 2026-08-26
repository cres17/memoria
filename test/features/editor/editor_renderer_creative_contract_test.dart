import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';

void main() {
  test('every bundled frame stays above the photo without covering its centre',
      () async {
    final source = _solid(96, 96, 19, 101, 173);
    const paths = <String>[
      'assets/frames/hp_frame_00_overlay.png',
      'assets/frames/hp_frame_01_overlay.png',
      'assets/frames/hp_frame_02_overlay.png',
      'assets/frames/hp_frame_03_overlay.png',
      'assets/frames/hp_frame_04_overlay.png',
      'assets/frames/hp_frame_05_overlay.png',
      'assets/frames/hp_frame_06_overlay.png',
      'assets/frames/hp_frame_07_overlay.png',
      'assets/frames/hp_frame_08_overlay.png',
      'assets/frames/hp_frame_09_overlay.png',
      'assets/frames/hp_frame_10_overlay.png',
      'assets/frames/hp_frame_11_overlay.png',
      'assets/frames/hp_frame_12_overlay.png',
    ];

    for (final path in paths) {
      final output = await EditorRenderer.applyVisual(
        source,
        _recipe(),
        EditorRenderResources(frameBytes: File(path).readAsBytesSync()),
      );
      final center = output.getPixel(48, 48);
      final edge = output.getPixel(0, 0);
      expect([center.r, center.g, center.b], <num>[19, 101, 173],
          reason: '$path must not hide the centre photo');
      expect(
        [edge.r, edge.g, edge.b],
        isNot(<num>[19, 101, 173]),
        reason: '$path must remain above the photo at its border',
      );
    }
  });

  test('blend and text raster resources composite at their expected positions',
      () async {
    final source = _solid(64, 64, 20, 40, 60);
    final blend = _solid(64, 64, 220, 120, 20);
    final text = img.Image(width: 64, height: 64, numChannels: 4);
    text.setPixelRgba(46, 11, 255, 255, 255, 255);

    final output = await EditorRenderer.applyVisual(
      source,
      _recipe(
        creative: const CreativeParams(
          blendMode: bm.BlendMode.normal,
          blendOpacity: 0.5,
        ),
      ),
      EditorRenderResources(
        blendImageBytes: img.encodePng(blend),
        textOverlayBytes: img.encodePng(text),
      ),
    );

    final blended = output.getPixel(4, 4);
    final textPixel = output.getPixel(46, 11);
    expect([blended.r, blended.g, blended.b], <num>[120, 80, 40]);
    expect([textPixel.r, textPixel.g, textPixel.b], <num>[255, 255, 255]);
  });
}

img.Image _solid(int width, int height, int red, int green, int blue) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  image.clear(img.ColorRgba8(red, green, blue, 255));
  return image;
}

EditorRenderRecipe _recipe({CreativeParams creative = CreativeParams.zero}) =>
    EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: CropState.identity,
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
      creative: creative,
      brushStrokes: const [],
    );
