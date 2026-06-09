import 'dart:math' as math;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────
//  기하 변환 헬퍼 — 4점 호모그래피 기반 원근 keystone 보정
// ─────────────────────────────────────────────────────────

/// 수평(hDeg)/수직(vDeg) 원근 keystone 변환의 역변환을 호모그래피(3x3)로 구현.
/// 각도를 degrees로 받아 target 모서리를 계산하고, 역매핑(Homography)과 bilinear 보간을 적용합니다.
img.Image applyPerspectiveSkewInverse(
    img.Image src, double hDeg, double vDeg) {
  if (hDeg == 0 && vDeg == 0) return src;

  final width = src.width;
  final height = src.height;
  final W = width.toDouble();
  final H = height.toDouble();

  // 각도를 -45~45 범위 내에서 sin 곡선으로 보정계수화 (최대 0.35 배율 변위)
  final kH = math.sin(hDeg * math.pi / 180.0) * 0.35;
  final kV = math.sin(vDeg * math.pi / 180.0) * 0.35;

  // 1. Target corners (Output 상의 4점 위치)
  // T0: Top-Left, T1: Top-Right, T2: Bottom-Right, T3: Bottom-Left
  final t0x = W * 0.5 * kV;
  final t0y = H * 0.5 * kH;

  final t1x = W - W * 0.5 * kV;
  final t1y = -H * 0.5 * kH;

  final t2x = W + W * 0.5 * kV;
  final t2y = H + H * 0.5 * kH;

  final t3x = -W * 0.5 * kV;
  final t3y = H - H * 0.5 * kH;

  final T = [
    _Pt(t0x, t0y), // T0
    _Pt(t1x, t1y), // T1
    _Pt(t2x, t2y), // T2
    _Pt(t3x, t3y), // T3
  ];

  // 2. Source corners (Input 상의 4점 매핑 대상)
  final S = [
    const _Pt(0.0, 0.0),     // S0
    _Pt(W, 0.0),       // S1
    _Pt(W, H),         // S2
    _Pt(0.0, H),       // S3
  ];

  // 3. Homography H가 T -> S 매핑하도록 8x8 선형 방정식 구성
  // A * h = B
  final A = List.generate(8, (_) => List<double>.filled(8, 0.0));
  final B = List<double>.filled(8, 0.0);

  for (var i = 0; i < 4; i++) {
    final x = T[i].x;
    final y = T[i].y;
    final u = S[i].x;
    final v = S[i].y;

    A[2 * i] = [x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u];
    B[2 * i] = u;

    A[2 * i + 1] = [0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v];
    B[2 * i + 1] = v;
  }

  final h = _solveLinearSystem(A, B);
  if (h == null) {
    // 방정식 해가 없을 경우 단순 전단(Shear) 폴백 적용
    return _applyPerspectiveSkewShearFallback(src, hDeg, vDeg);
  }

  final h00 = h[0];
  final h01 = h[1];
  final h02 = h[2];
  final h10 = h[3];
  final h11 = h[4];
  final h12 = h[5];
  final h20 = h[6];
  final h21 = h[7];

  final dst = img.Image(width: width, height: height);

  // 4. 역매핑 및 Bilinear 보간 적용
  for (var y = 0; y < height; y++) {
    final c1 = h21 * y + 1.0;
    final c2 = h01 * y + h02;
    final c3 = h11 * y + h12;
    
    for (var x = 0; x < width; x++) {
      final denom = h20 * x + c1;
      if (denom.abs() < 1e-9) {
        dst.setPixelRgba(x, y, 0, 0, 0, 255);
        continue;
      }

      final sx = (h00 * x + c2) / denom;
      final sy = (h10 * x + c3) / denom;

      if (sx >= 0 && sx < W - 1 && sy >= 0 && sy < H - 1) {
        dst.setPixel(x, y, src.getPixelInterpolate(sx, sy));
      } else {
        dst.setPixelRgba(x, y, 0, 0, 0, 255); // 빈 영역 검은색 채움
      }
    }
  }

  return dst;
}

class _Pt {
  final double x;
  final double y;
  const _Pt(this.x, this.y);
}

/// 8x8 Gaussian Elimination Solver with Partial Pivoting
List<double>? _solveLinearSystem(List<List<double>> A, List<double> B) {
  final n = B.length;
  final M = List.generate(n, (i) => List<double>.generate(n + 1, (j) => j < n ? A[i][j] : B[i]));

  for (var i = 0; i < n; i++) {
    var maxRow = i;
    for (var k = i + 1; k < n; k++) {
      if (M[k][i].abs() > M[maxRow][i].abs()) {
        maxRow = k;
      }
    }

    final temp = M[i];
    M[i] = M[maxRow];
    M[maxRow] = temp;

    if (M[i][i].abs() < 1e-9) {
      return null; // Singular matrix
    }

    for (var k = i + 1; k < n; k++) {
      final factor = M[k][i] / M[i][i];
      for (var j = i; j <= n; j++) {
        M[k][j] -= factor * M[i][j];
      }
    }
  }

  final x = List<double>.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var sum = M[i][n];
    for (var j = i + 1; j < n; j++) {
      sum -= M[i][j] * x[j];
    }
    x[i] = sum / M[i][i];
  }
  return x;
}

/// 전단(Shear) 변환 폴백 (단순 행렬 역변환 방식)
img.Image _applyPerspectiveSkewShearFallback(
    img.Image src, double hDeg, double vDeg) {
  final shX = math.tan(hDeg * math.pi / 180);
  final shY = math.tan(vDeg * math.pi / 180);
  final width = src.width;
  final height = src.height;
  final cx = (width - 1) / 2.0;
  final cy = (height - 1) / 2.0;
  final dst = img.Image(width: width, height: height);
  final denomBase = 1 - shX * shY;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final denom = denomBase.abs() < 0.0001 ? 0.0001 : denomBase;
      final sx = (dx - shY * dy) / denom + cx;
      final sy = (dy - shX * dx) / denom + cy;
      if (sx >= 0 && sx < width - 1 && sy >= 0 && sy < height - 1) {
        dst.setPixel(x, y, src.getPixelInterpolate(sx, sy));
      } else {
        dst.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
  }
  return dst;
}
