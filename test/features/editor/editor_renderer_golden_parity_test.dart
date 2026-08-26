import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/custom_lut_core.dart';
import 'package:memoria/engine/local_adjust.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';
import 'package:memoria/features/editor/editor_spatial_renderer.dart';

void main() {
  test('real-photo preview matches full export golden within tolerance',
      () async {
    final bytes = File('assets/images/summer_sapporo.jpg').readAsBytesSync();
    final source = img.decodeImage(bytes);
    expect(source, isNotNull, reason: 'Committed photo fixture must decode');

    final recipe = _fixtureRecipe();
    final preview = await EditorRenderer.renderPreview(
      source: source!,
      recipe: recipe,
      maxLongEdge: 480,
    );
    final fullExport = await EditorRenderer.renderExport(
      source: source,
      recipe: recipe,
    );
    final exportGolden = img.copyResize(
      fullExport,
      width: preview.width,
      height: preview.height,
      interpolation: img.Interpolation.cubic,
    );
    final metrics = _diff(preview, exportGolden);

    expect(preview.width / preview.height, closeTo(4 / 3, 0.01));
    expect(metrics.mean, lessThanOrEqualTo(2.0));
    expect(metrics.p99, lessThanOrEqualTo(9));
  });

  test('export applies portrait correction in the transformed mask space',
      () async {
    final source = img.Image(width: 4, height: 3);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, 40 + x * 30, 40 + y * 40, 80);
      }
    }
    final sourceMask = Float32List(4 * 3)..[1 * 4 + 1] = 1;
    final recipe = _fixtureRecipeWithPortrait();
    final resources = EditorRenderResources(
      segmentMask: sourceMask,
      segmentMaskWidth: 4,
      segmentMaskHeight: 3,
    );

    final exported = await EditorRenderer.renderExport(
      source: source,
      recipe: recipe,
      resources: resources,
    );
    final expectedMask = EditorSpatialRenderer.applyMask(
      EditorSpatialMask(sourceMask, 4, 3),
      recipe,
    );
    final expected = await EditorRenderer.applyVisual(
      EditorRenderer.prepareExportSource(source, recipe),
      recipe,
      resources.copyWith(
        segmentMask: expectedMask.data,
        segmentMaskWidth: expectedMask.width,
        segmentMaskHeight: expectedMask.height,
      ),
    );

    expect(exported.width, expected.width);
    expect(exported.height, expected.height);
    expect(exported.getBytes(), expected.getBytes());
  });

  test('real-photo tone, curve, HDR, grain, and drama recipe stays on baseline',
      () async {
    final source = img.decodeImage(
      File('assets/images/summer_sapporo.jpg').readAsBytesSync(),
    );
    expect(source, isNotNull);

    final rendered = await EditorRenderer.renderExport(
      source: source!,
      recipe: _highImpactRecipe(),
      maxDimension: 360,
    );

    expect(_rgbaHash(rendered), '0ea0059b');
  });

  test('real-photo custom LUT recipe stays on baseline', () async {
    final source = img.decodeImage(
      File('assets/images/summer_sapporo.jpg').readAsBytesSync(),
    );
    expect(source, isNotNull);

    final rendered = await EditorRenderer.renderExport(
      source: source!,
      recipe: _highImpactRecipe(lutBytes: _warmFixtureLut()),
      maxDimension: 360,
    );

    expect(_rgbaHash(rendered), 'a4af1c64');
  });

  test('real-photo local adjustment and blur recipe stays on baseline',
      () async {
    final source = img.decodeImage(
      File('assets/images/summer_sapporo.jpg').readAsBytesSync(),
    );
    expect(source, isNotNull);

    final rendered = await EditorRenderer.renderExport(
      source: source!,
      recipe: _localAndBlurRecipe(),
      maxDimension: 360,
    );

    expect(_rgbaHash(rendered), '5226899f');
  });

  test('production preview isolate matches the committed visual renderer',
      () async {
    final source = img.decodeImage(
      File('assets/images/summer_sapporo.jpg').readAsBytesSync(),
    );
    expect(source, isNotNull);
    final recipe = _localAndBlurRecipe();
    final prepared = EditorRenderer.preparePreviewSource(
      source!,
      recipe,
      maxLongEdge: 360,
    );
    final request = EditorPreviewRenderRequest(
      width: prepared.width,
      height: prepared.height,
      imageBytes: prepared.getBytes(order: img.ChannelOrder.rgba),
      recipe: recipe,
      resources: const EditorRenderResources(),
    );

    final workerBytes =
        await compute(EditorRenderer.renderPreviewBytes, request);
    final workerImage = img.decodeImage(workerBytes);
    final expected = await EditorRenderer.applyVisual(
      prepared,
      recipe,
      const EditorRenderResources(),
    );

    expect(workerImage, isNotNull);
    expect(workerImage!.getBytes(), expected.getBytes());
  });
}

EditorRenderRecipe _fixtureRecipe() => EditorRenderRecipe(
      adjustParams: const AdjustParams(
        exposure: 0.22,
        contrast: 18,
        saturation: 12,
        temperature: 8,
        tint: -4,
        highlights: -15,
        shadows: 10,
      ),
      lutBytes: null,
      intensity: 1,
      crop: const CropState(centerX: 0.46, centerY: 0.5, flipH: true),
      cropAspectRatio: 4 / 3,
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

EditorRenderRecipe _fixtureRecipeWithPortrait() => EditorRenderRecipe(
      adjustParams: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
      crop: const CropState(
        expandTop: 1 / 3,
        expandLeft: 1 / 4,
        expandMode: 'smart',
        cropLeft: 0.2,
        flipH: true,
        rotation: 90,
      ),
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
      portrait: const PortraitParams(spotlight: 75),
      creative: CreativeParams.zero,
      brushStrokes: const [],
    );

EditorRenderRecipe _highImpactRecipe({Uint8List? lutBytes}) =>
    EditorRenderRecipe(
      adjustParams: const AdjustParams(
        exposure: 0.18,
        contrast: 14,
        saturation: 9,
        highlights: -18,
        shadows: 13,
        luminanceCurve: CurveData(
          channel: CurveChannel.luminance,
          points: <CurvePoint>[
            CurvePoint(0, 0),
            CurvePoint(0.3, 0.24),
            CurvePoint(0.68, 0.77),
            CurvePoint(1, 1),
          ],
        ),
        hdrStrength: 35,
        hdrSaturation: 9,
        grainStrength: 11,
        grainSize: 1.2,
        grainSeed: 73,
      ),
      lutBytes: lutBytes,
      intensity: 0.82,
      crop: const CropState(flipH: true),
      cropAspectRatio: 4 / 3,
      effect: ArtisticEffect.dramaBright1,
      effectStrength: 0.65,
      grainVariant: 3,
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

EditorRenderRecipe _localAndBlurRecipe() => EditorRenderRecipe(
      adjustParams: const AdjustParams(exposure: 0.08, saturation: 5),
      lutBytes: null,
      intensity: 1,
      crop: const CropState(centerX: 0.47, flipV: true),
      cropAspectRatio: 4 / 3,
      effect: ArtisticEffect.none,
      effectStrength: 1,
      grainVariant: 0,
      selectiveActive: true,
      selectiveX: 0.36,
      selectiveY: 0.42,
      selectiveBrightness: 18,
      selectiveContrast: 10,
      selectiveSaturation: 12,
      selectiveRadius: 0.26,
      dodgeBurnActive: true,
      dodgeStrength: 0.28,
      dodgeY: 0.35,
      dodgeRadius: 0.22,
      burnStrength: 0.24,
      burnY: 0.71,
      burnRadius: 0.19,
      tiltActive: true,
      tiltFocusCenter: 0.48,
      tiltBandWidth: 0.31,
      tiltMaxBlur: 3.0,
      lensActive: true,
      lensFocusDepth: 0.43,
      lensMaxRadius: 2.0,
      portrait: PortraitParams.zero,
      creative: CreativeParams.zero,
      brushStrokes: const <DodgeBurnStroke>[
        DodgeBurnStroke(
          x: 0.31,
          y: 0.35,
          radius: 0.2,
          strength: 0.35,
          isDodge: true,
        ),
        DodgeBurnStroke(
          x: 0.68,
          y: 0.7,
          radius: 0.18,
          strength: 0.3,
          isDodge: false,
        ),
      ],
    );

({double mean, int p99}) _diff(img.Image a, img.Image b) {
  expect(a.width, b.width);
  expect(a.height, b.height);
  final values = <int>[];
  var sum = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final first = a.getPixel(x, y);
      final second = b.getPixel(x, y);
      for (final delta in [
        (first.r - second.r).abs().round(),
        (first.g - second.g).abs().round(),
        (first.b - second.b).abs().round(),
      ]) {
        values.add(delta);
        sum += delta;
      }
    }
  }
  values.sort();
  return (
    mean: sum / values.length,
    p99: values[(values.length * 0.99).floor().clamp(0, values.length - 1)],
  );
}

String _rgbaHash(img.Image image) {
  var hash = 0x811c9dc5;
  for (final byte in image.getBytes(order: img.ChannelOrder.rgba)) {
    hash = (hash ^ byte) * 0x01000193 & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Uint8List _warmFixtureLut() {
  final bytes = buildIdentityCustomLut();
  final values = bytes.buffer.asUint16List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ Uint16List.bytesPerElement,
  );
  for (var index = 0; index < values.length; index += 3) {
    final red = halfToFloat(values[index]);
    final green = halfToFloat(values[index + 1]);
    final blue = halfToFloat(values[index + 2]);
    values[index] = floatToHalf((red * 1.04 + 0.015).clamp(0.0, 1.0));
    values[index + 1] = floatToHalf((green * 0.98 + 0.01).clamp(0.0, 1.0));
    values[index + 2] = floatToHalf((blue * 0.90).clamp(0.0, 1.0));
  }
  return bytes;
}
