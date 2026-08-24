// Whitebox tests — custom_lut_core.dart
// Coverage: floatToHalf, halfToFloat, applyCustomLut (trilinear interpolation,
//   boundary conditions, identity LUT, clamp behaviour)

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/custom_lut_core.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

/// Build an identity 65³ LUT (output == input).
Uint8List _makeIdentityLut() {
  const dim = customLutDim;
  final lut = Uint16List(dim * dim * dim * 3);
  final max = (dim - 1).toDouble();
  var i = 0;
  for (var b = 0; b < dim; b++) {
    for (var g = 0; g < dim; g++) {
      for (var r = 0; r < dim; r++) {
        lut[i++] = floatToHalf(r / max);
        lut[i++] = floatToHalf(g / max);
        lut[i++] = floatToHalf(b / max);
      }
    }
  }
  return lut.buffer.asUint8List();
}

/// Build a constant LUT (every entry maps to the given colour).
Uint8List _makeConstantLut(double r, double g, double b) {
  const dim = customLutDim;
  final lut = Uint16List(dim * dim * dim * 3);
  for (var i = 0; i < lut.length; i += 3) {
    lut[i] = floatToHalf(r);
    lut[i + 1] = floatToHalf(g);
    lut[i + 2] = floatToHalf(b);
  }
  return lut.buffer.asUint8List();
}

img.Image _solidImage(int r, int g, int b) {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

img.Image _warmSceneImage({required int exposureOffset, required bool invert}) {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final position = invert ? image.width - 1 - x : x;
      final luminance =
          (45 + position * 5 + y * 2 + exposureOffset).clamp(0, 190).toInt();
      image.setPixelRgb(
        x,
        y,
        (luminance + 45).clamp(0, 255),
        (luminance + 12).clamp(0, 255),
        (luminance - 25).clamp(0, 255),
      );
    }
  }
  return image;
}

img.Image _saturatedReferenceImage() {
  final image = img.Image(width: 48, height: 48);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (x < 16) {
        image.setPixelRgb(x, y, 215, 62, 35);
      } else if (x < 32) {
        image.setPixelRgb(x, y, 40, 105, 220);
      } else {
        image.setPixelRgb(x, y, 225, 176, 68);
      }
    }
  }
  return image;
}

double _chroma(RgbColor color) {
  final maxChannel =
      [color.r, color.g, color.b].reduce((a, b) => a > b ? a : b);
  final minChannel =
      [color.r, color.g, color.b].reduce((a, b) => a < b ? a : b);
  return maxChannel - minChannel;
}

void main() {
  // ── floatToHalf / halfToFloat ─────────────────────────────────────────────
  group('floatToHalf / halfToFloat', () {
    test('0.0 round-trips exactly', () {
      expect(halfToFloat(floatToHalf(0.0)), closeTo(0.0, 1e-4));
    });

    test('1.0 round-trips exactly', () {
      expect(halfToFloat(floatToHalf(1.0)), closeTo(1.0, 1e-3));
    });

    test('0.5 round-trips within float16 precision (~0.001)', () {
      expect(halfToFloat(floatToHalf(0.5)), closeTo(0.5, 0.002));
    });

    test('values < 0 are clamped to 0 before encoding', () {
      // floatToHalf clamps to [0,1] per implementation
      expect(halfToFloat(floatToHalf(-0.5)), closeTo(0.0, 1e-4));
    });

    test('values > 1 are clamped to 1 before encoding', () {
      expect(halfToFloat(floatToHalf(1.5)), closeTo(1.0, 1e-3));
    });

    test('typical LUT values round-trip within ±0.001', () {
      const samples = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
      for (final v in samples) {
        final rt = halfToFloat(floatToHalf(v));
        expect(rt, closeTo(v, 0.002), reason: 'round-trip $v → $rt');
      }
    });

    test('halfToFloat(0 exponent) returns 0.0', () {
      // exp==0 → denorm, treated as 0 in our implementation
      expect(halfToFloat(0x0000), closeTo(0.0, 1e-10));
    });
  });

  // ── applyCustomLut: identity LUT ──────────────────────────────────────────
  group('applyCustomLut with identity LUT', () {
    late Uint8List identityLut;
    setUp(() => identityLut = _makeIdentityLut());

    const testColors = [
      RgbColor(0.0, 0.0, 0.0),
      RgbColor(1.0, 1.0, 1.0),
      RgbColor(0.5, 0.5, 0.5),
      RgbColor(1.0, 0.0, 0.0),
      RgbColor(0.0, 1.0, 0.0),
      RgbColor(0.0, 0.0, 1.0),
      RgbColor(0.25, 0.5, 0.75),
      RgbColor(0.9, 0.1, 0.4),
    ];

    for (final c in testColors) {
      test(
          'identity preserves (${c.r.toStringAsFixed(2)}, '
          '${c.g.toStringAsFixed(2)}, '
          '${c.b.toStringAsFixed(2)})', () {
        final out = applyCustomLut(identityLut, c);
        expect(out.r, closeTo(c.r, 0.01), reason: 'r channel');
        expect(out.g, closeTo(c.g, 0.01), reason: 'g channel');
        expect(out.b, closeTo(c.b, 0.01), reason: 'b channel');
      });
    }
  });

  // ── applyCustomLut: constant LUT ──────────────────────────────────────────
  group('decodeCustomLut cache', () {
    test('reuses the decoded lookup table for the same LUT bytes object', () {
      final lut = _makeIdentityLut();
      final decodedA = decodeCustomLut(lut);
      final decodedB = decodeCustomLut(lut);

      expect(decodedB, same(decodedA));
      expect(
        decodedA.values.length,
        customLutDim * customLutDim * customLutDim * 3,
      );
    });

    test('tryDecodeCustomLut returns null for corrupt bytes', () {
      expect(tryDecodeCustomLut(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('applyCustomLut with constant LUT', () {
    test('maps every colour to the constant value', () {
      const target = RgbColor(0.3, 0.6, 0.9);
      final lut = _makeConstantLut(target.r, target.g, target.b);
      final inputs = [
        const RgbColor(0, 0, 0),
        const RgbColor(1, 1, 1),
        const RgbColor(0.5, 0.2, 0.8),
      ];
      for (final c in inputs) {
        final out = applyCustomLut(lut, c);
        expect(out.r, closeTo(target.r, 0.003));
        expect(out.g, closeTo(target.g, 0.003));
        expect(out.b, closeTo(target.b, 0.003));
      }
    });
  });

  // ── applyCustomLut: boundary/corner lookup ────────────────────────────────
  group('applyCustomLut boundary lookup (exact LUT corners)', () {
    // Colours that land exactly on LUT grid points avoid interpolation
    // and should match their stored values within float16 precision.
    late Uint8List identityLut;
    setUp(() => identityLut = _makeIdentityLut());

    const corners = [
      RgbColor(0.0, 0.0, 0.0),
      RgbColor(1.0, 0.0, 0.0),
      RgbColor(0.0, 1.0, 0.0),
      RgbColor(0.0, 0.0, 1.0),
      RgbColor(1.0, 1.0, 0.0),
      RgbColor(1.0, 0.0, 1.0),
      RgbColor(0.0, 1.0, 1.0),
      RgbColor(1.0, 1.0, 1.0),
    ];

    for (final c in corners) {
      test('corner (${c.r}, ${c.g}, ${c.b}) preserved', () {
        final out = applyCustomLut(identityLut, c);
        expect(out.r, closeTo(c.r, 0.01));
        expect(out.g, closeTo(c.g, 0.01));
        expect(out.b, closeTo(c.b, 0.01));
      });
    }
  });

  // ── applyCustomLut: output always in [0,1] ───────────────────────────────
  test('output is always clamped to [0,1]', () {
    final identityLut = _makeIdentityLut();
    const extreme = [
      RgbColor(0.0, 0.0, 0.0),
      RgbColor(1.0, 1.0, 1.0),
      RgbColor(0.999, 0.999, 0.999),
      RgbColor(0.001, 0.001, 0.001),
    ];
    for (final c in extreme) {
      final out = applyCustomLut(identityLut, c);
      expect(out.r, inInclusiveRange(0.0, 1.0));
      expect(out.g, inInclusiveRange(0.0, 1.0));
      expect(out.b, inInclusiveRange(0.0, 1.0));
    }
  });

  // ── applyCustomLut: interpolation smoothness ─────────────────────────────
  group('trilinear interpolation continuity', () {
    test('closely-spaced inputs produce close outputs (identity LUT)', () {
      final lut = _makeIdentityLut();
      const c1 = RgbColor(0.5000, 0.5000, 0.5000);
      const c2 = RgbColor(0.5001, 0.5001, 0.5001);
      final o1 = applyCustomLut(lut, c1);
      final o2 = applyCustomLut(lut, c2);
      expect((o1.r - o2.r).abs(), lessThan(0.005));
      expect((o1.g - o2.g).abs(), lessThan(0.005));
      expect((o1.b - o2.b).abs(), lessThan(0.005));
    });
  });

  group('generated LUT safety constraints', () {
    test('identity LUT passes the safety inspection', () {
      final report = inspectCustomLutSafety(buildIdentityCustomLut());

      expect(report.isSafe, isTrue);
      expect(report.interiorClipRatio, lessThan(0.001));
      expect(report.neutralInversions, 0);
      expect(report.neutralLuminanceRange, greaterThan(0.9));
    });

    test('collapsed LUT is attenuated toward identity before persistence', () {
      final collapsed = _makeConstantLut(0.5, 0.5, 0.5);
      expect(inspectCustomLutSafety(collapsed).isSafe, isFalse);

      final constrained = constrainCustomLut(collapsed);

      expect(constrained.report.isSafe, isTrue);
      expect(constrained.appliedStrength, lessThan(1.0));
      expect(constrained.fallbackReason, 'lut_safety_strength_reduced');
      expect(constrained.report.primaryMinChroma, greaterThan(0.05));
    });

    test('malformed LUT falls back to a safe identity LUT', () {
      final constrained = constrainCustomLut(Uint8List(16));

      expect(constrained.appliedStrength, 0.0);
      expect(constrained.fallbackReason, 'lut_safety_identity_fallback');
      expect(constrained.report.isSafe, isTrue);
    });

    test('generated color LUT does not collapse saturated primaries to gray',
        () {
      final candidate =
          buildCustomLutFromStyleImage(_saturatedReferenceImage());
      final constrained = constrainCustomLut(candidate);
      final blue = applyCustomLut(
        constrained.bytes,
        const RgbColor(0.05, 0.25, 0.95),
      );
      final red = applyCustomLut(
        constrained.bytes,
        const RgbColor(0.95, 0.15, 0.08),
      );

      expect(constrained.report.isSafe, isTrue);
      expect(_chroma(blue), greaterThan(0.10));
      expect(_chroma(red), greaterThan(0.10));
    });
  });

  group('reference fusion diagnostics', () {
    test('keeps a shared look across differently composed scenes', () {
      final diagnostics = inspectReferenceFusion([
        _warmSceneImage(exposureOffset: -12, invert: false),
        _warmSceneImage(exposureOffset: 0, invert: true),
        _warmSceneImage(exposureOffset: 14, invert: false),
      ]);

      expect(diagnostics.inputReferenceCount, 3);
      expect(diagnostics.usedReferenceCount, 3);
      expect(diagnostics.confidence, greaterThan(0.60));
    });

    test('excludes a style outlier when three or more references agree', () {
      final warm = _solidImage(210, 150, 100);
      final coolOutlier = _solidImage(25, 70, 225);

      final diagnostics = inspectReferenceFusion([
        warm,
        _solidImage(210, 150, 100),
        _solidImage(210, 150, 100),
        _solidImage(210, 150, 100),
        coolOutlier,
      ]);

      expect(diagnostics.inputReferenceCount, 5);
      expect(diagnostics.usedReferenceCount, 4);
      expect(diagnostics.excludedReferenceCount, 1);
      expect(diagnostics.confidence, greaterThan(0.75));
    });

    test('keeps both references when exactly two looks disagree', () {
      final diagnostics = inspectReferenceFusion([
        _solidImage(210, 150, 100),
        _solidImage(25, 70, 225),
      ]);

      expect(diagnostics.inputReferenceCount, 2);
      expect(diagnostics.usedReferenceCount, 2);
      expect(diagnostics.excludedReferenceCount, 0);
      expect(diagnostics.confidence, lessThan(1.0));
    });
  });
}
