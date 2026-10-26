import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['DIRECT_MVP_PERF_OUTPUT'] ??
        'build/perf/direct_mvp_device_performance_report.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final report = data?['directMvpDevice'] ?? data ?? <String, dynamic>{};
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('Wrote Direct MVP device report: ${output.path}');
  });
}
