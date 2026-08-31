import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  group('HSL Engine Tests', () {
    // Helper to apply HSL bands
    RgbColor applyHslAdjust(RgbColor color, HslMap hsl) {
      final params = AdjustParams(hsl: hsl);
      return applyAdjustParams(color, params);
    }

    test('no-op when all parameters are zero', () {
      const original = RgbColor(0.8, 0.4, 0.2);
      final out = applyHslAdjust(original, const {});
      expect(out.r, closeTo(original.r, 1e-6));
      expect(out.g, closeTo(original.g, 1e-6));
      expect(out.b, closeTo(original.b, 1e-6));
    });

    test('hue shift red wrap-around near 0/360 boundary', () {
      // 0 degrees is Red.
      // Define a hue shift for the red band
      const redShift = {
        HslBand.red: HslBandParams(hue: 20.0),
      };

      // Test RgbColor representing red with hue close to 0 (e.g. 5 degrees)
      const redColor1 = RgbColor(1.0, 0.1, 0.0); // Hue ~ 6 degrees
      final out1 = applyHslAdjust(redColor1, redShift);
      final diff1 = (out1.r - redColor1.r).abs() +
          (out1.g - redColor1.g).abs() +
          (out1.b - redColor1.b).abs();
      expect(diff1, greaterThan(1e-4));

      // Test RgbColor representing red with hue close to 360 (e.g. 355 degrees)
      const redColor2 = RgbColor(1.0, 0.0, 0.1); // Hue ~ 354 degrees
      final out2 = applyHslAdjust(redColor2, redShift);
      final diff2 = (out2.r - redColor2.r).abs() +
          (out2.g - redColor2.g).abs() +
          (out2.b - redColor2.b).abs();
      expect(diff2, greaterThan(1e-4));
    });

    test('neutrals (R=G=B) are preserved under hue-only shifts', () {
      const gray = RgbColor(0.5, 0.5, 0.5);
      final hueShifts = {
        HslBand.red: const HslBandParams(hue: 50.0),
        HslBand.green: const HslBandParams(hue: -60.0),
        HslBand.blue: const HslBandParams(hue: 120.0),
      };

      final out = applyHslAdjust(gray, hueShifts);
      // Gray has 0 saturation, so hue shift should have no effect.
      // Out must still be neutral gray.
      expect(out.r, closeTo(0.5, 1e-6));
      expect(out.g, closeTo(0.5, 1e-6));
      expect(out.b, closeTo(0.5, 1e-6));
    });

    test('band isolation: blue adjustment does not affect red', () {
      const red = RgbColor(0.9, 0.1, 0.1);
      final blueAdjustment = {
        HslBand.blue:
            const HslBandParams(hue: 45.0, saturation: -80.0, luminance: 30.0),
      };

      final out = applyHslAdjust(red, blueAdjustment);
      // Red should remain practically unchanged.
      expect(out.r, closeTo(red.r, 0.008));
      expect(out.g, closeTo(red.g, 0.008));
      expect(out.b, closeTo(red.b, 0.008));
    });

    test('smooth Gaussian feathering between adjacent bands', () {
      const green = RgbColor(0.1, 0.9, 0.1); // Hue ~ 120 (Green)

      // Green band center is 120.
      // Cyan band center is 180.
      // Red band center is 0.
      final cyanAdjust = {
        HslBand.cyan: const HslBandParams(saturation: -50.0),
      };

      final out = applyHslAdjust(green, cyanAdjust);

      // green hue (120) has some weight relative to Cyan center (180) because sigma is 35.
      // (120 - 180)^2 = 3600. -3600 / (2 * 35^2) = -1.46. weight = exp(-1.46) = ~0.23.
      // So Green's saturation should decrease partially (be lower than original green).
      // Since green saturation drops, G value drops slightly, bringing R/B relatively closer.
      expect(out.g, lessThan(green.g));
    });

    test('skin tone adjustments affect orange and yellow bands', () {
      // Skin tone approximate (Orange-Yellow, e.g. R=0.9, G=0.7, B=0.55 => Hue ~ 25 degrees)
      const skin = RgbColor(0.9, 0.7, 0.55);

      // Adjust Orange saturation
      final orangeAdjust = {
        HslBand.orange: const HslBandParams(saturation: -30.0),
      };

      final out = applyHslAdjust(skin, orangeAdjust);
      expect(out.g, isNot(closeTo(skin.g, 1e-4)));
    });
  });
}
