// Whitebox tests — curve_data.dart
// Coverage: CurveData.isLinear, CurveData.toLut (linear interp, cubic spline,
//   monotonicity, boundary extrapolation), CurvePresets, JSON serialisation

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/models/curve_data.dart';

void main() {
  // ── isLinear ─────────────────────────────────────────────────────────────
  group('CurveData.isLinear', () {
    test('exact (0,0)→(1,1) is linear', () {
      final c = CurveData.linear(CurveChannel.luminance);
      expect(c.isLinear, isTrue);
    });

    test('three-point curve is not linear', () {
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [CurvePoint(0, 0), CurvePoint(0.5, 0.7), CurvePoint(1, 1)],
      );
      expect(c.isLinear, isFalse);
    });

    test('near-linear two-point (within 0.01 tolerance) is treated as linear',
        () {
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [CurvePoint(0.005, 0.005), CurvePoint(0.995, 0.995)],
      );
      expect(c.isLinear, isTrue);
    });

    test('two-point with non-zero endpoints is NOT linear', () {
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [CurvePoint(0.0, 0.1), CurvePoint(1.0, 0.9)],
      );
      expect(c.isLinear, isFalse);
    });
  });

  // ── toLut: boundary / degenerate cases ───────────────────────────────────
  group('CurveData.toLut — degenerate inputs', () {
    test('0 points → identity LUT', () {
      const c = CurveData(channel: CurveChannel.rgb, points: []);
      final lut = c.toLut();
      expect(lut.length, equals(256));
      for (int i = 0; i < 256; i++) {
        expect(lut[i], equals(i));
      }
    });

    test('1 point → constant LUT', () {
      const y = 0.6;
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [CurvePoint(0.5, y)],
      );
      final lut = c.toLut();
      final expected = (y * 255).round().clamp(0, 255);
      for (final v in lut) {
        expect(v, equals(expected));
      }
    });

    test('2 points → linear interpolation', () {
      // Line from (0,0) to (1,1) must equal identity
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [CurvePoint(0, 0), CurvePoint(1, 1)],
      );
      final lut = c.toLut();
      for (int i = 0; i < 256; i++) {
        expect(lut[i], closeTo(i, 1));
      }
    });

    test('2 points: faded (0→0.07, 1→0.93) lifts blacks and compresses whites',
        () {
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [CurvePoint(0, 0.07), CurvePoint(1, 0.93)],
      );
      final lut = c.toLut();
      expect(lut[0], greaterThan(0));
      expect(lut[255], lessThan(255));
      expect(lut[128], closeTo(128, 5));
    });
  });

  // ── toLut: cubic spline (≥3 points) ──────────────────────────────────────
  group('CurveData.toLut — cubic spline', () {
    test('endpoints match exactly', () {
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.7),
          CurvePoint(1, 1),
        ],
      );
      final lut = c.toLut();
      expect(lut[0], equals(0));
      expect(lut[255], equals(255));
    });

    test('midpoint is raised for brighten-like curve', () {
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.65),
          CurvePoint(1, 1),
        ],
      );
      final lut = c.toLut();
      expect(lut[128], greaterThan(128));
    });

    test('midpoint is lowered for darken-like curve', () {
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.35),
          CurvePoint(1, 1),
        ],
      );
      final lut = c.toLut();
      expect(lut[128], lessThan(128));
    });

    test('LUT is monotonically non-decreasing for natural S-curve', () {
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.25, 0.2),
          CurvePoint(0.75, 0.8),
          CurvePoint(1, 1),
        ],
      );
      final lut = c.toLut();
      for (int i = 1; i < 256; i++) {
        expect(lut[i], greaterThanOrEqualTo(lut[i - 1]));
      }
    });

    test('LUT values always in [0, 255]', () {
      const c = CurveData(
        channel: CurveChannel.rgb,
        points: [
          CurvePoint(0, 0.0),
          CurvePoint(0.3, 0.15),
          CurvePoint(0.7, 0.85),
          CurvePoint(1, 1),
        ],
      );
      final lut = c.toLut();
      for (final v in lut) {
        expect(v, inInclusiveRange(0, 255));
      }
    });

    test('5-point spline has 256 entries', () {
      const c = CurveData(
        channel: CurveChannel.red,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.25, 0.3),
          CurvePoint(0.5, 0.5),
          CurvePoint(0.75, 0.7),
          CurvePoint(1, 1),
        ],
      );
      expect(c.toLut().length, equals(256));
    });
  });

  // ── JSON round-trip ──────────────────────────────────────────────────────
  group('CurveData JSON serialisation', () {
    test('toJson → fromJson preserves channel and points', () {
      const original = CurveData(
        channel: CurveChannel.red,
        points: [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.6),
          CurvePoint(1, 1),
        ],
      );
      final rt = CurveData.fromJson(original.toJson());
      expect(rt.channel, equals(original.channel));
      expect(rt.points.length, equals(original.points.length));
      for (int i = 0; i < original.points.length; i++) {
        expect(rt.points[i].x, closeTo(original.points[i].x, 1e-10));
        expect(rt.points[i].y, closeTo(original.points[i].y, 1e-10));
      }
    });

    test('toJsonString → fromJsonString round-trip', () {
      const c = CurveData(
        channel: CurveChannel.luminance,
        points: [CurvePoint(0, 0.05), CurvePoint(1, 0.95)],
      );
      final rt = CurveData.fromJsonString(c.toJsonString());
      expect(rt.channel, equals(CurveChannel.luminance));
      expect(rt.points[0].y, closeTo(0.05, 1e-10));
    });

    test('unknown channel name falls back to luminance', () {
      final json = {'channel': '__unknown__', 'points': []};
      final c = CurveData.fromJson(json);
      expect(c.channel, equals(CurveChannel.luminance));
    });
  });

  // ── CurvePresets ─────────────────────────────────────────────────────────
  group('CurvePresets', () {
    for (final name in CurvePresets.presetNames) {
      test('$name generates a valid CurveData', () {
        for (final ch in CurveChannel.values) {
          final c = CurvePresets.fromPresetName(name, ch);
          expect(c.channel, equals(ch));
          expect(c.toLut().length, equals(256));
        }
      });
    }

    test('fromPresetName unknown → neutral (linear)', () {
      final c = CurvePresets.fromPresetName('??bad??', CurveChannel.rgb);
      expect(c.isLinear, isTrue);
    });
  });
}
