import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('Split Toning Engine Tests', () {
    test('no-op when shadow and highlight saturation are zero', () {
      const original = RgbColor(0.5, 0.5, 0.5);
      const params = AdjustParams(
        splitShadowHue: 120,
        splitShadowSat: 0,
        splitHighHue: 240,
        splitHighSat: 0,
        splitBalance: 0,
      );
      final out = applyAdjustParams(original, params);
      expect(out.r, closeTo(original.r, 1e-6));
      expect(out.g, closeTo(original.g, 1e-6));
      expect(out.b, closeTo(original.b, 1e-6));
    });

    test('shadow toning affects shadows but not highlights', () {
      // Teal shadows (hue ~ 180, sat ~ 40)
      const params = AdjustParams(
        splitShadowHue: 180,
        splitShadowSat: 40,
        splitHighSat: 0,
      );

      const shadowPixel = RgbColor(0.2, 0.2, 0.2);
      const highlightPixel = RgbColor(0.8, 0.8, 0.8);

      final outShadow = applyAdjustParams(shadowPixel, params);
      final outHighlight = applyAdjustParams(highlightPixel, params);

      // Shadow pixel should change (e.g. green and blue channels go up, red goes down under 180 degrees)
      expect(outShadow.r, isNot(closeTo(shadowPixel.r, 1e-4)));
      expect(outShadow.g, isNot(closeTo(shadowPixel.g, 1e-4)));
      expect(outShadow.b, isNot(closeTo(shadowPixel.b, 1e-4)));

      // Highlight pixel should not change because weight highW is ~0 below splitPoint, and highSat is 0
      expect(outHighlight.r, closeTo(highlightPixel.r, 1e-4));
      expect(outHighlight.g, closeTo(highlightPixel.g, 1e-4));
      expect(outHighlight.b, closeTo(highlightPixel.b, 1e-4));
    });

    test('highlight toning affects highlights but not shadows', () {
      // Warm highlights (hue ~ 30, sat ~ 50)
      const params = AdjustParams(
        splitShadowSat: 0,
        splitHighHue: 30,
        splitHighSat: 50,
      );

      const shadowPixel = RgbColor(0.2, 0.2, 0.2);
      const highlightPixel = RgbColor(0.8, 0.8, 0.8);

      final outShadow = applyAdjustParams(shadowPixel, params);
      final outHighlight = applyAdjustParams(highlightPixel, params);

      // Shadow pixel should remain unchanged because shadowSat is 0
      expect(outShadow.r, closeTo(shadowPixel.r, 1e-4));
      expect(outShadow.g, closeTo(shadowPixel.g, 1e-4));
      expect(outShadow.b, closeTo(shadowPixel.b, 1e-4));

      // Highlight pixel should change
      expect(outHighlight.r, isNot(closeTo(highlightPixel.r, 1e-4)));
    });

    test('balance shift changes the crossover point', () {
      // Set highlight toning only
      // If balance is shifted to -100 (shadows), the highlight mask is wider and covers lower-midtones too.
      const paramsBase = AdjustParams(
        splitShadowSat: 0,
        splitHighHue: 60, // Yellow highlights
        splitHighSat: 40,
        splitBalance: 0,
      );

      const paramsShifted = AdjustParams(
        splitShadowSat: 0,
        splitHighHue: 60,
        splitHighSat: 40,
        splitBalance: -100.0, // Shift crossover to shadows
      );

      const midtonePixel = RgbColor(0.4, 0.4, 0.4);

      final outBase = applyAdjustParams(midtonePixel, paramsBase);
      final outShifted = applyAdjustParams(midtonePixel, paramsShifted);

      // Under shifted balance (-100), the highlight toning should affect the midtone pixel more than at balance = 0.
      // At hue 60, red/green are boosted. So green should be higher in outShifted than outBase.
      expect(outShifted.g, greaterThan(outBase.g));
    });

    test('toning outputs are clamped to [0.0, 1.0]', () {
      const brightRed = RgbColor(0.98, 0.02, 0.02);
      const params = AdjustParams(
        splitShadowHue: 0,
        splitShadowSat: 100, // Maximum push
        splitHighHue: 0,
        splitHighSat: 100,
      );

      final out = applyAdjustParams(brightRed, params);
      expect(out.r, lessThanOrEqualTo(1.0));
      expect(out.g, greaterThanOrEqualTo(0.0));
      expect(out.b, greaterThanOrEqualTo(0.0));
    });
  });
}
