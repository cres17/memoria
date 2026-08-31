import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/reference_coverage_router.dart';

void main() {
  test('runtime coverage preserves the frozen 3 percent routing examples', () {
    const cases = <(String, bool)>[
      (
        'ml_pipeline/data/dataset_external_calibration_001/graded/ext_000000.jpg',
        false,
      ),
      (
        'ml_pipeline/data/dataset_external_calibration_001/graded/ext_000004.jpg',
        true,
      ),
      (
        'ml_pipeline/data/dataset_external_monochrome_calibration_001/graded/mono_000000.jpg',
        true,
      ),
    ];
    for (final entry in cases) {
      final result = analyzeReferenceCoverage(entry.$1);
      expect(result.belowCandidateThreshold, entry.$2, reason: entry.$1);
    }
  });
}
