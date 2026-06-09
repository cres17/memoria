import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/histogram_engine.dart';

void main() {
  group('computeHistogram', () {
    Uint8List solid(int r, int g, int b, int w, int h) {
      final buf = Uint8List(w * h * 4);
      for (int i = 0; i < w * h; i++) {
        buf[i * 4] = r;
        buf[i * 4 + 1] = g;
        buf[i * 4 + 2] = b;
        buf[i * 4 + 3] = 255;
      }
      return buf;
    }

    test('fully black image → bin[0] == W*H for all channels', () {
      const w = 10, h = 10;
      final bytes = solid(0, 0, 0, w, h);
      final data = computeHistogram(HistogramArgs(bytes, 4));
      expect(data.r[0], w * h);
      expect(data.g[0], w * h);
      expect(data.b[0], w * h);
      expect(data.luminance[0], w * h);
    });

    test('fully white image → bin[255] == W*H', () {
      const w = 8, h = 8;
      final bytes = solid(255, 255, 255, w, h);
      final data = computeHistogram(HistogramArgs(bytes, 4));
      expect(data.r[255], w * h);
      expect(data.g[255], w * h);
      expect(data.b[255], w * h);
      expect(data.luminance[255], w * h);
    });

    test('luminance channel uses correct BT.601 weights (77R+150G+29B)>>8', () {
      // Pure red pixel → lum = (77*255) >> 8 = 76
      final bytes = solid(255, 0, 0, 1, 1);
      final data = computeHistogram(HistogramArgs(bytes, 4));
      const expectedLum = (77 * 255) >> 8; // 76
      expect(data.luminance[expectedLum], 1);
    });

    test('pure green pixel → correct luminance bin', () {
      final bytes = solid(0, 255, 0, 1, 1);
      final data = computeHistogram(HistogramArgs(bytes, 4));
      const expectedLum = (150 * 255) >> 8; // 149
      expect(data.luminance[expectedLum], 1);
    });

    test('peak reflects the highest bin count across all channels', () {
      // 2 pixels: red (255,0,0) and green (0,255,0).
      // Both have b=0, so b[0] = 2 → peak = 2.
      final bytes = Uint8List(2 * 4)
        ..[0] = 255
        ..[1] = 0
        ..[2] = 0
        ..[3] = 255
        ..[4] = 0
        ..[5] = 255
        ..[6] = 0
        ..[7] = 255;
      final data = computeHistogram(HistogramArgs(bytes, 4));
      expect(data.peak, 2);
      expect(data.b[0], 2); // both pixels have blue=0
    });

    test('total pixel count across R histogram equals W*H', () {
      const w = 5, h = 5;
      final bytes = solid(128, 64, 32, w, h);
      final data = computeHistogram(HistogramArgs(bytes, 4));
      final total = data.r.fold<int>(0, (s, v) => s + v);
      expect(total, w * h);
    });

    test('RGB numChannels=3 is processed correctly', () {
      const w = 4, h = 4;
      final bytes = Uint8List(w * h * 3);
      for (int i = 0; i < w * h; i++) {
        bytes[i * 3] = 200;
        bytes[i * 3 + 1] = 100;
        bytes[i * 3 + 2] = 50;
      }
      final data = computeHistogram(HistogramArgs(bytes, 3));
      expect(data.r[200], w * h);
      expect(data.g[100], w * h);
      expect(data.b[50], w * h);
    });

    test('trailing incomplete pixel bytes are ignored safely', () {
      final bytes = Uint8List.fromList([
        10,
        20,
        30,
        255,
        40,
        50,
        60,
      ]);

      final data = computeHistogram(HistogramArgs(bytes, 4));

      expect(data.r[10], 1);
      expect(data.g[20], 1);
      expect(data.b[30], 1);
      expect(data.r[40], 0);
    });

    test('numChannels below RGB is rejected', () {
      expect(
        () => computeHistogram(HistogramArgs(Uint8List(4), 2)),
        throwsArgumentError,
      );
    });
  });
}
