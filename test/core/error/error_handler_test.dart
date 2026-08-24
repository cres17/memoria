import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/core/error/error_handler.dart';

void main() {
  test('diagnostics survive reinitialization and can be cleared', () async {
    final directory = await Directory.systemTemp.createTemp('memoria-log-');
    final file = File('${directory.path}/memoria.log');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    await ErrorLogger.initialize(file: file);
    ErrorLogger.log('preview failed', const FormatException('bad image'));
    ErrorLogger.log('export cancelled');
    await ErrorLogger.flush();

    expect(await file.readAsLines(), hasLength(2));
    await ErrorLogger.initialize(file: file);
    expect(ErrorLogger.logs, hasLength(2));
    expect(ErrorLogger.logs.first, contains('preview failed'));

    ErrorLogger.clear();
    await ErrorLogger.flush();
    expect(ErrorLogger.logs, isEmpty);
    expect(await file.readAsString(), isEmpty);
  });
}
