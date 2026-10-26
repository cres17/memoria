import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['EDITOR_4K_OUTPUT'] ??
        'build/perf/editor_4k_export_device_report.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final report = data?['editor4kExport'] ?? data ?? <String, dynamic>{};
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('Wrote editor 4K export report: ${output.path}');
  });
}
