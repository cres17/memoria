import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/domain/models/filter_recipe.dart';

void main() {
  test('generated recipe round-trips its render contract and diagnostics', () {
    final recipe = FilterRecipe(
      lutDimension: 65,
      engineVersion: 'on_device_lut_engine_v1',
      generatorType: 'algorithmic',
      lutStrength: 0.75,
      referenceCount: 4,
      safetyMetrics: const {'isSafe': true},
      referenceFusion: const {'confidence': 0.82},
      fallbackReason: 'lut_safety_strength_reduced',
      modelId: 'affine_plus_residual_lut',
      modelVersion: 'v1',
    );

    final restored = FilterRecipe.fromJson(recipe.toJson());

    expect(restored.version, FilterRecipe.currentVersion);
    expect(restored.colorSpace, FilterRecipe.srgb);
    expect(restored.lutAxisOrder, FilterRecipe.rFastestRgb);
    expect(restored.renderOrder, FilterRecipe.currentRenderOrder);
    expect(restored.lutDimension, 65);
    expect(restored.referenceFusion!['confidence'], 0.82);
    expect(restored.safetyMetrics['isSafe'], isTrue);
    expect(restored.modelId, 'affine_plus_residual_lut');
    expect(restored.modelVersion, 'v1');
  });

  test('legacy preset JSON is upgraded to a deterministic recipe on read', () {
    final legacyJson = {
      'id': 'legacy',
      'name': 'Legacy Filter',
      'type': 'custom',
      'lut_path': '/filters/legacy/lut.bin',
      'params': AdjustParams.zero.toJson(),
      'default_intensity': 0.8,
      'thumbnail_path': '/filters/legacy/thumb.jpg',
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
    };

    final preset = FilterPreset.fromJson(legacyJson);
    final persisted = preset.toJson();

    expect(preset.effectiveRecipe.engineVersion, 'legacy_preset_v0');
    expect(preset.effectiveRecipe.lutDimension, 65);
    expect(persisted['recipe'], isA<Map<String, dynamic>>());
  });
}
