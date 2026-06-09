// Whitebox tests — filter_preset.dart
// Coverage: FilterPreset toJson/fromJson, AdjustParams toJson/fromJson,
//   BuiltinPresets metadata consistency, isCustom/isBuiltin, isZero

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/filter_preset.dart';

void main() {
  // ── AdjustParams serialisation ───────────────────────────────────────────
  group('AdjustParams toJson / fromJson', () {
    test('zero params round-trips', () {
      final rt = AdjustParams.fromJson(AdjustParams.zero.toJson());
      expect(rt.exposure, closeTo(0, 1e-12));
      expect(rt.contrast, closeTo(0, 1e-12));
      expect(rt.saturation, closeTo(0, 1e-12));
      expect(rt.temperature, closeTo(0, 1e-12));
      expect(rt.tint, closeTo(0, 1e-12));
      expect(rt.highlights, closeTo(0, 1e-12));
      expect(rt.shadows, closeTo(0, 1e-12));
      expect(rt.sharpen, closeTo(0, 1e-12));
      expect(rt.vignette, closeTo(0, 1e-12));
      expect(rt.structure, closeTo(0, 1e-12));
      expect(rt.clarity, closeTo(0, 1e-12));
      expect(rt.bnwEnabled, isFalse);
      expect(rt.tonalShadows, closeTo(0, 1e-12));
      expect(rt.tonalMidtones, closeTo(0, 1e-12));
      expect(rt.tonalHighlights, closeTo(0, 1e-12));
    });

    test('non-zero values round-trip', () {
      const p = AdjustParams(
        exposure: 0.7,
        contrast: 30,
        saturation: -20,
        temperature: 15,
        tint: -5,
        highlights: -40,
        shadows: 25,
        sharpen: 50,
        vignette: 18,
        structure: 60,
        clarity: 40,
        bnwEnabled: true,
        bnwRed: 10,
        bnwGreen: -5,
        bnwBlue: -30,
        bnwYellow: 20,
        tonalShadows: -15,
        tonalMidtones: 5,
        tonalHighlights: 10,
      );
      final rt = AdjustParams.fromJson(p.toJson());
      expect(rt.exposure, closeTo(p.exposure, 1e-10));
      expect(rt.contrast, closeTo(p.contrast, 1e-10));
      expect(rt.saturation, closeTo(p.saturation, 1e-10));
      expect(rt.temperature, closeTo(p.temperature, 1e-10));
      expect(rt.tint, closeTo(p.tint, 1e-10));
      expect(rt.highlights, closeTo(p.highlights, 1e-10));
      expect(rt.shadows, closeTo(p.shadows, 1e-10));
      expect(rt.sharpen, closeTo(p.sharpen, 1e-10));
      expect(rt.vignette, closeTo(p.vignette, 1e-10));
      expect(rt.structure, closeTo(p.structure, 1e-10));
      expect(rt.clarity, closeTo(p.clarity, 1e-10));
      expect(rt.bnwEnabled, isTrue);
      expect(rt.bnwRed, closeTo(p.bnwRed, 1e-10));
      expect(rt.bnwGreen, closeTo(p.bnwGreen, 1e-10));
      expect(rt.bnwBlue, closeTo(p.bnwBlue, 1e-10));
      expect(rt.bnwYellow, closeTo(p.bnwYellow, 1e-10));
      expect(rt.tonalShadows, closeTo(p.tonalShadows, 1e-10));
      expect(rt.tonalMidtones, closeTo(p.tonalMidtones, 1e-10));
      expect(rt.tonalHighlights, closeTo(p.tonalHighlights, 1e-10));
    });

    test('params with curves round-trip', () {
      const p = AdjustParams(
        exposure: 0.2,
        rgbCurve: CurveData(
          channel: CurveChannel.rgb,
          points: [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)],
        ),
        luminanceCurve: CurveData(
          channel: CurveChannel.luminance,
          points: [CurvePoint(0, 0.05), CurvePoint(1, 0.95)],
        ),
      );
      final rt = AdjustParams.fromJson(p.toJson());
      expect(rt.rgbCurve, isNotNull);
      expect(rt.luminanceCurve, isNotNull);
      expect(rt.rgbCurve!.points.length, equals(3));
      expect(rt.luminanceCurve!.points[0].y, closeTo(0.05, 1e-10));
    });

    test('missing keys default to 0 / false', () {
      final rt = AdjustParams.fromJson(<String, dynamic>{});
      expect(rt.exposure, closeTo(0, 1e-12));
      expect(rt.bnwEnabled, isFalse);
    });

    test('isZero is true for default params', () {
      expect(AdjustParams.zero.isZero, isTrue);
    });

    test('isZero is false when any field is non-zero', () {
      expect(const AdjustParams(exposure: 0.1).isZero, isFalse);
      expect(const AdjustParams(bnwEnabled: true).isZero, isFalse);
    });

    test('hasCurves is false when all curves are null', () {
      expect(AdjustParams.zero.hasCurves, isFalse);
    });

    test('hasCurves is true when any curve is set', () {
      expect(
        AdjustParams(
          rgbCurve: CurveData.linear(CurveChannel.rgb),
        ).hasCurves,
        isTrue,
      );
    });
  });

  // ── FilterPreset serialisation ────────────────────────────────────────────
  group('FilterPreset toJson / fromJson', () {
    FilterPreset makePreset() => FilterPreset(
          id: 'test_id',
          name: 'Test Filter',
          type: FilterPresetType.custom,
          lutPath: '/tmp/lut.bin',
          params: const AdjustParams(exposure: 0.3, contrast: 20),
          defaultIntensity: 0.8,
          thumbnailPath: '/tmp/thumb.jpg',
          createdAt: DateTime(2026, 1, 15),
          updatedAt: DateTime(2026, 3, 10),
        );

    test('round-trip preserves all fields', () {
      final orig = makePreset();
      final rt = FilterPreset.fromJson(orig.toJson());
      expect(rt.id, equals(orig.id));
      expect(rt.name, equals(orig.name));
      expect(rt.type, equals(FilterPresetType.custom));
      expect(rt.lutPath, equals(orig.lutPath));
      expect(rt.defaultIntensity, closeTo(orig.defaultIntensity, 1e-10));
      expect(rt.thumbnailPath, equals(orig.thumbnailPath));
      expect(rt.createdAt, equals(orig.createdAt));
      expect(rt.updatedAt, equals(orig.updatedAt));
      expect(rt.params.exposure, closeTo(0.3, 1e-10));
      expect(rt.params.contrast, closeTo(20, 1e-10));
    });

    test('toJsonString is valid JSON', () {
      final json = makePreset().toJsonString();
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('type="custom" → FilterPresetType.custom', () {
      final json = makePreset().toJson();
      json['type'] = 'custom';
      expect(FilterPreset.fromJson(json).type, equals(FilterPresetType.custom));
    });

    test('type="builtin" → FilterPresetType.builtin', () {
      final json = makePreset().toJson();
      json['type'] = 'builtin';
      expect(
          FilterPreset.fromJson(json).type, equals(FilterPresetType.builtin));
    });

    test('isCustom / isBuiltin flags', () {
      expect(makePreset().isCustom, isTrue);
      expect(makePreset().isBuiltin, isFalse);
    });
  });

  // ── BuiltinPresets metadata ───────────────────────────────────────────────
  group('BuiltinPresets metadata', () {
    test('no duplicate ids', () {
      final ids = BuiltinPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, equals(ids.length));
    });

    test('ids list matches all list order', () {
      final ids = BuiltinPresets.all.map((p) => p.id).toList();
      expect(BuiltinPresets.ids, equals(ids));
    });

    test('every preset has non-empty id and name', () {
      for (final p in BuiltinPresets.all) {
        expect(p.id, isNotEmpty, reason: 'id empty');
        expect(p.name, isNotEmpty, reason: '${p.id} name empty');
      }
    });

    test('every preset type is builtin', () {
      for (final p in BuiltinPresets.all) {
        expect(p.type, equals(FilterPresetType.builtin),
            reason: '${p.id} must be builtin');
      }
    });

    test('defaultIntensity in [0,1] for all presets', () {
      for (final p in BuiltinPresets.all) {
        expect(p.defaultIntensity, inInclusiveRange(0.0, 1.0),
            reason: '${p.id} intensity out of range');
      }
    });

    test('lutPath is non-empty and starts with "assets/" for LUT-based presets',
        () {
      for (final p in BuiltinPresets.all) {
        if (p.lutPath.isNotEmpty) {
          expect(p.lutPath, startsWith('assets/'),
              reason: '${p.id} lutPath must be an asset path');
        }
      }
    });

    test('original preset remains available as a reset reference', () {
      expect(BuiltinPresets.original.params.isZero, isTrue);
    });

    test('BuiltinPresets.all exposes all Snapseed-style presets', () {
      expect(BuiltinPresets.all.length, equals(9));
      final expectedIds = [
        'original',
        'portrait',
        'smooth',
        'pop',
        'accentuate',
        'faded_glow',
        'morning',
        'fine_art',
        'structure',
      ];
      expect(BuiltinPresets.all.map((p) => p.id), equals(expectedIds));
    });

    test('copyWith preserves unchanged fields', () {
      final orig = BuiltinPresets.portrait;
      final modified = orig.copyWith(name: 'Portrait2');
      expect(modified.id, equals(orig.id));
      expect(modified.name, equals('Portrait2'));
      expect(modified.params.exposure, closeTo(orig.params.exposure, 1e-10));
    });
  });
}
