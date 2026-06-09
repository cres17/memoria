import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/crop_ratio_preset.dart';
import 'package:memoria/domain/models/curve_data.dart';
import 'package:memoria/domain/models/edit_operation.dart';
import 'package:memoria/domain/models/edit_session.dart';
import 'package:memoria/engine/blend_modes.dart' as bm;
import 'package:memoria/engine/edit_operation_player.dart';
import 'package:memoria/engine/portrait_engine.dart';

void main() {
  group('EditOperationPlayer no-op guard', () {
    test('globalAdjust changes pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.globalAdjust,
          params: const AdjustParams(exposure: 0.4, contrast: 10),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('globalAdjust ambiance changes pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.globalAdjust,
          params: const AdjustParams(ambiance: 50),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('filter params change pixels even without LUT bytes', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.filter,
          params: const AdjustParams(temperature: 25, saturation: 15),
          intensity: 1,
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('filter with corrupt LUT bytes falls back without throwing', () {
      final original = _sampleImage();
      final session = EditSession.forImage('memory://corrupt-lut').pushOp(
        _op(
          EditToolType.filter,
          params: const AdjustParams(exposure: 0.2),
          intensity: 1,
        ),
      );

      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(
          original: original,
          session: session,
          lutBytes: Uint8List.fromList([0, 1, 2, 3]),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('curve operation changes pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.curve,
          curves: const {
            CurveChannel.luminance: CurveData(
              channel: CurveChannel.luminance,
              points: [
                CurvePoint(0, 0.04),
                CurvePoint(0.5, 0.62),
                CurvePoint(1, 1),
              ],
            ),
          },
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('crop operation changes geometry', () {
      final original = _wideImage();
      final out = _play(
        original,
        _op(
          EditToolType.crop,
          cropState: const CropState(ratio: CropRatioPreset.r1x1),
        ),
      );

      expect(out.width, out.height);
      expect(out.width, lessThan(original.width));
    });

    test('brush operation changes the painted region', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.brush,
          brushMask: const BrushMaskData(
            localParams: AdjustParams(exposure: 0.8),
            toolName: 'exposure+',
            hardness: 1,
            strokes: [BrushStroke(x: 0.5, y: 0.5, radius: 0.25)],
          ),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
      expect(
        _pixelDelta(original.getPixel(16, 16), out.getPixel(16, 16)),
        greaterThan(8.0),
      );
    });

    test('selective point changes the selected region', () {
      final original = _sampleImage();
      final op = _op(
        EditToolType.selective,
        selectivePoints: const [
          SelectivePoint(
            x: 0.5,
            y: 0.5,
            radius: 0.35,
            localParams: AdjustParams(exposure: 0.8, saturation: 25),
          ),
        ],
      );

      final out = _play(original, op);

      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
      expect(
        _pixelDelta(original.getPixel(16, 16), out.getPixel(16, 16)),
        greaterThan(8.0),
      );
    });

    test('heal stroke replaces masked pixels with surrounding texture', () {
      final original = _sampleImage();
      final op = _op(
        EditToolType.heal,
        healStrokes: const [
          HealStroke(
            path: [
              {'x': 0.5, 'y': 0.5},
            ],
            radius: 0.12,
          ),
        ],
      );

      final out = _play(original, op);

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
      expect(
        _pixelDelta(original.getPixel(16, 16), out.getPixel(16, 16)),
        greaterThan(5.0),
      );
    });

    test('rawDevelop noise reduction is wired into playback', () {
      final original = _noisyImage();
      final op = _op(
        EditToolType.rawDevelop,
        params: const AdjustParams(luminanceNR: 80, exposure: 0.05),
      );

      final out = _play(original, op);

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
    });

    test('portrait operation changes face-masked pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.portrait,
          portrait: const PortraitParams(
            smooth: 35,
            spotlight: 30,
            skinTone: SkinTone.medium,
            skinToneStrength: 30,
          ),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
    });

    test('portrait head pose changes only the face-masked region', () {
      final original = _wideImage();
      final mask = _centerMask(original.width, original.height);
      final session = EditSession.forImage('memory://head-pose').pushOp(
        _op(
          EditToolType.portrait,
          portrait: const PortraitParams(headYaw: 100, headPitch: -80),
        ),
      );

      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(
          original: original,
          session: session,
          segmentMask: mask,
        ),
      );

      expect(
        _pixelDelta(original.getPixel(20, 12), out.getPixel(20, 12)),
        greaterThan(0.5),
      );
      expect(
        _pixelDelta(original.getPixel(1, 1), out.getPixel(1, 1)),
        equals(0),
      );
    });

    test('creative blend operation changes pixels', () {
      final original = _sampleImage();
      final blend = _solidImage(32, 32, 255, 255, 255);
      final session = EditSession.forImage('memory://creative').pushOp(
        _op(
          EditToolType.creative,
          creative: const CreativeParams(
            blendImagePath: 'memory://blend',
            blendMode: bm.BlendMode.lighten,
            blendOpacity: 0.6,
          ),
        ),
      );
      final out = const EditOperationPlayer().play(
        EditOperationPlayerArgs(
          original: original,
          session: session,
          blendImageBytes: img.encodePng(blend),
        ),
      );

      expect(_meanAbsoluteDelta(original, out), greaterThan(0.1));
    });

    test('vignette operation changes corner pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.vignette,
          params: const AdjustParams(vignette: 80),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('glow operation changes highlight pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.glow,
          params: const AdjustParams(glowStrength: 60, glowSaturation: 20),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('drama operation changes step contrast', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.drama,
          params: const AdjustParams(hdrStrength: 75),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('light leak operation adds directional flare', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.lightLeak,
          params: const AdjustParams(
            lightLeakStrength: 75,
            lightLeakAngle: 25,
            lightLeakWarmth: 60,
          ),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(1.0));
    });

    test('halation operation blooms highlights', () {
      final original = _highlightImage();
      final out = _play(
        original,
        _op(
          EditToolType.halation,
          params: const AdjustParams(
            halationStrength: 85,
            halationThreshold: 55,
            halationWarmth: 80,
          ),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
      expect(
        _pixelDelta(original.getPixel(15, 15), out.getPixel(15, 15)),
        greaterThan(0.5),
      );
    });

    test('grainOverlay operation changes pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.grainOverlay,
          params: const AdjustParams(
            grainStrength: 60,
            grainSize: 1.5,
            grainSeed: 42,
          ),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
    });

    test('splitTone operation changes pixels', () {
      final original = _sampleImage();
      final out = _play(
        original,
        _op(
          EditToolType.splitTone,
          params: const AdjustParams(
            splitShadowHue: 210,
            splitShadowSat: 40,
            splitHighHue: 45,
            splitHighSat: 40,
          ),
        ),
      );
      expect(_meanAbsoluteDelta(original, out), greaterThan(0.5));
    });
  });
}

img.Image _play(img.Image original, EditOperation op) {
  final session = EditSession.forImage('memory://sample').pushOp(op);
  return const EditOperationPlayer().play(
    EditOperationPlayerArgs(original: original, session: session),
  );
}

EditOperation _op(
  EditToolType tool, {
  AdjustParams? params,
  double? intensity,
  Map<CurveChannel, CurveData>? curves,
  CropState? cropState,
  BrushMaskData? brushMask,
  List<SelectivePoint>? selectivePoints,
  List<HealStroke>? healStrokes,
  PortraitParams? portrait,
  CreativeParams? creative,
}) =>
    EditOperation(
      id: 'op-${tool.name}',
      tool: tool,
      appliedAt: DateTime(2026, 6, 2),
      params: params,
      intensity: intensity,
      curves: curves,
      cropState: cropState,
      brushMask: brushMask,
      selectivePoints: selectivePoints,
      healStrokes: healStrokes,
      portrait: portrait,
      creative: creative,
    );

img.Image _sampleImage() {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 90 + x * 3, 96 + y * 3, 120);
    }
  }
  for (var y = 12; y < 20; y++) {
    for (var x = 12; x < 20; x++) {
      image.setPixelRgb(x, y, 235, 30, 34);
    }
  }
  return image;
}

img.Image _wideImage() {
  final image = img.Image(width: 40, height: 24);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 80 + x * 3, 100 + y * 4, 140);
    }
  }
  return image;
}

img.Image _solidImage(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

img.Image _noisyImage() {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final noise = ((x * 17 + y * 29) % 2) == 0 ? 8 : -8;
      final base = 128 + noise;
      image.setPixelRgb(x, y, base, base + ((x + y) % 9), base - 6);
    }
  }
  return image;
}

Float32List _centerMask(int width, int height) {
  final mask = Float32List(width * height);
  final cx = (width - 1) / 2;
  final cy = (height - 1) / 2;
  final rx = width * 0.32;
  final ry = height * 0.38;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = (x - cx) / rx;
      final dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) {
        mask[y * width + x] = 1;
      }
    }
  }
  return mask;
}

img.Image _highlightImage() {
  final image = img.Image(width: 32, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 42, 46, 54);
    }
  }
  for (var y = 13; y < 19; y++) {
    for (var x = 13; x < 19; x++) {
      image.setPixelRgb(x, y, 250, 242, 220);
    }
  }
  return image;
}

double _meanAbsoluteDelta(img.Image a, img.Image b) {
  var sum = 0.0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      sum += _pixelDelta(a.getPixel(x, y), b.getPixel(x, y));
    }
  }
  return sum / (a.width * a.height);
}

double _pixelDelta(img.Pixel a, img.Pixel b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) / 3.0;
