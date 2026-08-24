import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['PERF_OUTPUT'] ??
        'build/perf/editor_performance_report.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final report = data?['editorPerformance'] ?? data ?? <String, dynamic>{};
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('Wrote editor performance report: ${output.path}');
  });
}
