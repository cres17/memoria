// Whitebox tests — color_utils.dart
// Coverage: rgbToLab, labToRgb (round-trip, primaries, boundary values)

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/color_utils.dart';

void main() {
  // ── helpers ─────────────────────────────────────────────────────────────────
  void expectLabClose(LabColor actual, double l, double a, double b,
      {double tol = 0.5, String? reason}) {
    expect((actual.l - l).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} L: expected $l got ${actual.l}');
    expect((actual.a - a).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} a: expected $a got ${actual.a}');
    expect((actual.b - b).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} b: expected $b got ${actual.b}');
  }

  void expectRgbClose(RgbColor actual, double r, double g, double b,
      {double tol = 0.01, String? reason}) {
    expect((actual.r - r).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} r: expected $r got ${actual.r}');
    expect((actual.g - g).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} g: expected $g got ${actual.g}');
    expect((actual.b - b).abs(), lessThanOrEqualTo(tol),
        reason: '${reason ?? ''} b: expected $b got ${actual.b}');
  }

  // ── rgbToLab ────────────────────────────────────────────────────────────────
  group('rgbToLab', () {
    test('black (0,0,0) → Lab(0,0,0)', () {
      final lab = rgbToLab(const RgbColor(0, 0, 0));
      expectLabClose(lab, 0, 0, 0, reason: 'black');
    });

    test('white (1,1,1) → Lab(100,0,0)', () {
      final lab = rgbToLab(const RgbColor(1, 1, 1));
      expectLabClose(lab, 100, 0, 0, reason: 'white');
    });

    test('mid grey (0.5,0.5,0.5) → neutral L≈53, a≈0, b≈0', () {
      final lab = rgbToLab(const RgbColor(0.5, 0.5, 0.5));
      expect(lab.l, greaterThan(50));
      expect(lab.l, lessThan(56));
      expect(lab.a.abs(), lessThan(1.0));
      expect(lab.b.abs(), lessThan(1.0));
    });

    test('sRGB red (1,0,0) → L≈53, a≈80, b≈67', () {
      final lab = rgbToLab(const RgbColor(1, 0, 0));
      expectLabClose(lab, 53.2, 80.1, 67.2, tol: 1.5, reason: 'red');
    });

    test('sRGB green (0,1,0) → L≈88, a≈-86, b≈83', () {
      final lab = rgbToLab(const RgbColor(0, 1, 0));
      expectLabClose(lab, 87.7, -86.2, 83.2, tol: 1.5, reason: 'green');
    });

    test('sRGB blue (0,0,1) → L≈32, a≈79, b≈-107', () {
      final lab = rgbToLab(const RgbColor(0, 0, 1));
      expectLabClose(lab, 32.3, 79.2, -107.9, tol: 1.5, reason: 'blue');
    });

    test('L value is non-negative for all channels', () {
      final colors = [
        const RgbColor(0, 0, 0),
        const RgbColor(0.1, 0.1, 0.1),
        const RgbColor(0.5, 0, 0),
        const RgbColor(0, 0.5, 0),
        const RgbColor(0, 0, 0.5),
      ];
      for (final c in colors) {
        expect(rgbToLab(c).l, greaterThanOrEqualTo(0));
      }
    });
  });

  // ── labToRgb ────────────────────────────────────────────────────────────────
  group('labToRgb', () {
    test('Lab(0,0,0) → RGB(0,0,0)', () {
      final rgb = labToRgb(const LabColor(0, 0, 0));
      expectRgbClose(rgb, 0, 0, 0, reason: 'black');
    });

    test('Lab(100,0,0) → RGB(1,1,1)', () {
      final rgb = labToRgb(const LabColor(100, 0, 0));
      expectRgbClose(rgb, 1, 1, 1, reason: 'white');
    });

    test('result is always clamped to [0,1]', () {
      // Extreme a/b values that would exceed sRGB gamut
      final extreme = labToRgb(const LabColor(50, 128, 128));
      expect(extreme.r, inInclusiveRange(0.0, 1.0));
      expect(extreme.g, inInclusiveRange(0.0, 1.0));
      expect(extreme.b, inInclusiveRange(0.0, 1.0));
    });
  });

  // ── round-trip ───────────────────────────────────────────────────────────────
  group('rgbToLab → labToRgb round-trip', () {
    const testColors = [
      RgbColor(0, 0, 0),
      RgbColor(1, 1, 1),
      RgbColor(0.5, 0.5, 0.5),
      RgbColor(1, 0, 0),
      RgbColor(0, 1, 0),
      RgbColor(0, 0, 1),
      RgbColor(0.2, 0.5, 0.8),
      RgbColor(0.9, 0.1, 0.4),
    ];

    for (final c in testColors) {
      test('round-trip (${c.r.toStringAsFixed(1)}, '
          '${c.g.toStringAsFixed(1)}, '
          '${c.b.toStringAsFixed(1)})', () {
        final back = labToRgb(rgbToLab(c));
        expectRgbClose(back, c.r, c.g, c.b, tol: 0.002,
            reason: 'round-trip');
      });
    }
  });

  // ── RgbColor.clamp01 ────────────────────────────────────────────────────────
  group('RgbColor.clamp01', () {
    test('values > 1 clamped to 1', () {
      final c = const RgbColor(1.5, 2.0, -0.1).clamp01();
      expect(c.r, equals(1.0));
      expect(c.g, equals(1.0));
      expect(c.b, equals(0.0));
    });

    test('values already in range unchanged', () {
      final c = const RgbColor(0.3, 0.5, 0.7).clamp01();
      expect(c.r, closeTo(0.3, 1e-12));
      expect(c.g, closeTo(0.5, 1e-12));
      expect(c.b, closeTo(0.7, 1e-12));
    });
  });

  // ── monotonicity: brighter sRGB → higher L ──────────────────────────────────
  test('neutral ramp produces monotonically increasing L', () {
    double prevL = -1;
    for (int i = 0; i <= 10; i++) {
      final v = i / 10.0;
      final l = rgbToLab(RgbColor(v, v, v)).l;
      expect(l, greaterThanOrEqualTo(prevL - 0.01));
      prevL = l;
    }
  });

  // ── distance consistency ─────────────────────────────────────────────────────
  test('ΔE between identical colors is 0', () {
    final lab = rgbToLab(const RgbColor(0.4, 0.6, 0.8));
    final dE = math.sqrt(
      (lab.l - lab.l) * (lab.l - lab.l) +
      (lab.a - lab.a) * (lab.a - lab.a) +
      (lab.b - lab.b) * (lab.b - lab.b),
    );
    expect(dE, closeTo(0.0, 1e-12));
  });
}
