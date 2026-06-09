import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/domain/models/filter_preset.dart';
import 'package:memoria/engine/custom_lut_core.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  test('built-in preset metadata points to valid filter resources', () {
    final presets = BuiltinPresets.all;
    final ids = presets.map((p) => p.id).toList();

    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate preset ids');
    expect(BuiltinPresets.ids, ids, reason: 'ids order must match all presets');

    for (final preset in presets) {
      if (preset.lutPath.isNotEmpty) {
        final lut = File(preset.lutPath);
        expect(lut.existsSync(), isTrue, reason: preset.lutPath);
        expect(lut.lengthSync(),
            customLutDim * customLutDim * customLutDim * 3 * 2,
            reason: '${preset.id} LUT must be 65^3 RGB float16');
      }

      if (preset.thumbnailPath.isNotEmpty &&
          preset.thumbnailPath.startsWith('assets/')) {
        expect(File(preset.thumbnailPath).existsSync(), isTrue,
            reason: '${preset.id} thumbnail is referenced but missing');
      }
    }
  });

  test('zero-adjust pipeline preserves pixels without a LUT', () {
    final source = img.Image(width: 3, height: 2);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, 40 + x * 50, 70 + y * 60, 120 + x * 20);
      }
    }

    final out = applyImagePipeline(
      image: source,
      params: AdjustParams.zero,
      lutBytes: null,
      intensity: 1,
    );

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final a = source.getPixel(x, y);
        final b = out.getPixel(x, y);
        expect([b.r, b.g, b.b], [a.r, a.g, a.b], reason: 'pixel $x,$y');
      }
    }
  });

  test('identity LUT with full intensity preserves pixels', () {
    final source = img.Image(width: 2, height: 2)
      ..setPixelRgb(0, 0, 0, 0, 0)
      ..setPixelRgb(1, 0, 255, 0, 0)
      ..setPixelRgb(0, 1, 0, 255, 0)
      ..setPixelRgb(1, 1, 0, 0, 255);

    final out = applyImagePipeline(
      image: source,
      params: AdjustParams.zero,
      lutBytes: _identityLutBytes(),
      intensity: 1,
    );

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final a = source.getPixel(x, y);
        final b = out.getPixel(x, y);
        expect((b.r - a.r).abs(), lessThanOrEqualTo(1), reason: 'r $x,$y');
        expect((b.g - a.g).abs(), lessThanOrEqualTo(1), reason: 'g $x,$y');
        expect((b.b - a.b).abs(), lessThanOrEqualTo(1), reason: 'b $x,$y');
      }
    }
  });

  test('custom LUT preserves RGB channel order without inversion', () {
    final source = img.Image(width: 3, height: 1)
      ..setPixelRgb(0, 0, 255, 0, 0)
      ..setPixelRgb(1, 0, 0, 255, 0)
      ..setPixelRgb(2, 0, 0, 0, 255);

    final out = applyImagePipeline(
      image: source,
      params: AdjustParams.zero,
      lutBytes: _identityLutBytes(),
      intensity: 1,
    );

    final red = out.getPixel(0, 0);
    final green = out.getPixel(1, 0);
    final blue = out.getPixel(2, 0);
    expect(red.r, greaterThan(250));
    expect(red.g, lessThan(3));
    expect(red.b, lessThan(3));
    expect(green.r, lessThan(3));
    expect(green.g, greaterThan(250));
    expect(green.b, lessThan(3));
    expect(blue.r, lessThan(3));
    expect(blue.g, lessThan(3));
    expect(blue.b, greaterThan(250));
  });

  test('params-only filter at zero intensity preserves pixels', () {
    final source = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 60, 90, 120)
      ..setPixelRgb(1, 0, 180, 150, 100);

    final out = applyImagePipeline(
      image: source,
      params: const AdjustParams(
        exposure: 60,
        contrast: 45,
        saturation: -70,
        vignette: 100,
      ),
      lutBytes: null,
      intensity: 0,
    );

    for (var x = 0; x < source.width; x++) {
      final a = source.getPixel(x, 0);
      final b = out.getPixel(x, 0);
      expect([b.r, b.g, b.b], [a.r, a.g, a.b], reason: 'pixel $x');
    }
  });

  test('params-only filter at half intensity blends between source and full',
      () {
    final source = img.Image(width: 1, height: 1)
      ..setPixelRgb(0, 0, 80, 90, 100);
    const params = AdjustParams(exposure: 80, saturation: 40);

    final full = applyImagePipeline(
      image: source,
      params: params,
      lutBytes: null,
      intensity: 1,
    );
    final half = applyImagePipeline(
      image: source,
      params: params,
      lutBytes: null,
      intensity: 0.5,
    );

    final srcPx = source.getPixel(0, 0);
    final fullPx = full.getPixel(0, 0);
    final halfPx = half.getPixel(0, 0);
    expect(halfPx.r, closeTo((srcPx.r + fullPx.r) / 2, 1));
    expect(halfPx.g, closeTo((srcPx.g + fullPx.g) / 2, 1));
    expect(halfPx.b, closeTo((srcPx.b + fullPx.b) / 2, 1));
  });
}

Uint8List _identityLutBytes() {
  final values = Uint16List(customLutDim * customLutDim * customLutDim * 3);
  final max = (customLutDim - 1).toDouble();
  var i = 0;
  for (var b = 0; b < customLutDim; b++) {
    for (var g = 0; g < customLutDim; g++) {
      for (var r = 0; r < customLutDim; r++) {
        values[i++] = floatToHalf(r / max);
        values[i++] = floatToHalf(g / max);
        values[i++] = floatToHalf(b / max);
      }
    }
  }
  return values.buffer.asUint8List();
}
