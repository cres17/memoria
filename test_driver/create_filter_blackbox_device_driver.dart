import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['CREATE_FILTER_BLACKBOX_OUTPUT'] ??
        'build/test-results/create_filter_blackbox_device.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final report = data?['createFilterBlackBox'] ?? data ?? <String, dynamic>{};
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('Wrote create-filter black-box report: ${output.path}');
  });
}
