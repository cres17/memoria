import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_resource_preparer.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';

void main() {
  test('target geometry exactly matches the production spatial renderer', () {
    final recipe = _recipe(
      crop: const CropState(
        expandLeft: 0.1,
        expandRight: 0.2,
        cropLeft: 0.1,
        cropRight: 0.9,
        cropTop: 0.1,
        cropBottom: 0.9,
        rotation: 17,
      ),
    );
    final geometry = EditorSpatialRenderer.outputGeometry(
      200,
      100,
      recipe,
      maxDimension: 160,
    );
    final source = img.Image(width: 200, height: 100);
    final rendered = EditorRenderer.prepareExportSource(
      source,
      recipe,
      maxDimension: 160,
    );

    expect(
        (geometry.width, geometry.height), (rendered.width, rendered.height));
  });

  test('prepared resources keep preview and export pixels aligned', () async {
    final source = _solid(48, 32, 20, 40, 60);
    final blend = _solid(48, 32, 220, 120, 20);
    final frame = img.Image(width: 48, height: 32, numChannels: 4)
      ..setPixelRgba(0, 0, 255, 0, 0, 255);
    final recipe = _recipe(
      crop: const CropState(
        cropLeft: 0.1,
        cropTop: 0.1,
        cropRight: 0.9,
        cropBottom: 0.9,
        rotation: 90,
      ),
      portrait: const PortraitParams(spotlight: 25),
      creative: const CreativeParams(
        blendMode: bm.BlendMode.normal,
        blendOpacity: 0.5,
        overlayText: 'M',
        textSize: 32,
      ),
    );
    final preparer = EditorResourcePreparer(
      loadFrame: (_) async => Uint8List.fromList(img.encodePng(frame)),
      loadBlend: (_) async => Uint8List.fromList(img.encodePng(blend)),
      loadPortraitMask: (image, _) async => EditorPortraitMaskResource(
        data: Float32List(image.width * image.height)
          ..fillRange(0, image.width * image.height, 1),
        width: image.width,
        height: image.height,
      ),
    );

    final geometry = EditorSpatialRenderer.outputGeometry(
      source.width,
      source.height,
      recipe,
    );
    final prepared = await preparer.prepare(
      EditorResourcePreparationRequest(
        recipe: recipe,
        maskSource: source,
        maskSourceKey: 'source',
        targetGeometry: geometry,
        frameIndex: 0,
        blendImagePath: 'memory://blend',
        preparePortraitMask: true,
        prepareTextOverlay: true,
      ),
    );
    final preview = await EditorRenderer.renderPreview(
      source: source,
      recipe: recipe,
      resources: prepared.renderResources,
    );
    final exported = await EditorRenderer.renderExport(
      source: source,
      recipe: recipe,
      resources: prepared.renderResources,
    );

    expect(prepared.renderResources.segmentMaskWidth, 48);
    expect(prepared.renderResources.segmentMaskHeight, 32);
    expect(prepared.renderResources.textOverlayBytes, isNotNull);
    expect((preview.width, preview.height), (geometry.width, geometry.height));
    expect(preview.getBytes(), exported.getBytes());
  });

  test('loader errors are reported as typed preparation failures', () async {
    final preparer = EditorResourcePreparer(
      loadFrame: (_) => Future<Uint8List?>.error(StateError('missing frame')),
      loadBlend: (_) async => null,
      loadPortraitMask: (source, sourceKey) async => null,
    );

    await expectLater(
      preparer.prepare(EditorResourcePreparationRequest(
        recipe: _recipe(),
        maskSource: _solid(4, 4, 0, 0, 0),
        maskSourceKey: 'failure',
        targetGeometry: const EditorTargetGeometry(width: 4, height: 4),
        frameIndex: 0,
        blendImagePath: null,
        preparePortraitMask: false,
        prepareTextOverlay: false,
      )),
      throwsA(
        isA<EditorResourcePreparationFailure>().having(
          (failure) => failure.kind,
          'kind',
          EditorResourceFailureKind.frame,
        ),
      ),
    );
  });
}

img.Image _solid(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  image.clear(img.ColorRgba8(r, g, b, 255));
  return image;
}

EditorRenderRecipe _recipe({
  CropState crop = CropState.identity,
  PortraitParams portrait = PortraitParams.zero,
  CreativeParams creative = CreativeParams.zero,
}) =>
    EditorRenderRecipe(
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
      portrait: portrait,
      creative: creative,
      brushStrokes: const [],
    );
