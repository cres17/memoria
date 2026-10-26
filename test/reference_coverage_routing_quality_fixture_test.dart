import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/engine/lut_engine.dart';
import 'package:memoria/engine/reference_coverage_router.dart';

const _runQualityFixture = bool.fromEnvironment(
  'RUN_ROUTING_QUALITY_FIXTURE',
);

void main() {
  test(
    'generate one deployable low-coverage fallback per external monochrome LUT',
    () async {
      final sourceRows = File(
        'ml_pipeline/data/dataset_external_monochrome_calibration_001/manifest.jsonl',
      ).readAsLinesSync().map((line) {
        return Map<String, dynamic>.from(jsonDecode(line) as Map);
      });
      final firstBySource = <String, Map<String, dynamic>>{};
      for (final row in sourceRows) {
        firstBySource.putIfAbsent(row['sourceLut'] as String, () => row);
      }
      expect(firstBySource.length, 31);

      final output = await Directory.systemTemp.createTemp(
        'memoria-routing-quality-',
      );
      final evidence = <Map<String, dynamic>>[];
      for (final row in firstBySource.values) {
        final id = row['id'] as String;
        final imagePath =
            'ml_pipeline/data/dataset_external_monochrome_calibration_001/graded/$id.jpg';
        final coverage = analyzeReferenceCoverage(imagePath);
        expect(coverage.belowCandidateThreshold, isTrue, reason: id);
        final result = await generateLutFromStyle(
          [imagePath],
          basePath: output.path,
        );
        expect(result['generatorType'], 'algorithmic', reason: id);
        evidence.add(<String, dynamic>{
          'id': id,
          'sourceLut': row['sourceLut'],
          'generatedLut': result['lutPath'],
          'targetLut':
              'ml_pipeline/data/dataset_external_monochrome_calibration_001/luts/$id.bin',
          'referenceCoverage': coverage.fraction,
        });
      }
      final manifest = File('${output.path}/manifest.jsonl');
      await manifest.writeAsString(
        '${evidence.map(jsonEncode).join('\n')}\n',
        flush: true,
      );
      // ignore: avoid_print
      print('ROUTING_QUALITY_MANIFEST=${manifest.path}');
    },
    skip: !_runQualityFixture,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
