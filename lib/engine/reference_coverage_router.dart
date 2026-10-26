import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const double colorV3ReferenceCoverageThreshold = 0.03;

class LowReferenceCoverageException implements Exception {
  final double fraction;

  const LowReferenceCoverageException(this.fraction);

  @override
  String toString() =>
      'Reference coverage is below the supported color-transfer threshold.';
}

class ReferenceCoverageResult {
  final double fraction;

  const ReferenceCoverageResult(this.fraction);

  bool get belowCandidateThreshold =>
      fraction < colorV3ReferenceCoverageThreshold;
}

ReferenceCoverageResult analyzeReferenceCoverage(String imagePath) {
  const hueBins = 24;
  const saturationBins = 4;
  const valueBins = 3;
  const minSaturation = 0.05;
  const minValue = 0.03;
  const minCellPixels = 32;
  const cubeDim = 17;

  final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
  if (decoded == null) {
    throw StateError('Could not decode the reference image.');
  }
  final image = img.bakeOrientation(decoded);
  final chromaticCounts = List<int>.filled(
    hueBins * saturationBins * valueBins,
    0,
  );
  final achromaticCounts = List<int>.filled(valueBins, 0);

  for (final pixel in image) {
    final hsv = _rgbToHsv(
      pixel.rNormalized.toDouble(),
      pixel.gNormalized.toDouble(),
      pixel.bNormalized.toDouble(),
    );
    final valueIndex = (hsv.$3 * valueBins).floor().clamp(0, valueBins - 1);
    if (hsv.$2 >= minSaturation && hsv.$3 >= minValue) {
      final hueIndex = (hsv.$1 * hueBins).floor().clamp(0, hueBins - 1);
      final saturationIndex =
          (hsv.$2 * saturationBins).floor().clamp(0, saturationBins - 1);
      final index = (hueIndex * saturationBins + saturationIndex) * valueBins +
          valueIndex;
      chromaticCounts[index]++;
    } else {
      achromaticCounts[valueIndex]++;
    }
  }

  var observed = 0;
  for (var r = 0; r < cubeDim; r++) {
    for (var g = 0; g < cubeDim; g++) {
      for (var b = 0; b < cubeDim; b++) {
        final hsv = _rgbToHsv(
          r / (cubeDim - 1),
          g / (cubeDim - 1),
          b / (cubeDim - 1),
        );
        final valueIndex = (hsv.$3 * valueBins).floor().clamp(0, valueBins - 1);
        if (hsv.$2 >= minSaturation && hsv.$3 >= minValue) {
          final hueIndex = (hsv.$1 * hueBins).floor().clamp(0, hueBins - 1);
          final saturationIndex =
              (hsv.$2 * saturationBins).floor().clamp(0, saturationBins - 1);
          final index =
              (hueIndex * saturationBins + saturationIndex) * valueBins +
                  valueIndex;
          if (chromaticCounts[index] >= minCellPixels) observed++;
        } else if (achromaticCounts[valueIndex] >= minCellPixels) {
          observed++;
        }
      }
    }
  }
  return ReferenceCoverageResult(
    observed / (cubeDim * cubeDim * cubeDim),
  );
}

(double, double, double) _rgbToHsv(double r, double g, double b) {
  final maximum = math.max(r, math.max(g, b));
  final minimum = math.min(r, math.min(g, b));
  final delta = maximum - minimum;
  var hue = 0.0;
  if (delta > 1e-6) {
    if (maximum == r) {
      hue = ((g - b) / delta) % 6.0;
    } else if (maximum == g) {
      hue = (b - r) / delta + 2.0;
    } else {
      hue = (r - g) / delta + 4.0;
    }
    hue /= 6.0;
    if (hue < 0.0) hue += 1.0;
  }
  final saturation = maximum > 1e-6 ? delta / maximum : 0.0;
  return (hue, saturation, maximum);
}
