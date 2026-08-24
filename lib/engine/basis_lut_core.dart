import 'dart:typed_data';

import 'custom_lut_core.dart';

/// Result of reconstructing a full LUT from a mean LUT and residual bases.
/// This is deliberately separate from TFLite I/O: model weights are optional,
/// while LUT synthesis and safety behaviour remain deterministic and testable.
class BasisLutSynthesisResult {
  final Uint8List bytes;
  final double maxPreClampExcursion;
  final String? fallbackReason;

  const BasisLutSynthesisResult({
    required this.bytes,
    required this.maxPreClampExcursion,
    this.fallbackReason,
  });
}

class SafeBasisLutResult {
  final BasisLutSynthesisResult synthesis;
  final ConstrainedLutResult constrained;

  const SafeBasisLutResult({
    required this.synthesis,
    required this.constrained,
  });
}

/// Reconstructs `mean + Σ(coefficient × residualBasis)`.
///
/// Each residual basis must be a float32 RGB LUT in the shared R-fastest
/// layout. Invalid coefficients or tensors yield identity instead of a partial
/// or undefined filter. The result must still pass [constrainCustomLut] before
/// persistence or display.
BasisLutSynthesisResult synthesizeBasisLut({
  required Float32List mean,
  required List<Float32List> residualBases,
  required List<double> coefficients,
  int dim = customLutDim,
  double maxAbsCoefficient = 2.0,
}) {
  final expectedLength = dim * dim * dim * 3;
  final invalidInput = mean.length != expectedLength ||
      residualBases.length != coefficients.length ||
      residualBases.any((basis) => basis.length != expectedLength) ||
      !maxAbsCoefficient.isFinite ||
      maxAbsCoefficient <= 0 ||
      coefficients.any((coefficient) =>
          !coefficient.isFinite || coefficient.abs() > maxAbsCoefficient) ||
      mean.any((value) => !value.isFinite) ||
      residualBases.any((basis) => basis.any((value) => !value.isFinite));
  if (invalidInput) {
    return BasisLutSynthesisResult(
      bytes: buildIdentityCustomLut(dim: dim),
      maxPreClampExcursion: double.infinity,
      fallbackReason: 'basis_lut_invalid_input',
    );
  }

  final values = Uint16List(expectedLength);
  var maxPreClampExcursion = 0.0;
  for (var i = 0; i < expectedLength; i++) {
    var value = mean[i];
    for (var basisIndex = 0; basisIndex < residualBases.length; basisIndex++) {
      value += residualBases[basisIndex][i] * coefficients[basisIndex];
    }
    if (value < 0.0) {
      maxPreClampExcursion =
          maxPreClampExcursion > -value ? maxPreClampExcursion : -value;
    } else if (value > 1.0) {
      final excursion = value - 1.0;
      maxPreClampExcursion =
          maxPreClampExcursion > excursion ? maxPreClampExcursion : excursion;
    }
    values[i] = floatToHalf(value);
  }
  return BasisLutSynthesisResult(
    bytes: values.buffer.asUint8List(),
    maxPreClampExcursion: maxPreClampExcursion,
  );
}

/// Product-facing helper. A learned basis model must use this function before
/// its output can be persisted or applied, so it receives the same safety gate
/// as the algorithmic and direct-neural generators.
SafeBasisLutResult synthesizeAndConstrainBasisLut({
  required Float32List mean,
  required List<Float32List> residualBases,
  required List<double> coefficients,
  int dim = customLutDim,
  double maxAbsCoefficient = 2.0,
}) {
  final synthesis = synthesizeBasisLut(
    mean: mean,
    residualBases: residualBases,
    coefficients: coefficients,
    dim: dim,
    maxAbsCoefficient: maxAbsCoefficient,
  );
  if (dim != customLutDim) {
    throw ArgumentError.value(
      dim,
      'dim',
      'safe basis synthesis requires the persisted $customLutDim³ LUT format',
    );
  }
  return SafeBasisLutResult(
    synthesis: synthesis,
    constrained: constrainCustomLut(synthesis.bytes),
  );
}
