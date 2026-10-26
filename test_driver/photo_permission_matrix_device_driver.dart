import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(responseDataCallback: (data) async {
    final outputPath = Platform.environment['PHOTO_PERMISSION_OUTPUT'] ??
        'build/test-results/photo_permission_matrix_device.json';
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    final report =
        data?['photoPermissionMatrix'] ?? data ?? <String, dynamic>{};
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln('Wrote photo permission report: ${output.path}');
  });
}
