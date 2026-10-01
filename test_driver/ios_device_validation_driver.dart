import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        final output = File(
            Platform.environment['MEMORIA_IOS_VALIDATION_OUTPUT'] ??
                'build/device-validation/result.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(const JsonEncoder.withIndent('  ').convert({
          'collectedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'sourceCommit': Platform.environment['MEMORIA_IOS_VALIDATION_COMMIT'],
          'suiteReportedData': data,
        }));
        stdout.writeln('Device evidence saved: ${output.path}');
      },
    );
