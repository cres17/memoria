import 'dart:math' as math;
import 'package:memoria/domain/models/adjust_params.dart';
import 'package:memoria/engine/lut_engine.dart';

void main() {
  final p = AdjustParams.zero;
  double r = 128 / 255.0;
  double g = 128 / 255.0;
  double b = 128 / 255.0;
  
  print('Initial: $r, $g, $b');
  
  // 1. Exposure
  r = r * math.pow(2.0, p.exposure);
  g = g * math.pow(2.0, p.exposure);
  b = b * math.pow(2.0, p.exposure);
  print('Exposure: $r, $g, $b');
  
  // 2. Contrast
  if (p.contrast != 0) {
    final factor = (259.0 * (p.contrast + 255)) / (255.0 * (259 - p.contrast));
    r = factor * (r - 0.5) + 0.5;
    g = factor * (g - 0.5) + 0.5;
    b = factor * (b - 0.5) + 0.5;
    print('Contrast: $r, $g, $b');
  }
  
  // 3. Saturation
  if (p.saturation != 0) {
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final s = 1.0 + p.saturation / 100.0;
    r = lum + (r - lum) * s;
    g = lum + (g - lum) * s;
    b = lum + (b - lum) * s;
    print('Saturation: $r, $g, $b');
  }
  
  // 4. Hsl
  if (p.hasHsl) {
    print('hasHsl is true');
  } else {
    print('hasHsl is false');
  }
  
  // 5. Tonal
  if (p.tonalShadows != 0 || p.tonalMidtones != 0 || p.tonalHighlights != 0) {
    print('hasTonal is true');
  } else {
    print('hasTonal is false');
  }
  
  // 6. Curves
  if (p.hasCurves) {
    print('hasCurves is true');
  } else {
    print('hasCurves is false');
  }
  
  // 7. B&W
  if (p.bnwEnabled) {
    print('bnwEnabled is true');
  } else {
    print('bnwEnabled is false');
  }
  
  // Call the actual function
  final res = applyAdjustParamsFlat(128/255.0, 128/255.0, 128/255.0, p);
  print('applyAdjustParamsFlat: $res');
}
