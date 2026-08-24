import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['WHITEBOX_OUTPUT'] ??
        'build/test-results/editor/whitebox_device_report.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data ?? <String, dynamic>{}),
    );
    stdout.writeln('Wrote editor white-box device report: ${output.path}');
  });
}
