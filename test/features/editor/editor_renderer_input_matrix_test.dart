import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/core/services/export_preferences.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/engine/artistic_effects.dart';
import 'package:memoria/engine/export_encoder.dart';
import 'package:memoria/features/editor/editor_render_recipe.dart';
import 'package:memoria/features/editor/editor_renderer.dart';

void main() {
  test('wide and tall inputs export within the requested long edge', () async {
    for (final source in <img.Image>[
      _gradient(1500, 300),
      _gradient(300, 1500),
    ]) {
      final output = await EditorRenderer.renderExport(
        source: source,
        recipe: _identityRecipe(),
        maxDimension: 512,
      );
      expect(output.width, greaterThan(0));
      expect(output.height, greaterThan(0));
      expect(output.width > output.height ? output.width : output.height, 512);
    }
  });

  test('transparent PNG input remains encodable after production rendering',
      () async {
    final source = _gradient(257, 193, transparent: true);
    final output = await EditorRenderer.renderExport(
      source: source,
      recipe: _identityRecipe(),
    );
    final encoded = ExportEncoder.encode(
      output,
      format: ExportFormat.png,
      quality: 95,
    );
    final decoded = img.decodeImage(encoded);

    expect(ExportEncoder.matchesSignature(ExportFormat.png, encoded), isTrue);
    expect(decoded, isNotNull);
    expect(decoded!.width, source.width);
    expect(decoded.height, source.height);
    expect(decoded.getPixel(0, 96).a, 0);
    expect(decoded.getPixel(256, 96).a, 255);
  });

  test('12MP-equivalent input downscales before the visual render stage',
      () async {
    final source = img.Image(width: 4000, height: 3000, numChannels: 4)
      ..clear(img.ColorRgba8(38, 91, 154, 255));

    final output = await EditorRenderer.renderExport(
      source: source,
      recipe: _identityRecipe(),
      maxDimension: 1024,
    );

    expect(output.width, 1024);
    expect(output.height, 768);
  });
}

img.Image _gradient(int width, int height, {bool transparent = false}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        (x * 255 / (width - 1)).round(),
        (y * 255 / (height - 1)).round(),
        120,
        transparent ? (x * 255 / (width - 1)).round() : 255,
      );
    }
  }
  return image;
}

EditorRenderRecipe _identityRecipe() => EditorRenderRecipe(
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
      creative: CreativeParams.zero,
      brushStrokes: const [],
    );
