import 'dart:convert';

enum CurveChannel { luminance, rgb, red, green, blue }

class CurvePoint {
  final double x; // 0.0 ~ 1.0 (입력)
  final double y; // 0.0 ~ 1.0 (출력)
  const CurvePoint(this.x, this.y);

  CurvePoint copyWith({double? x, double? y}) =>
      CurvePoint(x ?? this.x, y ?? this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory CurvePoint.fromJson(Map<String, dynamic> j) =>
      CurvePoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

class CurveData {
  final List<CurvePoint> points;
  final CurveChannel channel;

  const CurveData({required this.points, required this.channel});

  static CurveData linear(CurveChannel channel) => CurveData(
        channel: channel,
        points: const [CurvePoint(0.0, 0.0), CurvePoint(1.0, 1.0)],
      );

  bool get isLinear {
    if (points.length != 2) return false;
    return (points[0].x - 0.0).abs() < 0.01 &&
        (points[0].y - 0.0).abs() < 0.01 &&
        (points[1].x - 1.0).abs() < 0.01 &&
        (points[1].y - 1.0).abs() < 0.01;
  }

  /// Cubic Spline 보간으로 256-entry LUT 생성
  List<int> toLut() {
    final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));
    final n = sorted.length;

    if (n == 0) return List.generate(256, (i) => i);
    if (n == 1) {
      return List.filled(256, (sorted[0].y * 255).round().clamp(0, 255));
    }
    if (n == 2) {
      // 선형 보간
      return List.generate(256, (i) {
        final t = i / 255.0;
        final y = sorted[0].y +
            (sorted[1].y - sorted[0].y) *
                ((t - sorted[0].x) / (sorted[1].x - sorted[0].x))
                    .clamp(0.0, 1.0);
        return (y * 255).round().clamp(0, 255);
      });
    }

    // Natural Cubic Spline
    final xs = sorted.map((p) => p.x).toList();
    final ys = sorted.map((p) => p.y).toList();
    final coeffs = _naturalCubicSpline(xs, ys);

    return List.generate(256, (i) {
      final t = i / 255.0;
      final y = _evalSpline(t, xs, ys, coeffs).clamp(0.0, 1.0);
      return (y * 255).round().clamp(0, 255);
    });
  }

  CurveData copyWith({List<CurvePoint>? points, CurveChannel? channel}) =>
      CurveData(
          points: points ?? this.points, channel: channel ?? this.channel);

  Map<String, dynamic> toJson() => {
        'channel': channel.name,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory CurveData.fromJson(Map<String, dynamic> j) => CurveData(
        channel: CurveChannel.values.firstWhere(
          (c) => c.name == j['channel'],
          orElse: () => CurveChannel.luminance,
        ),
        points: (j['points'] as List)
            .map((p) => CurvePoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  String toJsonString() => jsonEncode(toJson());
  factory CurveData.fromJsonString(String s) =>
      CurveData.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ── Natural Cubic Spline 계산 ────────────────────────────

// Thomas algorithm으로 3대각 행렬 풀기
List<double> _naturalCubicSpline(List<double> xs, List<double> ys) {
  final n = xs.length;
  final h = List.generate(n - 1, (i) => xs[i + 1] - xs[i]);
  final alpha = List.generate(n - 2, (i) {
    final idx = i + 1;
    return (3 / h[idx]) * (ys[idx + 1] - ys[idx]) -
        (3 / h[idx - 1]) * (ys[idx] - ys[idx - 1]);
  });

  final l = List.filled(n, 0.0);
  final mu = List.filled(n, 0.0);
  final z = List.filled(n, 0.0);
  l[0] = 1.0;

  for (int i = 1; i < n - 1; i++) {
    l[i] = 2 * (xs[i + 1] - xs[i - 1]) - h[i - 1] * mu[i - 1];
    mu[i] = h[i] / l[i];
    z[i] = (alpha[i - 1] - h[i - 1] * z[i - 1]) / l[i];
  }
  l[n - 1] = 1.0;

  final c = List.filled(n, 0.0);
  for (int j = n - 2; j >= 0; j--) {
    c[j] = z[j] - mu[j] * c[j + 1];
  }
  return c; // c[i] = 각 구간의 2차 계수
}

double _evalSpline(double t, List<double> xs, List<double> ys, List<double> c) {
  final n = xs.length;
  // 구간 탐색
  int seg = n - 2;
  for (int i = 0; i < n - 1; i++) {
    if (t <= xs[i + 1]) {
      seg = i;
      break;
    }
  }
  seg = seg.clamp(0, n - 2);

  final h = xs[seg + 1] - xs[seg];
  final dx = t - xs[seg];
  final a = ys[seg];
  final b = (ys[seg + 1] - ys[seg]) / h - h * (2 * c[seg] + c[seg + 1]) / 3;
  final cc = c[seg];
  final d = (c[seg + 1] - c[seg]) / (3 * h);

  return a + b * dx + cc * dx * dx + d * dx * dx * dx;
}

// ── 프리셋 ────────────────────────────────────────────────

abstract class CurvePresets {
  static CurveData neutral(CurveChannel ch) => CurveData.linear(ch);

  static CurveData brighten(CurveChannel ch) => CurveData(
        channel: ch,
        points: const [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.65),
          CurvePoint(1, 1)
        ],
      );

  static CurveData darken(CurveChannel ch) => CurveData(
        channel: ch,
        points: const [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.35),
          CurvePoint(1, 1)
        ],
      );

  static CurveData faded(CurveChannel ch) => CurveData(
        channel: ch,
        points: const [
          CurvePoint(0, 0.07),
          CurvePoint(0.5, 0.5),
          CurvePoint(1, 0.93)
        ],
      );

  static CurveData softContrast(CurveChannel ch) => CurveData(
        channel: ch,
        points: const [
          CurvePoint(0, 0),
          CurvePoint(0.25, 0.2),
          CurvePoint(0.75, 0.8),
          CurvePoint(1, 1),
        ],
      );

  static CurveData hardContrast(CurveChannel ch) => CurveData(
        channel: ch,
        points: const [
          CurvePoint(0, 0),
          CurvePoint(0.3, 0.15),
          CurvePoint(0.7, 0.85),
          CurvePoint(1, 1),
        ],
      );

  static const presetNames = [
    'Neutral',
    'Brighten',
    'Darken',
    'Faded',
    'Soft Contrast',
    'Hard Contrast'
  ];

  static CurveData fromPresetName(String name, CurveChannel ch) {
    switch (name) {
      case 'Brighten':
        return brighten(ch);
      case 'Darken':
        return darken(ch);
      case 'Faded':
        return faded(ch);
      case 'Soft Contrast':
        return softContrast(ch);
      case 'Hard Contrast':
        return hardContrast(ch);
      default:
        return neutral(ch);
    }
  }
}
