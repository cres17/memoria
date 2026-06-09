// Whitebox tests — lut_engine.dart
// Coverage:
//   applyAdjustParams  — exposure, contrast, saturation, temperature/tint,
//                        highlights, shadows, B&W, tonal contrast, curves
//   applyPipeline      — LUT+intensity mix order, null-LUT passthrough
//   applyImagePipeline — sharpen/structure/clarity/vignette gate conditions
//   loadLutBytes       — null/empty/asset/file path routing

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/custom_lut_core.dart';
import 'package:memoria/engine/lut_engine.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Uint8List _identityLut() {
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

const _mid = RgbColor(0.5, 0.5, 0.5);

void main() {
  // ── applyAdjustParams: identity ────────────────────────────────────────────
  group('applyAdjustParams — zero params = passthrough', () {
    const colors = [
      RgbColor(0, 0, 0),
      RgbColor(1, 1, 1),
      RgbColor(0.5, 0.5, 0.5),
      RgbColor(0.2, 0.7, 0.4),
    ];
    for (final c in colors) {
      test('zero (${c.r}, ${c.g}, ${c.b})', () {
        final out = applyAdjustParams(c, AdjustParams.zero);
        expect(out.r, closeTo(c.r, 0.002));
        expect(out.g, closeTo(c.g, 0.002));
        expect(out.b, closeTo(c.b, 0.002));
      });
    }
  });

  // ── applyAdjustParams: exposure ────────────────────────────────────────────
  group('applyAdjustParams — exposure', () {
    test('+1.0 exposure doubles luminance (approx)', () {
      final out = applyAdjustParams(
          const RgbColor(0.25, 0.25, 0.25), const AdjustParams(exposure: 1.0));
      // 2^1.0 = 2× → 0.25*2 = 0.5
      expect(out.r, closeTo(0.5, 0.01));
    });

    test('-1.0 exposure halves luminance (approx)', () {
      final out = applyAdjustParams(
          const RgbColor(0.5, 0.5, 0.5), const AdjustParams(exposure: -1.0));
      expect(out.r, closeTo(0.25, 0.01));
    });

    test('extreme +2.0 exposure clamps to 1.0', () {
      final out = applyAdjustParams(
          const RgbColor(0.9, 0.9, 0.9), const AdjustParams(exposure: 2.0));
      expect(out.r, closeTo(1.0, 0.001));
    });

    test('extreme -2.0 exposure produces near-black', () {
      final out = applyAdjustParams(
          const RgbColor(0.5, 0.5, 0.5), const AdjustParams(exposure: -2.0));
      // 0.5 * 2^(-2) = 0.125 → well below 0.20
      expect(out.r, lessThan(0.20));
    });
  });

  // ── applyAdjustParams: contrast ────────────────────────────────────────────
  group('applyAdjustParams — contrast', () {
    test('+100 contrast: dark pixel gets darker', () {
      final dark = applyAdjustParams(
          const RgbColor(0.2, 0.2, 0.2), const AdjustParams(contrast: 100));
      expect(dark.r, lessThan(0.2));
    });

    test('+100 contrast: bright pixel gets brighter', () {
      final bright = applyAdjustParams(
          const RgbColor(0.8, 0.8, 0.8), const AdjustParams(contrast: 100));
      expect(bright.r, greaterThan(0.8));
    });

    test('mid-grey (0.5) is unchanged by any contrast value', () {
      for (final c in [-100.0, 0.0, 100.0]) {
        final out = applyAdjustParams(_mid, AdjustParams(contrast: c));
        expect(out.r, closeTo(0.5, 0.02));
      }
    });

    test('-100 contrast: compresses towards grey (dark lifts)', () {
      final out = applyAdjustParams(
          const RgbColor(0.1, 0.1, 0.1), const AdjustParams(contrast: -100));
      expect(out.r, greaterThan(0.1));
    });
  });

  // ── applyAdjustParams: saturation ─────────────────────────────────────────
  group('applyAdjustParams — saturation', () {
    test('+100 increases colour distance from grey', () {
      const c = RgbColor(0.6, 0.3, 0.2);
      final out = applyAdjustParams(c, const AdjustParams(saturation: 100));
      final greyIn = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
      final greyOut = 0.2126 * out.r + 0.7152 * out.g + 0.0722 * out.b;
      final distIn =
          (c.r - greyIn).abs() + (c.g - greyIn).abs() + (c.b - greyIn).abs();
      final distOut = (out.r - greyOut).abs() +
          (out.g - greyOut).abs() +
          (out.b - greyOut).abs();
      expect(distOut, greaterThan(distIn));
    });

    test('-100 desaturates to grey', () {
      const c = RgbColor(0.8, 0.2, 0.1);
      final out = applyAdjustParams(c, const AdjustParams(saturation: -100));
      expect((out.r - out.g).abs(), lessThan(0.05));
      expect((out.g - out.b).abs(), lessThan(0.05));
    });

    test('neutral grey stays grey under any saturation', () {
      for (final s in [-100.0, 0.0, 100.0]) {
        final out = applyAdjustParams(_mid, AdjustParams(saturation: s));
        expect((out.r - out.g).abs(), lessThan(0.01));
        expect((out.g - out.b).abs(), lessThan(0.01));
      }
    });
  });

  // ── applyAdjustParams: temperature / tint ─────────────────────────────────
  group('applyAdjustParams — temperature & tint', () {
    test('positive temperature shifts R up and B down', () {
      final out = applyAdjustParams(_mid, const AdjustParams(temperature: 50));
      expect(out.r, greaterThan(_mid.r));
      expect(out.b, lessThan(_mid.b));
    });

    test('negative temperature shifts R down and B up', () {
      final out = applyAdjustParams(_mid, const AdjustParams(temperature: -50));
      expect(out.r, lessThan(_mid.r));
      expect(out.b, greaterThan(_mid.b));
    });

    test('positive tint shifts G up', () {
      final out = applyAdjustParams(_mid, const AdjustParams(tint: 50));
      expect(out.g, greaterThan(_mid.g));
    });
  });

  // ── applyAdjustParams: highlights / shadows ────────────────────────────────
  group('applyAdjustParams — highlights & shadows', () {
    test('+100 highlights brightens bright pixels', () {
      const bright = RgbColor(0.9, 0.9, 0.9);
      final out =
          applyAdjustParams(bright, const AdjustParams(highlights: 100));
      expect(out.r, greaterThan(bright.r));
    });

    test('+100 highlights has minimal effect on dark pixels', () {
      const dark = RgbColor(0.1, 0.1, 0.1);
      final out = applyAdjustParams(dark, const AdjustParams(highlights: 100));
      expect((out.r - dark.r).abs(), lessThan(0.05));
    });

    test('+100 shadows brightens dark pixels', () {
      const dark = RgbColor(0.1, 0.1, 0.1);
      final out = applyAdjustParams(dark, const AdjustParams(shadows: 100));
      expect(out.r, greaterThan(dark.r));
    });

    test('+100 shadows has minimal effect on bright pixels', () {
      const bright = RgbColor(0.9, 0.9, 0.9);
      final out = applyAdjustParams(bright, const AdjustParams(shadows: 100));
      expect((out.r - bright.r).abs(), lessThan(0.05));
    });
  });

  // ── applyAdjustParams: B&W ──────────────────────────────────────────────────
  group('applyAdjustParams — B&W mode', () {
    test('bnwEnabled=true collapses RGB to equal channels', () {
      const c = RgbColor(0.8, 0.3, 0.1);
      final out = applyAdjustParams(c, const AdjustParams(bnwEnabled: true));
      expect((out.r - out.g).abs(), lessThan(0.001));
      expect((out.g - out.b).abs(), lessThan(0.001));
    });

    test('positive bnwRed brightens red-dominant pixels in B&W', () {
      const red = RgbColor(1.0, 0.1, 0.1);
      final without =
          applyAdjustParams(red, const AdjustParams(bnwEnabled: true));
      final withRed = applyAdjustParams(
          red, const AdjustParams(bnwEnabled: true, bnwRed: 100));
      expect(withRed.r, greaterThan(without.r));
    });

    test('negative bnwBlue darkens blue-dominant pixels in B&W', () {
      const blue = RgbColor(0.1, 0.1, 1.0);
      final without =
          applyAdjustParams(blue, const AdjustParams(bnwEnabled: true));
      final withBlue = applyAdjustParams(
          blue, const AdjustParams(bnwEnabled: true, bnwBlue: -100));
      expect(withBlue.r, lessThan(without.r));
    });
  });

  // ── applyAdjustParams: tonal contrast ─────────────────────────────────────
  group('applyAdjustParams — tonal contrast', () {
    test('+tonalShadows brightens dark pixel', () {
      const dark = RgbColor(0.15, 0.15, 0.15);
      final out = applyAdjustParams(dark, const AdjustParams(tonalShadows: 80));
      expect(out.r, greaterThan(dark.r));
    });

    test('+tonalHighlights brightens bright pixel', () {
      const bright = RgbColor(0.85, 0.85, 0.85);
      final out =
          applyAdjustParams(bright, const AdjustParams(tonalHighlights: 80));
      expect(out.r, greaterThan(bright.r));
    });

    test('zero tonal contrast leaves midtone unchanged', () {
      final out = applyAdjustParams(
          _mid,
          const AdjustParams(
            tonalShadows: 0,
            tonalMidtones: 0,
            tonalHighlights: 0,
          ));
      expect(out.r, closeTo(0.5, 0.002));
    });

    test('output is always in [0,1]', () {
      final extremes = [
        const AdjustParams(
            tonalShadows: 100, tonalMidtones: 100, tonalHighlights: 100),
        const AdjustParams(
            tonalShadows: -100, tonalMidtones: -100, tonalHighlights: -100),
      ];
      const c = RgbColor(0.5, 0.5, 0.5);
      for (final p in extremes) {
        final out = applyAdjustParams(c, p);
        expect(out.r, inInclusiveRange(0.0, 1.0));
        expect(out.g, inInclusiveRange(0.0, 1.0));
        expect(out.b, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  // ── applyAdjustParams: curves ─────────────────────────────────────────────
  group('applyAdjustParams — curves', () {
    test('linear luminance curve has no effect', () {
      final out = applyAdjustParams(
          const RgbColor(0.4, 0.6, 0.3),
          AdjustParams(
            luminanceCurve: CurveData.linear(CurveChannel.luminance),
          ));
      final baseline =
          applyAdjustParams(const RgbColor(0.4, 0.6, 0.3), AdjustParams.zero);
      expect(out.r, closeTo(baseline.r, 0.005));
    });

    test('brighten RGB curve raises output', () {
      const c = RgbColor(0.4, 0.4, 0.4);
      final out = applyAdjustParams(
          c,
          const AdjustParams(
            rgbCurve: CurveData(
              channel: CurveChannel.rgb,
              points: [
                CurvePoint(0, 0),
                CurvePoint(0.5, 0.7),
                CurvePoint(1, 1),
              ],
            ),
          ));
      expect(out.r, greaterThan(c.r));
      expect(out.g, greaterThan(c.g));
      expect(out.b, greaterThan(c.b));
    });
  });

  // ── applyPipeline ──────────────────────────────────────────────────────────
  group('applyPipeline', () {
    test('null lutBytes: identity (zero params)', () {
      const c = RgbColor(0.3, 0.6, 0.9);
      final out = applyPipeline(
          original: c,
          params: AdjustParams.zero,
          lutBytes: null,
          intensity: 1.0);
      expect(out.r, closeTo(c.r, 0.002));
      expect(out.g, closeTo(c.g, 0.002));
      expect(out.b, closeTo(c.b, 0.002));
    });

    test('identity LUT at intensity=0: returns original', () {
      const c = RgbColor(0.4, 0.5, 0.6);
      final out = applyPipeline(
          original: c,
          params: AdjustParams.zero,
          lutBytes: _identityLut(),
          intensity: 0.0);
      expect(out.r, closeTo(c.r, 0.002));
      expect(out.g, closeTo(c.g, 0.002));
      expect(out.b, closeTo(c.b, 0.002));
    });

    test('identity LUT at intensity=1: returns original', () {
      const c = RgbColor(0.2, 0.7, 0.4);
      final out = applyPipeline(
          original: c,
          params: AdjustParams.zero,
          lutBytes: _identityLut(),
          intensity: 1.0);
      expect(out.r, closeTo(c.r, 0.01));
      expect(out.g, closeTo(c.g, 0.01));
      expect(out.b, closeTo(c.b, 0.01));
    });

    test('empty lutBytes treated as no LUT', () {
      const c = RgbColor(0.3, 0.3, 0.3);
      final out = applyPipeline(
          original: c,
          params: AdjustParams.zero,
          lutBytes: Uint8List(0),
          intensity: 1.0);
      expect(out.r, closeTo(c.r, 0.002));
    });

    test('corrupt lutBytes treated as no LUT', () {
      const c = RgbColor(0.3, 0.6, 0.9);
      final out = applyPipeline(
        original: c,
        params: AdjustParams.zero,
        lutBytes: Uint8List.fromList([0, 1, 2, 3]),
        intensity: 1.0,
      );
      expect(out.r, closeTo(c.r, 0.002));
      expect(out.g, closeTo(c.g, 0.002));
      expect(out.b, closeTo(c.b, 0.002));
    });
  });

  // ── applyImagePipeline: image-level effects gate ───────────────────────────
  group('applyImagePipeline — image-level effects', () {
    img.Image makeGrey(int size) {
      final im = img.Image(width: size, height: size);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          im.setPixelRgb(x, y, 128, 128, 128);
        }
      }
      return im;
    }

    test('zero params, no LUT: pixels unchanged', () {
      final src = makeGrey(4);
      final out = applyImagePipeline(
          image: src, params: AdjustParams.zero, lutBytes: null, intensity: 1);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final px = out.getPixel(x, y);
          expect((px.r - 128).abs(), lessThanOrEqualTo(2));
        }
      }
    });

    test('corrupt LUT falls back to editable params-only output', () {
      final src = makeGrey(4);
      final out = applyImagePipeline(
        image: src,
        params: const AdjustParams(exposure: 0.2),
        lutBytes: Uint8List.fromList([0, 1, 2, 3]),
        intensity: 1,
      );
      final px = out.getPixel(1, 1);
      expect(px.r, greaterThan(128));
    });

    test('vignette=100 darkens corners more than centre', () {
      const size = 8;
      final src = img.Image(width: size, height: size);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          src.setPixelRgb(x, y, 200, 200, 200);
        }
      }
      final out = applyImagePipeline(
          image: src,
          params: const AdjustParams(vignette: 100),
          lutBytes: null,
          intensity: 1);

      final centre = out.getPixel(size ~/ 2, size ~/ 2);
      final corner = out.getPixel(0, 0);
      expect(centre.r, greaterThan(corner.r));
    });

    test('sharpen=50 does not change image dimensions', () {
      final src = makeGrey(4);
      final out = applyImagePipeline(
          image: src,
          params: const AdjustParams(sharpen: 50),
          lutBytes: null,
          intensity: 1);
      expect(out.width, equals(src.width));
      expect(out.height, equals(src.height));
    });

    test('clarity=50 does not change image dimensions', () {
      // clarity uses radius=7 blur; need image larger than blur kernel
      final src = makeGrey(20);
      final out = applyImagePipeline(
          image: src,
          params: const AdjustParams(clarity: 50),
          lutBytes: null,
          intensity: 1);
      expect(out.width, equals(src.width));
      expect(out.height, equals(src.height));
    });

    test('structure=50 does not change image dimensions', () {
      final src = makeGrey(4);
      final out = applyImagePipeline(
          image: src,
          params: const AdjustParams(structure: 50),
          lutBytes: null,
          intensity: 1);
      expect(out.width, equals(src.width));
      expect(out.height, equals(src.height));
    });
  });

  // ── loadLutBytes ────────────────────────────────────────────────────────────
  group('loadLutBytes', () {
    test('null path returns null', () async {
      final result = await loadLutBytes(null);
      expect(result, isNull);
    });

    test('empty string returns null', () async {
      final result = await loadLutBytes('');
      expect(result, isNull);
    });

    test('non-existent file path returns null', () async {
      final result = await loadLutBytes('/tmp/__nonexistent_lut__.bin');
      expect(result, isNull);
    });
  });
}
