import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/reference_coverage_router.dart';

import 'support/reference_coverage_fixtures.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memoria-coverage-');
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final entry in const [
    ('broad', false),
    ('narrow', true),
    ('monochrome', true)
  ]) {
    test('${entry.$1} reference follows the 3 percent routing contract',
        () async {
      final path = await writeCoverageFixture(directory, entry.$1);
      final result = analyzeReferenceCoverage(path);
      expect(result.fraction, inInclusiveRange(0, 1));
      expect(result.belowCandidateThreshold, entry.$2);
    });
  }
}
