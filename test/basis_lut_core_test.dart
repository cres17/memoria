import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/basis_lut_core.dart';
import 'package:memoria/engine/color_utils.dart';
import 'package:memoria/engine/custom_lut_core.dart';

Float32List _identityValues() {
  final values = Float32List(customLutDim * customLutDim * customLutDim * 3);
  final max = (customLutDim - 1).toDouble();
  var index = 0;
  for (var b = 0; b < customLutDim; b++) {
    for (var g = 0; g < customLutDim; g++) {
      for (var r = 0; r < customLutDim; r++) {
        values[index++] = r / max;
        values[index++] = g / max;
        values[index++] = b / max;
      }
    }
  }
  return values;
}

void main() {
  test('zero basis coefficients preserve the mean LUT', () {
    final result = synthesizeBasisLut(
      mean: _identityValues(),
      residualBases: [
        Float32List(customLutDim * customLutDim * customLutDim * 3)
      ],
      coefficients: const [0.0],
    );
    final output = applyCustomLut(result.bytes, const RgbColor(0.2, 0.6, 0.9));

    expect(result.fallbackReason, isNull);
    expect(result.maxPreClampExcursion, 0.0);
    expect(output.r, closeTo(0.2, 0.01));
    expect(output.g, closeTo(0.6, 0.01));
    expect(output.b, closeTo(0.9, 0.01));
  });

  test('invalid model coefficient fails closed to identity', () {
    final result = synthesizeBasisLut(
      mean: _identityValues(),
      residualBases: const [],
      coefficients: const [double.nan],
    );
    final output = applyCustomLut(result.bytes, const RgbColor(0.3, 0.5, 0.7));

    expect(result.fallbackReason, 'basis_lut_invalid_input');
    expect(output.r, closeTo(0.3, 0.01));
    expect(output.g, closeTo(0.5, 0.01));
    expect(output.b, closeTo(0.7, 0.01));
  });

  test('basis reconstruction always passes the common safety gate', () {
    final residual =
        Float32List(customLutDim * customLutDim * customLutDim * 3);
    for (var i = 0; i < residual.length; i += 3) {
      residual[i] = 0.7;
      residual[i + 1] = -0.5;
      residual[i + 2] = 0.3;
    }
    final result = synthesizeAndConstrainBasisLut(
      mean: _identityValues(),
      residualBases: [residual],
      coefficients: const [1.0],
    );

    expect(result.constrained.report.isSafe, isTrue);
    expect(result.constrained.appliedStrength, lessThanOrEqualTo(1.0));
  });
}
